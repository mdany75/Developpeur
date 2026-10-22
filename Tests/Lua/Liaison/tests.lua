-- tests.lua : tests du module Lightroom hors de Lightroom (LuaJIT). Lancer avec
-- scripts/tester-module.sh, qui vérifie aussi la syntaxe de chaque fichier du module.

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local S = require 'Simulation'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'
local Recadrage = require 'Recadrage'
local Geometrie = require 'Geometrie'
local Locaux = require 'Locaux'
local Notation = require 'Notation'

-- Aides communes des essais de la liaison (Aides.lua) : avant chaque test, la simulation, la
-- liaison et les registres (Notation, Carnet) repartent de zéro.
local A = require 'Aides'
local test, egal, proche, echoue, contient, ligne = A.test, A.egal, A.proche, A.echoue, A.contient, A.ligne
local photoRaw, photoJpeg, photoFuji, appliquer = A.photoRaw, A.photoJpeg, A.photoFuji, A.appliquer
local JETON, ADOBE_COLOR = A.JETON, A.ADOBE_COLOR

-- Json ------------------------------------------------------------------------------

test("Json : aller-retour", function()
    local valeur = {
        texte = 'é ✓ 📷 "guillemets" \\ \n fin',
        nombres = Json.tableau({ 0.35, -40, 5650, 1e-05 }),
        vrai = true, faux = false,
        vide = Json.tableau(), objetVide = {},
        imbrique = { liste = Json.tableau({ 1, Json.null, 'x' }) },
    }
    local texte = Json.encode(valeur)
    local relu = Json.decode(texte)
    egal(relu.texte, valeur.texte, "texte")
    proche(relu.nombres[1], 0.35, "0.35")
    proche(relu.nombres[2], -40, "-40")
    proche(relu.nombres[3], 5650, "5650")
    proche(relu.nombres[4], 1e-05, "1e-05")
    egal(relu.vrai, true)
    egal(relu.faux, false)
    egal(Json.encode(relu.vide), '[]', "tableau vide")
    egal(Json.encode(relu.objetVide), '{}', "objet vide")
    egal(relu.imbrique.liste[2], Json.null, "null dans un tableau")
    egal(#relu.imbrique.liste, 3)
end)

test("Json : écriture des nombres et des chaînes", function()
    egal(Json.encode({ a = 0.35, b = -40, c = 5650 }), '{"a":0.35,"b":-40,"c":5650}')
    egal(Json.encode('a\tb\1'), '"a\\tb\\u0001"')
    egal(Json.encode({ 1, 2, 3 }), '[1,2,3]')
    egal(Json.encode(0 / 0), 'null', "NaN")
end)

test("Json : nombres indépendants de la locale française", function()
    local avant = os.setlocale(nil, 'numeric')
    if os.setlocale('fr_FR.UTF-8', 'numeric') then
        egal(Json.encode(0.35), '0.35')
        proche(Json.decode('0.35'), 0.35, "lecture")
        proche(Json.decode('-1.5e2'), -150, "exposant")
        os.setlocale(avant, 'numeric')
    end
end)

test("Json : échappements unicode et objets avec null", function()
    egal(Json.decode('"\\u00e9t\\u00e9"'), 'été')
    egal(Json.decode('"\\ud83d\\udcf7"'), '📷')
    local objet = Json.decode(' { "a" : null , "b" : [ ] } ')
    egal(objet.a, nil, "null efface la clé")
    egal(#objet.b, 0)
end)

test("Json : textes invalides", function()
    echoue(function() Json.decode('{"a":1} x') end, "caractères en trop")
    echoue(function() Json.decode('"pas fini') end, "chaîne non terminée")
    echoue(function() Json.decode('{a:1}') end, "clé attendue")
    echoue(function() Json.decode('') end, "valeur attendue")
end)

-- Commandes : lecture ----------------------------------------------------------------

test("ping et commande inconnue", function()
    egal(Commandes.executer('ping', {}).pong, true)
    echoue(function() Commandes.executer('pivoter', {}) end, "Commande inconnue : pivoter")
end)

test("etat : versions, mode, limites et photo active", function()
    S.active = photoRaw()
    S.selection = { S.active }
    local etat = Commandes.executer('etat', {})
    egal(etat.version_module, Liaison.VERSION)
    egal(etat.lightroom, '15.0')
    egal(etat.catalogue, 'Catalogue.lrcat')
    egal(etat.mode, 'appliquer directement')
    egal(etat.limites.saturation_max, 30)
    egal(etat.photo_active.fichier, 'DSC_0412.NEF')
    egal(etat.photo_active.appareil, 'NIKON Z 6')
    egal(etat.nombre_photos_visees, 1)
end)

test("selection : limite et photo active", function()
    local a, b = photoRaw(), photoJpeg()
    S.active = b
    S.selection = { a, b }
    local resultat = Commandes.executer('selection', { limite = 1 })
    egal(resultat.total, 2)
    egal(resultat.renvoyees, 1)
    egal(resultat.photos[1].id, 1)
    egal(resultat.photos[1].active, nil)
    resultat = Commandes.executer('selection', {})
    egal(resultat.photos[2].active, true)
    egal(Json.encode(Commandes.executer('selection', { limite = 0 }).photos), '[]', "liste vide en tableau JSON")
end)

test("reglages : valeurs demandées et échelle de température", function()
    S.active = photoRaw()
    local resultat = Commandes.executer('reglages', { cles = { 'Temperature', 'Exposure2012', 'Absent' } })
    egal(resultat.reglages.Temperature, 5200)
    egal(resultat.reglages.Exposure2012, 0)
    egal(resultat.reglages.Absent, nil)
    egal(resultat.echelle_temperature:sub(1, 8), 'kelvins ')
    egal(resultat.version_processus, '15.4')

    local jpeg = photoJpeg()
    jpeg.reglages.IncrementalTemperature = 12
    resultat = Commandes.executer('reglages', { photo = 2, cles = { 'Temperature', 'Tint' } })
    egal(resultat.echelle_temperature:sub(1, 8), 'relative')
    egal(resultat.reglages.Temperature, 12, "JPEG : lue dans IncrementalTemperature")
    egal(resultat.reglages.Tint, 0)
    echoue(function() Commandes.executer('reglages', { photo = 99 }) end, "Aucune photo n'a l'identifiant 99")

    -- Copie virtuelle supprimée : Lightroom rend encore un objet, qui ne répond plus.
    local disparue = S.Photo(9, {}, {})
    disparue.brut.uuid = ''
    echoue(function() Commandes.executer('reglages', { photo = 9 }) end, "Aucune photo n'a l'identifiant 9")
end)

test("reglages : sans photo active", function()
    echoue(function() Commandes.executer('reglages', {}) end, "Aucune photo active")
end)

test("apercu : export JPEG dans un dossier temporaire propre à l'aperçu", function()
    S.active = photoRaw()
    local resultat = Commandes.executer('apercu', { taille = 1568, cles = { 'Exposure2012' } })
    local reglages = S.dernierExport.exportSettings
    egal(reglages.LR_format, 'JPEG')
    egal(reglages.LR_size_maxWidth, 1568)
    egal(reglages.LR_export_colorSpace, 'sRGB')
    egal(S.dernierExport.photosToExport[1], S.active)
    egal(resultat.chemin:match('^/tmp/Developpeur/apercu%-1%-%d+/photo%.jpg$') ~= nil, true, "chemin " .. resultat.chemin)
    egal(resultat.photo.fichier, 'DSC_0412.NEF')
    egal(resultat.reglages.Exposure2012, 0)
    egal(resultat.photo.chemin_original, nil, "sans point_af : pas de chemin")
    egal(resultat.point_af_toujours, nil)
end)

-- 1.1.1 : le point de mise au point de view_photo, lu par le serveur dans l'original.
test("apercu : point_af donne le chemin, la géométrie et la préférence « en tout temps »", function()
    S.active = photoRaw()
    S.active.brut.path = '/Photos/2026/07/DSC_0412.NEF'
    local resultat = Commandes.executer('apercu', { taille = 1568, cles = {}, point_af = true })
    egal(resultat.photo.chemin_original, '/Photos/2026/07/DSC_0412.NEF')
    egal(type(resultat.photo.geometrie), 'table', 'orientation et cadre, pour passer dans l\'image affichée')
    egal(resultat.point_af_toujours, false, "décochée par défaut")
    S.prefs.pointMiseAuPoint = true
    resultat = Commandes.executer('apercu', { taille = 1568, cles = {}, point_af = true })
    egal(resultat.point_af_toujours, true)
    S.prefs.pointMiseAuPoint = nil
end)

-- 1.3.1 : le carnet de progrès ne cherche le bruit fort de la prise de vue qu'à un ISO élevé ; le
-- serveur lit la sensibilité en nombre (le texte formaté de la description ne se lit pas).
test("apercu : point_af donne la sensibilité ISO en nombre (sensibilite), à côté du texte de la description", function()
    S.active = photoFuji()
    S.active.brut.isoSpeedRating = 3200
    S.active.meta.isoSpeedRating = 'ISO 3200'
    local resultat = Commandes.executer('apercu', { taille = 1344, cles = {}, point_af = true })
    egal(resultat.photo.sensibilite, 3200)
    egal(resultat.photo.iso, 'ISO 3200', "le texte de la description, pour Claude")
    -- Rien sans sensibilité connue (un scan, une capture d'écran).
    S.active.brut.isoSpeedRating, S.active.meta.isoSpeedRating = nil, nil
    egal(Commandes.executer('apercu', { taille = 1344, cles = {}, point_af = true }).photo.sensibilite, nil)
    -- Sans point_af (aperçus d'analyse, avant/après), la description de toujours.
    S.active.brut.isoSpeedRating = 160
    egal(Commandes.executer('apercu', { taille = 1344, cles = {} }).photo.sensibilite, nil)
    -- Les vignettes du tri passent par la même description.
    egal(Commandes.executer('vignettes', { photos = Json.tableau({ 4 }), taille = 1024 }).photos[1].sensibilite, 160)
    -- La simulation : la valeur brute est un nombre (constaté), jamais le texte formaté.
    S.active.brut.isoSpeedRating = 'ISO 160'
    echoue(function() S.active:getRawMetadata('isoSpeedRating') end, "un nombre")
    S.active.brut.isoSpeedRating = nil
    S.active.meta.isoSpeedRating = 'ISO 12800'
    egal(S.active:getRawMetadata('isoSpeedRating'), 12800, "sans valeur brute posée : le nombre du texte")
end)

-- Commandes : retouche -----------------------------------------------------------------

test("appliquer : valeurs, arrondi, balance des blancs et mémoire d'origine", function()
    local photo = photoRaw()
    S.active = photo
    local resultat = appliquer({
        reglages = { Exposure2012 = 0.354, Highlights2012 = -40, Temperature = 5650, Vibrance = 0 },
        plages = { Exposure2012 = { -5, 5 }, Highlights2012 = { -100, 100 } },
        libelles = { Exposure2012 = "Exposition" },
        etape = 'passe 1 : lumière et couleur',
    })
    egal(photo.reglages.Exposure2012, 0.35, "exposition arrondie au centième")
    egal(photo.reglages.Highlights2012, -40)
    egal(photo.reglages.Temperature, 5650)
    egal(photo.reglages.WhiteBalance, 'Custom', "balance personnalisée")
    egal(#photo.appliques, 1)
    egal(photo.appliques[1].nom, 'Claude · passe 1 : lumière et couleur')
    egal(photo.appliques[1].reglages.Vibrance, nil, "réglage inchangé non envoyé")
    egal(S.ecritures[1], 'Claude · passe 1 : lumière et couleur')
    egal(#photo.instantanes, 1)
    egal(photo.instantanes[1], 'Avant Claude')
    egal(photo.proprietes.retoucheeParClaude, 'oui')

    local original = Json.decode(photo.proprietes.avantClaude)
    egal(original.Temperature, 5200)
    egal(original.WhiteBalance, 'As Shot')
    egal(original.Exposure2012, 0)

    local changements = resultat.resultats[1].changements
    egal(#changements, 3)
    egal(changements[1].cle, 'Exposure2012')
    egal(changements[1].apres, 0.35)
    egal(Liaison.dernierePhotoId, 1)
    egal(Liaison.derniersReglages:find("Exposition : 0 → 0,35", 1, true) ~= nil, true, Liaison.derniersReglages)
end)

test("étapes : le préfixe « Claude · » n'est pas doublé", function()
    local photo = photoFuji()
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.3 }, etape = 'Claude · passe 1' })
    egal(photo.appliques[1].nom, 'Claude · passe 1')
    appliquer({ reglages = { Exposure2012 = 0.4 }, etape = ' claude·Claude · passe 2' })
    egal(photo.appliques[2].nom, 'Claude · passe 2')
    Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.8 }, etape = 'Claude · plus clair' })
    egal(photo.appliques[3].nom, 'Claude · essai : plus clair')
    appliquer({ reglages = { Exposure2012 = 0.5 }, etape = 'Claude · ' })
    egal(photo.appliques[5].nom, 'Claude · retouche', "nom vide : celui par défaut")
    egal(Json.decode(photo.proprietes.journalClaude)[1].etape, 'Claude · passe 1')
end)

test("appliquer deux fois : un seul instantané, l'origine ne bouge pas", function()
    local photo = photoRaw()
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.5 } })
    appliquer({ reglages = { Exposure2012 = 0.7, Shadows2012 = 20 }, etape = 'passe 2' })
    egal(#photo.instantanes, 1)
    local original = Json.decode(photo.proprietes.avantClaude)
    egal(original.Exposure2012, 0, "valeur d'avant la première retouche")
    egal(original.Shadows2012, 0)
    egal(#Json.decode(photo.proprietes.etapesClaude), 2)
end)

test("appliquer : bornes, température d'un JPEG et limites de sécurité", function()
    local photo = photoJpeg()
    S.active = photo
    local resultat = appliquer({
        reglages = { Temperature = 5650, Exposure2012 = 3.5 },
        plages = { Exposure2012 = { -5, 5 } },
    })
    egal(photo.reglages.IncrementalTemperature, 100, "JPEG : température relative bornée à 100")
    egal(photo.reglages.Temperature, nil, "jamais Temperature sur un JPEG")
    egal(photo.reglages.WhiteBalance, 'Custom')
    egal(resultat.resultats[1].changements[2].cle, 'Temperature', "nom vu par Claude")
    egal(photo.reglages.Exposure2012, 2, "variation limitée à 2 IL")
    local notes = resultat.resultats[1].remarques
    egal(contient(notes, "Temperature : 5650 ramené à 100"), true, Json.encode(notes))
    egal(contient(notes, "variation limitée à ±2 IL"), true, Json.encode(notes))

    S.prefs.saturationMax = 20
    resultat = appliquer({ reglages = { Saturation = -60 }, plages = { Saturation = { -100, 100 } } })
    egal(photo.reglages.Saturation, -20)
    egal(contient(resultat.resultats[1].remarques, "Saturation : limitée à ±20"), true)
end)

test("appliquer en relatif sur plusieurs photos", function()
    local a = photoRaw()
    local b = S.Photo(3, { Temperature = 4800, Exposure2012 = -0.5, WhiteBalance = 'Custom' }, { fileName = 'B.NEF', fileFormat = 'RAW' })
    S.selection = { a, b }
    appliquer({ reglages = { Exposure2012 = 0.3, Temperature = 200 }, relatif = true, selection = true,
        plages = { Exposure2012 = { -5, 5 } } })
    proche(a.reglages.Exposure2012, 0.3)
    proche(b.reglages.Exposure2012, -0.2)
    egal(a.reglages.Temperature, 5400)
    egal(b.reglages.Temperature, 5000)
    egal(b.appliques[1].reglages.WhiteBalance, nil, "déjà personnalisée")
    egal(#S.ecritures, 1, "une seule écriture pour toute la sélection (une seule opération dans Édition › Annuler)")
    egal(S.ecrituresPrivees, 1, "l'état laissé par Claude, en écriture privée")
end)

test("appliquer : photos par identifiant", function()
    photoRaw()
    local b = photoJpeg()
    appliquer({ reglages = { Exposure2012 = 0.2 }, photos = { 2 } })
    egal(b.reglages.Exposure2012, 0.2)
    egal(S.photos[1].reglages.Exposure2012, 0)
end)

test("appliquer : mode « Proposer d'abord », pause et demandes invalides", function()
    local photo = photoRaw()
    S.active = photo
    S.prefs.mode = 'proposer'
    echoue(function() appliquer({ reglages = { Exposure2012 = 0.2 } }) end, "Proposer d'abord")
    egal(#photo.appliques, 0)
    appliquer({ reglages = { Exposure2012 = 0.2 }, confirme = true })
    egal(photo.reglages.Exposure2012, 0.2)

    S.prefs.mode = 'appliquer'
    Liaison.pause = true
    echoue(function() appliquer({ reglages = { Exposure2012 = 0.4 } }) end, "en pause")
    Liaison.pause = false

    echoue(function() appliquer({ reglages = {} }) end, "Aucun réglage")
    echoue(function() appliquer({ reglages = { Exposure2012 = 'beaucoup' } }) end, "Valeur invalide pour Exposure2012")
end)

test("annuler : défait la dernière retouche, puis plus rien", function()
    local photo = photoRaw()
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.5, Temperature = 5600 } })
    appliquer({ reglages = { Exposure2012 = 0.8, Shadows2012 = 15 }, etape = 'passe 2' })

    local resultat = Commandes.executer('annuler', {})
    egal(resultat.resultats[1].annulee, true)
    egal(resultat.resultats[1].etape, 'Claude · passe 2')
    egal(photo.reglages.Exposure2012, 0.5)
    egal(photo.reglages.Shadows2012, 0)
    egal(photo.reglages.Temperature, 5600, "la passe 1 reste")
    egal(photo.appliques[3].nom, 'Claude · annulation de « Claude · passe 2 »')

    Commandes.executer('annuler', {})
    egal(photo.reglages.Exposure2012, 0)
    egal(photo.reglages.Temperature, 5200)
    egal(photo.reglages.WhiteBalance, 'As Shot')

    resultat = Commandes.executer('annuler', {})
    egal(resultat.resultats[1].annulee, false)
end)

test("annuler depuis Lightroom pendant la pause", function()
    local photo = photoRaw()
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.5 } })
    Liaison.pause = true
    echoue(function() Commandes.executer('annuler', {}) end, "en pause")
    Commandes.executer('annuler', { photos = { 1 }, depuisLightroom = true })
    egal(photo.reglages.Exposure2012, 0)
end)

test("revenir : remet l'état d'avant Claude et oublie l'historique", function()
    local photo = photoRaw()
    S.active = photo
    S.selection = { photo, photoJpeg() }
    appliquer({ reglages = { Exposure2012 = 0.5, Temperature = 6000 } })
    appliquer({ reglages = { Exposure2012 = 0.9, Vibrance = 20 }, etape = 'passe 2' })
    photo.reglages.Clarity2012 = 10 -- retouche faite à la main entre-temps

    local resultat = Commandes.executer('revenir', { selection = true })
    egal(photo.reglages.Exposure2012, 0)
    egal(photo.reglages.Temperature, 5200)
    egal(photo.reglages.Vibrance, 0)
    egal(photo.reglages.WhiteBalance, 'As Shot')
    egal(photo.reglages.Clarity2012, 10, "la retouche manuelle reste")
    egal(photo.proprietes.avantClaude, nil)
    egal(photo.proprietes.etapesClaude, nil)
    egal(photo.proprietes.retoucheeParClaude, nil)
    egal(resultat.resultats[1].remise, false, "la photo JPEG n'avait rien")
    egal(resultat.resultats[2].remise, true)
end)

-- Profil -------------------------------------------------------------------------------

test("profil : simulation Fujifilm à la place d'Adobe Color, puis annulation", function()
    local photo = photoFuji()
    S.active = photo
    local resultat = appliquer({ profil = 'Camera CLASSIC CHROME', profil_marque = 'FUJIFILM',
        libelles = { CameraProfile = 'Profil' } })
    egal(photo.reglages.CameraProfile, 'Camera CLASSIC CHROME')
    egal(next(photo.reglages.Look), nil, "la Look d'Adobe Color est retirée")
    local changement = resultat.resultats[1].changements[1]
    egal(changement.cle, 'CameraProfile')
    egal(changement.avant, 'Adobe Color', "nom affiché dans Lightroom")
    egal(changement.apres, 'Camera CLASSIC CHROME')
    egal(Liaison.derniersReglages, "Profil : Adobe Color → Camera CLASSIC CHROME")

    local original = Json.decode(photo.proprietes.avantClaude)
    egal(original.CameraProfile, 'Adobe Standard')
    egal(original.Look.Name, 'Adobe Color', "la Look d'origine est mémorisée")

    -- Deuxième profil : la Look n'est plus là, seul le nom change.
    appliquer({ profil = 'Camera Velvia/Vivid', profil_marque = 'FUJIFILM', etape = 'passe 2' })
    egal(photo.appliques[2].reglages.Look, nil)

    Commandes.executer('annuler', {})
    egal(photo.reglages.CameraProfile, 'Camera CLASSIC CHROME')
    local annulation = Commandes.executer('annuler', {})
    egal(annulation.resultats[1].reglages_remis.Look, 'Adobe Color', "la réponse résume la Look à son nom")
    egal(photo.reglages.CameraProfile, 'Adobe Standard')
    egal(photo.reglages.Look.Name, 'Adobe Color', "Look remise")
    egal(photo.reglages.Look.Parameters.ToneCurvePV2012[3], 22, "Look remise en entier")
    egal(photo.reglages.Look.Group['x-default'], 'Profiles')
end)

test("profil : RAW seulement, de la bonne marque, et rien si c'est déjà le bon", function()
    local nikon = photoRaw()
    local jpeg = photoJpeg()
    S.selection = { nikon, jpeg }
    local resultat = appliquer({ profil = 'Camera Velvia/Vivid', profil_marque = 'FUJIFILM', selection = true })
    egal(nikon.reglages.CameraProfile, nil)
    egal(#nikon.appliques, 0)
    egal(contient(resultat.resultats[1].remarques, "réservé aux appareils FUJIFILM"), true, Json.encode(resultat.resultats[1].remarques))
    egal(contient(resultat.resultats[2].remarques, "qu'aux fichiers RAW"), true)
    egal(#jpeg.appliques, 0)

    appliquer({ profil = 'Adobe Standard', photos = { 1 } })
    egal(nikon.reglages.CameraProfile, 'Adobe Standard', "Adobe Standard : toutes marques")
    resultat = appliquer({ profil = 'Adobe Standard', photos = { 1 } })
    egal(#resultat.resultats[1].changements, 0, "déjà ce profil")
end)

-- Recadrage et transformation ------------------------------------------------------------

test("Recadrage : cadre entier, angle, ratio, centre et retrait", function()
    local cadre = Recadrage.calculer({ angle = 0 }, 6000, 4000, 'AB')
    egal(cadre.CropLeft, 0) egal(cadre.CropTop, 0) egal(cadre.CropRight, 1) egal(cadre.CropBottom, 1)
    egal(cadre.CropAngle, 0)

    -- Dimensions du cadre telles que Lightroom les déduit : les deux coins sont ceux du cadre tourné.
    local function dimensionsLightroom(c, largeur, hauteur)
        local r = math.rad(c.CropAngle)
        local dx, dy = (c.CropRight - c.CropLeft) * largeur, (c.CropBottom - c.CropTop) * hauteur
        return dx * math.cos(r) + dy * math.sin(r), -dx * math.sin(r) + dy * math.cos(r)
    end
    -- Point mesuré dans Lightroom Classic 15.6 : ces valeurs donnent un cadre de 5987 × 3554.
    local l, h = dimensionsLightroom({ CropAngle = 3, CropLeft = 0.035805, CropTop = 0.035805,
        CropRight = 0.964195, CropBottom = 0.964195 }, 6240, 4160)
    egal(math.floor(l + 0.5), 5987, "largeur mesurée")
    egal(math.floor(h + 0.5), 3554, "hauteur mesurée")

    -- Redresser de 3° au même ratio : le plus grand cadre 3:2 qui tient dans l'image tournée.
    cadre = Recadrage.calculer({ angle = 3 }, 6240, 4160, 'AB')
    egal(cadre.CropAngle, 3)
    l, h = dimensionsLightroom(cadre, 6240, 4160)
    egal(math.abs(l / h - 1.5) < 1e-4, true, "ratio 3:2 : " .. l / h)
    local t = math.rad(3)
    egal(math.abs(l - 4160 / (math.sin(t) + math.cos(t) / 1.5)) < 0.1, true, "largeur maximale : " .. l)
    proche(cadre.CropLeft + cadre.CropRight, 1, "centré")
    l, h = dimensionsLightroom(Recadrage.calculer({ angle = -3 }, 6240, 4160, 'AB'), 6240, 4160)
    egal(math.abs(l / h - 1.5) < 1e-4, true, "angle négatif")

    -- Carré au centre d'une photo horizontale.
    cadre = Recadrage.calculer({ ratio = 1 }, 6000, 4000, 'AB')
    proche(cadre.CropLeft, 0.166667) proche(cadre.CropRight, 0.833333)
    egal(cadre.CropTop, 0) egal(cadre.CropBottom, 1)

    -- Carré décentré vers le haut d'une photo verticale (fichier horizontal tourné de 90°) :
    -- le cadre rétrécit pour tenir et passe dans le repère du fichier.
    local remarque
    cadre, remarque = Recadrage.calculer({ ratio = 1, centre_y = 0.3 }, 4000, 6000, 'DA')
    proche(cadre.CropLeft, 0.4) proche(cadre.CropRight, 1)
    proche(cadre.CropTop, 0.05) proche(cadre.CropBottom, 0.95)
    egal(remarque, "Cadre réduit à 90 % de la taille demandée pour tenir dans l'image autour de ce centre.")
    cadre = Recadrage.calculer({ ratio = 1, centre_y = 0.3 }, 4000, 6000, 'BC')
    proche(cadre.CropLeft, 0) proche(cadre.CropRight, 0.6)

    -- Constaté dans Lightroom : sur une photo DA, ces valeurs gardent le haut de l'image affichée
    -- à 13 % et son bas à 97 %.
    cadre = Recadrage.calculer({ ratio = 0.8, centre_y = 0.55 }, 4160, 6240, 'DA')
    proche(cadre.CropLeft, 0.033333) proche(cadre.CropRight, 0.866667)
    egal(cadre.CropTop, 0) egal(cadre.CropBottom, 1)
    cadre = Recadrage.calculer({ ratio = 1, centre_x = 0.3 }, 6000, 4000, 'CD')
    proche(cadre.CropLeft, 0.4) proche(cadre.CropRight, 1)

    -- Taille réduite, et retrait.
    cadre = Recadrage.calculer({ taille = 0.5 }, 6000, 4000, 'AB')
    proche(cadre.CropLeft, 0.25) proche(cadre.CropTop, 0.25)
    cadre = Recadrage.calculer({ retirer = true }, nil, nil, 'AB')
    egal(cadre.CropRight, 1) egal(cadre.CropAngle, 0)

    echoue(function() Recadrage.calculer({ angle = 1 }, nil, 4000, 'AB') end, "Dimensions de la photo inconnues")
    echoue(function() Recadrage.calculer({ centre_x = 0.01 }, 6000, 4000, 'AB') end, "Cadre trop petit")
end)

test("appliquer : redresser, recadrer, annuler, et retirer le recadrage", function()
    local photo = photoFuji()
    S.active = photo
    local resultat = appliquer({ recadrage = { angle = -1.5, taille = 1, centre_x = 0.5, centre_y = 0.5 },
        libelles = { CropAngle = 'Recadrage : angle' } })
    egal(photo.reglages.CropAngle, -1.5)
    egal(photo.reglages.CropLeft > 0, true)
    egal(#resultat.resultats[1].changements, 5)
    local original = Json.decode(photo.proprietes.avantClaude)
    egal(original.CropLeft, 0, "valeur neutre mémorisée pour un réglage absent")
    egal(original.CropRight, 1)

    appliquer({ recadrage = { ratio = 0.8 }, etape = 'passe 2' })
    proche(photo.reglages.CropAngle, 0)
    egal(photo.reglages.CropTop, 0, "4:5 dans une photo 3:2 : pleine hauteur")
    egal(photo.reglages.CropBottom, 1)
    local largeur = photo.reglages.CropRight - photo.reglages.CropLeft
    egal(math.abs(largeur - 3328 / 6240) < 1e-5, true, "largeur 3328 px sur 6240 : " .. largeur)

    Commandes.executer('annuler', {})
    egal(photo.reglages.CropAngle, -1.5)
    Commandes.executer('annuler', {})
    egal(photo.reglages.CropAngle, 0)
    egal(photo.reglages.CropLeft, 0)
    egal(photo.reglages.CropBottom, 1)

    appliquer({ recadrage = { ratio = 1 } })
    appliquer({ recadrage = { retirer = true } })
    egal(photo.reglages.CropLeft, 0)
    egal(photo.reglages.CropRight, 1)
end)

test("appliquer : ratio relu dans Lightroom différent du ratio demandé", function()
    local photo = photoFuji()
    photo.brut.croppedDimensions = { width = 4000, height = 5000 }
    S.active = photo
    local resultat = appliquer({ recadrage = { ratio = 1.25 } })
    egal(contient(resultat.resultats[1].remarques, "ratio obtenu 0,8 au lieu de 1,25"), true, Json.encode(resultat.resultats[1].remarques))
    photo.brut.croppedDimensions = { width = 5000, height = 4000 }
    resultat = appliquer({ recadrage = { ratio = 1.25, angle = 1 } })
    egal(#resultat.resultats[1].remarques, 0)
end)

test("transformation : valeurs neutres, arrondi de la rotation, lecture du profil et du recadrage", function()
    local photo = photoFuji()
    S.active = photo
    local lus = Commandes.executer('reglages', { cles = { 'PerspectiveScale', 'PerspectiveUpright', 'PerspectiveRotate' } })
    egal(lus.reglages.PerspectiveScale, 100)
    egal(lus.reglages.PerspectiveUpright, 0, "absent : neutre")
    egal(lus.profil, 'Adobe Color')
    egal(lus.recadrage.angle, 0)
    egal(lus.recadrage.dimensions, '6240 x 4160')
    egal(lus.recadrage.orientation, 'AB (supposée)', "sans orientation du SDK")
    photo.brut.orientation = 'AB'
    egal(Commandes.executer('reglages', { cles = {} }).recadrage.orientation, 'AB')

    appliquer({ reglages = { PerspectiveRotate = 1.26, PerspectiveUpright = 1 },
        plages = { PerspectiveRotate = { -10, 10 }, PerspectiveUpright = { 0, 4 } } })
    proche(photo.reglages.PerspectiveRotate, 1.3)
    egal(photo.reglages.PerspectiveUpright, 1)
    Commandes.executer('annuler', {})
    egal(photo.reglages.PerspectiveUpright, 0, "remis à la valeur neutre")
end)

-- Constaté dans Lightroom Classic 15.6 : le cadre se pose sur l'image transformée, et Upright
-- complet laisse des coins vides, blancs dans l'aperçu (7,8 % de blanc pur sans recadrage ; encore
-- 0,4 % avec un cadre au ratio d'origine réduit à 85 %). Le module ne les voyait pas : il coche
-- maintenant « Contraindre le recadrage » (Lightroom resserre le cadre), et un cadre demandé se
-- calcule dans la partie de l'image que la grille de recalage dit remplie.

-- Grille de recalage telle que le serveur la calcule (Recalage.swift) pour cette déformation.
local function grilleDe(deformation, empreinte)
    local n, m = 17, 12
    local x, y = Json.tableau(), Json.tableau()
    for j = 0, m - 1 do
        for i = 0, n - 1 do
            local a, b = deformation(i / (n - 1), j / (m - 1))
            x[#x + 1], y[#y + 1] = a, b
        end
    end
    return { colonnes = n, lignes = m, x = x, y = y, empreinte = empreinte }
end

-- Part d'un cadre (réglages Crop*) qui tombe hors de l'image d'origine, comme le rendu simulé.
local function coinsVides(cadre, deformation, largeur, hauteur, orientation)
    local photo = S.Photo(99, { PerspectiveUpright = 2 }, {}, { dimensions = { width = largeur, height = hauteur }, orientation = orientation })
    for cle, valeur in pairs(cadre) do
        photo.reglages[cle] = valeur
    end
    photo.deformation = deformation
    return S.coinsVides(photo)
end

test("Recadrage : cadre sans coin vide dans la zone de la grille, ratio, angle, taille et centre", function()
    local deformation = S.trapeze(0.12)
    local zone = Geometrie.zone(grilleDe(deformation))
    egal(coinsVides(Recadrage.AUCUN, deformation, 6240, 4160, 'AB') > 0.02, true, "sans recadrage : coins vides")
    -- Sans la zone, le plus grand cadre est l'image entière : des coins vides.
    egal(coinsVides(Recadrage.calculer({ angle = 0 }, 6240, 4160, 'AB'), deformation, 6240, 4160, 'AB') > 0.02, true)

    for _, demande in ipairs({ { angle = 0 }, { angle = 2.5 }, { ratio = 0.8 }, { ratio = 1, centre_x = 0.3 }, { taille = 0.85 },
        { ratio = 16 / 9, angle = -3 } }) do
        local cadre, remarque = Recadrage.calculer(demande, 6240, 4160, 'AB', zone)
        egal(coinsVides(cadre, deformation, 6240, 4160, 'AB'), 0, "coins vides avec " .. Json.encode(demande))
        egal(tostring(remarque):find("Cadre resserré sur l'image redressée", 1, true) ~= nil, true, tostring(remarque))
        local lu = Recadrage.lire(cadre, 6240, 4160, 'AB')
        egal(math.abs(lu.ratio - (demande.ratio or 1.5)) < 1e-4, true, "ratio gardé : " .. lu.ratio)
        egal(math.abs(lu.angle - (demande.angle or 0)) < 1e-9, true, "angle gardé")
    end
    -- Le plus grand cadre se décale vers le haut, où l'image est entière ; un centre donné reste.
    local lu = Recadrage.lire(Recadrage.calculer({ angle = 0 }, 6240, 4160, 'AB', zone), 6240, 4160, 'AB')
    egal(lu.centre_y < 0.48, true, "centre " .. lu.centre_y)
    egal(math.abs(lu.centre_x - 0.5) < 0.002, true)
    egal(lu.largeur > 0.85 * 6240, true, "plus de 85 % de la largeur : " .. lu.largeur / 6240)
    local cadre, remarque = Recadrage.calculer({ ratio = 1, centre_x = 0.3, centre_y = 0.5 }, 6240, 4160, 'AB', zone)
    lu = Recadrage.lire(cadre, 6240, 4160, 'AB')
    proche(math.floor(lu.centre_x * 1e5 + 0.5) / 1e5, 0.3) proche(math.floor(lu.centre_y * 1e5 + 0.5) / 1e5, 0.5)
    egal(remarque:find("Cadre réduit à", 1, true) ~= nil, true, remarque)
    -- Plus petit que le plus grand cadre : il reste au milieu s'il y tient.
    lu = Recadrage.lire(Recadrage.calculer({ taille = 0.6 }, 6240, 4160, 'AB', zone), 6240, 4160, 'AB')
    egal(math.abs(lu.centre_y - 0.5) < 1e-4, true, "centre " .. lu.centre_y)
    -- Photo verticale (DA) : la zone porte sur l'image affichée.
    cadre = Recadrage.calculer({ ratio = 0.8 }, 4160, 6240, 'DA', zone)
    egal(coinsVides(cadre, deformation, 4160, 6240, 'DA'), 0)
    -- Sans zone, rien ne change : le cadre de toujours.
    local avant = Recadrage.calculer({ ratio = 1, centre_y = 0.3 }, 4000, 6000, 'DA')
    proche(avant.CropLeft, 0.4) proche(avant.CropTop, 0.05)
end)

test("Recadrage : lecture du cadre actuel dans l'image affichée", function()
    egal(Recadrage.lire(Recadrage.AUCUN, 6240, 4160, 'AB'), nil, "sans recadrage")
    for _, orientation in ipairs({ 'AB', 'DA', 'BC', 'CD' }) do
        local largeur, hauteur = 6240, 4160
        if orientation == 'DA' or orientation == 'BC' then
            largeur, hauteur = 4160, 6240
        end
        local cadre = Recadrage.calculer({ ratio = 1.25, angle = 2, taille = 0.7, centre_x = 0.45, centre_y = 0.55 }, largeur, hauteur, orientation)
        local lu = Recadrage.lire(cadre, largeur, hauteur, orientation)
        egal(math.abs(lu.ratio - 1.25) < 1e-4, true, orientation .. " ratio " .. lu.ratio)
        proche(lu.angle, 2)
        egal(math.abs(lu.centre_x - 0.45) < 1e-5 and math.abs(lu.centre_y - 0.55) < 1e-5, true, orientation .. " centre")
        -- Le même cadre, recalculé depuis sa lecture.
        local t = math.rad(math.abs(lu.angle))
        local maximum = math.min(largeur / (math.cos(t) + math.sin(t) / lu.ratio), hauteur / (math.sin(t) + math.cos(t) / lu.ratio))
        local refait = Recadrage.calculer({ ratio = lu.ratio, angle = lu.angle, centre_x = lu.centre_x, centre_y = lu.centre_y,
            taille = lu.largeur / maximum }, largeur, hauteur, orientation)
        for _, cle in ipairs({ 'CropLeft', 'CropTop', 'CropRight', 'CropBottom' }) do
            egal(math.abs(refait[cle] - cadre[cle]) < 1e-5, true, orientation .. ' ' .. cle)
        end
    end
end)

test("Upright : « Contraindre le recadrage » coché, cadre resserré par Lightroom, une seule étape à annuler", function()
    local photo = photoFuji()
    photo.brut.orientation = 'AB'
    S.active = photo
    local resultat = appliquer({ reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } }, etape = 'géométrie' })
    local r = resultat.resultats[1]
    egal(photo.reglages.CropConstrainToWarp, 1, "case cochée avec Upright")
    egal(S.coinsVides(photo), 0, "Lightroom a resserré le cadre")
    egal(r.a_recadrer, nil, "pas de cadre demandé : rien d'autre à faire")
    local cles = {}
    for _, c in ipairs(r.changements) do cles[c.cle] = c end
    egal(cles.CropConstrainToWarp.apres, 1)
    proche(cles.CropTop.avant, 0) proche(cles.CropTop.apres, photo.reglages.CropTop)
    egal(contient(r.remarques, "Cadre resserré par Lightroom"), true, Json.encode(r.remarques))
    Commandes.executer('apercu', { taille = 512 })
    egal(S.rendus[#S.rendus].coinsVides, 0, "l'aperçu ne montre aucun coin vide")

    -- Le journal donne le cadre que Lightroom a gardé ; l'annulation remet tout, cadre compris.
    local journal = Json.decode(photo.proprietes.journalClaude)
    local dansJournal = {}
    for _, c in ipairs(journal[#journal].changements) do dansJournal[c.cle] = c end
    proche(dansJournal.CropTop.apres, photo.reglages.CropTop)
    Commandes.executer('annuler', {})
    egal(photo.reglages.PerspectiveUpright, 0)
    egal(photo.reglages.CropConstrainToWarp, 0)
    egal(photo.reglages.CropLeft, 0) egal(photo.reglages.CropTop, 0)
    egal(photo.reglages.CropRight, 1) egal(photo.reglages.CropBottom, 1)

    -- Le retour à l'origine aussi : le cadre d'avant la case est mémorisé.
    appliquer({ reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } }, etape = 'géométrie' })
    appliquer({ reglages = { PerspectiveUpright = 4 }, plages = { PerspectiveUpright = { 0, 5 } }, etape = 'autre mode' })
    Commandes.executer('revenir', {})
    egal(photo.reglages.CropLeft, 0) egal(photo.reglages.CropBottom, 1)
    egal(photo.reglages.CropConstrainToWarp, 0)

    -- Sans transformation, la case reste comme elle était.
    appliquer({ reglages = { Exposure2012 = 0.2 }, plages = { Exposure2012 = { -5, 5 } } })
    egal(photo.reglages.CropConstrainToWarp, 0)
end)

test("Upright déjà posé : le cadre demandé tient compte de la grille et Lightroom le garde", function()
    local photo = photoFuji()
    photo.reglages.PerspectiveUpright = 2
    S.active = photo
    local empreinte = Commandes.executer('geometrie', {}).photos[1].empreinte
    local recalages = { ['4'] = grilleDe(S.deformation(photo), empreinte) }
    local resultat = appliquer({ recadrage = { ratio = 0.8, angle = 1, centre_x = 0.5 }, recalages = recalages })
    egal(resultat.resultats[1].a_recadrer, nil)
    egal(photo.reglages.CropConstrainToWarp, 1)
    egal(S.coinsVides(photo), 0)
    local voulu = Recadrage.calculer({ ratio = 0.8, angle = 1, centre_x = 0.5 }, 6240, 4160, 'AB', Geometrie.zone(recalages['4']))
    proche(photo.reglages.CropLeft, voulu.CropLeft) proche(photo.reglages.CropBottom, voulu.CropBottom)
    egal(contient(resultat.resultats[1].remarques, "Cadre resserré par Lightroom"), false, "cadre gardé tel quel")

    -- Un recadrage retiré reste retiré ; la case cochée, Lightroom le resserre.
    resultat = appliquer({ recadrage = { retirer = true } })
    egal(resultat.resultats[1].a_recadrer, nil)
    egal(S.coinsVides(photo), 0)
end)

test("Upright et recadrage dans la même retouche : le cadre se place ensuite sur la nouvelle grille", function()
    local photo = photoFuji()
    S.active = photo
    local resultat = appliquer({ reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } },
        recadrage = { ratio = 1, centre_x = 0.6 }, etape = 'géométrie' })
    local r = resultat.resultats[1]
    egal(r.a_recadrer, true, "cadre demandé sans grille pour la nouvelle géométrie")
    egal(r.etape_ecrite, true)
    egal(S.coinsVides(photo), 0, "Lightroom l'a déjà resserré")
    egal(contient(r.remarques, "Cadre resserré par Lightroom"), false, "le cadre sera placé ensuite")

    -- Le serveur mesure la nouvelle géométrie (deux rendus), puis demande le cadre.
    local info = Commandes.executer('geometrie', { photos = { 4 } }).photos[1]
    egal(info.transformation, true)
    local rendu = Commandes.executer('geometrie', { photos = { 4 }, rendre = true }).photos[1]
    egal(photo.reglages.UprightTransform_0 ~= nil, true, "matrices calculées au rendu")
    egal(rendu.empreinte, info.empreinte, "les matrices calculées ne changent pas l'empreinte")
    local recalages = { ['4'] = grilleDe(S.deformation(photo), rendu.empreinte) }
    local recadre = Commandes.executer('recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.6 }, recalages = recalages,
        completer = { 4 }, etape = r.etape, confirme = true })
    egal(S.coinsVides(photo), 0)
    local lu = Recadrage.lire(photo.reglages, 6240, 4160, 'AB')
    egal(math.abs(lu.centre_x - 0.6) < 1e-4, true, "centre demandé gardé : " .. lu.centre_x)
    egal(math.abs(lu.ratio - 1) < 1e-4, true)
    egal(contient(recadre.resultats[1].remarques, "Cadre resserré sur l'image redressée"), true, Json.encode(recadre.resultats[1].remarques))

    -- Une seule étape de Claude : l'annulation remet Upright, la case et le cadre d'avant.
    egal(#Json.decode(photo.proprietes.etapesClaude), 1)
    local journal = Json.decode(photo.proprietes.journalClaude)
    egal(#journal, 1)
    local cles = {}
    for _, c in ipairs(journal[1].changements) do cles[c.cle] = c end
    egal(cles.PerspectiveUpright ~= nil and cles.CropConstrainToWarp ~= nil and cles.CropLeft ~= nil, true, "une seule entrée")
    egal(cles.CropTop.avant, 0, "valeur d'avant l'étape")
    Commandes.executer('annuler', {})
    egal(photo.reglages.PerspectiveUpright, 0)
    egal(photo.reglages.CropConstrainToWarp, 0)
    egal(photo.reglages.CropLeft, 0) egal(photo.reglages.CropTop, 0)
    egal(photo.reglages.CropRight, 1) egal(photo.reglages.CropBottom, 1)

    -- Sans grille pour elle : Claude sait que Lightroom a choisi le cadre.
    appliquer({ reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } }, recadrage = { ratio = 1 } })
    recadre = Commandes.executer('recadrer', { photos = { 4 }, recadrage = { ratio = 1 }, etape = 'passe 1', completer = { 4 } })
    egal(contient(recadre.resultats[1].remarques, "sans recalage"), true)
    egal(S.coinsVides(photo), 0)
end)

test("geometrie : rendus du recalage case décochée, photo remise", function()
    local photo = photoFuji()
    photo.reglages.PerspectiveUpright = 2
    photo.reglages.CropConstrainToWarp = 1
    S.active = photo
    local cadre = Recadrage.calculer({ ratio = 1, taille = 0.5 }, 6240, 4160, 'AB')
    for cle, valeur in pairs(cadre) do photo.reglages[cle] = valeur end
    Commandes.executer('geometrie', { rendre = true })
    local corrige = S.rendus[#S.rendus - 1].reglagesRendus
    egal(corrige.CropConstrainToWarp, 0, "sinon Lightroom resserrerait l'image entière")
    egal(corrige.CropLeft, 0) egal(corrige.CropRight, 1)
    egal(corrige.PerspectiveUpright, 2)
    egal(photo.reglages.CropConstrainToWarp, 1, "case remise")
    proche(photo.reglages.CropLeft, cadre.CropLeft)
end)

test("proposition et copie avec Upright : case cochée, aucun coin vide", function()
    local photo = photoFuji()
    S.active = photo
    local essai = Commandes.executer('essayer', { action = 'appliquer', reglages = { PerspectiveUpright = 2 },
        plages = { PerspectiveUpright = { 0, 5 } }, taille = 512 })
    egal(S.rendus[#S.rendus].coinsVides, 0, "la proposition se rend sans coin vide")
    egal(S.rendus[#S.rendus].reglagesRendus.CropConstrainToWarp, 1)
    egal(photo.reglages.PerspectiveUpright, 0, "photo remise")
    egal(photo.reglages.CropConstrainToWarp, 0)
    egal(photo.reglages.CropLeft, 0) egal(photo.reglages.CropBottom, 1)
    egal(#essai.changements > 0, true)

    local cible = S.Photo(5, { PerspectiveScale = 100 }, { fileName = 'XH2S0321.RAF', fileFormat = 'RAW' },
        { dimensions = { width = 6240, height = 4160 } })
    photo.reglages.PerspectiveUpright = 2
    local copie = Commandes.executer('copier', { source = 4, photos = { 5 }, cles = { 'PerspectiveUpright' }, inclure = {},
        etape = 'copie' })
    egal(cible.reglages.PerspectiveUpright, 2)
    egal(cible.reglages.CropConstrainToWarp, 1)
    egal(S.coinsVides(cible), 0)
    egal(copie.resultats[1].a_recadrer, nil)
    Commandes.executer('annuler', { photos = { 5 } })
    egal(cible.reglages.CropLeft, 0) egal(cible.reglages.CropConstrainToWarp, 0)
end)

-- Version 1.2 : retouche globale étendue -----------------------------------------------

test("appliquer : noir et blanc, courbe, couleur ponctuelle, balance auto, tonalité auto, puis annulation", function()
    local photo = photoFuji()
    S.active = photo
    local resultat = appliquer({
        reglages = { ConvertToGrayscale = 1, GrayMixerBlue = -30 },
        booleens = { 'ConvertToGrayscale' },
        plages = { GrayMixerBlue = { -100, 100 } },
        courbes = { ToneCurvePV2012 = Json.tableau({ 0, 12, 128, 120, 255, 255 }) },
        couleurs_ponctuelles = Json.tableau({ { SrcHue = 0.08, SrcSat = 0.4, SrcLum = 0.6, HueShift = -0.1,
            SatScale = 0, LumScale = 0, RangeAmount = 0.5, Variance = 0 } }),
        balance = 'Auto',
        auto_ton = true,
        raison = "Essai complet.",
        etape = 'noir et blanc',
    })
    egal(photo.reglages.ConvertToGrayscale, true, "interrupteur rangé en booléen")
    egal(photo.reglages.GrayMixerBlue, -30)
    egal(photo.reglages.ToneCurvePV2012[2], 12)
    egal(photo.reglages.ToneCurveName2012, 'Custom')
    egal(#photo.reglages.PointColors, 1)
    egal(photo.reglages.WhiteBalance, 'Auto')
    egal(photo.reglages.AutoTone, true)
    egal(photo.appliques[1].preset, "Claude · balance des blancs Auto", "par un paramètre prédéfini du module")
    egal(photo.appliques[2].preset, "Claude · tonalité automatique")
    egal(photo.appliques[3].reglages.AutoTone, nil, "pas par les réglages")

    local changements = resultat.resultats[1].changements
    local parCle = {}
    for _, c in ipairs(changements) do
        parCle[c.cle] = c
    end
    egal(parCle.ToneCurvePV2012.avant, "linéaire")
    egal(parCle.ToneCurvePV2012.apres, "3 points")
    egal(parCle.PointColors.apres, "1 couleur")
    egal(parCle.WhiteBalance.avant, 'As Shot')
    egal(parCle.AutoTone.apres, "oui")

    local journal = Json.decode(photo.proprietes.journalClaude)
    egal(#journal, 1)
    egal(journal[1].raison, "Essai complet.")
    egal(journal[1].etape, 'Claude · noir et blanc')

    Commandes.executer('annuler', {})
    egal(photo.reglages.ConvertToGrayscale, false)
    egal(photo.reglages.ToneCurvePV2012[3], 255, "courbe linéaire remise")
    egal(photo.reglages.ToneCurveName2012, 'Linear')
    egal(#photo.reglages.PointColors, 0)
    egal(photo.reglages.WhiteBalance, 'As Shot')
    egal(photo.reglages.Temperature, 5350, "température d'avant la balance auto")
    egal(photo.reglages.AutoTone, false)
    egal(photo.reglages.Exposure2012, 0)
    egal(#Json.decode(photo.proprietes.journalClaude), 2, "l'annulation est journalisée")
end)

test("appliquer : limites des zones et saturation de la courbe, absentes des réglages, défaites à l'annulation", function()
    local photo = photoRaw()
    S.active = photo
    appliquer({ reglages = { ParametricShadowSplit = 30, CurveRefineSaturation = 80 },
        plages = { ParametricShadowSplit = { 10, 70 }, CurveRefineSaturation = { 0, 100 } } })
    egal(photo.reglages.ParametricShadowSplit, 30)
    egal(photo.reglages.CurveRefineSaturation, 80)
    Commandes.executer('annuler', {})
    egal(photo.reglages.ParametricShadowSplit, 25, "le défaut de Lightroom, gardé comme valeur d'avant")
    egal(photo.reglages.CurveRefineSaturation, 100)
end)

test("appliquer : version de processus mise à jour après un instantané, annulée ; refusée pour les versions 1 et 2", function()
    local demande = { valeur = '15.4', nom = 'version 6', noms = { ['10.0'] = 'version 4', ['15.4'] = 'version 6', ['5.7'] = 'version 2' },
        anciennes = { '5.0', '5.7' } }
    local photo = photoRaw()
    photo.reglages.ProcessVersion = '10.0'
    S.active = photo
    local resultat = appliquer({ version_processus = demande, etape = 'version' })
    egal(photo.reglages.ProcessVersion, '15.4')
    egal(resultat.resultats[1].changements[1].avant, 'version 4')
    egal(resultat.resultats[1].changements[1].apres, 'version 6')
    egal(photo.instantanes[#photo.instantanes], "Claude · avant version de processus", "instantané avant la mise à jour")
    Commandes.executer('annuler', {})
    egal(photo.reglages.ProcessVersion, '10.0')

    -- Version 2 (2010) : aucun chemin d'un module ne convertit les curseurs (constaté : ni
    -- setProcessVersion, ni ProcessVersion posé) : à faire à la main.
    photo.reglages.ProcessVersion = '5.7'
    resultat = appliquer({ version_processus = demande, etape = 'version' })
    egal(photo.reglages.ProcessVersion, '5.7', "pas de conversion des curseurs par un module")
    egal(contient(resultat.resultats[1].remarques, "à la main"), true)
    egal(#resultat.resultats[1].changements, 0)
end)

test("appliquer : balance de JPEG, paramètre prédéfini avant les réglages, et annulation", function()
    local jpeg = photoJpeg()
    S.active = jpeg
    local resultat = appliquer({ balance = 'Daylight' })
    egal(contient(resultat.resultats[1].remarques, "un JPEG n'a que"), true)
    egal(#jpeg.appliques, 0)

    local photo = photoFuji()
    S.active = photo
    S.presets = {
        { nom = 'Mes presets', presets = { { nom = 'Été', uuid = 'U1', reglages = { Exposure2012 = 0.5, Vibrance = 20, Look = { Name = 'Adobe Vivid', UUID = 'V' } } } } },
        { nom = 'Autres', presets = { { nom = 'Hiver', uuid = 'U2', reglages = { Exposure2012 = -0.3 } }, { nom = 'Été', uuid = 'U3', reglages = {} } } },
    }
    echoue(function() appliquer({ preset = 'Été' }) end, "Plusieurs paramètres prédéfinis")
    echoue(function() appliquer({ preset = 'Printemps' }) end, "introuvable")
    resultat = appliquer({ preset = 'Mes presets/Été', reglages = { Vibrance = 10 }, plages = { Vibrance = { -100, 100 } } })
    egal(photo.appliques[1].preset, 'Été', "le paramètre prédéfini d'abord")
    egal(photo.reglages.Vibrance, 10, "puis les réglages par-dessus")
    egal(photo.reglages.Exposure2012, 0.5)
    egal(photo.reglages.Look.Name, 'Adobe Vivid')
    egal(resultat.resultats[1].changements[1].apres, "Mes presets / Été")

    Commandes.executer('annuler', {})
    egal(photo.reglages.Exposure2012, 0)
    egal(photo.reglages.Vibrance, 0)
    egal(photo.reglages.Look.Name, 'Adobe Color')

    appliquer({ preset = 'U2' })
    egal(photo.reglages.Exposure2012, -0.3, "par l'UUID")
end)

test("profil Look : fichier de l'appareil, RAW seulement, intensité, noir et blanc, annulation", function()
    local photo = photoFuji()
    S.active = photo
    local candidats = Json.tableau({
        { restriction = 'Fujifilm X-T5', raw_seulement = true, look = { Name = 'Camera CLASSIC Neg', UUID = 'T5', Parameters = { CameraProfile = 'Camera PROVIA/Standard' } } },
        { restriction = 'Fujifilm X-H2S', raw_seulement = true, look = { Name = 'Camera CLASSIC Neg', UUID = 'H2S', SupportsAmount = false,
            Parameters = { CameraProfile = 'Camera PROVIA/Standard', ToneCurvePV2012 = Json.tableau({ 0, 0, 255, 255 }) } } },
    })
    local resultat = appliquer({ profil_look = { nom = 'Camera CLASSIC Neg', candidats = candidats } })
    egal(photo.reglages.Look.UUID, 'H2S', "le fichier du X-H2S")
    egal(photo.reglages.CameraProfile, 'Camera PROVIA/Standard', "profil de base de la Look")
    egal(resultat.resultats[1].changements[1].avant, 'Adobe Color')
    egal(resultat.resultats[1].changements[1].apres, 'Camera CLASSIC Neg')
    Commandes.executer('annuler', {})
    egal(photo.reglages.Look.Name, 'Adobe Color')
    egal(photo.reglages.CameraProfile, 'Adobe Standard')

    local nikon = photoRaw()
    S.active = nikon
    resultat = appliquer({ profil_look = { nom = 'Camera CLASSIC Neg', candidats = candidats } })
    egal(contient(resultat.resultats[1].remarques, "non disponible pour cet appareil"), true)

    local jpeg = photoJpeg()
    S.active = jpeg
    resultat = appliquer({ profil_look = { nom = 'Camera CLASSIC Neg', candidats = Json.tableau({ { restriction = '', raw_seulement = true, look = { Name = 'Adobe Color' } } }) } })
    egal(contient(resultat.resultats[1].remarques, "qu'aux fichiers RAW"), true)
    appliquer({ profil_look = { nom = 'B&W 01', intensite = 1.5, candidats = Json.tableau({
        { restriction = '', raw_seulement = false, look = { Name = 'B&W 01', UUID = 'BW', SupportsAmount = true, Parameters = { ConvertToGrayscale = true } } } }) } })
    egal(jpeg.reglages.Look.Amount, 1.5)
    egal(jpeg.reglages.ConvertToGrayscale, true, "profil noir et blanc")
    egal(jpeg.reglages.CameraProfile, nil, "pas de profil de base pour un JPEG")
end)

-- Adaptive Color tel que l'envoie le serveur (fichier du dossier Adaptive) : Look marquée comme
-- Lightroom la range à la main, et ce qui l'accompagne dans le paramètre prédéfini du module.
local function candidatsAdaptatifs(parPreset)
    return Json.tableau({ { restriction = '', raw_seulement = true,
        look = { Name = 'Adaptive Color', UUID = '226E6263ED94405B973B41F5A6E67BE9', Amount = 1, SupportsAmount = true,
            Cluster = 'Adobe', isAdobeAdaptive = true, Group = { ['x-default'] = 'Adaptive' },
            Parameters = { ConvertToGrayscale = false, LookTable = 'E1095149FDB39D7A057BAB208837E2E1', ProfileGainTableMap = 100, RGBTables = 100 } },
        par_preset = parPreset or { CameraProfile = 'Adobe Standard', AILook = { Active = true } } } })
end

-- La copie d'essai du constat : RAW de X-H2S sous CLASSIC CHROME, sans Look.
local function photoClassicChrome()
    local photo = photoFuji()
    photo.reglages.CameraProfile, photo.reglages.Look, photo.reglages.AILook = 'Camera CLASSIC CHROME', {}, {}
    return photo
end

-- Critère de la 1.8 : un masque ciel et un profil adaptatif posés, puis un aperçu, sans fenêtre
-- « Mises à jour IA recommandées » ni clic de l'utilisateur. Relevé dans Lightroom Classic 15.6 :
-- photo:updateAISettings() calcule ce que la case de cette fenêtre ferait calculer.
test("calcul IA par le SDK : profil adaptatif et masque ciel calculés après l'écriture, aperçu sans fenêtre", function()
    local photo = photoClassicChrome()
    S.active = photo
    S.calculDiffere, S.jamaisCalcule = true, true
    S.clicUtilisateur = false
    local resultat = appliquer({ profil_look = { nom = 'Adaptive Color', candidats = candidatsAdaptatifs() } })
    egal(photo.reglages.AILook.AILookData, 'look de 4', "calculé tout de suite, hors de l'écriture")
    egal(contient(resultat.resultats[1].remarques, "au prochain rendu"), false, "rien n'attend le rendu")
    resultat = Commandes.executer('masquer', { masques = { { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } } },
        etape = 'ciel' })
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].MaskDigest, 'calculé pour 4')
    egal(resultat.a_savoir, nil, "le ciel est calculé")
    S.attentes = 0
    resultat = Commandes.executer('apercu', { taille = 1344, cles = {} })
    egal(#S.fenetresIA, 0, "aucune fenêtre, sans clic")
    egal(S.attentes, 0, "rien à attendre")
    egal(resultat.a_savoir, nil)
    egal(#S.misesAJourIA, 2, "une mise à jour par retouche")

    -- Une retouche qui ne touche à rien de calculé ne demande rien.
    appliquer({ reglages = { Exposure2012 = 0.2 }, plages = { Exposure2012 = { -5, 5 } } })
    egal(#S.misesAJourIA, 2)
end)

test("calcul IA par le SDK : sans les modèles IA, la remarque, puis la fenêtre au rendu et le clic de l'utilisateur", function()
    local photo = photoClassicChrome()
    S.active = photo
    S.calculDiffere, S.jamaisCalcule = true, true
    S.modelesIAAbsents = true
    local resultat = Commandes.executer('masquer', { masques = { { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = {} } }, etape = 'ciel' })
    egal(contient(resultat.resultats[1].remarques, "modèles IA à télécharger"), true)
    egal(contient(resultat.resultats[1].remarques, "y répondre Exporter"), true, "la remarque dit quoi répondre à la fenêtre")
    egal(resultat.a_savoir ~= nil, true)
    resultat = Commandes.executer('apercu', { taille = 1344, cles = {} })
    egal(#S.fenetresIA, 1, "la fenêtre au rendu, à laquelle répond l'utilisateur")
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].MaskDigest, 'calculé pour 4')
    egal(resultat.a_savoir, nil)
end)

test("calcul IA par le SDK : profil adaptatif recalculé après une tache ou un flou, inchangé par une rotation", function()
    -- Constaté le 17 octobre 2026 (Lightroom Classic 15.6, Adaptive Color) : après une tache ou un flou
    -- d'objectif, updateAISettings le recalcule ; une rotation ne change pas son empreinte.
    local photo = photoClassicChrome()
    S.active = photo
    appliquer({ profil_look = { nom = 'Adaptive Color', candidats = candidatsAdaptatifs() } })
    local empreinte = photo.reglages.AILook.InputDigest
    local resultat = appliquer({ recadrage = { angle = 2, taille = 1 }, etape = 'redresser' })
    egal(photo.reglages.AILook.InputDigest, empreinte, "une rotation ne change rien au profil")
    egal(contient(resultat.resultats[1].remarques, "inchangé"), true)
    resultat = Commandes.executer('retoucher', { taches = { { x = 0.5, y = 0.5, rayon = 0.01 } }, yeux = {}, etape = 'tache' })
    egal(photo.reglages.AILook.InputDigest ~= empreinte, true, "recalculé après une tache")
    egal(contient(resultat.resultats[1].remarques, "Profil adaptatif recalculé"), true)
    S.lookFige = true
    resultat = appliquer({ flou_objectif = { intensite = 30 }, etape = 'flou' })
    egal(contient(resultat.resultats[1].remarques, "pas recalculé"), true, "Lightroom le laisse tel quel : la remarque le dit")
end)

test("calcul IA par le SDK : un second passage quand le premier laisse un calcul en attente", function()
    -- Constaté le 17 octobre 2026 : un flou d'objectif sur une photo à profil adaptatif laissait un
    -- calcul en attente après le premier passage.
    local photo = photoFuji()
    S.active = photo
    S.calculDiffere, S.jamaisCalcule = true, true
    local passages = 0
    S.pendantMiseAJourIA = function()
        passages = passages + 1
        S.modelesIAAbsents = passages == 1
    end
    local resultat = Commandes.executer('masquer', { masques = { { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = {} } }, etape = 'ciel' })
    egal(passages, 2)
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].MaskDigest, 'calculé pour 4')
    egal(#resultat.resultats[1].remarques, 0, "rien à dire")
end)

test("calcul IA par le SDK : une commande calcule 90 s au plus, le reste attend le rendu", function()
    S.dureeCalculIA = 50
    S.calculDiffere, S.jamaisCalcule = true, true
    local cibles = {}
    for id = 11, 13 do
        local cible = photoFuji()
        cible.localIdentifier = id
        S.photos[id] = cible
        cibles[#cibles + 1] = id
    end
    -- La source en dernier : photoFuji() est toujours la photo 4.
    local source = photoFuji()
    source.reglages.MaskGroupBasedCorrections = { Locaux.correction('Claude · Ciel', 1, {}, { Locaux.masqueIA(2, nil, 'Ciel') }) }
    S.active = S.photos[11]
    local resultat = Commandes.executer('copier', { source = 4, photos = cibles, cles = {}, inclure = { masques = true }, etape = 'copie' })
    egal(#S.misesAJourIA, 2, "deux photos calculées en 100 s")
    egal(contient(resultat.resultats[3].remarques, "laissés à Lightroom"), true)
end)

test("profil adaptatif : par un paramètre prédéfini du module, calculé au rendu par la fenêtre, annulation", function()
    -- Lightroom sans photo:updateAISettings (avant 13.3, refusé depuis la 2.6 ; le chemin reste) : la
    -- fenêtre au rendu, et le clic de l'utilisateur.
    S.miseAJourIA = false
    -- Constaté le 16 octobre 2026 : posé par applyDevelopSettings, Adaptive Color restait rangé
    -- sans calcul (AILook vide, profil de base d'avant), même après un rendu.
    local photo = photoClassicChrome()
    S.active = photo
    local resultat = appliquer({ profil_look = { nom = 'Adaptive Color', candidats = candidatsAdaptatifs() } })
    egal(photo.reglages.Look.Name, 'Adaptive Color')
    egal(photo.reglages.CameraProfile, 'Adobe Standard', "profil de base posé comme à la main")
    egal(photo.reglages.AILook.Active, true)
    egal(photo.reglages.AILook.AILookData, nil, "pas encore calculé")
    egal(photo.appliques[#photo.appliques].preset:find("Claude · profil Adaptive Color", 1, true), 1, "par un paramètre prédéfini du module")
    egal(resultat.resultats[1].changements[1].avant, 'Camera CLASSIC CHROME')
    egal(resultat.resultats[1].changements[1].apres, 'Adaptive Color')
    egal(contient(resultat.resultats[1].remarques, "au prochain rendu"), true)

    -- Rien à attendre au rendu : Lightroom ne le calcule pas de lui-même ; la fenêtre s'ouvre,
    -- l'utilisateur y clique Exporter, et Lightroom calcule avant de rendre.
    S.attentes = 0
    resultat = Commandes.executer('apercu', { taille = 1344, cles = {} })
    egal(S.attentes, 0, "pas d'attente inutile")
    egal(#S.fenetresIA, 1, "la fenêtre s'est ouverte")
    egal(photo.reglages.AILook.AILookData, 'look de 4', "calculé pour la photo")
    egal(resultat.a_savoir, nil)

    Commandes.executer('annuler', {})
    egal(photo.reglages.CameraProfile, 'Camera CLASSIC CHROME')
    egal(next(photo.reglages.Look), nil, "sans Look")
    egal(next(photo.reglages.AILook), nil, "calcul retiré")
end)

test("profil adaptatif : photo pas affichée, sans clic, sans AILook actif", function()
    -- Lightroom sans photo:updateAISettings (avant 13.3, refusé depuis la 2.6 ; le chemin reste) : la
    -- fenêtre au rendu, et le clic de l'utilisateur.
    S.miseAJourIA = false
    -- Constaté le 16 octobre 2026 : la fenêtre s'ouvre aussi pour une photo qui n'est pas affichée.
    local photo = photoClassicChrome()
    S.active = photoRaw()
    appliquer({ photos = { photo.localIdentifier }, profil_look = { nom = 'Adaptive Color', candidats = candidatsAdaptatifs() } })
    local resultat = Commandes.executer('apercu', { photo = photo.localIdentifier, taille = 1344, cles = {} })
    egal(#S.fenetresIA, 1, "la fenêtre s'est ouverte")
    egal(photo.reglages.AILook.AILookData, 'look de 4')
    egal(resultat.a_savoir, nil)

    -- Sans clic de l'utilisateur, la fenêtre retient la réponse.
    local autre = photoClassicChrome()
    S.active = autre
    S.clicUtilisateur = false
    appliquer({ profil_look = { nom = 'Adaptive Color', candidats = candidatsAdaptatifs() } })
    echoue(function() Commandes.executer('apercu', { taille = 1344, cles = {} }) end, "attend un clic")
    S.clicUtilisateur = true

    -- Sans AILook actif, Lightroom ne le calculerait jamais : le profil d'avant revient.
    local inerte = photoClassicChrome()
    S.active = inerte
    resultat = appliquer({ profil_look = { nom = 'Adaptive Color', candidats = candidatsAdaptatifs({ CameraProfile = 'Adobe Standard' }) } })
    egal(contient(resultat.resultats[1].remarques, "non appliqué"), true)
    egal(inerte.reglages.CameraProfile, 'Camera CLASSIC CHROME')
    egal(next(inerte.reglages.Look), nil)
    egal(#resultat.resultats[1].changements, 0, "pas de faux succès")
end)

test("copier : un profil adaptatif est recalculé pour chaque photo, sans les empreintes de la source", function()
    -- Lightroom sans photo:updateAISettings (avant 13.3, refusé depuis la 2.6 ; le chemin reste) : la
    -- fenêtre au rendu, et le clic de l'utilisateur.
    S.miseAJourIA = false
    local cible = photoClassicChrome()
    cible.localIdentifier = 6
    S.photos[6] = cible
    S.active = cible
    local source = photoFuji()
    source.reglages.Look = candidatsAdaptatifs()[1].look
    source.reglages.AILook = { Active = true, AILookData = 'look de la source', InputDigest = 'image de la source', InputDigestVersion = 5 }
    local resultat = Commandes.executer('copier', { source = 4, photos = { 6 }, cles = {}, inclure = { profil = true }, etape = 'copie' })
    egal(cible.reglages.Look.Name, 'Adaptive Color')
    egal(cible.reglages.CameraProfile, 'Adobe Standard')
    egal(cible.reglages.AILook.AILookData, nil, "empreintes de la source pas copiées")
    egal(contient(resultat.resultats[1].remarques, "au prochain rendu"), true)
    Commandes.executer('apercu', { taille = 1344, cles = {} })
    egal(cible.reglages.AILook.AILookData, 'look de 6', "calculé pour la photo")
end)

test("profil d'appareil ACROS : noir et blanc, puis retour à la couleur", function()
    local photo = photoFuji()
    S.active = photo
    appliquer({ profil = 'Camera ACROS', profil_marque = 'FUJIFILM' })
    egal(photo.reglages.ConvertToGrayscale, true)
    -- Constaté en 2.3 : sous un profil d'appareil monochrome, le mélangeur ne change rien.
    local melange = appliquer({ reglages = { GrayMixerBlue = -80 }, plages = { GrayMixerBlue = { -100, 100 } } })
    egal(photo.reglages.GrayMixerBlue, -80, "rangé quand même")
    egal(contient(melange.resultats[1].remarques, "sans effet sous le profil « Camera ACROS »"), true)
    appliquer({ profil = 'Camera Velvia/Vivid', profil_marque = 'FUJIFILM' })
    egal(photo.reglages.ConvertToGrayscale, false)
    local couleur = appliquer({ reglages = { GrayMixerBlue = -60 }, plages = { GrayMixerBlue = { -100, 100 } } })
    egal(contient(couleur.resultats[1].remarques, "sans effet"), false, "pas de remarque hors d'un profil monochrome")
end)

-- Profils que Lightroom trouve pour le X-H2S de photoFuji (« Camera Pro Neg Hi » : orthographe
-- supposée, pour les variantes).
-- Laisse à Lightroom le temps de résoudre le profil posé (il le fait de lui-même, peu après).
local function plusTard()
    import('LrTasks').sleep(0.5)
end

local function photoFujiProfils(id)
    local photo = photoFuji()
    if id then
        photo.localIdentifier = id
        S.photos[id] = photo
    end
    photo.profils = { 'Camera PROVIA/Standard', 'Camera ASTIA/Soft', 'Camera CLASSIC CHROME', 'Camera Pro Neg Hi', 'Camera Monochrome' }
    S.active = photo
    return photo
end

test("profil d'appareil introuvable : remarque et profil d'avant remis, pas de faux succès", function()
    local photo = photoFujiProfils()
    local resultat = appliquer({ profil = 'Camera ETERNA/Cinema', profil_marque = 'FUJIFILM', reglages = { Exposure2012 = 0.3 },
        plages = { Exposure2012 = Json.tableau({ -5, 5 }) } })
    local r = resultat.resultats[1]
    egal(photo.reglages.Exposure2012, 0.3, "les autres réglages restent")
    egal(photo.reglages.CameraProfile, 'Adobe Standard')
    egal(photo.reglages.Look.Name, 'Adobe Color', "Adobe Color remise : la Look n'est pas perdue")
    egal(photo.reglages.MissingCameraProfile, '', "plus de profil manquant qui bloquerait la suite")
    egal(#r.changements, 1, "seule l'exposition est annoncée")
    egal(r.changements[1].cle, 'Exposure2012')
    egal(contient(r.remarques, "Profil « Camera ETERNA/Cinema » non appliqué : Lightroom ne l'a pas gardé (relu : « Adobe Standard ») : "
        .. "il ne le trouve pas sous ce nom pour cet appareil. Profil d'avant remis : « Adobe Color »."), true, Json.encode(r.remarques))
    local journal = Json.decode(photo.proprietes.journalClaude)
    egal(#journal[1].changements, 1, "le journal ne garde pas le profil")
    egal(journal[1].note:find("non appliqué", 1, true) ~= nil, true, "la remarque va au journal")
end)

test("profil d'appareil sous une autre orthographe : celle que Lightroom connaît pour l'appareil", function()
    local photo = photoFujiProfils()
    local resultat = appliquer({ profil = 'Camera PRO Neg. Hi', profil_marque = 'FUJIFILM',
        profil_variantes = Json.tableau({ 'Camera Pro Neg. Hi', 'Camera Pro Neg Hi' }) })
    local r = resultat.resultats[1]
    egal(photo.reglages.CameraProfile, 'Camera Pro Neg Hi')
    egal(next(photo.reglages.Look), nil, "sans Look")
    egal(r.changements[1].apres, 'Camera Pro Neg Hi', "le nom réellement posé")
    egal(contient(r.remarques, "posé sous le nom que Lightroom lui donne pour cet appareil : « Camera Pro Neg Hi »"), true, Json.encode(r.remarques))

    resultat = appliquer({ profil = 'Camera PRO Neg. Std', profil_marque = 'FUJIFILM', etape = 'passe 2',
        profil_variantes = Json.tableau({ 'Camera Pro Neg Std' }) })
    egal(contient(resultat.resultats[1].remarques, "ni sous « Camera Pro Neg Std »"), true, Json.encode(resultat.resultats[1].remarques))
    egal(photo.reglages.CameraProfile, 'Camera Pro Neg Hi', "le profil d'avant, remis")
end)

test("profil d'appareil à la casse près : le nom que Lightroom range, noir et blanc compris", function()
    local photo = photoFujiProfils()
    local resultat = appliquer({ profil = 'Camera MONOCHROME', profil_marque = 'FUJIFILM' })
    egal(photo.reglages.CameraProfile, 'Camera Monochrome')
    egal(photo.reglages.ConvertToGrayscale, true, "MONOCHROME : noir et blanc")
    egal(#resultat.resultats[1].remarques, 0, Json.encode(resultat.resultats[1].remarques))
    egal(resultat.resultats[1].changements[1].apres, 'Camera Monochrome', "le nom rangé par Lightroom")
    resultat = appliquer({ profil = 'Camera Monochrome', profil_marque = 'FUJIFILM', etape = 'passe 2' })
    egal(#resultat.resultats[1].changements, 0, "déjà ce profil")
end)

-- Constaté en 2.3 (Lightroom Classic 15.6) sur une copie d'un RAF de X-T20 : les noms que Lightroom
-- range pour cet appareil, et les simulations qu'il n'a pas (ETERNA, REALA ACE).
test("profils d'un X-T20 : noms de l'appareil retrouvés, simulations absentes refusées", function()
    local photo = photoFuji()
    photo.meta.cameraModel = 'X-T20'
    photo.profils = { 'Camera PROVIA/STANDARD', 'Camera Velvia/VIVID', 'Camera ASTIA/SOFT', 'Camera CLASSIC CHROME',
        'Camera Pro Neg. Hi', 'Camera Pro Neg. Std', 'Camera ACROS', 'Camera ACROS+Ye FILTER', 'Camera ACROS+R FILTER',
        'Camera ACROS+G FILTER', 'Camera MONOCHROME', 'Camera MONOCHROME+Ye FILTER', 'Camera MONOCHROME+R FILTER', 'Camera MONOCHROME+G FILTER' }
    S.active = photo
    appliquer({ profil = 'Camera PROVIA/Standard', profil_marque = 'FUJIFILM' })
    egal(photo.reglages.CameraProfile, 'Camera PROVIA/STANDARD', "le nom rangé pour le X-T20")
    appliquer({ profil = 'Camera ACROS+Ye Filter', profil_marque = 'FUJIFILM', etape = 'passe 2' })
    egal(photo.reglages.CameraProfile, 'Camera ACROS+Ye FILTER')
    egal(photo.reglages.ConvertToGrayscale, true)
    local proNeg = appliquer({ profil = 'Camera Pro Neg Hi', profil_marque = 'FUJIFILM', etape = 'passe 3',
        profil_variantes = Json.tableau({ 'Camera PRO Neg. Hi' }) })
    egal(photo.reglages.CameraProfile, 'Camera Pro Neg. Hi')
    egal(contient(proNeg.resultats[1].remarques, "posé sous le nom que Lightroom lui donne"), true)
    local eterna = appliquer({ profil = 'Camera ETERNA/Cinema', profil_marque = 'FUJIFILM', etape = 'passe 4' })
    egal(photo.reglages.CameraProfile, 'Camera Pro Neg. Hi', "le profil d'avant revient")
    egal(contient(eterna.resultats[1].remarques, "non appliqué : Lightroom ne l'a pas gardé"), true, Json.encode(eterna.resultats[1].remarques))
end)

test("profil manquant d'une retouche précédente : il ne bloque plus le profil suivant", function()
    local photo = photoFujiProfils()
    -- Comme la copie 53631687 après « Camera PRO Neg. Hi ».
    photo.reglages.MissingCameraProfile = 'Camera PRO Neg. Hi'
    photo.reglages.MissingCameraProfileDigest = S.EMPREINTE_ADOBE_STANDARD
    local resultat = appliquer({ profil = 'Camera ASTIA/Soft', profil_marque = 'FUJIFILM' })
    plusTard()
    egal(photo.reglages.CameraProfile, 'Camera ASTIA/Soft')
    egal(#resultat.resultats[1].remarques, 0, Json.encode(resultat.resultats[1].remarques))
    appliquer({ profil = 'Camera CLASSIC CHROME', profil_marque = 'FUJIFILM', etape = 'passe 2' })
    plusTard()
    egal(photo.reglages.CameraProfile, 'Camera CLASSIC CHROME')
    local annulation = Commandes.executer('annuler', {})
    plusTard()
    egal(photo.reglages.CameraProfile, 'Camera ASTIA/Soft', "le profil d'avant")
    egal(annulation.resultats[1].remarque, nil)

    -- Profil à base de Look : son profil de base aussi.
    photo.reglages.MissingCameraProfile = 'Camera PRO Neg. Hi'
    local candidats = Json.tableau({ { restriction = 'Fujifilm X-H2S', raw_seulement = true,
        look = { Name = 'Camera CLASSIC Neg', UUID = 'H2S', Parameters = { CameraProfile = 'Camera PROVIA/Standard' } } } })
    resultat = appliquer({ profil_look = { nom = 'Camera CLASSIC Neg', candidats = candidats }, etape = 'passe 3' })
    plusTard()
    egal(photo.reglages.Look.Name, 'Camera CLASSIC Neg')
    egal(photo.reglages.CameraProfile, 'Camera PROVIA/Standard', "pas Adobe Standard sous la Look")
    egal(#resultat.resultats[1].remarques, 0)
end)

test("profil d'appareil sur une série : une seule attente pour toutes les photos", function()
    local photos = { photoFujiProfils(11), photoFujiProfils(12), photoFujiProfils(13) }
    S.attentes = 0
    local resultat = appliquer({ profil = 'Camera ASTIA/Soft', profil_marque = 'FUJIFILM', photos = { 11, 12, 13 } })
    for i, photo in ipairs(photos) do
        egal(photo.reglages.CameraProfile, 'Camera ASTIA/Soft')
        egal(#resultat.resultats[i].remarques, 0)
    end
    egal(S.attentes, 6, "1,5 s de relecture en tout")
end)

test("annulation d'un profil que Lightroom ne garde plus : la remarque le dit", function()
    local photo = photoFujiProfils()
    appliquer({ profil = 'Camera CLASSIC CHROME', profil_marque = 'FUJIFILM' })
    appliquer({ profil = 'Camera ASTIA/Soft', profil_marque = 'FUJIFILM', etape = 'passe 2' })
    photo.profils = { 'Camera ASTIA/Soft' }
    local annulation = Commandes.executer('annuler', {})
    egal(annulation.resultats[1].remarque, "Profil d'avant « Camera CLASSIC CHROME » non remis : Lightroom ne l'a pas gardé (relu : « Adobe Standard »).")
end)

test("proposition d'un profil introuvable : remarque, et la photo remise comme avant", function()
    local photo = photoFujiProfils()
    local resultat = Commandes.executer('essayer', { action = 'appliquer', profil = 'Camera ETERNA/Cinema', profil_marque = 'FUJIFILM', taille = 800 })
    egal(contient(resultat.remarques, "Profil « Camera ETERNA/Cinema » non appliqué"), true, Json.encode(resultat.remarques))
    egal(contient(resultat.remarques, "le rendu le montre ainsi"), true)
    egal(S.rendus[1].reglagesRendus.CameraProfile, 'Adobe Standard', "ce que montre le rendu")
    egal(photo.reglages.CameraProfile, 'Adobe Standard')
    egal(photo.reglages.Look.Name, 'Adobe Color', "remise comme avant")
end)

test("noir et blanc sous Adobe Color : passage à Adobe Monochrome, et retour à la couleur", function()
    local photo = photoFuji()
    S.active = photo
    local looks = {
        monochrome = { Name = 'Adobe Monochrome', UUID = 'M', Parameters = { ConvertToGrayscale = true } },
        couleur = ADOBE_COLOR,
    }
    local resultat = appliquer({ reglages = { ConvertToGrayscale = 1 }, booleens = { 'ConvertToGrayscale' }, looks_traitement = looks })
    egal(photo.reglages.ConvertToGrayscale, true)
    egal(photo.reglages.Look.Name, 'Adobe Monochrome')
    egal(contient((function()
        local liste = {}
        for _, c in ipairs(resultat.resultats[1].changements) do liste[#liste + 1] = tostring(c.apres) end
        return liste
    end)(), 'Adobe Monochrome'), true)
    appliquer({ reglages = { ConvertToGrayscale = 0 }, booleens = { 'ConvertToGrayscale' }, looks_traitement = looks })
    egal(photo.reglages.ConvertToGrayscale, false)
    egal(photo.reglages.Look.Name, 'Adobe Color', "retour à la couleur")

    local jpeg = photoJpeg()
    S.active = jpeg
    appliquer({ reglages = { ConvertToGrayscale = 1 }, booleens = { 'ConvertToGrayscale' }, looks_traitement = looks })
    egal(jpeg.reglages.Look, nil, "un JPEG n'a pas de Look Adobe Raw")
end)

test("diagnostic : fonctions offertes par le SDK", function()
    S.active = photoFuji()
    local resultat = Commandes.executer('diagnostic', { modules = { 'LrApplication', 'Inexistant' } })
    egal(resultat.lightroom, '15.0')
    egal(contient(resultat.modules.LrApplication, 'activeCatalog'), true)
    egal(resultat.modules.Inexistant, "indisponible")
end)

test("diagnostic : méthodes cherchées par leur nom, métadonnées de la photo active", function()
    S.active = photoFuji()
    local resultat = Commandes.executer('diagnostic', {
        methodes = { catalogue = { 'getTargetPhoto', 'inexistante' }, photo = { 'getRawMetadata' }, mot_cle = { 'getName' } },
        cles = { 'fileFormat', 'inexistante' },
    })
    egal(resultat.methodes.catalogue.getTargetPhoto, 'function')
    egal(resultat.methodes.catalogue.inexistante, 'nil')
    egal(resultat.methodes.photo.getRawMetadata, 'function')
    egal(resultat.methodes.mot_cle, "absent", "aucun mot-clé dans le catalogue simulé")
    egal(resultat.cles.fileFormat, 'string')
    egal(resultat.cles.inexistante, 'nil')
end)

-- Version 1.2 : géométrie et tables locales ------------------------------------------------

test("Geometrie : de l'aperçu au repère du fichier", function()
    local ctx = Geometrie.contexte(6000, 4000, 'AB', {})
    local x, y = Geometrie.point(ctx, 0.25, 0.5)
    proche(x, 0.25) proche(y, 0.5)
    local l, h = Geometrie.apercu(ctx)
    egal(l, 6000) egal(h, 4000)

    local cadre = Recadrage.calculer({ ratio = 0.8 }, 6000, 4000, 'AB')
    ctx = Geometrie.contexte(6000, 4000, 'AB', cadre)
    x, y = Geometrie.point(ctx, 0, 0)
    proche(x, cadre.CropLeft) proche(y, cadre.CropTop)
    x, y = Geometrie.point(ctx, 1, 1)
    egal(math.abs(x - cadre.CropRight) < 1e-6 and math.abs(y - cadre.CropBottom) < 1e-6, true, "coin bas droit")

    cadre = Recadrage.calculer({ angle = 3 }, 6240, 4160, 'AB')
    ctx = Geometrie.contexte(6240, 4160, 'AB', cadre)
    x, y = Geometrie.point(ctx, 0.5, 0.5)
    egal(math.abs(x - 0.5) < 1e-6 and math.abs(y - 0.5) < 1e-6, true, "centre du cadre tourné")
    l, h = Geometrie.apercu(ctx)
    egal(math.abs(l / h - 1.5) < 1e-4, true, "aperçu 3:2")

    ctx = Geometrie.contexte(4160, 6240, 'DA', {})
    x, y = Geometrie.point(ctx, 0, 0)
    proche(x, 1) proche(y, 0)
    l, h = Geometrie.apercu(ctx)
    egal(l, 4160) egal(h, 6240)
    local ex, ey = Geometrie.axes(ctx, 10, 20)
    egal(ex, 20) egal(ey, 10)
    echoue(function() Geometrie.contexte(nil, 4000, 'AB', {}) end, "Dimensions de la photo inconnues")
end)

test("Locaux : tables comme les range Lightroom", function()
    local c = Locaux.correction('Claude · Ciel', 0.8, { LocalExposure2012 = -0.15 }, { Locaux.masqueIA(2, nil, 'Claude · Ciel', false) })
    egal(c.What, 'Correction')
    egal(c.CorrectionAmount, 0.8)
    egal(c.LocalExposure2012, -0.15)
    egal(c.LocalContrast2012, 0)
    egal(c.LocalCurveRefineSaturation, 100)
    egal(c.CorrectionMasks[1].MaskSubType, 2)
    egal(c.CorrectionMasks[1].ReferencePoint, '0.500000 0.500000')
    egal(c.CorrectionMasks[1].MaskID:match('^%x+%-%x+%-%x+%-%x+%-%x+$') ~= nil, true, c.CorrectionMasks[1].MaskID)
    egal(#c.CorrectionSyncID, 32)

    local avant = os.setlocale(nil, 'numeric')
    os.setlocale('fr_FR.UTF-8', 'numeric')
    local plage = Locaux.luminance(0.7, 1, 0.1, 'Claude · Plage', false)
    os.setlocale(avant, 'numeric')
    egal(plage.CorrectionRangeMask.LumRange, '0.600000 0.700000 1.000000 1.000000', "points décimaux, quelle que soit la locale")
    egal(plage.CorrectionRangeMask.Type, 2)
    egal(Locaux.decimal(-0.5), '-0.500000')

    local t = Locaux.tache(0.2, 0.3, 0.01, 0.25, 0.3, 'heal', 0.43)
    egal(t.Masks[1].What, 'Mask/Ellipse')
    egal(t.Masks[1].SizeX, 0.01)
    egal(t.SourceX, 0.25) egal(t.OffsetY, 0.3)
    egal(t.spotType, 'heal')

    local copie = Locaux.sansCalculsIA({ { CorrectionMasks = { { What = 'Mask/Image', MaskSubType = 1, InputDigest = 'X', MaskDigest = 'Y', ModelVersion = 3 } } } })
    egal(copie[1].CorrectionMasks[1].InputDigest, nil)
    egal(copie[1].CorrectionMasks[1].MaskDigest, nil)
    egal(copie[1].CorrectionMasks[1].MaskSubType, 1)
end)

local MASQUE_UTILISATEUR = { What = 'Correction', CorrectionName = 'Masque 1', CorrectionMasks = { { What = 'Mask/Paint' } } }

test("masquer : ajoute aux masques existants, positions dans le fichier, annulation", function()
    local photo = photoFuji()
    photo.reglages.MaskGroupBasedCorrections = { MASQUE_UTILISATEUR }
    S.active = photo
    local resultat = Commandes.executer('masquer', {
        masques = Json.tableau({
            { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.15 }, quantite = 1 },
            { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.4, nom = 'Claude · Dégradé', locaux = { LocalExposure2012 = -0.25 } },
            { type = 'radial', centre_x = 0.5, centre_y = 0.5, rayon_x = 0.1, fondu = 50, nom = 'Claude · Rond', locaux = { LocalExposure2012 = 0.1 } },
            { type = 'luminance', min = 0.7, max = 1, fondu = 0.1, nom = 'Claude · Plage', locaux = { LocalHighlights2012 = -0.3 } },
        }),
        etape = 'masques', raison = "Ciel trop clair.",
    })
    local masques = photo.reglages.MaskGroupBasedCorrections
    egal(#masques, 5)
    egal(masques[1].CorrectionName, 'Masque 1', "le masque de l'utilisateur reste")
    egal(masques[2].CorrectionMasks[1].MaskSubType, 2, "masques dans l'ordre demandé")
    egal(masques[2].CorrectionMasks[1].MaskDigest, 'calculé pour 4', "masque IA calculé par Lightroom")
    egal(masques[2].LocalExposure2012, -0.15)
    local lineaire = masques[3].CorrectionMasks[1]
    proche(lineaire.FullX, 0.5) proche(lineaire.FullY, 0) proche(lineaire.ZeroY, 0.4)
    local radial = masques[4].CorrectionMasks[1]
    proche(radial.Left, 0.4) proche(radial.Right, 0.6)
    egal(math.abs(radial.Top - (0.5 - 624 / 4160)) < 1e-9, true, "un cercle : même rayon en pixels")
    egal(masques[5].CorrectionMasks[1].What, 'Mask/RangeMask')
    egal(#photo.appliques, 1, "tous les masques dans un seul paramètre prédéfini")
    egal(photo.appliques[1].preset:find("Claude · masques IA", 1, true) ~= nil, true)
    local changement = resultat.resultats[1].changements[1]
    egal(changement.avant, "1 masque")
    egal(changement.apres, "5 masques (+ Claude · Ciel, Claude · Dégradé, Claude · Rond, Claude · Plage)")

    Commandes.executer('annuler', {})
    egal(#photo.reglages.MaskGroupBasedCorrections, 1)

    photo.reglages.PerspectiveUpright = 1
    resultat = Commandes.executer('masquer', { masques = Json.tableau({ { type = 'lineaire', de_x = 0, de_y = 0, a_x = 0, a_y = 1, nom = 'n', locaux = {} } }) })
    egal(contient(resultat.resultats[1].remarques, "Upright ou perspective active, sans recalage"), true)

    S.prefs.mode = 'proposer'
    echoue(function() Commandes.executer('masquer', { masques = Json.tableau({ { type = 'ia', soustype = 1, nom = 'n', locaux = {} } }) }) end, "add_mask avec confirm")
end)

-- Constaté sur XH2S0500.RAF (Copie 1) : un masque IA ajouté à cinq masques IA n'en laissait qu'un.
test("masquer : courbe et grain locaux rangés dans la correction, et relus", function()
    local photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', { masques = { { type = 'luminance', min = 0.2, max = 0.8, nom = 'Claude · Tons moyens',
        locaux = { LocalGrain = 0.2, MainCurve = Json.tableau({ '0,10', '128,140', '255,245' }) } } }, etape = 'local' })
    local correction = photo.reglages.MaskGroupBasedCorrections[1]
    egal(correction.LocalGrain, 0.2)
    egal(correction.MainCurve[2], '128,140', "un tableau de textes « x,y »")
    local masque = Commandes.executer('reglages', { cles = {}, details = true }).masques[1]
    egal(masque.reglages_locaux.MainCurve, "3 points")
    egal(masque.reglages_locaux.LocalGrain, 0.2)
    egal(masque.reglages_locaux.LocalCurveRefineSaturation, nil, "à 100, rien à dire")
end)

test("masquer : pinceau et objet comme Lightroom les range, positions dans le fichier", function()
    -- Relevé dans Lightroom Classic 15.6 sur des masques Pinceau et Objets faits à la main.
    local photo = photoFuji()
    S.active = photo
    S.calculDiffere, S.jamaisCalcule = true, true
    Commandes.executer('masquer', { masques = {
        { type = 'pinceau', nom = 'Claude · Pinceau', auto = false, locaux = { LocalExposure2012 = -0.1 },
            traits = { { points = { { 0.2, 0.5 }, { 0.3, 0.5 } }, rayon = 0.03, durete = 0.4, flux = 0.5 } } },
        { type = 'objet', nom = 'Claude · Objet', locaux = { LocalExposure2012 = 0.05 },
            traits = { { points = { { 0.55, 0.26 }, { 0.55, 0.54 } }, rayon = 0.025 } } },
    }, etape = 'pinceau' })
    local corrections = photo.reglages.MaskGroupBasedCorrections
    local agregat = corrections[1].CorrectionMasks[1]
    egal(agregat.What, 'Mask/Aggregate')
    egal(agregat.MaskName, 'Claude · Pinceau')
    local trait = agregat.Masks[1]
    egal(trait.What, 'Mask/Paint')
    egal(trait.MaskName, nil)
    proche(trait.Radius, 0.03, "rayon rapporté au grand côté, aperçu et fichier de même largeur")
    egal(trait.Dabs[1], 'r 0.030000')
    egal(trait.Dabs[2], 'f 0.5000')
    egal(trait.Dabs[3], 'h 0.4000')
    egal(trait.Dabs[4], 'd 0.200000 0.500000')
    egal(trait.Dabs[#trait.Dabs], 'd 0.300000 0.500000')
    -- 0,1 de 6240 px = 624 px, touches tous les 0,2 × 187 px = 37 px : 17 pas.
    egal(#trait.Dabs, 4 + 17)
    local objet = corrections[2].CorrectionMasks[1]
    egal(objet.What, 'Mask/Image')
    egal(objet.MaskSubType, 0)
    egal(objet.MaskSubCategoryID, nil)
    egal(objet.Gesture[1].What, 'Mask/Paint')
    egal(objet.Gesture[1].Radius, 0)
    egal(objet.Gesture[1].Dabs[1], 'r 0.025000')
    egal(objet.ReferencePoint, '0.550000 0.400000')
    egal(photo.appliques[#photo.appliques].preset ~= nil, true, "l'objet est un masque IA : par un paramètre prédéfini du module")
    egal(objet.MaskDigest, 'calculé pour 4', "calculé tout de suite (updateAISettings)")
end)

test("masquer : un masque IA que Lightroom n'a pas su calculer est dit, et n'attend plus rien", function()
    -- Constaté le 17 octobre 2026 : un objet désigné par un trait large rangé ErrorReason = 1, sans MaskDigest.
    local photo = photoFuji()
    S.active = photo
    S.calculDiffere, S.jamaisCalcule = true, true
    S.pendantMiseAJourIA = function(p)
        for _, c in ipairs(p.reglages.MaskGroupBasedCorrections or {}) do
            for _, m in ipairs(c.CorrectionMasks) do
                if m.Gesture then m.ErrorReason = 1 end
            end
        end
    end
    S.modelesIAAbsents = true
    local resultat = Commandes.executer('masquer', { masques = { { type = 'objet', nom = 'Claude · Objet', locaux = {},
        traits = { { points = { { 0.5, 0.3 }, { 0.5, 0.6 } }, rayon = 0.05 } } } }, etape = 'objet' })
    egal(contient(resultat.resultats[1].remarques, "n'a pas su calculer le masque « Claude · Objet »"), true)
    egal(resultat.a_savoir, nil, "rien n'attend le rendu")
    S.attentes = 0
    Commandes.executer('apercu', { taille = 1344, cles = {} })
    egal(S.attentes, 0)
end)

test("masquer : un masque IA s'ajoute aux masques IA déjà calculés", function()
    local photo = photoFuji()
    local existants = {}
    for i, categorie in ipairs({ 50001, 50002, 50004, 50006, 50007 }) do
        local nom = 'Claude · Paysage ' .. i
        existants[i] = Locaux.correction(nom, 1, { LocalExposure2012 = 0.1 }, { Locaux.masqueIA(0, categorie, nom, false) })
        existants[i].CorrectionMasks[1].MaskDigest = 'D' .. i
    end
    photo.reglages.MaskGroupBasedCorrections = existants
    S.active = photo
    local resultat = Commandes.executer('masquer', {
        masques = Json.tableau({ { type = 'ia', soustype = 0, categorie = 50005, nom = 'Claude · Végétation', locaux = { LocalSaturation = 0.1 } } }),
        etape = 'végétation',
    })
    local masques = photo.reglages.MaskGroupBasedCorrections
    egal(#masques, 6, "les cinq masques restent")
    for i = 1, 5 do
        egal(masques[i].CorrectionName, 'Claude · Paysage ' .. i)
        egal(masques[i].CorrectionMasks[1].MaskDigest, 'D' .. i, "déjà calculé pour la photo : gardé tel quel")
    end
    egal(masques[6].CorrectionMasks[1].MaskSubCategoryID, 50005)
    egal(masques[6].CorrectionMasks[1].MaskDigest, 'calculé pour 4', "le nouveau masque est calculé")
    egal(resultat.resultats[1].changements[1].apres, "6 masques (+ Claude · Végétation)")

    Commandes.executer('annuler', {})
    egal(#photo.reglages.MaskGroupBasedCorrections, 5)
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].MaskDigest, 'D1')

    Commandes.executer('essayer', { action = 'masquer', masques = Json.tableau({ { type = 'ia', soustype = 2, nom = 'n', locaux = {} } }) })
    egal(#S.dernierExport.reglagesRendus.MaskGroupBasedCorrections, 6, "la proposition montre tous les masques")
    egal(#photo.reglages.MaskGroupBasedCorrections, 5, "puis la photo est remise comme avant")
    egal(photo.reglages.MaskGroupBasedCorrections[5].CorrectionMasks[1].MaskDigest, 'D5')

    local presets = #S.presetsCrees
    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.4, nom = 'Claude · Dégradé', locaux = {} } }) })
    egal(#photo.reglages.MaskGroupBasedCorrections, 6, "un dégradé seul s'ajoute aussi")
    egal(#S.presetsCrees, presets, "sans masque IA, pas de paramètre prédéfini")
end)

test("retoucher : taches avec source par défaut, yeux rouges, photo tournée", function()
    local photo = photoFuji()
    S.active = photo
    Commandes.executer('retoucher', {
        taches = Json.tableau({ { x = 0.2, y = 0.3, rayon = 0.01, mode = 'heal', fondu = 0.43 } }),
        yeux = Json.tableau({ { x = 0.5, y = 0.5, rayon = 0.005, pupille = 0.5, assombrir = 0.5 } }),
        etape = 'taches',
    })
    local tache = photo.reglages.RetouchAreas[1]
    proche(tache.centerX, 0.2) proche(tache.centerY, 0.3)
    proche(tache.radius, 0.01)
    proche(tache.sourceX, 0.225)
    local oeil = photo.reglages.RedEyeInfo[1]
    proche(oeil.pupil.ellipse.centerX, 0.5)
    proche(oeil.pupil.ellipse.sizeX, 0.005)
    proche(oeil.pupil.ellipse.sizeY, 31.2 / 4160)
    Commandes.executer('annuler', {})
    egal(#photo.reglages.RetouchAreas, 0)
    egal(type(photo.reglages.RetouchInfo), 'table', "liste vide : l'ancienne forme est vidée aussi")

    local verticale = S.Photo(6, { Temperature = 5000, WhiteBalance = 'As Shot' }, { fileName = 'V.RAF', fileFormat = 'RAW' },
        { dimensions = { width = 4160, height = 6240 }, orientation = 'DA' })
    Commandes.executer('retoucher', { photo = 6, taches = Json.tableau({ { x = 0.2, y = 0.3, rayon = 0.01 } }) })
    proche(verticale.reglages.RetouchAreas[1].centerX, 0.7)
    proche(verticale.reglages.RetouchAreas[1].centerY, 0.2)
end)

-- Constaté dans Lightroom Classic 15.6 : Lightroom range les positions des masques, des taches et
-- des yeux rouges avant la correction de profil d'objectif (jusqu'à 26 px au bord d'un RAW de
-- 6240 px, 0 px une fois le profil coupé). Le serveur mesure ce déplacement sur deux rendus
-- (commande « geometrie ») et le donne en grille ; sans elle, les positions restaient décalées.
local function grilleDecalee(dx, dy)
    return { colonnes = 2, lignes = 2, x = Json.tableau({ dx, 1 + dx, dx, 1 + dx }), y = Json.tableau({ dy, dy, 1 + dy, 1 + dy }) }
end

test("retoucher : sur une photo qui porte RemoveAreas, les taches y vont aussi, et l'annulation la remet", function()
    -- Relevé dans Lightroom Classic 15.6 : RemoveAreas, quand il existe, est lu avant RetouchAreas,
    -- qui en est dérivé (sans les taches à détection d'objet).
    local objet = { SpotType = 'heal_patchmatch', fill_method = 'patchmatch', Masks = { { What = 'Mask/Image' } } }
    local cercle = { SpotType = 'heal', Masks = { { What = 'Mask/Ellipse', X = 0.2, Y = 0.2 } } }
    local photo = S.Photo(7, { RemoveAreas = { objet, cercle }, RetouchAreas = { cercle }, Exposure2012 = 0 },
        { fileName = 'DSCF0001.RAF', fileFormat = 'RAW' }, { dimensions = { width = 6000, height = 4000 } })
    S.active = photo
    Commandes.executer('retoucher', { taches = { { x = 0.5, y = 0.5, rayon = 0.01, mode = 'heal' } }, yeux = {}, etape = 'tache' })
    egal(#photo.reglages.RemoveAreas, 3, "la tache rejoint RemoveAreas")
    egal(#photo.reglages.RetouchAreas, 2, "et RetouchAreas, dérivé sans la tache à détection d'objet")
    Commandes.executer('annuler', {})
    egal(#photo.reglages.RemoveAreas, 2, "RemoveAreas d'avant")
    egal(photo.reglages.RemoveAreas[1].SpotType, 'heal_patchmatch')
    egal(#photo.reglages.RetouchAreas, 1)
end)

-- Constaté en 2.3 (Lightroom Classic 15.6) : une tache Supprimer faite à la main, objet détecté, est
-- dans RemoveAreas seulement (pas de RetouchAreas) ; une tache Supprimer de Claude va dans les deux,
-- et l'annulation rend exactement l'état fait à la main.
test("retoucher : tache Supprimer de Claude sur une photo qui n'a qu'une tache Supprimer faite à la main", function()
    local objet = { SpotType = 'heal_patchmatch', Method = 'poisson', SourceState = 'sourceAutoComputed',
        Masks = { { What = 'Mask/Image', ReferencePoint = '0.670502 0.123274' } } }
    local photo = S.Photo(9, { RemoveAreas = { objet }, Exposure2012 = 0 },
        { fileName = 'DSCF4961.RAF', fileFormat = 'RAW' }, { dimensions = { width = 6240, height = 4160 } })
    S.active = photo
    Commandes.executer('retoucher', { taches = { { x = 0.78, y = 0.21, rayon = 0.015, mode = 'remove' } }, yeux = {}, etape = 'tache supprimer' })
    egal(#photo.reglages.RemoveAreas, 2, "la tache de Claude rejoint RemoveAreas")
    egal(photo.reglages.RemoveAreas[2].SpotType, 'heal_patchmatch')
    egal(#photo.reglages.RetouchAreas, 1, "RetouchAreas : la seule tache de Claude")
    local annule = Commandes.executer('annuler', {})
    egal(#photo.reglages.RemoveAreas, 1, "la tache faite à la main reste")
    egal(photo.reglages.RemoveAreas[1].Masks[1].ReferencePoint, '0.670502 0.123274')
    egal(#(photo.reglages.RetouchAreas or {}), 0)
    egal(annule.resultats[1].reglages_remis.RetouchAreas, "0 tache")
end)

test("retoucher : mode Supprimer sans IA générative, calculé par Lightroom, puis annulé", function()
    -- Relevé dans Lightroom Classic 15.6 : SpotType heal_patchmatch, fill_method patchmatch (une autre
    -- valeur pour le génératif), Method poisson ; le remplissage (pm_patch…) est calculé par Lightroom.
    local photo = photoFuji()
    S.active = photo
    S.miseAJourIA = false
    local ecrite = photoFuji()
    S.active = ecrite
    Commandes.executer('retoucher', { taches = { { x = 0.4, y = 0.4, rayon = 0.01, mode = 'remove' } }, yeux = {}, etape = 'supprimer' })
    egal(ecrite.reglages.RetouchAreas[1].fill_method, 'patchmatch', "écrite sans IA générative")
    S.miseAJourIA = true
    S.active = photo
    local resultat = Commandes.executer('retoucher', { taches = { { x = 0.4, y = 0.4, rayon = 0.01, mode = 'remove' } }, yeux = {}, etape = 'supprimer' })
    local tache = photo.reglages.RetouchAreas[1]
    egal(tache.SpotType, 'heal_patchmatch')
    egal(tache.fill_method, nil, "calculée : Lightroom retire fill_method (patchmatch par défaut)")
    egal(tache.Method, 'poisson')
    egal(tache.pm_patch ~= nil, true, "calculé tout de suite (updateAISettings)")
    egal(#resultat.resultats[1].changements, 1)
    Commandes.executer('annuler', {})
    egal(next(photo.reglages.RetouchAreas or {}), nil)
end)

test("Geometrie : recalage par la grille du serveur, photo tournée et recadrée comprise", function()
    local ctx = Geometrie.contexte(6240, 4160, 'AB', nil, grilleDecalee(0.01, -0.02))
    local x, y = Geometrie.point(ctx, 0.5, 0.5)
    proche(x, 0.51) proche(y, 0.48)
    proche(Geometrie.ecart(ctx), math.sqrt((0.01 * 6240) ^ 2 + (0.02 * 4160) ^ 2))
    -- Photo verticale (DA) : la grille porte sur l'image affichée ; sans recalage, (0,5 ; 0,25)
    -- affiché donne (0,75 ; 0,5) dans le fichier.
    ctx = Geometrie.contexte(4160, 6240, 'DA', nil, grilleDecalee(0.01, 0))
    x, y = Geometrie.point(ctx, 0.5, 0.25)
    proche(x, 0.75) proche(y, 0.51)
    -- Recadrée : la grille porte sur l'image entière, le cadre est passé avant.
    ctx = Geometrie.contexte(6240, 4160, 'AB', { CropLeft = 0.1, CropTop = 0, CropRight = 0.9, CropBottom = 1, CropAngle = 0 },
        grilleDecalee(0.01, 0))
    x = Geometrie.point(ctx, 0.5, 0.5)
    proche(x, 0.51)
    egal(Geometrie.grille({ colonnes = 2, lignes = 2, x = Json.tableau({ 0, 1 }), y = Json.tableau({ 0, 0, 1, 1 }) }), nil,
        "grille incomplète refusée")
    egal(Geometrie.contexte(6240, 4160, 'AB').recalage, nil)
end)

test("retoucher et masquer : positions recalées sur la correction d'objectif, empreinte vérifiée", function()
    local photo = photoFuji()
    photo.reglages.LensProfileEnable = 1
    S.active = photo
    local info = Commandes.executer('geometrie', {}).photos[1]
    egal(info.active, true)
    egal(info.chemin_corrige, nil, "sans rendre : l'empreinte seulement")
    local grille = grilleDecalee(0.01, 0)
    grille.empreinte = info.empreinte
    local recalages = { [tostring(photo.localIdentifier)] = grille }
    local taches = Json.tableau({ { x = 0.2, y = 0.3, rayon = 0.01 } })
    local resultat = Commandes.executer('retoucher', { taches = taches, yeux = Json.tableau({ { x = 0.5, y = 0.5, rayon = 0.005 } }),
        recalages = recalages, etape = 'taches' })
    proche(photo.reglages.RetouchAreas[1].centerX, 0.21)
    proche(photo.reglages.RedEyeInfo[1].pupil.ellipse.centerX, 0.51)
    egal(contient(resultat.resultats[1].remarques, "Positions recalées"), true)
    Commandes.executer('annuler', {})

    -- La géométrie a changé depuis le calcul de la grille : elle ne vaut plus, et Claude le sait.
    photo.reglages.LensProfileDistortionScale = 50
    resultat = Commandes.executer('retoucher', { taches = taches, recalages = recalages, etape = 'taches' })
    proche(photo.reglages.RetouchAreas[1].centerX, 0.2)
    egal(contient(resultat.resultats[1].remarques, "sans recalage"), true)
    Commandes.executer('annuler', {})
    photo.reglages.LensProfileDistortionScale = nil

    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'radial', centre_x = 0.5, centre_y = 0.5, rayon_x = 0.1,
        nom = 'Rond', locaux = {} } }), recalages = recalages, etape = 'rond' })
    local masques = photo.reglages.MaskGroupBasedCorrections
    local radial = masques[#masques].CorrectionMasks[1]
    proche((radial.Left + radial.Right) / 2, 0.51)
end)

test("geometrie : deux rendus non recadrés, avec puis sans corrections, photo remise", function()
    local photo = photoFuji()
    S.active = photo
    local info = Commandes.executer('geometrie', { rendre = true }).photos[1]
    egal(info.active, false, "sans correction géométrique : rien à rendre")
    egal(#S.rendus, 0)

    photo.reglages.LensProfileEnable = 1
    photo.reglages.CropLeft, photo.reglages.CropTop, photo.reglages.CropRight, photo.reglages.CropBottom = 0.1, 0, 0.9, 1
    photo.reglages.CropAngle = 2
    info = Commandes.executer('geometrie', { photos = { photo.localIdentifier }, rendre = true, taille = 2048 }).photos[1]
    egal(info.active, true)
    egal(type(info.chemin_corrige), 'string')
    egal(type(info.chemin_origine), 'string')
    egal(#S.rendus, 2)
    local corrige, origine = S.rendus[1].reglagesRendus, S.rendus[2].reglagesRendus
    egal(corrige.CropLeft, 0) egal(corrige.CropAngle, 0) egal(corrige.LensProfileEnable, 1)
    egal(origine.CropLeft, 0) egal(origine.LensProfileEnable, 0) egal(origine.PerspectiveUpright, 0)
    egal(S.rendus[1].exportSettings.LR_size_maxWidth, 2048)
    egal(photo.reglages.LensProfileEnable, 1, "photo remise")
    egal(photo.reglages.CropLeft, 0.1)
    egal(photo.reglages.CropAngle, 2)
    egal(S.ecritures[#S.ecritures], "Claude · recalage (retour)")

    Liaison.pause = true
    echoue(function() Commandes.executer('geometrie', { rendre = true }) end, "en pause")
    Liaison.pause = false
end)

test("copier : réglages, balance entre RAW et JPEG, profil, masques à recalculer", function()
    local source = photoFuji()
    source.reglages.Exposure2012 = 0.5
    source.reglages.Temperature = 6000
    source.reglages.Look = { Name = 'Adobe Vivid', UUID = 'V' }
    source.reglages.MaskGroupBasedCorrections = { { What = 'Correction', CorrectionMasks = { { What = 'Mask/Image', MaskSubType = 1, InputDigest = 'X', MaskDigest = 'Y' } } } }
    local cible = S.Photo(5, { Temperature = 5000, Tint = 0, Exposure2012 = 0, WhiteBalance = 'As Shot', CameraProfile = 'Adobe Standard', Look = ADOBE_COLOR },
        { fileName = 'C.RAF', fileFormat = 'RAW' })
    local jpeg = photoJpeg()
    local resultat = Commandes.executer('copier', {
        source = 4, photos = { 5, 2, 4 }, cles = { 'Exposure2012', 'Temperature' },
        inclure = { profil = true, masques = true }, etape = 'copie', raison = "Même lumière.",
    })
    egal(#resultat.resultats, 2, "la source n'est pas visée")
    egal(cible.reglages.Exposure2012, 0.5)
    egal(cible.reglages.Temperature, 6000)
    egal(cible.reglages.Look.Name, 'Adobe Vivid')
    local ia = cible.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1]
    egal(ia.InputDigest, nil, "empreintes de la source retirées")
    egal(ia.MaskDigest, 'calculé pour 5', "masque IA recalculé pour la photo, par un paramètre prédéfini")
    egal(jpeg.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].MaskDigest, 'calculé pour 2')
    egal(#S.presetsCrees, 1, "un paramètre prédéfini pour toutes les photos de la copie")
    egal(jpeg.reglages.Exposure2012, 0.5)
    egal(jpeg.reglages.IncrementalTemperature, 0, "balance non copiée vers un JPEG")
    egal(contient(resultat.resultats[2].remarques, "Balance des blancs non copiée"), true)
    egal(contient(resultat.resultats[2].remarques, "Profil non copié"), true)

    Commandes.executer('annuler', { photos = { 5 } })
    egal(cible.reglages.Exposure2012, 0)
    egal(cible.reglages.Look.Name, 'Adobe Color')
    egal(#cible.reglages.MaskGroupBasedCorrections, 0)
end)

-- Version 1.2 : proposition, comparaison, presets, journal ----------------------------

test("essayer : applique, rend, remet comme avant, sans rien mémoriser", function()
    local photo = photoFuji()
    S.active = photo
    S.prefs.mode = 'proposer'
    local resultat = Commandes.executer('essayer', {
        action = 'appliquer', reglages = { Exposure2012 = 0.8 }, plages = { Exposure2012 = { -5, 5 } },
        taille = 1344, comparer = true, etape = 'plus clair',
    })
    egal(photo.reglages.Exposure2012, 0, "remise comme avant")
    egal(#photo.appliques, 2)
    egal(photo.appliques[1].nom, 'Claude · essai : plus clair')
    egal(photo.appliques[2].nom, "Claude · fin de l'essai")
    egal(#S.rendus, 2, "état actuel puis proposition")
    egal(resultat.chemin ~= nil and resultat.chemin_actuel ~= nil, true)
    egal(resultat.changements[1].apres, 0.8)
    egal(photo.proprietes.avantClaude, nil, "rien de mémorisé")
    egal(photo.proprietes.journalClaude, nil)

    resultat = Commandes.executer('essayer', { action = 'masquer', masques = Json.tableau({ { type = 'ia', soustype = 2, nom = 'n', locaux = {} } }) })
    egal(photo.reglages.MaskGroupBasedCorrections and #photo.reglages.MaskGroupBasedCorrections or 0, 0, "masque retiré après l'essai")

    resultat = Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0 } })
    egal(contient(resultat.remarques, "Rien ne changerait"), true)

    Liaison.pause = true
    echoue(function() Commandes.executer('essayer', { reglages = { Exposure2012 = 1 } }) end, "en pause")
end)

test("essayer : une erreur après l'application (instantané impossible) remet quand même la photo", function()
    local photo = photoFuji()
    S.active = photo
    -- Entre l'application et la remise, l'instantané d'une variante échoue : la photo doit
    -- revenir comme avant, et l'erreur partir vers le serveur.
    photo.createDevelopSnapshot = function() error("instantané impossible", 0) end
    echoue(function()
        Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.8 }, plages = { Exposure2012 = { -5, 5 } },
            instantane = 'chaude', etape = 'plus clair' })
    end, "instantané impossible")
    egal(photo.reglages.Exposure2012, 0, "remise comme avant malgré l'erreur")
    egal(photo.appliques[#photo.appliques].nom, "Claude · fin de l'essai")
end)

test("balance personnalisée : gardée par les masques IA, la tonalité auto et leur essai", function()
    local photo = photoFuji()
    photo.reglages.WhiteBalance, photo.reglages.Temperature, photo.reglages.Tint = 'Custom', 5700, 12
    S.active = photo
    local function ciel()
        return Json.tableau({ { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } } })
    end

    Commandes.executer('masquer', { masques = ciel(), etape = 'ciel' })
    egal(photo.reglages.Temperature, 5700, "température gardée après le masque IA")
    egal(photo.reglages.Tint, 12, "teinte gardée")
    egal(photo.appliques[2].reglages.Temperature, 5700, "reposée après le paramètre prédéfini")
    photo.reglages.Temperature, photo.reglages.Tint = 2000, -150
    Commandes.executer('annuler', {})
    egal(photo.reglages.Temperature, 5700, "l'annulation connaît la balance")
    egal(photo.reglages.Tint, 12)
    egal(#photo.reglages.MaskGroupBasedCorrections, 0)

    local avant = #photo.appliques
    appliquer({ auto_ton = true, etape = 'tonalité auto' })
    egal(photo.reglages.Temperature, 5700, "gardée après la tonalité automatique")
    egal(photo.reglages.Tint, 12)
    egal(#photo.appliques, avant + 2, "reposée avec les réglages, en une étape")
    appliquer({ auto_ton = true, reglages = { Temperature = 6100 }, etape = 'tonalité auto et température' })
    egal(photo.reglages.Temperature, 6100, "la nouvelle température")
    egal(photo.reglages.Tint, 12, "la teinte d'avant, pas la butée")

    Commandes.executer('essayer', { action = 'masquer', masques = ciel() })
    egal(photo.reglages.Temperature, 6100, "gardée après l'essai d'un masque IA")
    egal(photo.reglages.Tint, 12)

    appliquer({ balance = 'Auto', auto_ton = true, etape = 'balance auto' })
    egal(photo.reglages.WhiteBalance, 'Auto', "un préréglage n'est pas reposé en personnalisé")

    local telleQuelle = photoFuji()
    S.active = telleQuelle
    Commandes.executer('masquer', { masques = ciel() })
    egal(#telleQuelle.appliques, 1, "balance « Telle quelle » : rien à reposer")
    egal(telleQuelle.reglages.Temperature, 5350)
end)

test("apercu : pleine résolution et comparaison avec l'avant-Claude", function()
    local photo = photoFuji()
    S.active = photo
    echoue(function() Commandes.executer('apercu', { comparer = 'avantClaude' }) end, "rien à comparer")
    appliquer({ reglages = { Exposure2012 = 0.5 }, plages = { Exposure2012 = { -5, 5 } } })
    local resultat = Commandes.executer('apercu', { comparer = 'avantClaude', taille = 800, cles = { 'Exposure2012' } })
    egal(resultat.chemin_avant ~= nil, true)
    egal(photo.reglages.Exposure2012, 0.5, "état actuel remis")
    egal(photo.appliques[2].nom, "Claude · comparaison (avant)")
    egal(photo.appliques[2].reglages.Exposure2012, 0)
    egal(photo.appliques[3].reglages.Exposure2012, 0.5)
    egal(#S.rendus, 2)

    Commandes.executer('apercu', { taille = 0 })
    egal(S.dernierExport.exportSettings.LR_size_doConstrain, false, "pleine résolution")
end)

test("presets : liste filtrée et création depuis une photo", function()
    S.presets = {
        { nom = 'Adobe : Paysage', presets = { { nom = 'Été doré', uuid = 'A1', reglages = {} }, { nom = 'Hiver', uuid = 'A2', reglages = {} } } },
        { nom = 'Mes presets', presets = { { nom = 'Portrait', uuid = 'M1', reglages = {} } } },
    }
    local liste = Commandes.executer('presets', { filtre = 'été', limite = 10 })
    egal(liste.total, 1)
    egal(liste.presets[1].uuid, 'A1')
    egal(Commandes.executer('presets', { filtre = 'mes presets' }).total, 1, "par le nom du dossier")
    egal(Commandes.executer('presets', { limite = 2 }).renvoyes, 2)

    local photo = photoFuji()
    S.active = photo
    local resultat = Commandes.executer('creerPreset', { nom = 'Bateau', cles = { 'Exposure2012', 'Temperature' }, inclure = { profil = true } })
    local reglages = resultat.reglages
    egal(reglages.Exposure2012, 0)
    egal(reglages.Temperature, 5350)
    egal(reglages.WhiteBalance, 'As Shot')
    egal(reglages.Look.Name, 'Adobe Color')
    egal(reglages.ProcessVersion, '15.4')
    egal(reglages.CameraProfile, 'Adobe Standard')
    egal(#S.presetsCrees, 0, "le serveur écrit le fichier, pas le module")
end)

test("journal : retouche avec raison, annulation, retour à l'avant-Claude", function()
    local photo = photoFuji()
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.4 }, plages = { Exposure2012 = { -5, 5 } }, raison = "Un peu sombre." })
    Commandes.executer('annuler', {})
    appliquer({ reglages = { Exposure2012 = 0.2 }, plages = { Exposure2012 = { -5, 5 } }, etape = 'passe 2' })
    Commandes.executer('revenir', {})
    local journal = Commandes.executer('journal', {}).photos[1]
    egal(journal.photo.fichier, 'XH2S0320.RAF (Copie 1)')
    egal(#journal.entrees, 4)
    egal(journal.entrees[1].raison, "Un peu sombre.")
    egal(journal.entrees[1].changements[1].apres, 0.4)
    egal(journal.entrees[2].type, 'annulation')
    egal(journal.entrees[4].etape, "Retour à l'état d'avant Claude")
    egal(photo.proprietes.avantClaude, nil, "l'historique de Claude est oublié…")
    egal(photo.proprietes.journalClaude ~= nil, true, "…mais pas le journal")
end)

-- Analyse et recette ---------------------------------------------------------------------

test("apercu : attend le calcul des masques IA avant d'exporter", function()
    -- Lightroom sans photo:updateAISettings (avant 13.3, refusé depuis la 2.6 ; le chemin reste) : la
    -- fenêtre au rendu, et le clic de l'utilisateur.
    S.miseAJourIA = false
    local photo = photoFuji()
    S.active = photo
    S.calculDiffere = true
    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'ia', soustype = 2, nom = 'Ciel', locaux = {} } }) })
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].MaskDigest, nil, "pas encore calculé")
    local resultat = Commandes.executer('apercu', { taille = 1344, cles = {} })
    egal(S.attentes, 1, "une attente, le temps du calcul")
    egal(resultat.a_savoir, nil)

    -- Lightroom ne calcule rien de lui-même : la fenêtre « Mises à jour IA recommandées » s'ouvre à
    -- l'exportation, l'utilisateur y clique Exporter, et Lightroom calcule avant de rendre.
    S.jamaisCalcule = true
    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'ia', soustype = 1, nom = 'Sujet', locaux = {} } }) })
    S.attentes = 0
    resultat = Commandes.executer('apercu', { taille = 1344, cles = {} })
    egal(S.attentes, 40, "une dizaine de secondes au plus")
    egal(#S.fenetresIA, 1, "la fenêtre s'est ouverte")
    egal(S.fenetresIA[1].photo, 'XH2S0320.RAF')
    egal(resultat.a_savoir, nil, "masques calculés pendant l'exportation")
    egal(contient(Liaison.journal, "Réglages IA mis à jour pendant l'exportation"), true)
    egal(#S.rendus, 2)

    -- Une photo qui n'est pas affichée : Lightroom ne calcule rien de lui-même, l'exportation le fait.
    local autre = photoRaw()
    autre.reglages.MaskGroupBasedCorrections = photo.reglages.MaskGroupBasedCorrections
    S.attentes = 0
    resultat = Commandes.executer('apercu', { photo = autre.localIdentifier, taille = 1344, cles = {} })
    egal(S.attentes, 0, "pas d'attente inutile")
    egal(resultat.a_savoir, nil)
end)

test("rendu : sans clic de l'utilisateur, la fenêtre des mises à jour IA retient la réponse", function()
    -- Lightroom sans photo:updateAISettings (avant 13.3, refusé depuis la 2.6 ; le chemin reste) : la
    -- fenêtre au rendu, et le clic de l'utilisateur.
    S.miseAJourIA = false
    local photo = photoFuji()
    S.active = photo
    S.calculDiffere, S.jamaisCalcule, S.clicUtilisateur = true, true, false
    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'ia', soustype = 2, nom = 'Ciel', locaux = {} } }) })
    echoue(function() Commandes.executer('apercu', { taille = 1344, cles = {} }) end, "attend un clic")
    egal(S.fenetresIA[1].photo, 'XH2S0320.RAF')

    S.renduImpossible = "disque plein"
    S.clicUtilisateur = true
    echoue(function() Commandes.executer('apercu', { taille = 1344, cles = {} }) end, "disque plein")
end)

test("essayer : un ciel pas encore calculé ne retient plus la proposition, et la photo est remise", function()
    -- Lightroom sans photo:updateAISettings (avant 13.3, refusé depuis la 2.6 ; le chemin reste) : la
    -- fenêtre au rendu, et le clic de l'utilisateur.
    S.miseAJourIA = false
    -- Constaté le 16 octobre 2026 : add_mask (preview, compare) d'un ciel, photo pas affichée dans
    -- Développement ; la fenêtre a retenu la réponse et les masques de l'essai sont restés.
    local photo = photoFuji()
    S.active = photo
    S.calculDiffere, S.jamaisCalcule = true, true
    local resultat = Commandes.executer('essayer', { action = 'masquer', comparer = true,
        masques = Json.tableau({ { type = 'ia', soustype = 2, nom = 'Ciel', locaux = {} },
            { type = 'lineaire', de_x = 0.5, de_y = 1, a_x = 0.5, a_y = 0.84, nom = 'Premier plan', locaux = {} } }) })
    egal(resultat.chemin ~= nil and resultat.chemin_actuel ~= nil, true, "état actuel puis proposition")
    egal(#S.fenetresIA, 1, "une fenêtre, au rendu de la proposition")
    egal(photo.reglages.MaskGroupBasedCorrections and #photo.reglages.MaskGroupBasedCorrections or 0, 0, "masques de l'essai retirés")
end)

test("appliquer : flou d'objectif par un paramètre prédéfini, balance gardée, annulation, retrait", function()
    -- Lightroom sans photo:updateAISettings (avant 13.3, refusé depuis la 2.6 ; le chemin reste) : la
    -- fenêtre au rendu, et le clic de l'utilisateur.
    S.miseAJourIA = false
    local photo = photoFuji()
    photo.reglages.WhiteBalance, photo.reglages.Temperature, photo.reglages.Tint = 'Custom', 5700, 12
    S.active = photo
    local resultat = appliquer({ flou_objectif = { intensite = 40 }, etape = 'flou' })
    local flou = photo.reglages.LensBlur
    egal(flou.Active, true)
    egal(flou.BlurAmount, 40)
    egal(flou.FocalRangeSource, 1, "mise au point sur le sujet")
    egal(flou.FocalRange, '-80 0 55 135', "comme Lightroom : fondus de 80")
    egal(flou.Version, 1)
    egal(photo.appliques[1].preset:find("Claude · flou d'objectif", 1, true) ~= nil, true, "par un paramètre prédéfini du module")
    egal(photo.reglages.Temperature, 5700, "la balance personnalisée reste")
    egal(photo.reglages.DepthMapInfo ~= nil, true, "Lightroom calcule la profondeur")
    egal(resultat.resultats[1].changements[1].apres, "intensité 40, mise au point sur le sujet")
    egal(resultat.resultats[1].changements[1].avant, "inactif")

    local regle = appliquer({ flou_objectif = { intensite = 60, proche = 20, loin = 45 }, etape = 'flou réglé' })
    egal(photo.reglages.LensBlur.FocalRange, '-60 20 45 125')
    egal(photo.reglages.LensBlur.FocalRangeSource, 3, "zone nette manuelle, rangée à 3 par Lightroom")
    egal(tostring(regle.resultats[1].changements[1].apres):find("zone nette 20 45", 1, true) ~= nil, true, "décrite comme une zone nette")
    Commandes.executer('annuler', {})
    egal(photo.reglages.LensBlur.BlurAmount, 40, "retour au flou d'avant")

    local avant = #S.presetsCrees
    appliquer({ flou_objectif = { retirer = true }, etape = 'sans flou' })
    egal(photo.reglages.LensBlur.Active, false)
    egal(photo.reglages.LensBlur.BlurAmount, 40, "désactivé, réglages gardés")
    egal(#S.presetsCrees, avant, "retirer ne demande aucun calcul")
    egal(Commandes.executer('reglages', { cles = {}, details = true }).flou_objectif, "inactif")

    S.calculDiffere = true
    appliquer({ flou_objectif = { intensite = 30 }, etape = 'flou' })
    photo.reglages.DepthMapInfo = nil
    S.attentes = 0
    Commandes.executer('apercu', { taille = 1344, cles = {} })
    egal(S.attentes, 1, "l'aperçu attend la carte de profondeur")
end)

test("appliquer : forme du bokeh sur un flou déjà posé, le reste du flou gardé", function()
    local photo = photoFuji()
    S.active = photo
    appliquer({ flou_objectif = { intensite = 40, proche = 20, loin = 45 }, etape = 'flou' })
    -- Champs de la forme « Ring » (relevés dans Camera Raw, Lightroom Classic 15.6), tels que le serveur les envoie.
    local resultat = appliquer({ flou_objectif = { bokeh = { nom = "anneau", champs = { BokehShape = 1, BokehShapeDetail = 3, BokehAspect = 0,
        BokehRotation = 0, SphericalAberration = 25, CatEyeScale = 100 } }, oeil_de_chat = 30 }, etape = 'bokeh' })
    local flou = photo.reglages.LensBlur
    egal(flou.BokehShape, 1)
    egal(flou.BokehShapeDetail, 3)
    egal(flou.SphericalAberration, 25)
    egal(flou.CatEyeAmount, 30)
    egal(flou.BlurAmount, 40, "l'intensité reste")
    egal(flou.FocalRange, '-60 20 45 125', "la zone nette reste")
    egal(flou.FocalRangeSource, 3)
    egal(tostring(resultat.resultats[1].changements[1].apres):find("bokeh anneau", 1, true) ~= nil, true)
    Commandes.executer('annuler', {})
    egal(photo.reglages.LensBlur.BokehShape, 0, "la forme d'avant")
end)

test("reglages : copie virtuelle, et tous les réglages bruts sur demande", function()
    local copie = S.Photo(7, { Exposure2012 = 0.2, LensBlur = { Active = true, BlurAmount = 50 } },
        { fileName = 'C.RAF', copyName = 'Copie 1', fileFormat = 'RAW' }, { isVirtualCopy = true })
    S.active = copie
    local resultat = Commandes.executer('reglages', { cles = { 'Exposure2012' } })
    egal(resultat.photo.copie_virtuelle, true)
    egal(resultat.tous, nil, "seulement sur demande")
    resultat = Commandes.executer('reglages', { cles = { 'Exposure2012' }, toutes = true })
    egal(resultat.tous.LensBlur.BlurAmount, 50, "même une clé que le serveur ne connaît pas")
    local original = photoRaw()
    S.active = original
    egal(Commandes.executer('reglages', { cles = {} }).photo.copie_virtuelle, false)
end)

-- Version 1.5 : traitements calculés par Lightroom, masques combinés ------------------------

local function debruiter(params)
    params.etape = params.etape or 'débruitage'
    return Commandes.executer('ameliorer', params)
end

local function demande(nom, actif, intensite)
    return Json.tableau({ { nom = nom, actif = actif, intensite = intensite } })
end

-- Relevé dans le code de Lightroom Classic 15.6 : LrDevelopController n'agit que sur la photo
-- affichée dans le module Développement, et le résultat d'un débruitage arrive après le calcul.
test("ameliorer : débruitage dans le module Développement, attendu jusqu'au bout, vue remise, annulation", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    local resultat = debruiter({ ameliorations = demande('denoise', true, 40), raison = "ISO 6400, bruit fort." })
    egal(S.modulesOuverts[1], 'develop', "photo affichée dans le module Développement")
    egal(S.module, 'library', "puis la vue d'avant est remise")
    egal(#S.appelsAmelioration, 1)
    egal(S.appelsAmelioration[1].intensite, 40)
    egal(type(photo.reglages.FilterList), 'table', "le résultat est rangé")
    egal(S.attentes >= S.dureeAmelioration, true, "attendu jusqu'à la fin du calcul")
    local changement = resultat.resultats[1].changements[1]
    egal(changement.cle, 'Amelioration.denoise')
    egal(changement.avant, 0)
    egal(changement.apres, 40)
    egal(resultat.resultats[1].amelioration.denoise, true)
    egal(#photo.instantanes, 1, "instantané « Avant Claude » à la première retouche")
    local etapes = Json.decode(photo.proprietes.etapesClaude)
    egal(etapes[1].avant.Amelioration.denoise, false, "l'état d'avant est mémorisé")
    -- Constaté dans Lightroom Classic 15.6 : le débruitage coche aussi les détails bruts.
    egal(resultat.resultats[1].changements[2].cle, 'Amelioration.rawDetails')
    egal(etapes[1].avant.Amelioration.rawDetails, false, "ce que Lightroom change de lui-même est mémorisé aussi")
    local filtres = Commandes.executer('reglages', { cles = {}, details = true }).filtres_calcules
    egal(filtres[1], 'Denoise', "le filtre calculé se lit sur toute photo")
    egal(Json.decode(photo.proprietes.avantClaude).Amelioration.denoise, false)
    egal(photo.proprietes.retoucheeParClaude, 'oui')

    resultat = debruiter({ ameliorations = demande('denoise', true, 40) })
    egal(contient(resultat.resultats[1].remarques, "déjà l'état de la photo"), true)
    egal(#S.appelsAmelioration, 1, "rien de relancé")

    debruiter({ ameliorations = demande('denoise', true, 60), etape = 'plus fort' })
    egal(photo.amelioration.denoiseAmount, 60)
    egal(S.appelsAmelioration[#S.appelsAmelioration].fonction, 'changeDenoiseAmount', "intensité changée sans relancer le traitement")

    resultat = Commandes.executer('annuler', {})
    egal(resultat.resultats[1].annulee, true)
    egal(photo.amelioration.denoiseAmount, 40, "retour à l'intensité d'avant")
    Commandes.executer('annuler', {})
    egal(photo.amelioration.denoise, false, "le débruitage est retiré")
    egal(photo.amelioration.rawDetails, false, "avec ses détails bruts")
    egal(#Commandes.executer('reglages', { cles = {}, details = true }).filtres_calcules, 0)
    egal(S.appelsAmelioration[#S.appelsAmelioration].actif, false)
    egal(S.module, 'library')
    egal(#Json.decode(photo.proprietes.journalClaude), 4)
    -- La mémoire seule (avant le calcul, le journal après) s'écrit en écriture privée : rien dans
    -- Édition › Annuler à part l'étape que Lightroom écrit lui-même ; seul l'instantané « Avant
    -- Claude » passe par une écriture ordinaire.
    egal(S.ecrituresPrivees >= 4, true, "mémoire des traitements en écriture privée")
    for _, nom in ipairs(S.ecritures) do
        egal(nom:find("rien lancé", 1, true), nil, "pas d'écriture ordinaire pour la seule mémoire")
    end
end)

test("ameliorer : photo par identifiant, sélection remise, refus de Lightroom avec sa raison", function()
    local active, autre = photoRaw(), photoJpeg()
    local cible = photoFuji()
    S.active, S.selection, S.module = active, { active, autre }, 'develop'
    cible.ameliorationsRefusees = { denoise = true }
    cible.raisonAmelioration = "Le débruitage n'est pas disponible pour cette photo."
    local resultat = debruiter({ photo = cible.localIdentifier, ameliorations = Json.tableau({
        { nom = 'denoise', actif = true, intensite = 50 }, { nom = 'superRes', actif = true } }) })
    egal(S.active, active, "photo active remise")
    egal(#S.selection, 2, "sélection remise")
    egal(S.module, 'develop')
    egal(contient(resultat.resultats[1].remarques, "Le débruitage n'est pas disponible"), true)
    -- Constaté dans Lightroom Classic 15.6 : la super résolution coche aussi les détails bruts.
    egal(#resultat.resultats[1].changements, 2, "seule la super résolution est faite, avec ses détails bruts")
    egal(resultat.resultats[1].changements[1].cle, 'Amelioration.rawDetails')
    egal(resultat.resultats[1].changements[2].cle, 'Amelioration.superRes')
    egal(cible.amelioration.superRes, true)

    local seule = photoRaw()
    seule.localIdentifier = 9
    S.photos[9] = seule
    seule.ameliorationsRefusees = { rawDetails = true }
    resultat = debruiter({ photo = 9, ameliorations = demande('rawDetails', true) })
    egal(#resultat.resultats[1].changements, 0)
    egal(seule.proprietes.etapesClaude, nil, "rien de mémorisé si rien ne change")
    egal(#seule.instantanes, 0)
end)

test("ameliorer : calcul trop long, photo invisible, mode « Proposer d'abord », pause, version de Lightroom", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    S.ameliorationBloquee = true
    local resultat = debruiter({ ameliorations = demande('superRes', true) })
    egal(contient(resultat.resultats[1].remarques, "calcule encore"), true)
    egal(resultat.resultats[1].changements[1].apres, "oui", "la case est cochée : l'étape est mémorisée pour l'annuler")
    S.ameliorationBloquee = false

    local cachee = photoRaw()
    S.invisibles[cachee.localIdentifier] = true
    echoue(function() debruiter({ photo = cachee.localIdentifier, ameliorations = demande('denoise', true) }) end, "film fixe")
    egal(S.active, photo, "vue remise après l'échec")

    S.prefs.mode = 'proposer'
    echoue(function() debruiter({ ameliorations = demande('denoise', true) }) end, "enhance_photo avec confirm = true")
    S.prefs.mode = 'appliquer'
    Liaison.pause = true
    echoue(function() debruiter({ ameliorations = demande('denoise', true) }) end, "en pause")
    Liaison.pause = false
    echoue(function() debruiter({ ameliorations = demande('flou', true) }) end, "Traitement inconnu")

    local setEnhance = S.module and import('LrDevelopController').setEnhance
    import('LrDevelopController').setEnhance = nil
    echoue(function() debruiter({ ameliorations = demande('denoise', true) }) end, "15.3 ou plus récent")
    import('LrDevelopController').setEnhance = setEnhance
end)

test("revenir et comparer : le débruitage se défait au retour à l'origine, pas pendant une comparaison", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    debruiter({ ameliorations = demande('denoise', true, 50) })
    echoue(function() Commandes.executer('apercu', { taille = 1344, cles = {}, comparer = 'etapePrecedente' }) end, "ne peut pas le défaire")
    appliquer({ reglages = { Exposure2012 = 0.5 }, plages = { Exposure2012 = { -5, 5 } } })
    local apercu = Commandes.executer('apercu', { taille = 1344, cles = {}, comparer = 'avantClaude' })
    egal(apercu.remarque_comparaison ~= nil, true, "la comparaison dit qu'elle garde le débruitage")
    egal(photo.amelioration.denoise, true, "la comparaison n'y touche pas")

    local resultat = Commandes.executer('revenir', {})
    egal(resultat.resultats[1].remise, true)
    egal(photo.amelioration.denoise, false)
    egal(photo.reglages.Exposure2012, 0)
    egal(photo.proprietes.avantClaude, nil)
    egal(resultat.resultats[1].reglages_remis.Amelioration, "aucune amélioration")

    -- Lightroom ne suit pas : la photo reste telle quelle, sa mémoire aussi.
    debruiter({ ameliorations = demande('denoise', true, 50) })
    S.invisibles[photo.localIdentifier] = true
    S.active = photoRaw()
    resultat = Commandes.executer('revenir', { photos = { photo.localIdentifier } })
    egal(resultat.resultats[1].remise, false)
    egal(contient({ resultat.resultats[1].raison }, "film fixe"), true)
    egal(photo.proprietes.avantClaude ~= nil, true, "mémoire gardée pour réessayer")
end)

test("reglages : l'amélioration n'est connue que pour la photo affichée dans le module Développement", function()
    local photo = photoFuji()
    S.active = photo
    egal(type(Commandes.executer('reglages', { cles = {}, details = true }).amelioration), 'string')
    S.module = 'develop'
    photo.amelioration = { denoise = true, rawDetails = false, superRes = false, denoiseAmount = 35 }
    local resultat = Commandes.executer('reglages', { cles = {}, details = true })
    egal(resultat.amelioration.denoise, true)
    egal(resultat.amelioration.denoiseAmount, 35)
end)

test("ameliorer : attend que le module Développement ait chargé la photo, seule sélectionnée", function()
    local affichee, cible, autre = photoRaw(), photoFuji(), photoJpeg()
    S.module, S.active, S.selection, S.affichee = 'develop', affichee, { affichee }, affichee
    S.delaiChargement = 1.2
    debruiter({ photo = cible.localIdentifier, ameliorations = demande('denoise', true, 30) })
    egal(affichee.amelioration == nil or affichee.amelioration.denoise == false, true, "la photo affichée avant n'est pas touchée")
    egal(cible.amelioration.denoise, true)
    egal(S.active, affichee, "vue remise")

    -- Synchronisation automatique (supposée suivie par LrDevelopController) : la photo visée est
    -- active, mais pas seule sélectionnée.
    S.synchroAuto = true
    S.active, S.selection = cible, { cible, autre }
    debruiter({ ameliorations = demande('superRes', true) })
    egal(cible.amelioration.superRes, true)
    egal(autre.amelioration, nil, "les autres photos sélectionnées ne reçoivent rien")
    egal(#S.selection, 2, "sélection remise")
end)

test("ameliorer : mémoire écrite avant le calcul, un seul traitement à la fois", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    local pendant, refus, annulation
    S.pendantAttente = function()
        if pendant == nil and photo.calculAmelioration then
            S.pendantAttente = nil
            pendant = photo.proprietes.etapesClaude
            refus = select(2, pcall(Commandes.executer, 'ameliorer', { ameliorations = demande('superRes', true), etape = 'autre' }))
            annulation = Commandes.executer('annuler', {})
        end
    end
    debruiter({ ameliorations = demande('denoise', true, 30), etape = 'nuit' })
    egal(pendant ~= nil and pendant:find('nuit', 1, true) ~= nil, true, "l'étape est mémorisée avant la fin du calcul")
    egal(tostring(refus):find("calcule déjà", 1, true) ~= nil, true, "une deuxième commande attend son tour")
    egal(annulation.resultats[1].annulee, false, "pas d'annulation au milieu du calcul")
    egal(#Json.decode(photo.proprietes.etapesClaude), 1, "la mémoire reste")
    egal(photo.amelioration.denoise, true)
    egal(photo.amelioration.superRes, false)
    Commandes.executer('annuler', {})
    egal(photo.amelioration.denoise, false, "après le calcul, l'annulation passe")
end)

test("ameliorer : rien de lancé, la mémoire revient ; seuls les traitements changés sont défaits", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    photo.erreurAmelioration = "GPU indisponible"
    local resultat = debruiter({ ameliorations = demande('denoise', true, 30) })
    egal(contient(resultat.resultats[1].remarques, "GPU indisponible"), true)
    egal(photo.proprietes.etapesClaude, nil, "rien de lancé : mémoire remise comme avant")
    egal(photo.proprietes.avantClaude, nil)
    egal(photo.proprietes.retoucheeParClaude, nil)
    photo.erreurAmelioration = nil

    debruiter({ ameliorations = demande('denoise', true, 30) })
    egal(Json.decode(photo.proprietes.etapesClaude)[1].avant.Amelioration.superRes, nil, "seul le débruitage est mémorisé")
    photo.amelioration.superRes = true      -- l'utilisateur ajoute lui-même la super résolution
    Commandes.executer('annuler', {})
    egal(photo.amelioration.denoise, false)
    egal(photo.amelioration.superRes, true, "ce que Claude n'a pas changé reste")
end)

-- Constaté dans Lightroom Classic 15.6 : la super résolution coche aussi les détails bruts, et
-- Lightroom refuse d'y toucher tant qu'elle est active ; l'annulation de la 1.5 les retirait en
-- premier et échouait.
test("ameliorer : la super résolution se défait avec ses détails bruts, retirés en dernier", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    debruiter({ ameliorations = demande('superRes', true), etape = 'super résolution' })
    egal(photo.amelioration.rawDetails, true, "Lightroom coche aussi les détails bruts")
    egal(Json.decode(photo.proprietes.etapesClaude)[1].avant.Amelioration.rawDetails, false)
    egal(Commandes.executer('reglages', { cles = {}, details = true }).filtres_calcules[1], 'Super Resolution')
    local resultat = Commandes.executer('annuler', {})
    egal(resultat.resultats[1].annulee, true, tostring(resultat.resultats[1].raison))
    egal(photo.amelioration.superRes, false)
    egal(photo.amelioration.rawDetails, false)
    egal(#Commandes.executer('reglages', { cles = {}, details = true }).filtres_calcules, 0)

    -- Les deux retirés par une commande, dans l'ordre du catalogue : la super résolution d'abord.
    debruiter({ ameliorations = demande('superRes', true), etape = 'super résolution' })
    local appels = #S.appelsAmelioration
    resultat = debruiter({ ameliorations = Json.tableau({ { nom = 'rawDetails', actif = false }, { nom = 'superRes', actif = false } }),
        etape = 'retirer' })
    egal(#resultat.resultats[1].remarques, 0, tostring(resultat.resultats[1].remarques[1]))
    egal(#S.appelsAmelioration, appels + 1, "les détails bruts partent avec la super résolution")
    egal(photo.amelioration.rawDetails, false)

    -- Détails bruts seuls : ils restent tant que la super résolution est là, et Claude le sait.
    debruiter({ ameliorations = demande('superRes', true), etape = 'super résolution' })
    resultat = debruiter({ ameliorations = demande('rawDetails', false), etape = 'sans détails' })
    egal(contient(resultat.resultats[1].remarques, "Les détails bruts restent"), true)
    egal(photo.amelioration.rawDetails, true)

    -- Retour à l'origine.
    resultat = Commandes.executer('revenir', {})
    egal(resultat.resultats[1].remise, true, tostring(resultat.resultats[1].raison))
    egal(photo.amelioration.superRes, false)
    egal(photo.amelioration.rawDetails, false)

    -- Détails bruts mémorisés par Claude, super résolution ajoutée ensuite par l'utilisateur :
    -- l'annulation laisse les détails bruts que la super résolution impose.
    debruiter({ ameliorations = demande('rawDetails', true), etape = 'détails' })
    photo.amelioration.superRes = true
    resultat = Commandes.executer('annuler', {})
    egal(resultat.resultats[1].annulee, true, tostring(resultat.resultats[1].raison))
    egal(photo.amelioration.rawDetails, true)
end)

-- Relevé dans DevelopEnhance et constaté dans Lightroom Classic 15.6 : juste après l'ouverture du
-- module Développement, tant que la photo n'est pas chargée en pleine qualité, Lightroom dit tous
-- les traitements impossibles ; l'annulation d'une super résolution échouait au premier passage
-- après la relance de Lightroom.
test("ameliorer : attend que la photo soit chargée en pleine qualité avant de juger", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    debruiter({ ameliorations = demande('superRes', true), etape = 'super résolution' })
    S.delaiQualite = 4
    local resultat = Commandes.executer('annuler', {})
    egal(resultat.resultats[1].annulee, true, tostring(resultat.resultats[1].raison))
    egal(photo.amelioration.superRes, false)

    resultat = debruiter({ ameliorations = demande('superRes', true), etape = 'super résolution' })
    egal(#resultat.resultats[1].remarques, 0, tostring(resultat.resultats[1].remarques[1]))
    egal(photo.amelioration.superRes, true, "pas de refus pendant le chargement")

    -- Jamais en pleine qualité (supposé : original hors ligne) : refus au bout du délai, qui le dit.
    S.delaiQualite = 1000
    resultat = debruiter({ ameliorations = demande('denoise', true, 30), etape = 'nuit' })
    egal(contient(resultat.resultats[1].remarques, "pleine qualité"), true)
    egal(photo.amelioration.denoise, false)
    resultat = Commandes.executer('annuler', {})
    egal(resultat.resultats[1].annulee, false)
    egal(contient({ resultat.resultats[1].raison }, "pleine qualité"), true)
end)

-- Relevé dans le code de Lightroom Classic 15.6 (DevelopModuleCommands, DevelopLocalizedConstants) :
-- un composant ajouté porte MaskBlendMode 0, soustrait 1, et une intersection est la
-- soustraction du composant inversé.
test("Locaux : modes des composants d'un masque combiné", function()
    local m = Locaux.combiner(Locaux.masqueIA(1, nil, 'Sujet', false), 'soustraire', false)
    egal(m.MaskBlendMode, 1) egal(m.MaskInverted, false)
    m = Locaux.combiner(Locaux.masqueIA(1, nil, 'Sujet', false), 'intersecter', false)
    egal(m.MaskBlendMode, 1) egal(m.MaskInverted, true)
    m = Locaux.combiner(Locaux.masqueIA(1, nil, 'Sujet', false), 'intersecter', true)
    egal(m.MaskBlendMode, 1) egal(m.MaskInverted, false, "intersection avec l'inverse = soustraction")
    m = Locaux.combiner(Locaux.masqueIA(1, nil, 'Sujet', false), 'ajouter', true)
    egal(m.MaskBlendMode, 0) egal(m.MaskInverted, true)
    egal(Locaux.empreinte('abc'), Locaux.empreinte('abc'))
    egal(Locaux.empreinte('abc') ~= Locaux.empreinte('abd'), true)
    egal(#Locaux.empreinte('abc'), 16)
end)

test("masquer : masque combiné (ciel sans l'architecture, limité au haut), calculé par Lightroom", function()
    local photo = photoFuji()
    photo.reglages.MaskGroupBasedCorrections = { MASQUE_UTILISATEUR }
    S.active = photo
    local resultat = Commandes.executer('masquer', {
        masques = Json.tableau({ {
            type = 'ia', soustype = 2, nom = 'Claude · Ciel sans bâtiment', locaux = { LocalExposure2012 = -0.1 },
            composants = Json.tableau({
                { mode = 'soustraire', type = 'ia', soustype = 0, categorie = 50001, nom = 'Architecture' },
                { mode = 'intersecter', type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.6, nom = 'Haut' },
            }),
        } }),
        etape = 'ciel',
    })
    local masques = photo.reglages.MaskGroupBasedCorrections
    egal(#masques, 2, "un seul masque ajouté")
    local composants = masques[2].CorrectionMasks
    egal(#composants, 3)
    egal(composants[1].MaskBlendMode, 0) egal(composants[1].MaskSubType, 2)
    egal(composants[2].MaskBlendMode, 1) egal(composants[2].MaskInverted, false) egal(composants[2].MaskSubCategoryID, 50001)
    egal(composants[3].MaskBlendMode, 1) egal(composants[3].MaskInverted, true) egal(composants[3].What, 'Mask/Gradient')
    egal(composants[1].MaskDigest, 'calculé pour 4', "chaque composant IA est calculé")
    egal(composants[2].MaskDigest, 'calculé pour 4')
    egal(#photo.appliques, 1, "par un seul paramètre prédéfini du module")
    egal(resultat.resultats[1].changements[1].apres, "2 masques (+ Claude · Ciel sans bâtiment)")

    local lu = Commandes.executer('reglages', { cles = {}, details = true }).masques[2]
    egal(lu.composants[2], "Architecture (soustrait)")
    egal(lu.composants[3], "Haut (intersection)")

    Commandes.executer('annuler', {})
    egal(#photo.reglages.MaskGroupBasedCorrections, 1)

    -- Sans IA : par applyDevelopSettings, comme un dégradé seul.
    local presets = #S.presetsCrees
    Commandes.executer('masquer', { masques = Json.tableau({ {
        type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.4, nom = 'Dégradé', locaux = {},
        composants = Json.tableau({ { mode = 'soustraire', type = 'luminance', min = 0.8, max = 1, fondu = 0.1 } }),
    } }) })
    egal(#S.presetsCrees, presets)
    egal(photo.reglages.MaskGroupBasedCorrections[2].CorrectionMasks[2].What, 'Mask/RangeMask')
end)

test("paramètres prédéfinis du module : nommés d'après leur contenu, un seul pour un même contenu", function()
    local photo = photoFuji()
    S.active = photo
    -- Intensités propres à ce test : le module garde ses paramètres prédéfinis pour la session.
    appliquer({ flou_objectif = { intensite = 37 }, etape = 'flou' })
    appliquer({ flou_objectif = { intensite = 63 }, etape = 'flou' })
    appliquer({ flou_objectif = { intensite = 37 }, etape = 'flou' })
    local noms = {}
    for _, preset in ipairs(S.presetsCrees) do
        noms[preset.nom] = true
    end
    local differents = 0
    for _ in pairs(noms) do
        differents = differents + 1
    end
    egal(differents, 2, "deux contenus, deux paramètres prédéfinis")
    egal(#S.presetsCrees, 2, "le même contenu reprend le même")
    egal(S.presetsCrees[1].nom:match("^Claude · flou d'objectif %x+$") ~= nil, true)
end)

-- Mémoire et copies virtuelles -----------------------------------------------------------

local function retoucheeParClaude(photo)
    S.selection = { photo }
    return Commandes.executer('selection', {}).photos[1].retouchee_par_claude
end

local function entreesDuJournal(photo)
    return #Commandes.executer('journal', { photos = { photo.localIdentifier } }).photos[1].entrees
end

-- Constaté dans Lightroom Classic 15.6 : une copie virtuelle reçoit les champs du module de son
-- original (S.copieVirtuelle), proprietaireMemoire compris (constaté en 2.3) ; elle croyait avoir
-- ses retouches.
test("copie virtuelle d'une photo retouchée : sa mémoire ne voit rien de l'original", function()
    local original = photoRaw()
    S.active = original
    appliquer({ reglages = { Exposure2012 = 0.3, Vibrance = 15 }, etape = "passe de l'original", raison = "Original." })
    local copie = S.copieVirtuelle(original, 8)
    copie.reglages.Exposure2012, copie.reglages.Vibrance = -0.2, 0 -- réinitialisée à la main
    egal(copie.proprietes.retoucheeParClaude, 'oui', "Lightroom a copié la mémoire")

    S.active = copie
    egal(retoucheeParClaude(copie), false, "pas encore retouchée par Claude")
    echoue(function() Commandes.executer('apercu', { comparer = 'avantClaude' }) end, "rien à comparer")
    egal(Commandes.executer('annuler', {}).resultats[1].annulee, false)
    egal(Commandes.executer('revenir', {}).resultats[1].remise, false)
    egal(entreesDuJournal(copie), 0)
    egal(copie.reglages.Exposure2012, -0.2, "rien de l'original n'est remis")
    S.selection = { copie }
    copie.erreurAmelioration = "GPU indisponible"
    local resultat = debruiter({ ameliorations = demande('denoise', true, 30) })
    copie.erreurAmelioration = nil
    egal(contient(resultat.resultats[1].remarques, "GPU indisponible"), true)
    egal(copie.proprietes.proprietaireMemoire, 'uuid-1', "rien de lancé : mémoire remise comme avant")
    egal(retoucheeParClaude(copie), false)

    appliquer({ reglages = { Exposure2012 = 0.5 }, etape = 'passe de la copie', raison = "Copie." })
    egal(copie.proprietes.proprietaireMemoire, 'uuid-8')
    local avant = Json.decode(copie.proprietes.avantClaude)
    egal(avant.Exposure2012, -0.2, "l'état d'avant Claude est celui de la copie")
    egal(avant.Vibrance, nil, "rien de celui de l'original")
    Commandes.executer('apercu', { comparer = 'avantClaude', taille = 800, cles = { 'Exposure2012' } })
    local comparaison = copie.appliques[#copie.appliques - 1]
    egal(comparaison.nom, "Claude · comparaison (avant)")
    egal(comparaison.reglages.Exposure2012, -0.2)
    egal(comparaison.reglages.Vibrance, nil)
    local journal = Commandes.executer('journal', {}).photos[1].entrees
    egal(#journal, 1)
    egal(journal[1].raison, "Copie.")
    egal(Commandes.executer('annuler', {}).resultats[1].annulee, true)
    egal(copie.reglages.Exposure2012, -0.2)
    egal(Commandes.executer('annuler', {}).resultats[1].annulee, false, "l'étape de l'original n'est pas défaite")
    egal(copie.reglages.Vibrance, 0)

    S.active = original
    egal(retoucheeParClaude(original), true, "l'original garde sa mémoire")
    egal(entreesDuJournal(original), 1)
    Commandes.executer('revenir', {})
    egal(original.reglages.Exposure2012, 0)
    egal(original.reglages.Vibrance, 0)
end)

test("copie virtuelle : le débruitage, écrit en deux temps, efface d'abord la mémoire de l'original", function()
    local original = photoFuji()
    S.active = original
    appliquer({ reglages = { Exposure2012 = 0.3 }, raison = "Original." })
    local copie = S.copieVirtuelle(original, 8)
    S.active, S.selection = copie, { copie }
    debruiter({ ameliorations = demande('denoise', true, 40), raison = "Copie bruitée." })
    egal(copie.amelioration.denoise, true)
    local journal = Commandes.executer('journal', {}).photos[1].entrees
    egal(#journal, 1, "seulement l'entrée de la copie")
    egal(journal[1].raison, "Copie bruitée.")
    egal(Json.decode(copie.proprietes.avantClaude).Exposure2012, nil, "rien de l'original")
    egal(#Json.decode(copie.proprietes.etapesClaude), 1)
end)

-- Une mémoire écrite avant le propriétaire (proprietaireMemoire) n'en a pas.
test("mémoire sans propriétaire : celle de la photo, rattachée à l'écriture ; une copie qui l'a reçue n'en voit rien", function()
    local original = photoRaw()
    local ancienne = S.copieVirtuelle(original, 9)
    appliquer({ photos = { 9 }, reglages = { Exposure2012 = -0.4 }, etape = 'passe de la copie', raison = "Copie claire." })
    appliquer({ photos = { 1 }, reglages = { Exposure2012 = 0.3 }, etape = "passe de l'original", raison = "Original sombre." })
    original.proprietes.proprietaireMemoire, ancienne.proprietes.proprietaireMemoire = nil, nil
    local recue = S.copieVirtuelle(original, 10, 'Copie 2')

    egal(retoucheeParClaude(original), true, "lue comme avant")
    egal(retoucheeParClaude(ancienne), true, "la copie retouchée elle-même garde la sienne")
    egal(retoucheeParClaude(recue), false, "reçue de l'original à la création de la copie")
    egal(entreesDuJournal(recue), 0)
    egal(Commandes.executer('annuler', { photos = { 10 } }).resultats[1].annulee, false)

    appliquer({ photos = { 1 }, reglages = { Vibrance = 10 }, etape = 'passe 2' })
    egal(original.proprietes.proprietaireMemoire, 'uuid-1', "rattachée à la première écriture")
    egal(Json.decode(original.proprietes.avantClaude).Exposure2012, 0, "sans rien perdre")
    egal(entreesDuJournal(original), 2)
    egal(retoucheeParClaude(recue), false, "le journal de l'original s'allonge : la copie n'en voit toujours rien")

    egal(Commandes.executer('annuler', { photos = { 9 } }).resultats[1].annulee, true)
    egal(ancienne.reglages.Exposure2012, 0)
    egal(ancienne.proprietes.proprietaireMemoire, 'uuid-9')
end)

-- Version 1.7 : Bibliothèque -------------------------------------------------------------

local function classer(params)
    params.etape = params.etape or 'tri'
    return Commandes.executer('metadonnees', params)
end

local function cheminsMotsCles(photo)
    local chemins = {}
    for _, m in ipairs(photo.motsCles) do
        local noms, courant = {}, m
        while courant do
            table.insert(noms, 1, courant.nom)
            courant = courant.parent
        end
        chemins[#chemins + 1] = table.concat(noms, ' > ')
    end
    table.sort(chemins)
    return table.concat(chemins, ' ; ')
end

-- Critère de passage de la 1.7 : une note ou un mot-clé s'annule comme un réglage.
test("Bibliothèque : note, drapeau, libellé et mots-clés, puis undo_last les remet", function()
    local photo = photoRaw()
    photo.meta.title = "Lac au matin"
    S.active = photo
    local lieux = S.MotCle('Lieux')
    S.MotCle('Canada', lieux)
    local resultat = classer({ note = 4, drapeau = 'retenue', libelle = 'rouge', titre = "Lac Brome au matin",
        ajouter = { 'Lieux > Canada > Montréal', 'Paysage' }, raison = "Meilleure de la série." })
    egal(photo.brut.rating, 4)
    egal(photo.brut.pickStatus, 1)
    egal(photo.meta.label, 'Rouge', "le texte du jeu de libellés par défaut")
    egal(photo.meta.title, "Lac Brome au matin")
    egal(cheminsMotsCles(photo), "Lieux > Canada > Montréal ; Paysage")
    egal(contient(S.motsClesCrees, 'Montréal') and contient(S.motsClesCrees, 'Paysage'), true)
    egal(#S.motsClesCrees, 2, "Lieux et Canada existaient")
    egal(resultat.resultats[1].etape, "Claude · tri")
    egal(#resultat.resultats[1].changements, 5)
    egal(photo.reglages.Exposure2012, 0, "aucun réglage touché")
    egal(#photo.appliques, 0, "rien par applyDevelopSettings")
    egal(photo.proprietes.retoucheeParClaude, nil, "un classement n'est pas une retouche")
    local journal = Commandes.executer('journal', {}).photos[1].entrees
    egal(journal[#journal].type, 'classement')
    egal(journal[#journal].raison, "Meilleure de la série.")

    local annule = Commandes.executer('annuler', {})
    egal(annule.resultats[1].annulee, true)
    egal(photo.brut.rating, nil)
    egal(photo.brut.pickStatus, 0)
    egal(photo.meta.label, '', "un libellé s'efface par un texte vide")
    egal(photo.meta.title, "Lac au matin")
    egal(cheminsMotsCles(photo), "")
    egal(#photo.appliques, 0, "l'annulation non plus ne passe pas par applyDevelopSettings")
    egal(contient({ annule.resultats[1].reglages_remis.Bibliotheque }, "note"), true)
end)

test("Bibliothèque : retirer un mot-clé, puis l'annulation le remet", function()
    local photo = photoRaw()
    S.active = photo
    local paysage = S.MotCle('Paysage')
    local hiver = S.MotCle('Hiver')
    photo.motsCles = { paysage, hiver }
    classer({ retirer = { 'hiver' } })
    egal(cheminsMotsCles(photo), "Paysage")
    local rien = classer({ retirer = { 'Été' } })
    egal(contient(rien.resultats[1].remarques, "absent de cette photo"), true)
    Commandes.executer('annuler', {})
    egal(cheminsMotsCles(photo), "Hiver ; Paysage", "l'étape sans changement n'a rien gardé")
    egal(Commandes.executer('annuler', {}).resultats[1].sans_retouche, true)
end)

test("Bibliothèque : un nom de mot-clé en double demande son chemin", function()
    local photo = photoRaw()
    S.active = photo
    S.MotCle('Paris', S.MotCle('France'))
    S.MotCle('Paris', S.MotCle('Ontario'))
    echoue(function() classer({ ajouter = { 'Paris' } }) end, "Plusieurs mots-clés")
    egal(#photo.motsCles, 0)
    classer({ ajouter = { 'France > Paris' } })
    egal(cheminsMotsCles(photo), "France > Paris")
    echoue(function() classer({ ajouter = { 'paris' } }) end, "Ontario > Paris")
    egal(#photo.motsCles, 1)
end)

test("Bibliothèque : le libellé prend le texte du jeu de libellés actif, lu directement", function()
    S.jeuLibelles = { ['À garder'] = 'red', ['À revoir'] = 'yellow' }
    local photo = photoRaw()
    S.active = photo
    classer({ libelle = 'jaune' })
    egal(photo.meta.label, 'À revoir', "getLabelMapToColorName, sans photo jaune dans le catalogue")
    egal(#S.ecritures, 1, "un seul essai, une seule écriture")
end)

test("Bibliothèque : sans le jeu de libellés actif, le texte s'apprend d'une photo de cette couleur", function()
    S.jeuLibelles = { ['À garder'] = 'red', ['À revoir'] = 'yellow' }
    S.jeuLibellesIllisible = true
    local deja = photoJpeg()
    deja.meta.label = 'À garder'
    local photo = photoRaw()
    S.active = photo
    classer({ libelle = 'rouge' })
    egal(photo.meta.label, 'À garder', "appris d'une photo déjà rouge")
end)

test("Bibliothèque : un libellé inconnu du jeu actif laisse le libellé d'avant", function()
    S.jeuLibelles = { ['À garder'] = 'red' }
    local deja = photoJpeg()
    deja.meta.label = 'À garder'
    local photo = photoRaw()
    S.active = photo
    classer({ libelle = 'rouge' })
    egal(photo.meta.label, 'À garder', "le texte du jeu actif")
    local resultat = classer({ libelle = 'jaune' })
    egal(photo.meta.label, 'À garder', "aucun texte connu pour le jaune : le libellé d'avant reste")
    egal(contient(resultat.resultats[1].remarques, "Libellé jaune non posé"), true)
    classer({ libelle = 'aucun' })
    egal(photo.meta.label, '')
    Commandes.executer('annuler', {})
    egal(photo.meta.label, 'À garder')
end)

test("Bibliothèque : le libellé se vérifie après l'écriture, puis le texte suivant est essayé", function()
    S.jeuLibelles = { Red = 'red' }
    local photo = photoRaw()
    S.active = photo
    local resultat = classer({ libelle = 'rouge' })
    egal(photo.meta.label, 'Red', "« Rouge » n'était pas rouge pour ce jeu de libellés")
    egal(#resultat.resultats[1].remarques, 0)
    egal(resultat.resultats[1].changements[1].apres, 'rouge')
    Commandes.executer('annuler', {})
    egal(photo.meta.label, '')
end)

test("Bibliothèque : titre, légende et droits se lisent comme Lightroom les donne", function()
    local photo = photoRaw()
    S.active = photo
    echoue(function() photo:getRawMetadata('title') end, "clé inconnue")
    classer({ legende = "Brume sur le lac", droits = "© Dany Ménard" })
    egal(photo.meta.caption, "Brume sur le lac")
    egal(photo.meta.copyright, "© Dany Ménard")
    S.selection = { photo }
    egal(Commandes.executer('selection', { limite = 1 }).photos[1].drapeau, 'aucun')
    egal(Commandes.executer('selection', { limite = 1 }).photos[1].libelle, 'aucun')
end)

test("Bibliothèque : revert_to_original remet le classement et les réglages", function()
    local photo = photoRaw()
    photo.brut.rating = 2
    S.active = photo
    S.prefs.instantane = true
    classer({ note = 3 })
    appliquer({ reglages = { Exposure2012 = 0.5 } })
    egal(#photo.instantanes, 1, "l'instantané « Avant Claude » malgré le classement d'avant")
    classer({ note = 5, ajouter = { 'Choix' } })
    Commandes.executer('revenir', {})
    egal(photo.brut.rating, 2, "la note d'avant Claude, pas celle de l'étape précédente")
    egal(photo.reglages.Exposure2012, 0)
    egal(#photo.motsCles, 0)
end)

test("Bibliothèque : ajouter puis retirer le même mot-clé ne laisse rien à remettre", function()
    local photo = photoRaw()
    S.active = photo
    classer({ ajouter = { 'Temporaire' } })
    classer({ retirer = { 'Temporaire' } })
    local original = require('Json').decode(photo.proprietes.avantClaude)
    egal(#original.Bibliotheque.motsCles.ajoutes, 0)
    egal(#original.Bibliotheque.motsCles.retires, 0)
end)

test("Bibliothèque : plusieurs photos en une écriture, une étape chacune", function()
    local a, b = photoRaw(), photoJpeg()
    S.active, S.selection = a, { a, b }
    local ecritures = #S.ecritures
    local resultat = classer({ selection = true, drapeau = 'rejetee' })
    egal(#S.ecritures, ecritures + 1)
    egal(#resultat.resultats, 2)
    egal(b.brut.pickStatus, -1)
    Commandes.executer('annuler', { photos = { 2 } })
    egal(b.brut.pickStatus, 0)
    egal(a.brut.pickStatus, -1)
end)

test("Bibliothèque : pause, « Proposer d'abord » et demande vide", function()
    local photo = photoRaw()
    S.active = photo
    echoue(function() classer({}) end, "Aucune métadonnée")
    echoue(function() classer({ note = 7 }) end, "Note invalide")
    echoue(function() classer({ libelle = 'orange' }) end, "Libellé invalide")
    S.prefs.mode = 'proposer'
    echoue(function() classer({ note = 3 }) end, "Proposer d'abord")
    egal(photo.brut.rating, nil)
    classer({ note = 3, confirme = true })
    egal(photo.brut.rating, 3)
    S.prefs.mode = nil
    Liaison.pause = true
    echoue(function() classer({ note = 1 }) end, "pause")
end)

test("Bibliothèque : comparer après un classement ne rend rien de plus", function()
    local photo = photoRaw()
    S.active = photo
    classer({ note = 3 })
    echoue(function() Commandes.executer('apercu', { comparer = 'etapePrecedente' }) end, "ne touche que la Bibliothèque")
end)

test("Bibliothèque : get_settings donne le classement de la photo", function()
    local photo = photoRaw()
    S.active = photo
    classer({ note = 2, libelle = 'bleu', titre = "Brume", ajouter = { 'Lieux > Lac' } })
    local c = Commandes.executer('reglages', { cles = {}, details = true }).classement
    egal(c.note, 2)
    egal(c.drapeau, 'aucun')
    egal(c.libelle, 'bleu')
    egal(c.titre, "Brume")
    egal(c.mots_cles[1], "Lieux > Lac")
end)

test("Bibliothèque : mots-clés du catalogue, par chemin, avec leur nombre de photos", function()
    local photo = photoRaw()
    local lieux = S.MotCle('Lieux')
    local canada = S.MotCle('Canada', lieux)
    photo.motsCles = { canada }
    local resultat = Commandes.executer('motsCles', { filtre = 'can' })
    egal(resultat.total, 1)
    egal(resultat.mots_cles[1].chemin, "Lieux > Canada")
    egal(resultat.mots_cles[1].photos, 1)
end)

test("Bibliothèque : collections créées dans « Claude », photos ajoutées puis retirées", function()
    local a, b = photoRaw(), photoJpeg()
    S.active, S.selection = a, { a, b }
    local cree = Commandes.executer('collections', { action = 'creer', nom = "Sélection du lac", selection = true, etape = 'collection' })
    egal(cree.collection.ensemble, "Claude")
    egal(#cree.resultats, 2)
    local c = S.collections[1]
    egal(c.parent.nom, "Claude")
    egal(c.membres[a] and c.membres[b], true)
    local liste = Commandes.executer('collections', { action = 'lister' })
    egal(liste.collections[1].nom, "Sélection du lac")
    egal(liste.collections[1].photos, 2)
    egal(liste.ensembles[1], "Claude")

    Commandes.executer('collections', { action = 'retirer', collection = "sélection du lac", photos = { 2 }, etape = 'tri' })
    egal(c.membres[b], nil)
    Commandes.executer('annuler', { photos = { 2 } })
    egal(c.membres[b], true, "l'annulation la remet dans la collection")
    Commandes.executer('annuler', { photos = { 2 } })
    egal(c.membres[b], nil, "puis défait l'ajout de la création")
end)

-- Constaté dans Lightroom Classic 15.6 : une collection créée dans une écriture ne se lit pas dans
-- la même ; la simulation le refuse (et pour un ensemble, supposé). Un mot-clé créé dans une
-- écriture y sert de parent et se pose sur une photo, sans s'y lire (constaté en 2.3).
test("Bibliothèque : mots-clés créés et posés en une écriture ; ensemble, collection et photos dans des écritures distinctes", function()
    local photo = photoRaw()
    S.active = photo
    local avant = #S.ecritures
    local resultat = classer({ ajouter = { 'Voyages > Québec > Charlevoix', 'Voyages > Québec > Tadoussac' } })
    egal(#S.ecritures - avant, 1, "les trois niveaux qui manquent et le classement : une seule opération (⌘Z)")
    egal(cheminsMotsCles(photo), "Voyages > Québec > Charlevoix ; Voyages > Québec > Tadoussac")
    egal(#S.motsClesCrees, 4, "Voyages et Québec créés une seule fois")
    egal(#resultat.mots_cles_crees, 4)
    Commandes.executer('annuler', {})
    egal(cheminsMotsCles(photo), "", "l'annulation retire les deux")
    avant = #S.ecritures
    Commandes.executer('collections', { action = 'creer', nom = "Charlevoix", ensemble = "Claude > Voyages", photos = { 1 }, etape = 'c' })
    egal(#S.ecritures - avant, 4, "deux ensembles, la collection, puis ses photos")
    egal(S.collections[1].parent.nom, "Voyages")
    egal(S.collections[1].membres[photo], true)
end)

test("Bibliothèque : un retrait annulé compte au retour à l'origine", function()
    local photo = photoRaw()
    S.active = photo
    Commandes.executer('collections', { action = 'creer', nom = "Essai", photos = { 1 }, etape = 'c' })
    local c = S.collections[1]
    Commandes.executer('collections', { action = 'retirer', collection = "Essai", photos = { 1 }, etape = 'c' })
    Commandes.executer('annuler', {})
    egal(c.membres[photo], true, "le retrait annulé")
    classer({ ajouter = { 'Brouillon' } })
    Commandes.executer('annuler', {})
    Commandes.executer('revenir', {})
    egal(c.membres[photo], nil, "la photo sort de la collection où Claude l'avait mise")
    egal(#photo.motsCles, 0)
end)

test("Bibliothèque : collection dynamique d'après une recherche", function()
    local a = photoRaw()
    a.brut.rating = 5
    photoJpeg()
    S.active = a
    local cree = Commandes.executer('collections', { action = 'creer', nom = "Cinq étoiles", recherche = { note_min = 5 }, etape = 'c' })
    egal(cree.collection.dynamique, true)
    local c = S.collections[1]
    egal(#c:getPhotos(), 1)
    echoue(function() Commandes.executer('collections', { action = 'ajouter', collection = cree.collection.id, etape = 'c' }) end, "dynamique")
    echoue(function() Commandes.executer('collections', { action = 'creer', nom = "Juillet", recherche = { date_debut = '2026-07-01' }, etape = 'c' }) end, "pas les dates exactes")
end)

test("Bibliothèque : recherche par critères, filtre des dates, tri et pages", function()
    local a, b, c = photoRaw(), photoJpeg(), photoFuji()
    a.brut.rating, b.brut.rating, c.brut.rating = 3, 4, 5
    a.brut.dateTimeOriginal = S.maintenant - 2 * 86400    -- 19 juillet
    b.brut.dateTimeOriginal = S.maintenant - 40 * 86400   -- 11 juin
    c.brut.dateTimeOriginal = S.maintenant - 1 * 86400    -- 20 juillet
    local resultat = Commandes.executer('chercher', { note_min = 3, depuis_jours = 30 })
    egal(resultat.total, 2)
    egal(resultat.photos[1].id, 1, "triées par date de prise de vue")
    egal(resultat.photos[2].id, 4)
    resultat = Commandes.executer('chercher', { note_min = 4, tri = 'note' })
    egal(resultat.photos[1].note, 5)
    resultat = Commandes.executer('chercher', { note_min = 1, date_debut = '2026-07-20', date_fin = '2026-07-20' })
    egal(resultat.total, 1)
    egal(resultat.photos[1].id, 4)
    resultat = Commandes.executer('chercher', { note_min = 1, limite = 1, decalage = 1 })
    egal(resultat.total, 3)
    egal(resultat.renvoyees, 1)
    egal(resultat.photos[1].id, 1)
    resultat = Commandes.executer('chercher', { appareil = 'x-h2s', format = 'raw' })
    egal(resultat.total, 1)
    echoue(function() Commandes.executer('chercher', {}) end, "Aucun critère")
    echoue(function() Commandes.executer('chercher', { date_debut = '2026-07-01' }) end, "Préciser la recherche")
    echoue(function() Commandes.executer('chercher', { note_min = 1, date_debut = '1er juillet' }) end, "AAAA-MM-JJ")
end)

test("Bibliothèque : recherche par mot-clé, libellé, drapeau et retouche de Claude", function()
    local a, b = photoRaw(), photoJpeg()
    S.active = a
    classer({ ajouter = { 'Lac' }, libelle = 'vert', drapeau = 'retenue' })
    appliquer({ reglages = { Exposure2012 = 0.2 } })
    egal(Commandes.executer('chercher', { mots_cles = 'lac' }).total, 1)
    egal(Commandes.executer('chercher', { libelle = 'vert' }).photos[1].libelle, 'vert')
    egal(Commandes.executer('chercher', { drapeau = 'retenue' }).photos[1].drapeau, 'retenue')
    egal(Commandes.executer('chercher', { retouchee_par_claude = true }).total, 1)
    egal(Commandes.executer('chercher', { retouchee_par_claude = false }).photos[1].id, 2)
    egal(Commandes.executer('chercher', { sans_mots_cles = true }).total, 1)
    egal(Commandes.executer('chercher', { texte = 'lac' }).total, 1)
    local details = Commandes.executer('chercher', { mots_cles = 'lac', mots_cles_details = true })
    egal(details.photos[1].mots_cles[1], 'Lac')
end)

test("Bibliothèque : recherche dans un dossier ou une collection", function()
    local a, b, c = photoRaw(), photoJpeg(), photoFuji()
    a.brut.path = '/Photos/2026/07/DSC_0412.NEF'
    b.brut.path = '/Photos/2026/07/jour 2/IMG_0001.JPG'
    c.brut.path = '/Photos/2026/06/XH2S0320.RAF'
    egal(Commandes.executer('chercher', { dossier = '/Photos/2026/07' }).total, 2)
    egal(Commandes.executer('chercher', { dossier = '/Photos/2026/07', sous_dossiers = false }).total, 1)
    echoue(function() Commandes.executer('chercher', { dossier = '/Ailleurs' }) end, "Dossier introuvable")
    S.active, S.selection = a, { a, c }
    Commandes.executer('collections', { action = 'creer', nom = "Choix", selection = true, etape = 'c' })
    egal(Commandes.executer('chercher', { collection = 'Choix', format = 'RAW' }).total, 2)
    egal(Commandes.executer('chercher', { collection = 'Choix', dossier = '/Photos/2026/06' }).total, 1)
end)

test("Bibliothèque : copie virtuelle nommée, sélection remise", function()
    local original = photoRaw()
    local autre = photoJpeg()
    S.active, S.selection = autre, { autre }
    local resultat = Commandes.executer('copieVirtuelle', { photos = { 1 }, nom = "Claude" })
    egal(#resultat.copies, 1)
    local copie = S.photos[resultat.copies[1].id]
    egal(copie.meta.copyName, "Claude")
    egal(resultat.copies[1].original, 1)
    egal(S.active, autre, "la sélection d'avant est remise")
    egal(contient({ resultat.a_savoir }, "undo_last"), true)
    resultat = Commandes.executer('copieVirtuelle', { photos = { 1 }, afficher = true })
    egal(S.active.localIdentifier, resultat.copies[1].id, "la copie est montrée")
end)

test("Bibliothèque : une photo hors du film fixe fait afficher son dossier", function()
    local photo = photoRaw()
    photo.brut.path = '/Photos/2026/07/DSC_0412.NEF'
    S.invisibles[1] = true
    local resultat = Commandes.executer('montrer', { photos = { 1 }, module = 'developpement' })
    egal(S.active, photo)
    egal(S.module, 'develop')
    egal(resultat.source_changee, true)
    S.module = 'library'
    resultat = Commandes.executer('montrer', { photos = { 1 } })
    egal(S.vue, 'loupe')
    egal(resultat.source_changee, false)
    photoJpeg()
    Commandes.executer('montrer', { photos = { 1, 2 } })
    egal(S.vue, 'grid')
end)

test("Bibliothèque : avant/après dans le module Développement, ensemble dans la Bibliothèque", function()
    photoRaw()
    local resultat = Commandes.executer('montrer', { photos = { 1 }, vue = 'avant_apres' })
    egal(S.module, 'develop', "l'avant/après est une vue du module Développement")
    egal(S.vue, 'develop_before_after_horiz')
    egal(resultat.module, "Développement")
    egal(tostring(resultat.a_savoir):find("pas l'état d'avant Claude", 1, true) ~= nil, true, "la limite est dite")
    photoJpeg()
    resultat = Commandes.executer('montrer', { photos = { 1, 2 }, vue = 'ensemble' })
    egal(S.module, 'library')
    egal(S.vue, 'survey')
    egal(resultat.a_savoir, nil)
end)

test("Bibliothèque : copie virtuelle refusée en mode « Proposer d'abord » sans accord", function()
    photoRaw()
    S.prefs.mode = 'proposer'
    echoue(function() Commandes.executer('copieVirtuelle', { photos = { 1 } }) end, "create_virtual_copy")
    egal(S.photos[1].copies, nil)
end)

-- Liaison ------------------------------------------------------------------------------

test("Liaison : réponse sur la prise, avec l'identifiant de la commande", function()
    Liaison.prise = { send = function(self, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    Liaison.recevoir(ligne({ id = 3, command = 'ping', params = {} }))
    egal(S.envois[1], '{"id":3,"result":{"pong":true,"version":"' .. Liaison.VERSION .. '"}}\n', "le ping donne la version du module")

    Liaison.recevoir(ligne({ id = 4, command = 'pivoter' }))
    egal(S.envois[2], '{"error":"Commande inconnue : pivoter","id":4}\n')

    Liaison.recevoir('pas du json')
    egal(#S.envois, 2, "message illisible ignoré")
    egal(contient(Liaison.journal, "Message illisible ignoré"), true)
    Liaison.prise = nil
end)

test("Liaison : textes d'état et messages d'erreur", function()
    Liaison.actif = false
    egal(Liaison.texteEtat(), "Liaison arrêtée")
    Liaison.actif = true
    Liaison.erreur = nil
    Liaison.dernierEchange = nil
    egal(Liaison.texteEtat(), "Liaison active, prête pour Claude")
    Liaison.dernierEchange = 0
    egal(Liaison.texteEtat(), "Liaison active, prête pour Claude (dernier échange à 12:00:00)")
    Liaison.pause = true
    egal(Liaison.texteEtat():find("en pause", 1, true) ~= nil, true)
    Liaison.erreur = "address already in use"
    egal(Liaison.texteEtat(), "Liaison en erreur : address already in use")
    Liaison.actif, Liaison.erreur = false, nil
    egal(Liaison.messageErreur("Commandes.lua:42: Aucune photo"), "Aucune photo")
    egal(Liaison.messageErreur("Aucune photo"), "Aucune photo")
end)

test("Liaison : sans prise des réponses, la réponse est abandonnée après l'attente", function()
    Liaison.prise = nil
    Liaison.reponsesConnectee = false
    Liaison.recevoir(ligne({ id = 5, command = 'ping', params = {} }))
    egal(#S.envois, 0)
end)

test("Suivi : journal du plus récent au plus ancien", function()
    local Suivi = require 'Suivi'
    egal(Suivi.journalRecentEnTete({ "10:00  a", "10:01  b", "10:02  c" }), "10:02  c\n10:01  b\n10:00  a")
    egal(Suivi.journalRecentEnTete({}), "")
end)

-- Version 1.9 : tri d'une séance (vignettes), suppression des reflets --------------------------

test("vignettes : une vignette par photo, écrite dans un dossier temporaire, avec sa description", function()
    local raw, jpeg = photoFuji(), photoJpeg()
    raw.brut.path = '/Volumes/Photos/DSCF0001.RAF'
    raw.reglages.CropLeft, raw.reglages.CropRight, raw.reglages.CropAngle = 0.1, 0.9, 2
    S.active, S.selection = raw, { raw }
    local resultat = Commandes.executer('vignettes', { photos = Json.tableau({ raw.localIdentifier, jpeg.localIdentifier }), taille = 1024 })
    egal(resultat.taille, 1024)
    egal(#resultat.photos, 2)
    egal(#S.vignettesDemandees, 2, "une requête par photo")
    egal(S.vignettesDemandees[1].largeur, 1024, "taille demandée (un minimum)")
    local premiere = resultat.photos[1]
    egal(premiere.id, raw.localIdentifier)
    egal(premiere.vignette:match('^/tmp/Developpeur/vignettes%-%d+/%d+%.jpg$') ~= nil, true, premiere.vignette)
    egal(S.fichiers[premiere.vignette], 'JPEG ' .. raw.localIdentifier .. ' 1024', "le JPEG est écrit tel quel")
    egal(premiere.chemin_original, '/Volumes/Photos/DSCF0001.RAF')
    egal(premiere.geometrie.cadre.CropLeft, 0.1, "le cadre, pour situer le point de mise au point")
    egal(premiere.geometrie.cadre.CropAngle, 2)
    egal(resultat.photos[2].geometrie.cadre, nil, "pas de cadre sans recadrage")
    egal(premiere.fichier:find(raw.meta.fileName, 1, true), 1, "description de la photo")
end)

test("vignettes : rappels différés attendus, échec d'une photo sans bloquer les autres, limites", function()
    local a, b, c = photoRaw(), photoJpeg(), photoFuji()
    S.vignettesDifferees = true
    b.vignetteImpossible = "aperçu introuvable"
    local Vignettes = require 'Vignettes'
    local delai = Vignettes.DELAI
    Vignettes.DELAI = 2
    c.vignetteJamais = true
    local resultat = Commandes.executer('vignettes', { photos = Json.tableau({ a.localIdentifier, b.localIdentifier, c.localIdentifier, 777 }) })
    Vignettes.DELAI = delai
    egal(resultat.photos[1].vignette ~= nil, true, "rappel différé attendu")
    egal(resultat.photos[2].vignette, nil)
    egal(resultat.photos[2].erreur:find("aperçu introuvable", 1, true) ~= nil, true, resultat.photos[2].erreur)
    egal(resultat.photos[3].erreur:find("Pas de vignette après", 1, true) ~= nil, true)
    egal(resultat.photos[4].erreur:find("777", 1, true) ~= nil, true, "photo inconnue")
    echoue(function() Commandes.executer('vignettes', {}) end, "Aucune photo")
    local trop = Json.tableau()
    for i = 1, Vignettes.MAX_PAR_COMMANDE + 1 do trop[i] = a.localIdentifier end
    echoue(function() Commandes.executer('vignettes', { photos = trop }) end, "Au plus")
end)

local function reflets(params)
    params.etape = params.etape or 'reflets'
    return Commandes.executer('supprimer', params)
end

-- Relevé dans le code de Lightroom Classic 15.6 : toggleReflectionRemoval pose le filtre
-- dereflect à la fin d'un calcul en arrière-plan, sur la photo affichée dans Développement.
test("supprimer : reflets calculés dans le module Développement, attendus, vue remise, annulation", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    local resultat = reflets({ reflets = { actif = true, intensite = 80, qualite = 'standard' }, raison = "Reflets de vitre." })
    egal(S.modulesOuverts[1], 'develop', "photo affichée dans le module Développement")
    egal(S.module, 'library', "vue d'avant remise")
    egal(S.outil, 'loupe', "outil d'avant remis après avoir lu le panneau Reflets")
    egal(#S.appelsReflets, 1)
    egal(S.appelsReflets[1].intensite, 80)
    egal(photo.reglages.FilterList.Filters[1].Name, 'Reflections')
    egal(require('Suppression').intensite(photo.reglages.FilterList.Filters[1]), 80, "intensité lue dans BlendParams")
    local changement = resultat.resultats[1].changements[1]
    egal(changement.cle, 'Suppression.reflets')
    egal(changement.avant, 0)
    egal(changement.apres, 80)
    egal(resultat.resultats[1].reflets.reflets, true)
    local etapes = Json.decode(photo.proprietes.etapesClaude)
    egal(etapes[1].avant.Suppression.reflets, false, "l'état d'avant est mémorisé")
    egal(Json.decode(photo.proprietes.avantClaude).Suppression.reflets, false)

    resultat = reflets({ reflets = { actif = true, intensite = 80 } })
    egal(contient(resultat.resultats[1].remarques, "déjà l'état de la photo"), true)

    -- Constaté : changeReflectionRemovalAmount ne change pas le filtre rangé ; le module le retire
    -- puis le repose.
    resultat = reflets({ reflets = { actif = true, intensite = 50 }, etape = 'moins fort' })
    local Suppression = require 'Suppression'
    egal(Suppression.intensite(photo.reglages.FilterList.Filters[1]), 50)
    egal(resultat.resultats[1].changements[1].avant, 80)
    egal(resultat.resultats[1].changements[1].apres, 50)
    egal(S.appelsReflets[#S.appelsReflets].fonction, 'toggleReflectionRemoval')

    Commandes.executer('annuler', {})
    egal(Suppression.intensite(photo.reglages.FilterList.Filters[1]), 80, "retour à l'intensité d'avant")
    resultat = Commandes.executer('annuler', {})
    egal(resultat.resultats[1].annulee, true)
    egal(#photo.reglages.FilterList.Filters, 0, "les reflets sont rendus")
    egal(S.module, 'library')
    egal(#photo.appliques, 0, "jamais par applyDevelopSettings")
end)

test("supprimer : photo pas prise en charge, pas chargée, rien de lancé ; retour à l'origine ; refus", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    photo.refletsNonPris = true
    local resultat = reflets({ reflets = { actif = true } })
    egal(contient(resultat.resultats[1].remarques, "ne permet pas la suppression des reflets"), true)
    egal(photo.proprietes.etapesClaude, nil, "rien de mémorisé")
    photo.refletsNonPris = false

    reflets({ reflets = { actif = true } })
    egal(require('Suppression').intensite(photo.reglages.FilterList.Filters[1]), 100, "intensité de Lightroom par défaut")
    Commandes.executer('revenir', {})
    egal(#photo.reglages.FilterList.Filters, 0, "revenir retire les reflets")
    egal(photo.proprietes.avantClaude, nil)

    echoue(function() reflets({ reflets = { actif = true, intensite = 140 } }) end, "de 1 à 100")
    echoue(function() reflets({ reflets = { actif = true, qualite = 'max' } }) end, "preview, standard ou best")
    echoue(function() reflets({}) end, "Rien à supprimer")
    S.prefs.mode = 'proposer'
    echoue(function() reflets({ reflets = { actif = true } }) end, "remove_distractions avec confirm")
end)

test("supprimer : comparaison et résumé d'une étape de reflets", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    reflets({ reflets = { actif = true, intensite = 70 } })
    echoue(function() Commandes.executer('apercu', { comparer = 'etapePrecedente', cles = {} }) end, "reflets")
    local resultat = Commandes.executer('annuler', {})
    egal(resultat.resultats[1].reglages_remis.Suppression, "reflets laissés")
end)

-- Version 1.9 : retouche avancée (plage de couleurs, de profondeur, objet par un rectangle,
-- couleurs ponctuelles dans un masque) ------------------------------------------------------------

test("masquer : objet désigné par un rectangle, des points {X, Y}, calculé par Lightroom", function()
    -- Constaté le 17 octobre 2026 : des points en textes font rejeter le geste ; des tables {X, Y} non.
    local photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', { masques = { { type = 'objet', nom = 'Claude · Objet', locaux = { LocalExposure2012 = -0.25 },
        rectangle = { x = 0.4, y = 0.14, largeur = 0.6, hauteur = 0.62 } } }, etape = 'objet' })
    local objet = photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1]
    egal(objet.What, 'Mask/Image')
    egal(objet.Gesture[1].What, 'Mask/Polygon')
    egal(#objet.Gesture[1].Points, 4)
    proche(objet.Gesture[1].Points[1].X, 0.4)
    proche(objet.Gesture[1].Points[3].Y, 0.76)
    egal(objet.ReferencePoint, '0.700000 0.450000')
    egal(objet.MaskDigest, 'calculé pour 4', "calculé (updateAISettings)")

    -- Des points en textes : Lightroom retire le geste (la règle de la simulation).
    local Locaux = require 'Locaux'
    local m = Locaux.objetRectangle({ { 0.1, 0.1 }, { 0.2, 0.1 }, { 0.2, 0.2 } }, 'x', false)
    m.Gesture[1].Points = { '0.1 0.1', '0.2 0.1', '0.2 0.2' }
    local autre = photoRaw()
    S.ecritureEnCours = true
    autre:applyDevelopSettings({ MaskGroupBasedCorrections = { Locaux.correction('x', 1, {}, { m }) } }, 'essai')
    S.ecritureEnCours = false
    egal(autre.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].ErrorReason, 1)
    egal(autre.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].Gesture, nil)
end)

test("masquer : plage de couleurs prélevée, rangée comme Lightroom (PointModels)", function()
    local photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', { masques = { { type = 'couleur', nom = 'Claude · Plage de couleurs', etendue = 0.6,
        locaux = { LocalExposure2012 = -0.1 },
        prelevements = { { x = 0.1, y = 0.47, modele = { 0.76, 0.41, 0.21 } }, { x = 0.2, y = 0.3, modele = { 0.7, 0.45, 0.3 } } } } },
        etape = 'ciel' })
    local m = photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1]
    egal(m.What, 'Mask/RangeMask')
    egal(m.CorrectionRangeMask.Type, 1)
    egal(m.CorrectionRangeMask.ColorAmount, 0.6)
    egal(m.CorrectionRangeMask.PointModels[1], '0.760000 0.410000 0.210000 0.100000 0.470000 0')
    egal(#m.CorrectionRangeMask.PointModels, 2)
    proche(m.CorrectionReferenceX, 0.1)
    egal(photo.appliques[#photo.appliques].preset, nil, "pas un masque IA : par applyDevelopSettings")
    echoue(function()
        Commandes.executer('masquer', { masques = { { type = 'couleur', nom = 'x', locaux = {}, prelevements = {} } }, etape = 'x' })
    end, "sans couleur prélevée")
end)

test("masquer : plage de profondeur rangée en DepthRange de 0 à 1", function()
    local photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', { masques = { { type = 'profondeur', nom = 'Claude · Plage de profondeur', min = 0, max = 0.35, fondu = 0.1,
        locaux = { LocalExposure2012 = -0.5 } } }, etape = 'proche' })
    local r = photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].CorrectionRangeMask
    egal(r.Type, 3)
    egal(r.DepthRange, '0.000000 0.000000 0.350000 0.450000')
    egal(r.LumRange, nil)
end)

test("masquer : couleurs ponctuelles dans le masque, en textes de 19 nombres (LocalPointColors)", function()
    local photo = photoFuji()
    S.active = photo
    local couleur = { SrcHue = 0.95, SrcSat = 0.45, SrcLum = 0.65, HueShift = 1, SatScale = -1, LumScale = 0, RangeAmount = 0.8,
        HueRange = { LowerNone = 0, LowerFull = 0.33, UpperFull = 0.67, UpperNone = 1 },
        SatRange = { LowerNone = 0, LowerFull = 0, UpperFull = 1, UpperNone = 1 },
        LumRange = { LowerNone = 0, LowerFull = 0, UpperFull = 1, UpperNone = 1 }, Variance = 0 }
    Commandes.executer('masquer', { masques = { { type = 'radial', nom = 'Claude · Dégradé radial', centre_x = 0.5, centre_y = 0.5,
        rayon_x = 2, fondu = 0, locaux = {}, couleurs_ponctuelles = { couleur } } }, etape = 'couleur locale' })
    local correction = photo.reglages.MaskGroupBasedCorrections[1]
    egal(correction.LocalPointColors[1], '0.950000, 0.450000, 0.650000, 1.000000, -1.000000, 0.000000, 0.800000, '
        .. '0.000000, 0.330000, 0.670000, 1.000000, 0.000000, 0.000000, 1.000000, 1.000000, 0.000000, 0.000000, 1.000000, 1.000000')
end)

-- Version 2.0 : garde-fous des photos, accord dans Lightroom, retour visuel, journal du module -----

local function plusieurs(n)
    local liste = Json.tableau()
    for i = 1, n do
        local photo = S.Photo(500 + i, { Exposure2012 = 0, ProcessVersion = '15.4' }, { fileName = 'P' .. i .. '.JPG', fileFormat = 'JPG' })
        liste[i] = photo.localIdentifier
    end
    return liste
end

test("garde-fous : copies virtuelles seulement, libellé protégé, photos rejetées", function()
    local original = photoRaw()
    S.active = original
    S.prefs.copiesSeulement = true
    echoue(function() appliquer({ reglages = { Exposure2012 = 0.2 } }) end, "pas une copie virtuelle")
    echoue(function() Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.2 }, taille = 512 }) end, "protégées")
    echoue(function() Commandes.executer('metadonnees', { note = 3, etape = 'x' }) end, "protégées")
    egal(original.reglages.Exposure2012, 0, "rien n'a été écrit")
    local copie = S.copieVirtuelle(original, 77, 'Copie 1')
    S.active = copie
    appliquer({ reglages = { Exposure2012 = 0.2 }, plages = { Exposure2012 = { -5, 5 } } })
    egal(copie.reglages.Exposure2012, 0.2, "une copie virtuelle se retouche")
    S.prefs.copiesSeulement = false

    S.prefs.libelleProtege = 'rouge'
    original.meta.label = 'Rouge'
    S.active = original
    echoue(function() appliquer({ reglages = { Exposure2012 = 0.2 } }) end, "libellé rouge protégé")
    S.prefs.libelleProtege = 'aucun'
    original.meta.label = nil
    S.prefs.rejeteesProtegees = true
    original.brut.pickStatus = -1
    echoue(function() Commandes.executer('ameliorer', { ameliorations = Json.tableau({ { nom = 'denoise', actif = true } }), etape = 'x' }) end, "rejetée")
    original.brut.pickStatus = 0
    -- Annuler et revenir défont ce que Claude a fait, même sur une photo protégée.
    S.active = copie
    S.prefs.copiesSeulement = true
    egal(Commandes.executer('annuler', {}).resultats[1].annulee, true)
end)

test("garde-fous : plafond de photos par écriture, levé par un accord explicite", function()
    local ids = plusieurs(21)
    echoue(function() appliquer({ photos = ids, reglages = { Exposure2012 = 0.1 } }) end, "21 photos visées : plus que le plafond de 20")
    egal(S.photos[501].reglages.Exposure2012, 0)
    local resultat = appliquer({ photos = ids, reglages = { Exposure2012 = 0.1 }, plages = { Exposure2012 = { -5, 5 } }, confirme = true })
    egal(#resultat.resultats, 21, "accord explicite : les 21 photos")
    S.prefs.plafondPhotos = 0
    appliquer({ photos = ids, reglages = { Exposure2012 = 0.2 }, plages = { Exposure2012 = { -5, 5 } } })
    egal(S.photos[521].reglages.Exposure2012, 0.2, "sans plafond")
end)

test("accord dans Lightroom : confirm ne suffit pas, l'utilisateur accepte dans la fenêtre de suivi", function()
    local photo = photoRaw()
    S.active = photo
    S.prefs.mode, S.prefs.accordDansLightroom = 'proposer', true
    local essai = Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } },
        taille = 512, etape = 'passe 1' })
    egal(essai.etape ~= nil, true)
    egal(Liaison.propositionEnAttente.etape, 'Claude · essai : passe 1', "la proposition attend dans la fenêtre de suivi")
    echoue(function() appliquer({ reglages = { Exposure2012 = 0.3 }, confirme = true }) end, "bouton Accepter")
    egal(photo.reglages.Exposure2012, 0)
    Liaison.repondreProposition(true)
    appliquer({ reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } }, confirme = true })
    egal(photo.reglages.Exposure2012, 0.3, "accepté dans Lightroom")
    echoue(function() appliquer({ reglages = { Exposure2012 = 0.4 }, confirme = true }) end, "bouton Accepter")
    Liaison.repondreProposition(false)
    echoue(function() appliquer({ reglages = { Exposure2012 = 0.4 }, confirme = true }) end, "a refusé")
    -- La Bibliothèque aussi.
    echoue(function() Commandes.executer('metadonnees', { note = 2, etape = 'x', confirme = true }) end, "bouton Accepter")
    local Suivi = require 'Suivi'
    egal(Suivi.ligneEtat():find("accord donné ici", 1, true) ~= nil, true)
    egal(Suivi.textePropositon():find("attend votre accord", 1, true) ~= nil, true)
end)

test("retour visuel et journal du module : un message par écriture, une ligne par événement, rotation", function()
    local photo = photoRaw()
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } }, etape = 'passe 1' })
    egal(S.bezels[#S.bezels], "Claude · passe 1 : 1 changement")
    S.prefs.retourVisuel = false
    appliquer({ reglages = { Exposure2012 = 0.4 }, plages = { Exposure2012 = { -5, 5 } } })
    egal(#S.bezels, 1, "retour visuel coupé")
    local _, chemin = Liaison.cheminJournal()
    egal(chemin, S.home .. '/Library/Logs/Developpeur/module.log')
    egal(S.fichiers[chemin]:find("Claude · passe 1 : 1 changement(s) sur", 1, true) ~= nil, true, "écrit dans le journal du module")
    local photoDuJournal = Liaison.journalPhotos[#Liaison.journalPhotos]
    egal(photoDuJournal, photo.localIdentifier, "la ligne garde sa photo")
    local taille = Liaison.TAILLE_JOURNAL
    Liaison.TAILLE_JOURNAL = 10
    Liaison.noter("après rotation")
    Liaison.TAILLE_JOURNAL = taille
    egal(S.fichiers[chemin .. '.1'] ~= nil, true, "l'ancien journal devient module.log.1")
    egal(S.fichiers[chemin]:find("après rotation", 1, true) ~= nil, true)
    local Suivi = require 'Suivi'
    local lignes = Suivi.lignesJournal(Liaison.journal)
    egal(lignes[1].value, #Liaison.journal, "le plus récent en haut")
end)

test("arrêt du module : les paramètres prédéfinis invisibles sont effacés", function()
    local dossier = S.home .. '/Library/Application Support/Adobe/Lightroom/Plugin Develop Presets/com.danymenard.developpeur'
    S.fichiers[dossier] = 'dossier'
    S.fichiers[dossier .. '/Claude · masques IA 1A2B.lrtemplate'] = 's = {}'
    S.fichiers[dossier .. '/Claude · flou 3C4D.lrtemplate'] = 's = {}'
    S.fichiers[dossier .. '/autre.txt'] = 'garde'
    dofile(dossierModule .. 'Arret.lua')
    egal(S.fichiers[dossier .. '/Claude · masques IA 1A2B.lrtemplate'], nil)
    egal(S.fichiers[dossier .. '/Claude · flou 3C4D.lrtemplate'], nil)
    egal(S.fichiers[dossier .. '/autre.txt'], 'garde')
    egal(contient(Liaison.journal, "2 paramètre(s) prédéfini(s) invisible(s)"), true)
end)

-- Constaté le 17 octobre 2026 : Arret.lua ne s'exécute pas à la fermeture de Lightroom.
test("chargement du module : les paramètres prédéfinis invisibles de la session précédente sont effacés", function()
    local dossier = S.home .. '/Library/Application Support/Adobe/Lightroom/Plugin Develop Presets/com.danymenard.developpeur'
    S.fichiers[dossier] = 'dossier'
    S.fichiers[dossier .. '/Claude · masques IA 9F.lrtemplate'] = 's = {}'
    dofile(dossierModule .. 'Init.lua')
    egal(S.fichiers[dossier .. '/Claude · masques IA 9F.lrtemplate'], nil)
    egal(contient(Liaison.journal, "de la session précédente"), true)
end)

test("photo hors du film fixe : son dossier s'affiche le temps du débruitage, puis la source revient", function()
    local affichee = photoRaw()
    local cachee = photoFuji()
    cachee.brut.path = '/Volumes/Photos/Gaspesie/DSCF0001.RAF'
    S.active, S.selection = affichee, { affichee }
    S.sources = { { nom = 'Recette' } }
    S.invisibles[cachee.localIdentifier] = true
    local resultat = Commandes.executer('ameliorer', { photo = cachee.localIdentifier, ameliorations = Json.tableau({ { nom = 'denoise', actif = true, intensite = 30 } }),
        etape = 'débruitage' })
    egal(resultat.resultats[1].changements[1].cle, 'Amelioration.denoise', "le dossier affiché, le débruitage se fait")
    egal(S.sourcesChangees[1][1].chemin, '/Volumes/Photos/Gaspesie')
    egal(S.sources[1].nom, 'Recette', "la source d'avant revient")
    egal(S.active, affichee, "la photo active revient")
end)

-- Constaté le 21 octobre 2026 (mesures de la 1.3) : la photo active d'avant ne revenait pas après
-- un débruitage, son annulation ou une variante retenue ; remise aussitôt après setActiveSources,
-- sa sélection n'était pas prise (règle de la simulation, setActiveSources).
test("photo hors du film fixe : après un débruitage puis son annulation, la photo active et la sélection d'avant reviennent", function()
    local affichee, autre = photoRaw(), photoJpeg()
    local cachee = photoFuji()
    cachee.brut.path = '/Volumes/Photos/Gaspesie/DSCF0001.RAF'
    local essais = { { nom = 'Développeur › Essais' } }
    S.sources = essais
    S.active, S.selection = affichee, { affichee, autre }
    S.invisibles[cachee.localIdentifier] = true
    debruiter({ photo = cachee.localIdentifier, ameliorations = demande('denoise', true, 30) })
    egal(cachee.amelioration.denoise, true)
    egal(S.sources, essais, "la source d'avant revient")
    egal(S.active, affichee, "la photo active d'avant revient")
    egal(#S.selection, 2, "avec la sélection d'avant")
    egal(S.selection[2], autre)
    egal(S.invisibles[cachee.localIdentifier], true, "la photo traitée ressort du film fixe")
    -- L'annulation repasse par le module Développement (Amelioration.remettreAmelioration).
    local resultat = Commandes.executer('annuler', { photos = { cachee.localIdentifier } })
    egal(resultat.resultats[1].annulee, true)
    egal(cachee.amelioration.denoise, false, "débruitage retiré")
    egal(S.sources, essais)
    egal(S.active, affichee, "la photo active d'avant revient après l'annulation")
    egal(#S.selection, 2)
    egal(contient(Liaison.journal, "non remise"), false)
end)

test("photo active d'avant sortie du film fixe entre-temps : rien ne la force, le journal le dit", function()
    local affichee = photoRaw()
    local cachee = photoFuji()
    cachee.brut.path = '/Volumes/Photos/Gaspesie/DSCF0001.RAF'
    local essais = { { nom = 'Développeur › Essais' } }
    S.sources = essais
    S.active, S.selection = affichee, { affichee }
    S.invisibles[cachee.localIdentifier] = true
    local horloge = S.horloge
    -- Pendant le traitement, la photo d'avant quitte la source (filtre changé à la main).
    S.pendantAttente = function()
        if S.visiblesSous[essais] then
            S.visiblesSous[essais][affichee.localIdentifier] = nil
        end
    end
    debruiter({ photo = cachee.localIdentifier, ameliorations = demande('denoise', true, 30) })
    S.pendantAttente = nil
    egal(S.sources, essais, "la source d'avant revient quand même")
    egal(S.active ~= affichee, true)
    egal(contient(Liaison.journal, "Photo active d'avant non remise : « DSC_0412.NEF »"), true)
    egal(S.horloge - horloge < 30, true, "l'attente est bornée")
end)

test("copie virtuelle d'une photo hors du film fixe : la photo active et la source d'avant reviennent", function()
    local affichee = photoRaw()
    local cachee = photoFuji()
    cachee.brut.path = '/Volumes/Photos/Gaspesie/DSCF0001.RAF'
    local essais = { { nom = 'Développeur › Essais' } }
    S.sources = essais
    S.active, S.selection = affichee, { affichee }
    S.invisibles[cachee.localIdentifier] = true
    local resultat = Commandes.executer('copieVirtuelle', { photos = { cachee.localIdentifier } })
    egal(#resultat.copies, 1)
    egal(S.sources, essais, "la source d'avant revient")
    egal(S.active, affichee, "la photo active d'avant revient")
end)


test("liaison : une photo active changée part une fois avec la réponse suivante, avec la nouvelle photo", function()
    local premiere, seconde = photoRaw(), photoFuji()
    seconde.localIdentifier = 2
    S.photos[2] = seconde
    S.active = premiere
    Liaison.derniereActive = premiere.localIdentifier
    local envoyes = {}
    Liaison.prise = { send = function(_, texte) envoyes[#envoyes + 1] = texte end }
    Liaison.reponsesConnectee = true
    S.active = seconde
    Liaison.photoActiveChangee = true
    Liaison.repondre({ id = 1, result = {} })
    Liaison.repondre({ id = 2, result = {} })
    local evenements = Json.decode(envoyes[1]).evenements
    egal(evenements.photo_active, true)
    egal(evenements.id, 2, "la nouvelle photo active")
    egal(type(evenements.fichier), 'string')
    egal(Json.decode(envoyes[2]).evenements, nil, "une seule fois")
    -- Un aperçu qui affiche une autre photo puis remet la vue : la photo active n'a pas changé.
    Liaison.photoActiveChangee = true
    Liaison.repondre({ id = 3, result = {} })
    egal(Json.decode(envoyes[3]).evenements, nil, "même photo active : rien à signaler")
    Liaison.prise, Liaison.reponsesConnectee, Liaison.derniereActive = nil, false, nil
end)

test("liaison : une proposition en attente d'accord n'est pas notée comme un refus", function()
    local photo = photoRaw()
    S.active = photo
    S.prefs.mode, S.prefs.accordDansLightroom = 'proposer', true
    Liaison.journal, Liaison.journalPhotos = {}, {}
    Liaison.prise = { send = function() end }
    Liaison.reponsesConnectee = true
    Liaison.recevoir(ligne({ id = 7, command = 'appliquer', params = { reglages = { Exposure2012 = 0.2 }, plages = { Exposure2012 = { -5, 5 } },
        confirme = true, etape = 'passe 3 : bougies', raison = "Flammes encore brûlées." } }))
    local journal = table.concat(Liaison.journal, "\n")
    egal(journal:find("Proposition en attente", 1, true) ~= nil, true)
    egal(journal:find("Refusé", 1, true), nil, "pas de « Refusé » pour une proposition qui attend")
    egal(Liaison.propositionEnAttente.detail, "Flammes encore brûlées.", "la raison s'affiche avec la proposition")
    Liaison.prise, Liaison.reponsesConnectee, Liaison.propositionEnAttente = nil, false, nil
end)

-- Liaison fermée (1.2) ---------------------------------------------------------------------------

-- Prise des réponses connectée : chaque réponse va dans S.envois, relue en JSON par reponse(i).
local function priseDesReponses()
    Liaison.prise = { send = function(_, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
end

local function reponse(i)
    return Json.decode(S.envois[i or #S.envois])
end

local function compter(liste, morceau)
    local n = 0
    for _, texte in ipairs(liste) do
        if tostring(texte):find(morceau, 1, true) then
            n = n + 1
        end
    end
    return n
end

local function exposer(valeur, extra)
    local params = { reglages = { Exposure2012 = valeur }, plages = { Exposure2012 = { -5, 5 } }, confirme = true, etape = 'passe 1' }
    for cle, v in pairs(extra or {}) do
        params[cle] = v
    end
    return params
end

-- Démarre la liaison dans la simulation : la tâche de la liaison tourne aussitôt, LrSocket.bind
-- rend de fausses prises (notées dans la liste rendue), et pendantTour(n) est appelé à chaque
-- tour de sa boucle (0,5 s) ; il doit finir par arrêter la liaison.
local function demarrerLiaison(pendantTour)
    local LrFunctionContext, LrSocket = import 'LrFunctionContext', import 'LrSocket'
    local poster, lier = LrFunctionContext.postAsyncTaskWithContext, LrSocket.bind
    local prises, tours = {}, 0
    LrFunctionContext.postAsyncTaskWithContext = function(_, fonction) fonction({}) end
    LrSocket.bind = function(args)
        local prise = { port = args.port, fichierAuLien = S.fichiers[select(2, Liaison.cheminJeton())] }
        function prise.close(self) self.fermee = true end
        function prise.reconnect() end
        prises[#prises + 1] = prise
        return prise
    end
    S.pendantAttente = function()
        tours = tours + 1
        if tours > 100 then
            Liaison.arreter()
        elseif pendantTour then
            pendantTour(tours)
        end
    end
    Liaison.actif = false
    local ok, erreur = pcall(Liaison.demarrer)
    LrFunctionContext.postAsyncTaskWithContext, LrSocket.bind = poster, lier
    S.pendantAttente = nil
    if not ok then
        Liaison.actif = false
        error(erreur, 2)
    end
    return prises
end

test("Liaison fermée : une ligne sans jeton est refusée avant la commande, même avec confirme", function()
    local photo = photoRaw()
    S.active = photo
    S.prefs.mode = 'proposer'
    priseDesReponses()
    Liaison.dernierEchange = nil
    Liaison.recevoir(ligne({ id = 8, command = 'appliquer', params = exposer(0.5) }, false))
    local refus = reponse(1)
    egal(refus.id, 8)
    egal(refus.error, Liaison.REFUS_JETON.sans)
    egal(refus.code, 'jeton')
    egal(refus.result, nil)
    egal(#S.ecritures, 0, "rien d'écrit")
    egal(photo.reglages.Exposure2012, 0, "exposition inchangée")
    egal(Liaison.dernierEchange, nil, "une ligne refusée n'est pas un échange")
    egal(contient(Liaison.journal, "Commande refusée sans jeton"), true)
    egal(contient(Liaison.journal, "Refusé :"), false, "noté comme un refus du jeton, pas de la commande")
    -- La même ligne avec le jeton passe : mode « Proposer d'abord » et confirme.
    Liaison.recevoir(ligne({ id = 9, command = 'appliquer', params = exposer(0.5) }))
    egal(reponse(2).error, nil)
    egal(photo.reglages.Exposure2012, 0.5, "écrite avec le jeton")
    Liaison.prise, Liaison.reponsesConnectee = nil, false
end)

test("Liaison fermée : mauvais jeton refusé, même presque juste", function()
    local photo = photoRaw()
    S.active = photo
    S.prefs.mode = 'appliquer'
    priseDesReponses()
    local presque = JETON:sub(1, 63) .. 'c'
    for i, autre in ipairs({ string.rep('cd', 32), presque, JETON:sub(1, 63), JETON .. 'a', 42, '' }) do
        Liaison.recevoir(ligne({ id = i, command = 'appliquer', params = exposer(0.8) }, autre))
        egal(reponse(i).error, Liaison.REFUS_JETON.faux, "jeton " .. tostring(autre))
        egal(reponse(i).code, 'jeton')
    end
    egal(#S.ecritures, 0)
    egal(photo.reglages.Exposure2012, 0, "photo inchangée")
    egal(Liaison.refus, 6)
    egal(contient(Liaison.journal, "Commande refusée : mauvais jeton"), true)
    Liaison.prise, Liaison.reponsesConnectee = nil, false
end)

test("Liaison fermée : ping sans jeton refusé ; avec le bon jeton, pong et version", function()
    priseDesReponses()
    Liaison.recevoir(ligne({ id = 1, command = 'ping', params = {} }, false))
    egal(reponse(1).error, Liaison.REFUS_JETON.sans)
    egal(reponse(1).result, nil, "pas de pong sans jeton")
    Liaison.recevoir(ligne({ id = 2, command = 'ping', params = {} }))
    egal(S.envois[2], '{"id":2,"result":{"pong":true,"version":"' .. Liaison.VERSION .. '"}}\n', "réponse au ping inchangée")
    Liaison.prise, Liaison.reponsesConnectee = nil, false
end)

test("Liaison fermée : liaison sans jeton, tout est refusé, même une ligne qui porte un jeton", function()
    local photo = photoRaw()
    S.active = photo
    priseDesReponses()
    Liaison.jeton = nil
    Liaison.recevoir(ligne({ id = 1, command = 'ping', params = {} }))
    Liaison.recevoir(ligne({ id = 2, command = 'appliquer', params = exposer(0.3) }))
    Liaison.recevoir(ligne({ id = 3, command = 'etat', params = {} }, false))
    for i = 1, 3 do
        egal(reponse(i).error, Liaison.REFUS_JETON.aucun, "ligne " .. i)
        egal(reponse(i).code, 'jeton')
    end
    egal(#S.ecritures, 0)
    egal(contient(Liaison.journal, "la liaison n'a pas de jeton"), true)
    Liaison.prise, Liaison.reponsesConnectee = nil, false
end)

test("Liaison fermée : depuisLightroom venu du réseau est retiré, la pause tient", function()
    local photo = photoRaw()
    S.active = photo
    priseDesReponses()
    Liaison.pause = true
    Liaison.recevoir(ligne({ id = 1, command = 'appliquer', params = exposer(0.5, { depuisLightroom = true }) }))
    egal(reponse(1).error:find("La liaison est en pause", 1, true) ~= nil, true, reponse(1).error)
    egal(#S.ecritures, 0, "rien d'écrit pendant la pause")
    egal(photo.reglages.Exposure2012, 0)
    -- Le drapeau garde son effet par appel direct (menus, fenêtre de suivi, carte Note).
    Commandes.executer('appliquer', exposer(0.5, { depuisLightroom = true }))
    egal(photo.reglages.Exposure2012, 0.5, "appel direct depuis Lightroom")
    Liaison.pause = false
    Liaison.prise, Liaison.reponsesConnectee = nil, false
end)

test("Liaison fermée : depuisLightroom venu du réseau ne saute pas l'accord dans Lightroom", function()
    local photo = photoRaw()
    S.active = photo
    S.prefs.mode, S.prefs.accordDansLightroom = 'proposer', true
    priseDesReponses()
    Liaison.propositionEnAttente = nil
    Liaison.recevoir(ligne({ id = 1, command = 'appliquer', params = exposer(0.4, { depuisLightroom = true }) }))
    egal(Liaison.propositionEnAttente ~= nil, true, "la proposition attend dans la fenêtre de suivi")
    egal(reponse(1).error:sub(1, #Liaison.EN_ATTENTE), Liaison.EN_ATTENTE)
    egal(#S.ecritures, 0)
    egal(photo.reglages.Exposure2012, 0)
    Liaison.prise, Liaison.reponsesConnectee, Liaison.propositionEnAttente = nil, false, nil
end)

test("Liaison fermée : refus notés une fois par 10 s et par genre, tous comptés", function()
    priseDesReponses()
    for i = 1, 3 do
        Liaison.recevoir(ligne({ id = i, command = 'etat', params = {} }, false))
    end
    egal(compter(Liaison.journal, "Commande refusée sans jeton"), 1, "une seule ligne au journal")
    egal(Liaison.refus, 3)
    Liaison.recevoir(ligne({ id = 4, command = 'etat', params = {} }, string.rep('0', 64)))
    egal(compter(Liaison.journal, "mauvais jeton"), 1, "un autre genre se note à part")
    Liaison.recevoir('GET / HTTP/1.1')
    Liaison.recevoir('Host: 127.0.0.1:54770')
    egal(compter(Liaison.journal, "Message illisible ignoré"), 1, "lignes illisibles : une note")
    egal(Liaison.refus, 6)
    S.horloge = S.horloge + 11
    Liaison.recevoir(ligne({ id = 5, command = 'etat', params = {} }, false))
    egal(compter(Liaison.journal, "Commande refusée sans jeton"), 2, "notée de nouveau après 10 s")
    egal(#S.envois, 5, "chaque ligne lisible reçoit son refus ; une illisible, rien")
    local _, chemin = Liaison.cheminJournal()
    egal(select(2, S.fichiers[chemin]:gsub("Commande refusée sans jeton", "")), 2, "module.log : deux lignes, pas quatre")
    Liaison.prise, Liaison.reponsesConnectee = nil, false
end)

test("Liaison fermée : un refus n'emporte pas l'événement de la photo active", function()
    local premiere, seconde = photoRaw(), photoFuji()
    seconde.localIdentifier = 2
    S.photos[2] = seconde
    S.active = premiere
    Liaison.derniereActive = premiere.localIdentifier
    priseDesReponses()
    S.active = seconde
    Liaison.photoActiveChangee = true
    Liaison.recevoir(ligne({ id = 1, command = 'etat', params = {} }, false))
    egal(reponse(1).code, 'jeton')
    egal(reponse(1).evenements, nil, "pas d'événement avec un refus")
    Liaison.recevoir(ligne({ id = 2, command = 'ping', params = {} }))
    egal(reponse(2).evenements.id, 2, "l'événement part avec la réponse suivante, au vrai serveur")
    Liaison.prise, Liaison.reponsesConnectee, Liaison.derniereActive, Liaison.photoActiveChangee = nil, false, nil, false
end)

test("Liaison fermée : preparerJeton, 64 chiffres hexadécimaux, droits 600, rangé d'un coup, un autre à chaque fois", function()
    local _, chemin = Liaison.cheminJeton()
    egal(chemin, S.home .. '/Library/Application Support/Developpeur/liaison.jeton', "là où le serveur le lit")
    local premier = Liaison.preparerJeton()
    egal(type(premier), 'string')
    egal(premier:match('^' .. string.rep('[0-9a-f]', 64) .. '$') ~= nil, true, premier)
    egal(S.fichiers[chemin]:match('^' .. string.rep('[0-9a-f]', 64) .. '\n$') ~= nil, true)
    egal(S.fichiers[chemin], premier .. '\n')
    egal(S.droits[chemin], '600')
    egal(S.fichiers[chemin .. '.nouveau'], nil, "le fichier provisoire a disparu")
    egal(#S.commandesSysteme, 2)
    egal(S.commandesSysteme[1]:find('umask 077', 1, true), 1, "créé vide en 600 avant d'y écrire")
    egal(S.commandesSysteme[2]:find('/bin/mv -f', 1, true), 1, "rangé d'un coup")
    egal(Liaison.lireFichierJeton(), premier)
    local second = Liaison.preparerJeton()
    egal(second ~= premier, true, "un autre jeton à chaque démarrage")
    egal(S.fichiers[chemin], second .. '\n')
    -- Jamais au journal ni sur une ligne de commande, même à moitié.
    for _, jeton in ipairs({ premier, second }) do
        for _, morceau in ipairs({ jeton, jeton:sub(1, 32), jeton:sub(33) }) do
            egal(contient(Liaison.journal, morceau), false, "journal")
            egal(contient(S.commandesSysteme, morceau), false, "commandes du système")
        end
    end
end)

test("Liaison fermée : preparerJeton, aléa illisible ou commande en échec, nil et la raison, rien d'écrit à la place du jeton", function()
    local _, chemin = Liaison.cheminJeton()
    local ancien = string.rep('1', 64) .. '\n'
    S.fichiers[chemin] = ancien
    S.aleaIllisible = true
    local jeton, raison = Liaison.preparerJeton()
    egal(jeton, nil)
    egal(raison, "aléa du système illisible (/dev/urandom)")
    egal(#S.commandesSysteme, 0, "rien tenté sans aléa")
    S.aleaIllisible = 'court'
    jeton, raison = Liaison.preparerJeton()
    egal(jeton, nil, "moins de 32 octets")
    egal(raison, "aléa du système illisible (/dev/urandom)")
    S.aleaIllisible = false
    S.codeCommandes = 1
    jeton, raison = Liaison.preparerJeton()
    egal(jeton, nil)
    egal(raison, "fichier du jeton impossible à créer")
    egal(S.fichiers[chemin], ancien, "l'ancien fichier reste tel quel")
    egal(S.fichiers[chemin .. '.nouveau'], nil)
end)

test("Liaison fermée : lireFichierJeton n'accepte que 64 chiffres hexadécimaux en minuscules", function()
    local _, chemin = Liaison.cheminJeton()
    egal(Liaison.lireFichierJeton(), nil, "fichier absent")
    for _, contenu in ipairs({ '', string.rep('a', 63), string.rep('a', 65), string.rep('A', 64), string.rep('a', 63) .. 'g',
        string.rep('a', 64) .. '\n\n', ' ' .. string.rep('a', 64) }) do
        S.fichiers[chemin] = contenu
        egal(Liaison.lireFichierJeton(), nil, "« " .. contenu .. " »")
    end
    S.fichiers[chemin] = string.rep('0f', 32)
    egal(Liaison.lireFichierJeton(), string.rep('0f', 32), "sans saut de ligne")
    S.fichiers[chemin] = string.rep('0f', 32) .. '\n'
    egal(Liaison.lireFichierJeton(), string.rep('0f', 32), "avec un saut de ligne")
end)

test("Liaison fermée : garderFichierJeton réécrit un fichier effacé ou remplacé ; fichier juste, aucune commande", function()
    local _, chemin = Liaison.cheminJeton()
    Liaison.jeton = Liaison.preparerJeton()
    S.commandesSysteme = {}
    egal(Liaison.garderFichierJeton(), false)
    egal(#S.commandesSysteme, 0, "fichier juste : rien à faire")
    S.fichiers[chemin] = nil
    egal(Liaison.garderFichierJeton(), true, "effacé")
    egal(S.fichiers[chemin], Liaison.jeton .. '\n')
    egal(S.droits[chemin], '600')
    S.fichiers[chemin] = string.rep('0', 64) .. '\n'
    egal(Liaison.garderFichierJeton(), true, "remplacé (démarrage plus ancien)")
    egal(S.fichiers[chemin], Liaison.jeton .. '\n')
    egal(compter(Liaison.journal, "Fichier du jeton réécrit"), 2)
    -- Un échec n'est noté qu'au premier tour qui échoue.
    S.fichiers[chemin] = nil
    S.codeCommandes = 1
    egal(Liaison.garderFichierJeton(), false)
    egal(Liaison.garderFichierJeton(), false)
    egal(compter(Liaison.journal, "Fichier du jeton impossible à réécrire"), 1)
    S.codeCommandes = 0
    egal(Liaison.garderFichierJeton(), true, "réécrit dès que possible")
    -- Liaison sans jeton : rien à garder.
    Liaison.jeton = nil
    S.fichiers[chemin] = nil
    egal(Liaison.garderFichierJeton(), false)
    egal(S.fichiers[chemin], nil)
end)

test("Liaison fermée : memeJeton et refusJeton", function()
    egal(Liaison.memeJeton(JETON, JETON), true)
    egal(Liaison.memeJeton(JETON, string.rep('ab', 32)), true, "texte égal")
    egal(Liaison.memeJeton(JETON, JETON:sub(1, 63)), false, "longueurs différentes")
    egal(Liaison.memeJeton(JETON, nil), false)
    egal(Liaison.memeJeton(nil, nil), false)
    egal(Liaison.memeJeton(42, 42), false, "nombre")
    egal(Liaison.memeJeton(JETON, 'b' .. JETON:sub(2)), false, "premier caractère")
    egal(Liaison.refusJeton(JETON), nil)
    egal(Liaison.refusJeton(nil), 'sans')
    egal(Liaison.refusJeton(string.rep('cd', 32)), 'faux')
    egal(Liaison.refusJeton(Json.null), 'faux')
    Liaison.jeton = nil
    egal(Liaison.refusJeton(JETON), 'aucun')
    egal(Liaison.refusJeton(nil), 'aucun')
end)

test("Liaison fermée : etat dit liaison_fermee, sans le jeton ; le diagnostic dit son état, jamais sa valeur", function()
    photoRaw()
    local etat = Commandes.executer('etat', {})
    egal(etat.liaison_fermee, true)
    egal(Json.encode(etat):find(JETON, 1, true), nil, "le jeton n'est pas dans l'état")
    egal(Json.encode(etat):find('liaison.jeton', 1, true), nil, "ni son chemin")
    local PluginInfoProvider = require 'PluginInfoProvider'
    Liaison.refus = 4
    local diagnostic = PluginInfoProvider.diagnostic()
    egal(diagnostic:find("Jeton : présent (" .. select(2, Liaison.cheminJeton()) .. ") ; commandes refusées : 4", 1, true) ~= nil, true, diagnostic)
    egal(diagnostic:find(JETON, 1, true), nil, "jamais la valeur du jeton")
    Liaison.jeton = nil
    egal(PluginInfoProvider.diagnostic():find("Jeton : absent", 1, true) ~= nil, true)
end)

test("Liaison fermée : la liaison tire son jeton avant ses prises, le garde, puis l'oublie à l'arrêt", function()
    local _, chemin = Liaison.cheminJeton()
    Liaison.jeton = nil
    Liaison.refus, Liaison.derniersRefus = 5, { sans = 0 }
    local pendant, refusAuDebut, reecrit
    local prises = demarrerLiaison(function(tour)
        if tour == 1 then
            pendant, refusAuDebut = Liaison.jeton, Liaison.refus
            S.fichiers[chemin] = nil -- effacé pendant que Lightroom tourne
        elseif tour == Liaison.VERIFIER_JETON_TOUTES + 1 then
            reecrit = S.fichiers[chemin]
            Liaison.arreter()
        end
    end)
    egal(type(pendant), 'string')
    egal(#pendant, 64)
    egal(refusAuDebut, 0, "compte des refus remis à zéro au démarrage")
    egal(#prises, 2, "les deux prises")
    egal(prises[1].fichierAuLien, pendant .. '\n', "le fichier existe avant la première prise")
    egal(prises[1].fermee and prises[2].fermee, true, "prises fermées à l'arrêt")
    egal(reecrit, pendant .. '\n', "fichier effacé : réécrit dans les 5 s")
    egal(S.droits[chemin], '600')
    egal(Liaison.jeton, nil, "jeton oublié à l'arrêt")
    egal(contient(Liaison.journal, "Liaison démarrée (ports 54770 et 54771, jeton privé)"), true)
    egal(contient(Liaison.journal, "Fichier du jeton réécrit"), true)
    egal(contient(Liaison.journal, pendant), false, "le jeton n'est jamais journalisé")
    egal(Liaison.erreur, nil)
end)

test("Liaison fermée : sans jeton écrit, aucune prise ne s'ouvre et la liaison reste en erreur", function()
    local preparer = Liaison.preparerJeton
    local ok, erreur = pcall(function()
        S.aleaIllisible = true
        Liaison.jeton = JETON
        local prises = demarrerLiaison()
        egal(#prises, 0, "aucune prise")
        egal(Liaison.actif, true, "voyant rouge : un clic relance")
        egal(Liaison.jeton, nil)
        egal(Liaison.erreur, "jeton de la liaison : aléa du système illisible (/dev/urandom)")
        egal(Liaison.texteEtat(), "Liaison en erreur : jeton de la liaison : aléa du système illisible (/dev/urandom)")
        egal(contient(Liaison.journal, "Erreur de la liaison : jeton de la liaison"), true)
        -- En erreur, la liaison reste active : le menu Démarrer seul n'y fait rien, d'où « Arrêter,
        -- puis Démarrer » dans la réponse à une commande refusée.
        local generation = Liaison.generation
        Liaison.demarrer()
        egal(Liaison.generation, generation, "Démarrer seul ne relance pas une liaison en erreur")
        egal(Liaison.REFUS_JETON.aucun:find("Arrêter, puis Démarrer la liaison avec Claude", 1, true) ~= nil, true,
            Liaison.REFUS_JETON.aucun)
        priseDesReponses()
        Liaison.recevoir(ligne({ id = 1, command = 'ping', params = {} }))
        egal(reponse(1).error, Liaison.REFUS_JETON.aucun, "tout est refusé")
        Liaison.prise, Liaison.reponsesConnectee = nil, false
        Liaison.arreter()
        -- Une erreur levée pendant la préparation : son message, sans le nom du fichier Lua.
        S.aleaIllisible = false
        Liaison.preparerJeton = function() error("disque plein") end
        prises = demarrerLiaison()
        egal(#prises, 0)
        egal(Liaison.erreur, "jeton de la liaison : disque plein")
        Liaison.arreter()
        -- Un démarrage remplacé pendant la préparation ne touche ni au jeton ni aux prises.
        Liaison.jeton = 'jeton du démarrage suivant'
        Liaison.preparerJeton = function()
            Liaison.generation = Liaison.generation + 1
            return string.rep('e', 64)
        end
        prises = demarrerLiaison()
        egal(#prises, 0)
        egal(Liaison.jeton, 'jeton du démarrage suivant')
    end)
    Liaison.preparerJeton = preparer
    Liaison.actif, Liaison.erreur = false, nil
    if not ok then
        error(erreur, 0)
    end
end)

-- Livraison (2.0) --------------------------------------------------------------------

local function deuxPhotosALivrer()
    local a, b = photoRaw(), photoJpeg()
    S.active, S.selection = a, { a, b }
    S.fichiers['/Volumes/Photos'] = 'dossier'
    return a, b
end

local REGLAGES_WEB = { format = 'JPEG', qualite = 80, espace = 'sRGB', taille = { type = 'megapixels', valeur = 5 },
    nettete = { support = 'screen', niveau = 2 }, metadonnees = 'copyrightAndContactOnly', sans_lieu = true }

test("livraison : deux photos exportées, jamais d'écrasement (renommées), réglages de Lightroom", function()
    deuxPhotosALivrer()
    local params = { photos = { 1, 2 }, dossier = '/Volumes/Photos/Livraison web', reglages = REGLAGES_WEB }
    local premiere = Commandes.executer('exporter', params)
    egal(#premiere.fichiers, 2)
    egal(premiere.fichiers[1].chemin, '/Volumes/Photos/Livraison web/DSC_0412.jpg')
    egal(premiere.fichiers[2].chemin, '/Volumes/Photos/Livraison web/IMG_0001.jpg')
    egal(S.fichiers['/Volumes/Photos/Livraison web'], 'dossier', "le dossier est créé")
    local r = S.dernierExport.exportSettings
    egal(r.LR_collisionHandling, 'rename', "jamais d'écrasement")
    egal(r.LR_size_resizeType, 'megapixels')
    egal(r.LR_size_megapixels, 5)
    proche(r.LR_jpeg_quality, 0.8)
    egal(r.LR_outputSharpeningMedia, 'screen')
    egal(r.LR_outputSharpeningLevel, 2)
    egal(r.LR_embeddedMetadataOption, 'copyrightAndContactOnly')
    egal(r.LR_removeLocationMetadata, true)
    egal(#S.dernierExport.photosToExport, 2, "une seule session pour le lot")
    local seconde = Commandes.executer('exporter', params)
    egal(seconde.fichiers[1].chemin, '/Volumes/Photos/Livraison web/DSC_0412-2.jpg', "le fichier existant est gardé")
    egal(S.fichiers['/Volumes/Photos/Livraison web/DSC_0412.jpg'], 'fichier livré de DSC_0412.NEF')
    egal(contient(Liaison.journal, "Livraison : 2 fichier(s)"), true)
end)

test("livraison : modèle de noms, texte personnalisé et numéro de départ d'un lot", function()
    deuxPhotosALivrer()
    local resultat = Commandes.executer('exporter', { photos = { 1, 2 }, dossier = '/Volumes/Photos/Gaspesie', sous_dossier = 'web',
        reglages = { format = 'JPEG', qualite = 90 }, jetons = '{{custom_token}}-{{naming_sequenceNumber_3Digits}}',
        texte_perso = 'Gaspesie', sequence = 11, suite = true })
    egal(resultat.fichiers[1].chemin, '/Volumes/Photos/Gaspesie/web/Gaspesie-011.jpg')
    egal(resultat.fichiers[2].chemin, '/Volumes/Photos/Gaspesie/web/Gaspesie-012.jpg')
    egal(S.dernierExport.exportSettings.LR_renamingTokensOn, true)
    egal(S.dernierExport.exportSettings.LR_export_destinationPathSuffix, 'web')
end)

test("livraison : « Proposer d'abord », pause, dossier impossible", function()
    deuxPhotosALivrer()
    S.prefs.mode = 'proposer'
    echoue(function() Commandes.executer('exporter', { photos = { 1 }, dossier = '/Volumes/Photos/x', reglages = REGLAGES_WEB }) end,
        "rien n'a été exporté")
    egal(#S.rendus, 0)
    Commandes.executer('exporter', { photos = { 1 }, dossier = '/Volumes/Photos/x', reglages = REGLAGES_WEB, confirme = true })
    egal(#S.rendus, 1)
    Commandes.executer('exporter', { photos = { 2 }, dossier = '/Volumes/Photos/x', reglages = REGLAGES_WEB, suite = true })
    egal(#S.rendus, 2, "un lot suivant : l'accord est déjà donné")
    S.prefs.mode = nil
    echoue(function() Commandes.executer('exporter', { photos = { 1 }, dossier = '/Volumes/Absent/Livraison', reglages = REGLAGES_WEB }) end,
        "disque débranché")
    echoue(function() Commandes.executer('exporter', { photos = { 1 }, dossier = 'Livraison', reglages = REGLAGES_WEB }) end, "chemin complet")
    S.fichiers['/Volumes/Photos/note.txt'] = 'texte'
    echoue(function() Commandes.executer('exporter', { photos = { 1 }, dossier = '/Volumes/Photos/note.txt', reglages = REGLAGES_WEB }) end,
        "est un fichier")
    Liaison.pause = true
    echoue(function() Commandes.executer('exporter', { photos = { 1 }, dossier = '/Volumes/Photos/x', reglages = REGLAGES_WEB }) end, "pause")
end)

test("livraison : une photo que Lightroom ne rend pas est dite, les autres partent", function()
    local a = deuxPhotosALivrer()
    a.exportImpossible = "fichier original introuvable"
    local resultat = Commandes.executer('exporter', { photos = { 1, 2 }, dossier = '/Volumes/Photos/x', reglages = REGLAGES_WEB })
    egal(resultat.fichiers[1].erreur, "fichier original introuvable")
    egal(resultat.fichiers[2].chemin ~= nil, true)
end)

test("livraison : fenêtre d'exportation de Lightroom et options", function()
    local a, b = deuxPhotosALivrer()
    S.selection = { a }
    local ouverte = Commandes.executer('fenetreExport', { photos = { 1, 2 } })
    egal(ouverte.ouverte, true)
    egal(S.fenetreExport, a)
    egal(#S.selection, 2, "les photos sont sélectionnées")
    S.modelesNoms = { ['Date - Nom du fichier'] = '/Users/x/Filename Templates/Date - Nom du fichier.lrtemplate' }
    S.presetsMeta = { ['uuid-droits'] = { nom = 'Droits Dany', champs = { copyright = '© Dany' } } }
    S.Service('Flickr', 'com.adobe.lightroom.export.flickr')
    local options = Commandes.executer('livraison', {})
    egal(options.modeles_noms[1].nom, 'Date - Nom du fichier')
    egal(options.presets_metadonnees[1].nom, 'Droits Dany')
    egal(options.services_publication[1].nom, 'Flickr')
    egal(options.services_publication[1].module, 'com.adobe.lightroom.export.flickr')
    egal(options.services_publication[1].collections, nil, "les collections publiées ne sont pas lues")
end)

test("métadonnées : paramètre prédéfini de l'utilisateur appliqué, puis défait", function()
    local photo = photoRaw()
    S.active = photo
    photo.meta.copyright = '© ancien'
    local voyage = S.MotCle('Voyage')
    S.presetsMeta = { ['uuid-droits'] = { nom = 'Droits Dany', champs = { copyright = '© 2026 Dany Ménard', creator = 'Dany Ménard' },
        motsCles = { voyage } } }
    local resultat = Commandes.executer('metadonnees', { preset_metadonnees = 'droits dany', etape = 'droits' })
    egal(photo.meta.copyright, '© 2026 Dany Ménard')
    egal(photo.meta.creator, 'Dany Ménard')
    egal(S.presetsMetaAppliques[1].id, 'uuid-droits')
    local changements = Json.encode(resultat.resultats[1].changements)
    egal(changements:find('copyright', 1, true) ~= nil, true)
    egal(changements:find('Voyage', 1, true) ~= nil, true)
    -- Relu après l'écriture (constaté en 2.3) : le journal porte aussi ce qui a changé.
    local journal = Json.decode(photo.proprietes.journalClaude)
    egal(Json.encode(journal[#journal].changements):find('copyright', 1, true) ~= nil, true, "le journal dit ce qui a changé")
    egal(S.ecritures[#S.ecritures], 'Claude · droits', "la relecture n'ajoute pas d'opération à Édition › Annuler")
    local annule = Commandes.executer('annuler', {})
    egal(contient({ annule.resultats[1].reglages_remis.Bibliotheque }, "champs IPTC"), true, "le résumé nomme les champs IPTC")
    egal(photo.meta.copyright, '© ancien', "les droits d'avant reviennent")
    egal(photo.meta.creator, '', "le créateur est vidé")
    egal(#photo.motsCles, 0, "le mot-clé ajouté est retiré")
    echoue(function() Commandes.executer('metadonnees', { preset_metadonnees = 'Inconnu', etape = 'x' }) end, "« Droits Dany »")
end)

-- Variantes (2.0) ----------------------------------------------------------------------

local function variante(nom, reglages)
    return Commandes.executer('essayer', { action = 'appliquer', reglages = reglages, libelles = {},
        etape = 'variante ' .. nom, instantane = nom, taille = 800 })
end

test("variantes : rangées en instantanés, la photo revient ; une est choisie comme une étape", function()
    local photo = photoRaw()
    S.active, S.selection = photo, { photo }
    local naturelle = variante('naturelle', { Exposure2012 = 0.3 })
    local chaude = variante('chaude', { Exposure2012 = 0.3, Temperature = 6200, Vibrance = 15 })
    egal(naturelle.instantane, 'Claude · naturelle')
    egal(chaude.instantane, 'Claude · chaude')
    egal(photo.reglages.Exposure2012, 0, "la photo revient comme avant")
    egal(photo.reglages.Temperature, 5200)
    egal(#photo.snapshots, 2)
    egal(photo.snapshots[2].reglages.Temperature, 6200, "l'instantané garde la variante")
    local liste = Commandes.executer('variantes', { action = 'lister' })
    egal(#liste.variantes, 2)
    egal(liste.variantes[2].nom, 'Claude · chaude')
    egal(contient(liste.variantes[2].reglages, 'Temperature'), true)

    local choix = Commandes.executer('variantes', { action = 'choisir', nom = 'chaude', etape = 'variante chaude', effacer_autres = true })
    egal(photo.reglages.Temperature, 6200)
    egal(photo.reglages.Vibrance, 15)
    egal(choix.etape, 'Claude · variante chaude')
    egal(choix.effaces[1], 'Claude · naturelle', "les autres variantes sont effacées")
    egal(#photo.snapshots, 2, "« Avant Claude » et la variante choisie")
    local details = Commandes.executer('reglages', { cles = {}, details = true })
    egal(contient(details.instantanes, 'Avant Claude'), true, "get_settings nomme les instantanés")
    egal(S.modulesOuverts[1], 'develop', "posée photo affichée dans le module Développement")
    egal(S.module, 'library', "puis la vue d'avant est remise")
    egal(contient(photo.instantanes, 'Avant Claude'), true)
    egal(Json.encode(choix.changements):find('Temperature', 1, true) ~= nil, true)
    Commandes.executer('annuler', {})
    egal(photo.reglages.Temperature, 5200, "undo_last défait la variante")
    egal(photo.reglages.Vibrance, 0)
    egal(photo.reglages.Exposure2012, 0)
end)

-- Constaté le 17 octobre 2026 : dans une écriture, ou photo pas affichée dans le module
-- Développement, applyDevelopSnapshot ne change rien.
test("variantes : l'instantané se pose hors de l'écriture ; s'il ne prend pas, l'étape est retirée", function()
    local photo = photoRaw()
    S.active, S.selection = photo, { photo }
    variante('chaude', { Temperature = 6400 })
    S.instantaneBloque = true
    echoue(function() Commandes.executer('variantes', { action = 'choisir', nom = 'chaude', etape = 'chaude' }) end, "n'a pas posé")
    local etapes = Json.decode(photo:getPropertyForPlugin(nil, 'etapesClaude') or '[]')
    egal(#etapes, 0, "pas d'étape sans changement")
    egal(photo.reglages.Temperature, 5200)
    S.instantaneBloque = false
    Commandes.executer('variantes', { action = 'choisir', nom = 'chaude', etape = 'chaude' })
    egal(photo.reglages.Temperature, 6400)
    egal(#S.instantanesIgnores, 1, "le seul appel ignoré : celui qui était bloqué")
end)

test("variantes : accord, instantané inconnu ou pas de Claude, effacement", function()
    local photo = photoRaw()
    S.active, S.selection = photo, { photo }
    variante('noir et blanc', { Saturation = -100 })
    S.prefs.mode = 'proposer'
    echoue(function() Commandes.executer('variantes', { action = 'choisir', nom = 'noir et blanc', etape = 'nb' }) end, "Proposer d'abord")
    S.prefs.mode = nil
    echoue(function() Commandes.executer('variantes', { action = 'choisir', nom = 'chaude', etape = 'x' }) end, "Aucun instantané")
    S.ecritureEnCours = true
    photo:createDevelopSnapshot('Mon instantané', false)
    S.ecritureEnCours = false
    echoue(function() Commandes.executer('variantes', { action = 'choisir', nom = 'Mon instantané', etape = 'x' }) end,
        "pas une variante préparée par Claude")
    local efface = Commandes.executer('variantes', { action = 'effacer' })
    egal(efface.effaces[1], 'Claude · noir et blanc')
    egal(#photo.snapshots, 1, "l'instantané de l'utilisateur reste")
end)

-- 2.3 : retouche globale ------------------------------------------------------------------

test("appliquer : quantité d'un paramètre prédéfini, passée à applyDevelopPreset", function()
    local photo = photoRaw()
    S.active = photo
    S.presets = { { nom = 'Mes réglages', presets = { { nom = 'Chaud', uuid = 'U1', reglages = { Exposure2012 = 1, Vibrance = 40 } } } } }
    local resultat = appliquer({ preset = 'Chaud', quantite_preset = 50 })
    egal(S.quantitesPresets[1], 50, "quantité en %, comme le curseur Quantité prédéfinie")
    proche(photo.reglages.Exposure2012, 0.5)
    egal(resultat.resultats[1].changements[1].apres, "Mes réglages / Chaud (50 %)")
    Commandes.executer('annuler', {})
    proche(photo.reglages.Exposure2012, 0)
    appliquer({ preset = 'Chaud', quantite_preset = 100 })
    egal(#S.quantitesPresets, 1, "à 100 %, l'appel ordinaire")
end)

test("appliquer : mélange noir et blanc automatique par un paramètre prédéfini, après le noir et blanc", function()
    local photo = photoRaw()
    photo.reglages.ConvertToGrayscale = false
    S.active = photo
    local resultat = appliquer({ melange_nb_auto = true })
    egal(contient(resultat.resultats[1].remarques, "pas en noir et blanc"), true)
    egal(#photo.appliques, 0)
    appliquer({ reglages = { ConvertToGrayscale = 1 }, booleens = Json.tableau({ 'ConvertToGrayscale' }), melange_nb_auto = true })
    egal(photo.reglages.ConvertToGrayscale, true)
    egal(photo.appliques[1].reglages.ConvertToGrayscale, true, "le noir et blanc d'abord")
    egal(photo.appliques[2].preset, "Claude · mélange noir et blanc automatique", "puis le mélange automatique")
    egal(photo.reglages.GrayMixerOrange ~= 0, true, "calculé par Lightroom")
    Commandes.executer('annuler', {})
    egal(photo.reglages.GrayMixerOrange, 0, "les curseurs d'avant reviennent")
    egal(photo.reglages.ConvertToGrayscale, false)
end)

test("appliquer : profil d'objectif choisi, puis par défaut, et annulation", function()
    local photo = photoFuji()
    photo.reglages.LensProfileSetup, photo.reglages.LensProfileName, photo.reglages.LensProfileEnable = 'LensDefaults', 'Camera Settings', 1
    photo.reglages.LensProfileDigest, photo.reglages.LensProfileIsEmbedded = 'AB6A', true
    photo.objectifParDefaut = { LensProfileName = 'Camera Settings', LensProfileFilename = '', LensProfileDigest = 'AB6A', LensProfileIsEmbedded = true }
    S.active = photo
    local fichier = 'Fujifilm (Fujifilm FUJINON 55mm f1.8 M42) - RAW.lcp'
    local resultat = appliquer({ profil_objectif = { nom = 'Adobe (Fujifilm FUJINON 55mm f/1.8 M42)', fichier = fichier } })
    egal(photo.reglages.LensProfileSetup, 'Custom')
    egal(photo.reglages.LensProfileFilename, fichier)
    egal(photo.reglages.LensProfileIsEmbedded, false)
    egal(resultat.resultats[1].changements[1].avant, 'Camera Settings')
    Commandes.executer('annuler', {})
    egal(photo.reglages.LensProfileSetup, 'LensDefaults')
    egal(photo.reglages.LensProfileName, 'Camera Settings')
    egal(photo.reglages.LensProfileDigest, 'AB6A')
    egal(photo.reglages.LensProfileEnable, 1)
    appliquer({ profil_objectif = { nom = 'X', fichier = fichier } })
    appliquer({ profil_objectif = { auto = true } })
    egal(photo.reglages.LensProfileSetup, 'LensDefaults', "par un paramètre prédéfini du module")
    egal(photo.reglages.LensProfileEnable, 1)
    egal(photo.reglages.LensProfileName, 'Camera Settings', "le profil par défaut, repris par Lightroom")
end)

test("appliquer : Upright avec repères, dans le repère du fichier (photo DA), case Contraindre cochée", function()
    local photo = photoFuji()
    photo.brut.orientation = 'DA'
    photo.brut.dimensions = { width = 4160, height = 6240 }
    S.active = photo
    -- Constaté le 17 octobre 2026 : un repère vertical tracé de (0,28 ; 0,08) à (0,29 ; 0,84) sur une
    -- photo « DA » est rangé de (0,914 ; 0,287) à (0,167 ; 0,294).
    local resultat = appliquer({ reperes = Json.tableau({ { x1 = 0.28, y1 = 0.08, x2 = 0.29, y2 = 0.84 }, { x1 = 0.7, y1 = 0.1, x2 = 0.71, y2 = 0.9 } }) })
    egal(photo.reglages.PerspectiveUpright, 5)
    egal(photo.reglages.UprightFourSegmentsCount, 2)
    local x1, y1, x2, y2 = photo.reglages.UprightFourSegments_0:match('^(%S+),(%S+),(%S+),(%S+)$')
    egal(#x1, 11, "neuf décimales, comme Lightroom")
    proche(math.floor(tonumber(x1) * 1000 + 0.5) / 1000, 0.92)
    proche(math.floor(tonumber(y1) * 1000 + 0.5) / 1000, 0.28)
    proche(math.floor(tonumber(x2) * 1000 + 0.5) / 1000, 0.16)
    proche(math.floor(tonumber(y2) * 1000 + 0.5) / 1000, 0.29)
    egal(photo.reglages.CropConstrainToWarp, 1, "les repères laissent des coins vides")
    egal(contient(resultat.resultats[1].remarques, "sans recalage"), false, "pas de correction d'objectif ici")
    egal(contient(resultat.resultats[1].remarques, "« Mettre à jour »"), true, "le calcul est demandé à l'utilisateur")
    Commandes.executer('apercu', { photo = photo.localIdentifier, taille = 1024 })
    egal(photo.reglages.UprightTransform_0, nil, "le rendu ne calcule pas le mode avec repères")
    Commandes.executer('annuler', {})
    egal(photo.reglages.PerspectiveUpright, 0)
    egal(photo.reglages.UprightFourSegmentsCount, 0)
end)

test("appliquer : instantané demandé avant la retouche", function()
    local photo = photoRaw()
    S.active = photo
    local resultat = appliquer({ reglages = { Exposure2012 = 0.5 }, instantane_avant = "avant la passe 2" })
    egal(photo.instantanes[#photo.instantanes], "Claude · avant la passe 2")
    egal(photo.snapshots[#photo.snapshots].reglages.Exposure2012, 0, "l'état d'avant la retouche")
    egal(contient(resultat.resultats[1].remarques, "Claude · avant la passe 2"), true)
end)

test("appliquer : rotation d'un quart de tour, hors d'une écriture ; annulation et retour à l'origine", function()
    local photo = photoFuji()
    photo.brut.orientation = 'AB'
    S.active = photo
    local resultat = appliquer({ rotation = 'droite' })
    egal(photo.brut.orientation, 'BC')
    egal(photo.brut.dimensions.width, 4160, "dimensions affichées échangées")
    egal(resultat.resultats[1].changements[1].cle, 'Rotation')
    appliquer({ rotation = 'demi', reglages = { Exposure2012 = 0.2 } })
    egal(photo.brut.orientation, 'DA')
    Commandes.executer('annuler', {})
    egal(photo.brut.orientation, 'BC', "la dernière rotation défaite")
    proche(photo.reglages.Exposure2012, 0)
    appliquer({ rotation = 'gauche' })
    egal(photo.brut.orientation, 'AB')
    appliquer({ rotation = 'gauche' })
    egal(photo.brut.orientation, 'DA')
    Commandes.executer('revenir', {})
    egal(photo.brut.orientation, 'AB', "retour à l'orientation d'avant Claude")
    echoue(function() appliquer({ rotation = 'travers' }) end, "Rotation inconnue")
end)

test("couleurs ponctuelles d'un masque : la variance à part, dans LocalColorVariance", function()
    local textes, variances = Locaux.couleursPonctuelles({ { SrcHue = 4.5, SrcSat = 0.2, SrcLum = 0.5, HueShift = 0.1, SatScale = 0,
        LumScale = 0, RangeAmount = 0.5, Variance = 0.4, HueRange = {}, SatRange = {}, LumRange = {} } })
    egal(#textes, 1)
    egal(variances[1], '0.400000')
    local photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'radial', centre_x = 0.5, centre_y = 0.5, rayon_x = 0.4, nom = 'Claude · r',
        locaux = {}, couleurs_ponctuelles = Json.tableau({ { SrcHue = 1, SrcSat = 0.5, SrcLum = 0.5, HueShift = 0, SatScale = -0.5,
            LumScale = 0, RangeAmount = 0.5, Variance = -0.2, HueRange = {}, SatRange = {}, LumRange = {} } }) } }) })
    local correction = photo.reglages.MaskGroupBasedCorrections[1]
    egal(correction.LocalColorVariance[1], '-0.200000')
end)

test("corrections de l'utilisateur après Claude : relevées, dites par reglages, apercu et annuler", function()
    local photo = photoRaw()
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.5, Vibrance = 10 }, etape = 'passe 1' })
    local lu = Commandes.executer('reglages', { cles = {} })
    egal(lu.corrections_utilisateur, nil, "rien de changé depuis Claude")
    -- Lightroom résout de lui-même, peu après l'écriture, des réglages absents et l'origine du
    -- profil d'objectif (constaté le 18 octobre 2026) : pas des corrections de l'utilisateur.
    S.ecritureEnCours = true
    photo:applyDevelopSettings({ LensProfileVignettingScale = 100, LensProfileIsEmbedded = true })
    S.ecritureEnCours = false
    lu = Commandes.executer('reglages', { cles = {} })
    egal(lu.corrections_utilisateur, nil, "réglages ajoutés ou résolus par Lightroom")
    -- L'utilisateur baisse la vibrance et monte les ombres à la main.
    S.ecritureEnCours = true
    photo:applyDevelopSettings({ Vibrance = 4, Shadows2012 = 20 })
    S.ecritureEnCours = false
    lu = Commandes.executer('reglages', { cles = {} })
    egal(lu.corrections_utilisateur.etape, "Claude · passe 1")
    local cles = {}
    for _, c in ipairs(lu.corrections_utilisateur.changements) do cles[c.cle] = c end
    egal(cles.Vibrance.claude, 10) egal(cles.Vibrance.maintenant, 4)
    egal(cles.Shadows2012.claude, 0) egal(cles.Shadows2012.maintenant, 20)
    egal(cles.Exposure2012, nil)
    local apercu = Commandes.executer('apercu', { cles = {} })
    egal(#apercu.corrections_utilisateur.changements, 2)
    local annule = Commandes.executer('annuler', {})
    egal(contient({ annule.resultats[1].remarque }, "remet aussi Vibrance, que l'utilisateur avait changé à la main"), true)
    egal(contient({ annule.resultats[1].remarque }, "restent (Shadows2012)"), true)
    proche(photo.reglages.Shadows2012, 20, "la correction de l'utilisateur sur un autre réglage reste")
    lu = Commandes.executer('reglages', { cles = {} })
    egal(lu.corrections_utilisateur, nil, "l'état après l'annulation est le nouveau repère")
end)

-- 2.4 : masques et flou d'objectif ----------------------------------------------------------

test("masquer : une personne précise, avec les cadres de toutes les personnes ; sans eux, masque retiré", function()
    local photo = photoFuji()
    photo.personnes = { { Left = 0.2, Right = 0.38, Top = 0.28, Bottom = 1 }, { Left = 0.35, Right = 0.46, Top = 0.34, Bottom = 1 },
        { Left = 0.45, Right = 0.57, Top = 0.35, Bottom = 1 } }
    S.active = photo
    -- Cadres de Vision, approchés de ceux de Lightroom (dans l'aperçu, ici sans transformation).
    local cadres = Json.tableau({ { Left = 0.21, Right = 0.37, Top = 0.29, Bottom = 0.99 }, { Left = 0.36, Right = 0.45, Top = 0.33, Bottom = 0.98 },
        { Left = 0.46, Right = 0.56, Top = 0.36, Bottom = 0.99 } })
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'personne', numero = 2, cadres = cadres, nom = 'Claude · Personne du milieu', locaux = { LocalExposure2012 = 0.1 } },
        { type = 'personne', numero = 3, categorie = 5, cadres = cadres, nom = 'Claude · Cheveux', locaux = { LocalSaturation = -0.2 } },
        -- Un seul cadre : Lightroom ne reconnaît pas la personne (constaté).
        { type = 'personne', numero = 1, cadres = Json.tableau({ cadres[2] }), nom = 'Claude · Seule', locaux = { LocalSaturation = -0.2 } },
    }) })
    local masques = photo.reglages.MaskGroupBasedCorrections
    egal(#masques, 2, "le masque non reconnu est retiré")
    local entiere, cheveux = masques[1].CorrectionMasks[1], masques[2].CorrectionMasks[1]
    egal(entiere.MaskSubType, 0) egal(entiere.MaskSubCategoryID, 20036)
    egal(entiere.InstanceIDs[1].InstanceID, 1, "Personne 2 → 1")
    egal(#entiere.InstanceBounds, 3, "les cadres de toutes les personnes")
    egal(cheveux.MaskSubCategoryID, 5)
    egal(cheveux.InstanceIDs[1].InstanceID, 2)
    egal(cheveux.MaskDigest ~= nil, true, "calculé")
    egal(contient(resultat.resultats[1].remarques, "Masque « Claude · Seule » retiré"), true)
    Commandes.executer('annuler', {})
    egal(#(photo.reglages.MaskGroupBasedCorrections or {}), 0)
end)

test("masquer : la personne seule d'un portrait, sans numéro ni cadres, gardée et recalculée", function()
    -- Constaté le 20 octobre 2026 sur un portrait : Lightroom range le masque de la seule personne
    -- sans InstanceIDs ni InstanceBounds ; un masque numéroté y est calculé de même, et il retire le
    -- numéro. Le module le retirait comme « non reconnu ».
    local photo = photoFuji()
    photo.personnes = { { Left = 0.2, Right = 0.55, Top = 0.15, Bottom = 1 } }
    S.active = photo
    local cadre = Json.tableau({ { Left = 0.21, Right = 0.54, Top = 0.16, Bottom = 1 } })
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'personne', numero = 1, seule = true, cadres = cadre, nom = 'Claude · Personne 1', locaux = { LocalExposure2012 = 0.1 } },
        { type = 'personne', numero = 1, categorie = 2, seule = true, cadres = cadre, nom = 'Claude · Peau du visage', locaux = { LocalTexture = -0.2 } },
        -- Envoyé numéroté (comme avant le 20 octobre 2026) : Lightroom retire le numéro, gardé quand même.
        { type = 'personne', numero = 1, cadres = cadre, nom = 'Claude · Numérotée', locaux = { LocalSaturation = -0.1 } },
    }) })
    egal(contient(resultat.resultats[1].remarques, "retiré"), false, "aucun masque retiré")
    local masques = photo.reglages.MaskGroupBasedCorrections
    egal(#masques, 3)
    local entiere, visage = masques[1].CorrectionMasks[1], masques[2].CorrectionMasks[1]
    egal(entiere.InstanceIDs, nil, "sans numéro, comme fait à la main")
    egal(entiere.InstanceBounds, nil, "sans cadres")
    egal(entiere.MaskSubType, 0) egal(entiere.MaskSubCategoryID, 20036)
    egal(entiere.ReferencePoint, string.format('%f %f', 0.375, 0.575), "calculé sur elle")
    egal(visage.MaskSubCategoryID, 2)
    egal(masques[3].CorrectionMasks[1].InstanceIDs, nil, "Lightroom retire le numéro")
    local liste = Commandes.executer('masques', { action = 'lister' })
    egal(liste.masques[1].composants[1].personne, 1, "la personne 1")
    egal(liste.masques[1].composants[1].ia, "personne")
    -- Recalculée, elle reste la sienne.
    resultat = Commandes.executer('masques', { action = 'recalculer', masque = 'Personne 1' })
    egal(contient(resultat.resultats[1].remarques, "n'a plus reconnu"), false)
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].MaskSubType, 0)
end)

test("masquer : contour d'un masque IA (affinage) et masques vides retirés après le calcul", function()
    local photo = photoFuji()
    photo.reglages.MaskGroupBasedCorrections = { MASQUE_UTILISATEUR }
    photo.vides = { [50005] = true }
    S.active = photo
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'ia', soustype = 1, nom = 'Claude · Sujet', locaux = { LocalExposure2012 = 0.1 }, affinage = { contour = 1.92, decalage = -2 } },
        { type = 'ia', soustype = 0, categorie = 50005, nom = 'Claude · Végétation', locaux = { LocalSaturation = 0.2 } },
    }) })
    local masques = photo.reglages.MaskGroupBasedCorrections
    egal(#masques, 2, "la végétation, vide, est retirée")
    egal(masques[2].CorrectionMasks[1].Feather, 1.92)
    egal(masques[2].CorrectionMasks[1].EdgeShift, -2)
    egal(S.masquesVidesRetires, 1)
    egal(contient(resultat.resultats[1].remarques, "« Claude · Végétation »"), true)
    Commandes.executer('annuler', {})
    egal(#photo.reglages.MaskGroupBasedCorrections, 1)
end)

test("masques : lister, masquer, afficher, dupliquer inversé, affiner, recalculer, retirer, chacun annulé", function()
    local photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } },
        { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.4, nom = 'Claude · Haut', locaux = { LocalExposure2012 = -0.2 } },
    }) })
    local liste = Commandes.executer('masques', { action = 'lister' })
    egal(#liste.masques, 2)
    egal(liste.masques[1].composants[1].ia, 'ciel')
    egal(liste.masques[1].composants[1].calcule, true)

    Commandes.executer('masques', { action = 'masquer', masque = 'Ciel', etape = 'sans ciel' })
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionActive, false)
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].MaskDigest ~= nil, true, "empreinte gardée")
    Commandes.executer('annuler', {})
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionActive, true)

    Commandes.executer('masques', { action = 'dupliquer', masque = 1, inverser = true, nom = 'Sol' })
    local masques = photo.reglages.MaskGroupBasedCorrections
    egal(#masques, 3)
    egal(masques[2].CorrectionName, 'Claude · Sol')
    egal(masques[2].CorrectionMasks[1].MaskInverted, true)
    egal(masques[2].CorrectionID ~= masques[1].CorrectionID, true, "d'autres identifiants")
    Commandes.executer('annuler', {})
    egal(#photo.reglages.MaskGroupBasedCorrections, 2)

    Commandes.executer('masques', { action = 'affiner', masque = 'Claude · Ciel', contour = 10, decalage = 5 })
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].Feather, 10)
    echoue(function() Commandes.executer('masques', { action = 'affiner', masque = 'Haut', contour = 1 }) end, "pas de composant IA")

    local avant = #photo.appliques
    Commandes.executer('masques', { action = 'recalculer', masque = 'Ciel' })
    egal(photo.appliques[avant + 1].preset:find("masques recalculés", 1, true) ~= nil, true, "par un paramètre prédéfini du module")
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].MaskDigest ~= nil, true, "recalculé")
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].Feather, 10, "le contour reste")

    Commandes.executer('masques', { action = 'retirer', masque = 2 })
    egal(#photo.reglages.MaskGroupBasedCorrections, 1)
    Commandes.executer('annuler', {})
    egal(#photo.reglages.MaskGroupBasedCorrections, 2)
    echoue(function() Commandes.executer('masques', { action = 'retirer', masque = 'Nuages' }) end, "Aucun masque « Nuages »")
    echoue(function() Commandes.executer('masques', { action = 'retirer', masque = 7 }) end, "Pas de masque n° 7")

    -- Une personne précise recalculée garde ses cadres, sans lesquels Lightroom ne la reconnaît plus
    -- (constaté le 18 octobre 2026).
    photo.personnes = { { Left = 0.2, Right = 0.4, Top = 0.3, Bottom = 1 }, { Left = 0.5, Right = 0.7, Top = 0.3, Bottom = 1 } }
    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'personne', numero = 2, nom = 'Claude · Invitée',
        cadres = Json.tableau({ { Left = 0.21, Right = 0.39, Top = 0.31, Bottom = 1 }, { Left = 0.51, Right = 0.69, Top = 0.32, Bottom = 1 } }),
        locaux = { LocalExposure2012 = 0.1 } } }) })
    local resultat = Commandes.executer('masques', { action = 'recalculer', masque = 'Invitée' })
    local invitee = photo.reglages.MaskGroupBasedCorrections[#photo.reglages.MaskGroupBasedCorrections].CorrectionMasks[1]
    egal(invitee.InstanceIDs[1].InstanceID, 1, "toujours la personne 2")
    egal(#invitee.InstanceBounds, 2)
    egal(contient(resultat.resultats[1].remarques, "n'a plus reconnu"), false)
end)

test("masques : retirer les masques vides, l'étape garde la liste d'avant", function()
    local photo = photoFuji()
    photo.reglages.MaskGroupBasedCorrections = { MASQUE_UTILISATEUR,
        { What = 'Correction', CorrectionName = 'Personnes', CorrectionID = 'P', CorrectionMasks = { { What = 'Mask/Image', MaskSubType = 3, MaskSubCategoryID = 2, MaskDigest = 'x' } } } }
    photo.vides = { [2] = true }
    S.active = photo
    local resultat = Commandes.executer('masques', { action = 'retirer_vides' })
    egal(#photo.reglages.MaskGroupBasedCorrections, 1)
    egal(contient(resultat.resultats[1].remarques, "« Personnes »"), true)
    Commandes.executer('annuler', {})
    egal(#photo.reglages.MaskGroupBasedCorrections, 2)
    resultat = Commandes.executer('masques', { action = 'retirer_vides' })
    photo.vides = {}
    resultat = Commandes.executer('masques', { action = 'retirer_vides' })
    egal(contient(resultat.resultats[1].remarques, "Aucun masque vide"), true)
end)

test("flou d'objectif : pinceau d'affinage (DepthBasedCorrections), Net et Flou", function()
    local photo = photoFuji()
    S.active = photo
    appliquer({ flou_objectif = { intensite = 40,
        affinage = Json.tableau({ { mode = 'net', traits = Json.tableau({ { points = Json.tableau({ { 0.29, 0.1 }, { 0.61, 0.11 } }), rayon = 0.08 } }) },
            { mode = 'flou', traits = Json.tableau({ { points = Json.tableau({ { 0.3, 0.88 }, { 0.4, 0.88 } }), rayon = 0.05 } }) } }) } })
    egal(photo.reglages.LensBlur.FocalRangeSource, 1, "mise au point sur le sujet")
    local corrections = photo.reglages.DepthBasedCorrections
    egal(#corrections, 2)
    egal(corrections[1].LocalCorrectedDepth, -1, "Net")
    egal(corrections[2].LocalCorrectedDepth, 1, "Flou")
    egal(corrections[1].CorrectionMasks[1].What, 'Mask/Aggregate')
    egal(corrections[1].CorrectionMasks[1].Masks[1].What, 'Mask/Paint')
    local dabs = corrections[1].CorrectionMasks[1].Masks[1].Dabs
    egal(dabs[#dabs]:sub(1, 2), 'd ')
    Commandes.executer('annuler', {})
    egal(#(photo.reglages.DepthBasedCorrections or {}), 0)
    egal(photo.reglages.LensBlur.Active, false)
end)

test("copier : Upright exact (matrices de la source, sans ses empreintes)", function()
    local source = photoFuji()
    source.reglages.PerspectiveUpright = 2
    source.reglages.UprightTransform_2 = '1.42,0,0,0,1.1,0,0,0,1'
    source.reglages.UprightTransformCount = 6
    source.reglages.UprightVersion = 151388160
    source.reglages.UprightDependentDigest = 'EMPREINTE DE LA SOURCE'
    local cible = S.Photo(9, { PerspectiveUpright = 0 }, { fileName = 'B.RAF', fileFormat = 'RAW' }, { dimensions = { width = 6240, height = 4160 } })
    local resultat = Commandes.executer('copier', { source = 4, photos = Json.tableau({ 9 }), cles = {}, inclure = { upright_exact = true },
        etape = 'série' })
    egal(cible.reglages.UprightTransform_2, '1.42,0,0,0,1.1,0,0,0,1')
    egal(cible.reglages.PerspectiveUpright, 2)
    egal(cible.reglages.UprightDependentDigest, nil, "sans les empreintes, comme le Copier de Lightroom")
    egal(contient(resultat.resultats[1].remarques, "matrices de la source sont gardées"), true)
    Commandes.executer('annuler', { photos = Json.tableau({ 9 }) })
    egal(cible.reglages.PerspectiveUpright, 0)
end)

test("supprimer : la poussière se retire (faite à la main), ne se lance pas", function()
    local photo = photoFuji()
    S.active = photo
    -- Une suppression faite à la main dans Lightroom (relevé le 17 octobre 2026), avec un autre filtre.
    local poussiere = { Name = 'Dust Removal', FilterID = 6, Title = 'Dust Removal', SrcBoundsRight = 6240, DstBoundsBottom = 4160,
        Images = { { ReferenceImageAreaLeft = 6078 }, { ReferenceImageAreaLeft = 120 } } }
    local reflets = { Name = 'Reflection Removal', FilterID = 3, SrcBoundsRight = 6240, DstBoundsBottom = 4160 }
    photo.reglages.FilterList = { Filters = { reflets, poussiere } }
    local resultat = Commandes.executer('supprimer', { poussiere = { actif = false }, etape = 'sans poussière' })
    egal(#photo.reglages.FilterList.Filters, 1, "les reflets restent")
    egal(photo.reglages.FilterList.Filters[1].Name, 'Reflection Removal')
    egal(resultat.resultats[1].changements[1].apres, "retirée")
    Commandes.executer('annuler', {})
    egal(#photo.reglages.FilterList.Filters, 2, "undo_last la remet")
    -- Constaté le 18 octobre 2026 : aucune fonction du SDK ne la lance.
    echoue(function() Commandes.executer('supprimer', { poussiere = { actif = true } }) end, "que dans son interface")
    photo.reglages.FilterList = {}
    resultat = Commandes.executer('supprimer', { poussiere = { actif = false } })
    egal(contient(resultat.resultats[1].remarques, "rien à retirer"), true)
end)


-- Version 2.4 : tri, Bibliothèque ---------------------------------------------------------------

test("2.4 : la pile d'une photo est décrite, par des lectures groupées", function()
    local dessus, dessous = photoRaw(), photoJpeg()
    dessus.brut.isInStackInFolder, dessous.brut.isInStackInFolder = true, true
    dessus.brut.topOfStackInFolderContainingPhoto, dessous.brut.topOfStackInFolderContainingPhoto = dessus, dessus
    dessus.brut.stackPositionInFolder, dessous.brut.stackPositionInFolder = 1, 2
    dessus.brut.countStackInFolderMembers, dessous.brut.countStackInFolderMembers = 2, 2
    dessous.proprietes.retoucheeParClaude, dessous.proprietes.proprietaireMemoire = 'oui', 'uuid-2'
    dessus.proprietes.retoucheeParClaude, dessus.proprietes.proprietaireMemoire = 'oui', 'uuid-autre'
    S.active, S.selection = dessus, { dessus, dessous }
    local liste = Commandes.executer('selection', { limite = 10 }).photos
    egal(S.lecturesGroupees, 1, "une lecture groupée des métadonnées formatées")
    egal(liste[2].pile.dessus, 1)
    egal(liste[2].pile.position, 2)
    egal(liste[2].pile.photos, 2)
    egal(liste[2].retouchee_par_claude, true, "sa propre mémoire")
    egal(liste[1].retouchee_par_claude, false, "la mémoire d'une autre photo ne compte pas")
    egal(liste[1].fichier, 'DSC_0412.NEF')
    egal(liste[1].active, true)
end)

test("2.4 : texte alternatif, description longue et champs IPTC, puis undo_last les remet", function()
    local photo = photoRaw()
    photo.meta.city = 'Québec'
    S.active = photo
    local resultat = classer({ iptc = { altTextAccessibility = "Deux érables au bord du lac.", extDescrAccessibility = "Longue description.",
        city = 'Montréal', headline = 'Anniversaire', event = 'Anniversaire de Samuel', personShown = 'Samuel', isoCountryCode = 'CA' } })
    egal(photo.brut.altTextAccessibility, "Deux érables au bord du lac.")
    egal(photo.meta.city, 'Montréal')
    egal(photo.meta.event, 'Anniversaire de Samuel')
    egal(#resultat.resultats[1].changements, 7)
    local classement = Commandes.executer('reglages', { cles = {}, details = true }).classement
    egal(classement.texte_alternatif, "Deux érables au bord du lac.")
    egal(classement.iptc.personShown, 'Samuel')
    Commandes.executer('annuler', {})
    egal(photo.brut.altTextAccessibility, '', "un texte vide l'efface")
    egal(photo.meta.city, 'Québec')
    egal(photo.meta.event, '')
    echoue(function() classer({ iptc = { inconnu = 'x' } }) end, "Champ IPTC inconnu")
    S.presetsMeta = { ['p-1'] = { nom = 'Droits', champs = { copyright = '© D' } } }
    echoue(function() classer({ iptc = { city = 'Laval' }, preset_metadonnees = 'Droits' }) end, "même appel")
end)

test("2.4 : position GPS posée, effacée, puis remise par undo_last", function()
    local photo = photoRaw()
    S.active = photo
    classer({ gps = { latitude = 45.5017, longitude = -73.5673, altitude = 40 } })
    egal(photo.brut.gps.latitude, 45.5017)
    egal(photo.brut.gpsAltitude, 40)
    local classement = Commandes.executer('reglages', { cles = {}, details = true }).classement
    egal(classement.gps.longitude, -73.5673)
    classer({ gps = 'aucune' })
    egal(photo.brut.gps, nil)
    Commandes.executer('annuler', {})
    egal(photo.brut.gps.latitude, 45.5017, "l'effacement annulé")
    Commandes.executer('annuler', {})
    egal(photo.brut.gps, nil, "la photo n'en avait pas")
    egal(photo.brut.gpsAltitude, nil)
    echoue(function() classer({ gps = { latitude = 95, longitude = 0 } }) end, "latitude")
end)

test("2.4 : position GPS d'après la photo de téléphone prise au plus près", function()
    local appareil, autre = photoRaw(), photoFuji()
    local telephone = photoJpeg()
    telephone.brut.gps, telephone.brut.gpsAltitude, telephone.brut.gpsImgDirection = { latitude = 46.81, longitude = -71.21 }, 12, 300
    telephone.brut.dateTimeOriginal = 1000
    local tard = S.Photo(3, {}, { fileName = 'IMG_0002.HEIC' }, { gps = { latitude = 45.0, longitude = -73.0 }, dateTimeOriginal = 1000 + 7200 })
    appareil.brut.dateTimeOriginal = 1000 + 90
    autre.brut.dateTimeOriginal = 1000 + 3600
    local resultat = classer({ photos = { 1, 4 }, gps_depuis = { photos = { 2, 3 }, ecart_max = 30 } })
    egal(appareil.brut.gps.latitude, 46.81)
    egal(appareil.brut.gpsAltitude, 12)
    egal(appareil.brut.gpsImgDirection, nil, "la direction du téléphone n'est pas celle de l'appareil")
    egal(contient(resultat.resultats[1].remarques, "IMG_0001.JPG"), true)
    egal(contient(resultat.resultats[1].remarques, "90 s"), true)
    egal(autre.brut.gps, nil, "à une heure des deux références")
    egal(contient(resultat.resultats[2].remarques, "Aucune photo de référence à moins de 30 min"), true)
    -- L'horloge de l'appareil retarde d'une heure : décalage.
    classer({ photos = { 4 }, gps_depuis = { photos = { 2, 3 }, decalage = 60 } })
    egal(autre.brut.gps.latitude, 45.0)
    S.Photo(5, {}, { fileName = 'SANS_GPS.JPG' }, { dateTimeOriginal = 1000 })
    echoue(function() classer({ photos = { 1 }, gps_depuis = { photos = { 5 } } }) end, "Aucune des photos de référence")
end)

test("2.4 : recherche des photos jamais exportées", function()
    local livree, pas = photoRaw(), photoJpeg()
    livree.brut.isExported, livree.brut.pickStatus, pas.brut.pickStatus = true, 1, 1
    local trouvees = Commandes.executer('chercher', { drapeau = 'retenue', exportee = false, limite = 10 })
    egal(trouvees.total, 1)
    egal(trouvees.photos[1].id, 2)
    egal(Commandes.executer('chercher', { drapeau = 'retenue', exportee = true, limite = 10 }).photos[1].id, 1)
    echoue(function() Commandes.executer('chercher', { exportee = false }) end, "Préciser la recherche")
end)

test("2.4 : un aperçu de Claude ne fait pas d'une photo une photo exportée ; une livraison, oui", function()
    local photo, autre = deuxPhotosALivrer()
    photo.brut.pickStatus = 1
    Commandes.executer('apercu', { photo = 1, taille = 512 })
    egal(photo.brut.isExported, true, "Lightroom la compte exportée")
    egal(photo.proprietes.apercuSeulement, 'oui')
    egal(photo.proprietes.proprietaireMemoire, nil, "pas une mémoire de Claude")
    egal(Commandes.executer('reglages', { photo = 1, cles = {}, details = true }).classement.exportee, false)
    egal(Commandes.executer('chercher', { drapeau = 'retenue', exportee = false, limite = 10 }).total, 1)
    Commandes.executer('exporter', { photos = { 1 }, dossier = '/Volumes/Photos/Livraison', reglages = REGLAGES_WEB, suite = true })
    egal(photo.proprietes.apercuSeulement, nil, "livrée pour de bon")
    egal(Commandes.executer('chercher', { drapeau = 'retenue', exportee = true, limite = 10 }).photos[1].id, 1)
    -- Déjà exportée avant l'aperçu : rien n'est noté.
    autre.brut.isExported = true
    Commandes.executer('apercu', { photo = 2, taille = 512 })
    egal(autre.proprietes.apercuSeulement, nil)
end)

test("2.4 : ETERNA refusé sur un X-T20, que Lightroom rendrait comme Adobe Standard", function()
    local photo = photoFuji()
    photo.meta.cameraModel = 'X-T20'
    S.active = photo
    local resultat = appliquer({ profil = 'Camera ETERNA/Cinema', profil_marque = 'FUJIFILM', profil_absent_sur = Json.tableau({ 'X-T20' }) })
    egal(photo.reglages.CameraProfile, 'Adobe Standard', "profil d'avant gardé")
    egal(contient(resultat.resultats[1].remarques, "non disponible pour cet appareil"), true)
    -- Un X-H2S le garde.
    photo.meta.cameraModel = 'X-H2S'
    appliquer({ profil = 'Camera ETERNA/Cinema', profil_marque = 'FUJIFILM', profil_absent_sur = Json.tableau({ 'X-T20' }) })
    egal(photo.reglages.CameraProfile, 'Camera ETERNA/Cinema')
end)

test("2.4 : le jour d'une prise de vue se lit à l'heure locale (une photo du soir n'est pas du lendemain)", function()
    S.fuseau = -4 * 3600
    local soir = photoRaw()
    -- 29 juin 2025 à 0 h 13 UTC : le 28 juin à 20 h 13, heure de l'Est.
    soir.brut.dateTimeOriginal = 772848780
    soir.brut.pickStatus = 0
    local trouvees = Commandes.executer('chercher', { drapeau = 'aucun', date_debut = '2025-06-28', date_fin = '2025-06-28', limite = 10 })
    egal(trouvees.total, 1, "le 28 juin à l'heure locale")
    egal(Commandes.executer('chercher', { drapeau = 'aucun', date_debut = '2025-06-29', limite = 10 }).total, 0)
end)

test("2.4 : collection renommée, déplacée, critères changés ; mot-clé renommé, synonymes", function()
    local c = S.Collection('Sélection', nil)
    local dyn = S.Collection('Les meilleures', nil, { { criteria = 'rating', operation = '>=', value = 4 }, combine = 'intersect' })
    local r = Commandes.executer('collections', { action = 'renommer', collection = 'Sélection', nouveau_nom = 'Sélection finale', etape = 'x' })
    egal(c.nom, 'Sélection finale')
    egal(r.collection.avant.nom, 'Sélection')
    Commandes.executer('collections', { action = 'deplacer', collection = c.id, ensemble = 'Voyages > 2026', etape = 'x' })
    egal(c.parent.nom, '2026')
    egal(c.parent.parent.nom, 'Voyages')
    Commandes.executer('collections', { action = 'criteres', collection = 'Les meilleures', recherche = { note_min = 5 }, etape = 'x' })
    egal(dyn.recherche[1].value, 5)
    echoue(function() Commandes.executer('collections', { action = 'criteres', collection = c.id, recherche = { note_min = 5 }, etape = 'x' }) end, "pas une collection dynamique")
    local chien = S.MotCle('chien', S.MotCle('Animaux'))
    local m = Commandes.executer('collections', { action = 'mot_cle', mot_cle = 'Animaux > chien', nouveau_nom = 'Chien', synonymes = Json.tableau({ 'dog' }), etape = 'x' })
    egal(chien.nom, 'Chien')
    egal(chien.synonymes[1], 'dog')
    egal(m.mot_cle.apres.chemin, 'Animaux > Chien')
    -- Un mot-clé créé reçoit ses synonymes.
    local photo = photoRaw()
    S.active = photo
    classer({ ajouter = { 'Lieux > plage' }, synonymes = { ['Lieux > plage'] = Json.tableau({ 'beach' }) } })
    egal(photo.motsCles[1].nom, 'plage')
    egal(photo.motsCles[1].synonymes[1], 'beach')
end)

test("2.4 : filtre de la Bibliothèque posé, puis le filtre d'avant remis", function()
    local photo = photoRaw()
    S.active = photo
    S.filtre = { filtersActive = true, minRating = 1, ratingOp = '>=', pick = '<nil>', columnBrowserDesc = { { criteria = 'focalLength' } } }
    S.presetsFiltre = { ['Retenues'] = 'uuid-retenues' }
    photo.brut.path = '/Volumes/Photos/Gaspesie/DSC_0412.NEF'
    local r = Commandes.executer('montrer', { source_dossier = '/Volumes/Photos/Gaspesie', filtre = { drapeau = 'retenue', note_min = 3, libelle = 'rouge' } })
    egal(S.filtre.pick, 'flagged')
    egal(S.filtre.minRating, 3)
    egal(S.filtre.label1, true)
    egal(S.filtre.columnBrowserDesc[1].criteria, 'focalLength', "les colonnes du filtre Métadonnées gardées")
    egal(S.vue, 'grid')
    egal(contient({ r.filtre }, "Filtre posé"), true)
    Commandes.executer('montrer', { filtre_preset = 'retenues' })
    egal(S.filtrePreset, 'Retenues')
    Commandes.executer('montrer', { remettre_filtre = true })
    egal(S.filtre.minRating, 1, "le filtre d'avant le premier changement")
    egal(S.filtre.pick, '<nil>')
    egal(S.filtrePreset, nil, "ses valeurs exactes, pas un paramètre prédéfini")
    Commandes.executer('montrer', { filtre = 'aucun' })
    egal(S.filtre.filtersActive, false)
    egal(S.filtre.columnBrowserDesc[1].criteria, 'focalLength')
    echoue(function() Commandes.executer('montrer', { filtre_preset = 'Inconnu' }) end, "« Retenues »")
end)

test("2.4 : un original absent est refusé avec sa raison", function()
    local photo = photoRaw()
    photo.absente = true
    photo.brut.path = '/Volumes/Disque/DSC_0412.NEF'
    S.active, S.module = photo, 'develop'
    echoue(function() debruiter({ ameliorations = demande('denoise', true, 40) }) end, "original introuvable (/Volumes/Disque/DSC_0412.NEF)")
    echoue(function() Commandes.executer('supprimer', { reflets = { actif = true }, etape = 'x' }) end, "La suppression des reflets se calcule sur l'original")
    egal(#S.appelsAmelioration, 0)
    echoue(function() Commandes.executer('apercu', { taille = 512 }) end, "Sans aperçu dynamique")
    photo.brut.smartPreviewInfo = { smartPreviewPath = '/x.dng', smartPreviewSize = 1000 }
    local apercu = Commandes.executer('apercu', { taille = 512 })
    egal(contient({ apercu.original }, "aperçu dynamique"), true)
    local absente, autre = deuxPhotosALivrer()
    absente.absente = true
    absente.brut.smartPreviewInfo = { smartPreviewPath = '/x.dng', smartPreviewSize = 1000 }
    local livraison = Commandes.executer('exporter', { photos = { 1, 2 }, dossier = '/Volumes/Photos/Livraison', reglages = REGLAGES_WEB, suite = true })
    egal(#S.dernierExport.photosToExport, 1, "seule la photo présente")
    egal(S.dernierExport.photosToExport[1], autre)
    egal(contient({ livraison.fichiers[1].erreur }, "2560 px"), true)
    egal(livraison.fichiers[2].chemin ~= nil, true)
end)

test("2.4 : barre de progression de Lightroom, arrêtée par la croix, fermée à la fin", function()
    local r = Commandes.executer('progression', { id = 'a', titre = 'tri des photos', fait = 0, total = 300, message = 'tri' })
    egal(r.annulee, false)
    local barre = S.barres[1]
    egal(barre.titre, 'Claude : tri des photos')
    egal(barre.annulable, true)
    Commandes.executer('progression', { id = 'a', fait = 25, total = 300, message = '25 sur 300' })
    egal(barre.fait, 25)
    egal(#S.barres, 1, "la même barre")
    barre.annulee = true
    egal(Commandes.executer('progression', { id = 'a', fait = 50, total = 300 }).annulee, true)
    Commandes.executer('progression', { id = 'a', fin = true })
    egal(barre.finie, true)
    -- Une barre sans nouvelle se ferme à la commande suivante.
    Commandes.executer('progression', { id = 'b', fait = 1, total = 2 })
    S.horloge = S.horloge + 301
    Commandes.executer('ping', {})
    egal(S.barres[2].finie, true)
end)

test("2.4 : sauvegarde du catalogue demandée pour la prochaine fermeture", function()
    local etat = Commandes.executer('etat', { sauvegarde = true })
    egal(S.sauvegardeDemandee, true)
    egal(contient({ etat.sauvegarde }, "prochaine fermeture"), true)
    egal(Commandes.executer('etat', {}).sauvegarde, nil)
end)


-- Livraison (2.5) ------------------------------------------------------------------------

local function photoHdr()
    local photo = photoFuji()
    photo.reglages.HDREditMode = 1
    photo.brut.path = '/Volumes/Photos/2025/Gaspesie/XH2S0320.RAF'
    S.active, S.selection = photo, { photo }
    S.fichiers['/Volumes/Photos'] = 'dossier'
    return photo
end

test("2.5 : AVIF HDR avec carte de gain ; une photo hors du mode HDR est refusée avec sa raison", function()
    local photo = photoHdr()
    local sdr = photoJpeg()
    local resultat = Commandes.executer('exporter', { photos = { 4, 2 }, dossier = '/Volumes/Photos/HDR',
        reglages = { format = 'AVIF', hdr = true, espace = 'p3_hdr', qualite = 75, compatibilite = true } })
    local r = S.dernierExport.exportSettings
    egal(r.LR_format, 'AVIF')
    egal(r.LR_enableHDRDisplay, true)
    egal(r.LR_export_colorSpace, 'p3_hdr')
    egal(r.LR_export_bitDepth, 10, "AVIF : 10 bits")
    egal(r.LR_maximumCompatibility, true)
    proche(r.LR_avif_quality, 0.75)
    egal(#S.dernierExport.photosToExport, 1, "seule la photo en mode HDR est rendue")
    egal(resultat.fichiers[1].chemin, '/Volumes/Photos/HDR/XH2S0320.avif')
    egal(resultat.fichiers[2].erreur:find("HDREditMode", 1, true) ~= nil, true)
    echoue(function() Commandes.executer('exporter', { photos = { 2 }, dossier = '/Volumes/Photos/HDR', reglages = { format = 'AVIF', hdr = true } }) end,
        "pas en mode HDR")
    egal(sdr.reglages.HDREditMode, nil)
end)

test("2.5 : JPEG HDR toujours avec carte de gain, jamais en HDR Rec. 2020 ; JPEG XL et PSD", function()
    photoHdr()
    Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/HDR',
        reglages = { format = 'JPEG', hdr = true, espace = 'Rec2020_hdr', compatibilite = false } })
    local r = S.dernierExport.exportSettings
    egal(r.LR_export_colorSpace, 'p3_hdr', "relevé dans Lightroom : pas de HDR Rec. 2020 en JPEG")
    egal(r.LR_maximumCompatibility, true, "le JPEG HDR a toujours sa carte de gain")
    egal(r.LR_export_bitDepth, 8)
    Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/HDR',
        reglages = { format = 'JXL', hdr = true, espace = 'Rec2020_hdr', sans_perte = true } })
    r = S.dernierExport.exportSettings
    egal(r.LR_export_colorSpace, 'Rec2020_hdr')
    egal(r.LR_jxl_losslessQuality, true)
    egal(r.LR_export_bitDepth, 16, "JPEG XL en HDR : 16 bits")
    Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/HDR',
        reglages = { format = 'PSD', hdr = true, profondeur = 32 } })
    egal(S.dernierExport.exportSettings.LR_export_bitDepth, 32)
    egal(S.dernierExport.exportSettings.LR_maximumCompatibility, false, "pas de carte de gain en PSD")
    Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/HDR', reglages = { format = 'TIFF', profondeur = 32 } })
    egal(S.dernierExport.exportSettings.LR_export_bitDepth, 8, "32 bits seulement en HDR")
end)

test("2.5 : poids maximal (JPEG) et filigrane ; ni l'un ni l'autre pour l'original", function()
    deuxPhotosALivrer()
    Commandes.executer('exporter', { photos = { 1 }, dossier = '/Volumes/Photos/Web',
        reglages = { format = 'JPEG', qualite = 90, poids_max_ko = 500, filigrane = '8A6E-ESSAI' } })
    local r = S.dernierExport.exportSettings
    egal(r.LR_jpeg_useLimitSize, true)
    egal(r.LR_jpeg_limitSize, 500)
    egal(r.LR_useWatermark, true)
    egal(S.dernierExport.filigrane, '8A6E-ESSAI')
    Commandes.executer('exporter', { photos = { 1 }, dossier = '/Volumes/Photos/Web',
        reglages = { format = 'PNG', poids_max_ko = 500 } })
    egal(S.dernierExport.exportSettings.LR_jpeg_useLimitSize, false, "PNG : pas de limite de poids")
    Commandes.executer('exporter', { photos = { 1 }, dossier = '/Volumes/Photos/Web',
        reglages = { format = 'ORIGINAL', filigrane = '<simpleCopyrightWatermark>' } })
    egal(S.dernierExport.exportSettings.LR_useWatermark, false, "pas de filigrane sur l'original")
end)

test("2.5 : réimportée et empilée, la livraison va dans le dossier de l'original ; la recette la retire", function()
    local photo = photoHdr()
    local resultat = Commandes.executer('exporter', { photos = { 4 },
        reglages = { format = 'TIFF', reimporter = 'pile' } })
    local r = S.dernierExport.exportSettings
    egal(r.LR_export_destinationType, 'sourceFolder', "Lightroom n'empile que dans le dossier de l'original")
    egal(r.LR_reimportExportedPhoto, true)
    egal(r.LR_reimport_stackWithOriginal, true)
    egal(r.LR_reimport_stackWithOriginal_position, 'below')
    egal(resultat.dossier, '/Volumes/Photos/2025/Gaspesie')
    local chemin = resultat.fichiers[1].chemin
    egal(chemin, '/Volumes/Photos/2025/Gaspesie/XH2S0320.tif')
    local id = resultat.fichiers[1].reimportee
    egal(type(id), 'number', "la photo réimportée est trouvée par son chemin")
    egal(S.photos[id].empileeAvec, photo, "empilée avec l'original")
    echoue(function() Commandes.executer('retirerReimportees', { chemins = { '/Volumes/Photos/autre.tif' } }) end, "pas été réimporté")
    Commandes.executer('retirerReimportees', { chemins = { chemin } })
    egal(S.photos[id], nil, "retirée du catalogue")
    egal(S.retireesDuCatalogue[1].localIdentifier, id)
    echoue(function() Commandes.executer('retirerReimportees', { chemins = { chemin } }) end, "pas été réimporté")
    Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/Imprimerie', reglages = { format = 'TIFF', reimporter = 'catalogue' } })
    egal(S.dernierExport.exportSettings.LR_export_destinationType, 'specificFolder')
    egal(S.dernierExport.exportSettings.LR_reimport_stackWithOriginal, false)
end)

-- Constaté le 21 octobre 2026 : après la recette, la photo active était une photo du dossier de la
-- livraison réimportée puis retirée ; la vue d'avant est remise (source, puis photo active).
test("recette : la photo réimportée retirée hors du film fixe, la photo active et la source d'avant reviennent", function()
    local photo = photoHdr()
    local resultat = Commandes.executer('exporter', { photos = { 4 }, reglages = { format = 'TIFF', reimporter = 'pile' } })
    local chemin, id = resultat.fichiers[1].chemin, resultat.fichiers[1].reimportee
    local affichee = photoRaw()
    local essais = { { nom = 'Développeur › Essais' } }
    S.sources = essais
    S.active, S.selection = affichee, { affichee }
    S.invisibles[id] = true
    Commandes.executer('retirerReimportees', { chemins = { chemin } })
    egal(S.photos[id], nil, "retirée du catalogue")
    egal(S.sourcesChangees[#S.sourcesChangees - 1][1].chemin, '/Volumes/Photos/2025/Gaspesie', "son dossier affiché le temps du retrait")
    egal(S.sources, essais, "la source d'avant revient")
    egal(S.active, affichee, "la photo active d'avant revient")
    egal(photo.retireeDuCatalogue, nil, "l'original reste")
    -- Même après un échec : la vue revient.
    resultat = Commandes.executer('exporter', { photos = { 4 }, reglages = { format = 'TIFF', reimporter = 'pile' } })
    chemin, id = resultat.fichiers[1].chemin, resultat.fichiers[1].reimportee
    S.invisibles[id] = true
    echoue(function() Commandes.executer('retirerReimportees', { chemins = { chemin, '/Volumes/Photos/autre.tif' } }) end, "pas été réimporté")
    egal(S.sources, essais)
    egal(S.active, affichee, "la photo active d'avant revient après l'échec")
end)

test("2.5 : original débranché, livraison depuis l'aperçu dynamique jusqu'à 2560 px", function()
    local photo = photoHdr()
    photo.reglages.HDREditMode = 0
    photo.absente = true
    echoue(function() Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/Web', reglages = { format = 'JPEG' } }) end,
        "original introuvable")
    photo.brut.smartPreviewInfo = { smartPreviewPath = '/Apercus/4.dng', smartPreviewSize = 1000 }
    echoue(function() Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/Web', reglages = { format = 'JPEG' } }) end,
        "2560 px")
    echoue(function() Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/Web',
        reglages = { format = 'JPEG', taille = { type = 'megapixels', valeur = 5 } } }) end, "2560 px")
    local resultat = Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/Web',
        reglages = { format = 'JPEG', taille = { type = 'longEdge', valeur = 2048 } } })
    egal(resultat.fichiers[1].depuis_apercu_dynamique, true)
    egal(S.dernierExport.depuisApercu, true)
    Commandes.executer('exporter', { photos = { 4 }, dossier = '/Volumes/Photos/Web',
        reglages = { format = 'JPEG', taille = { type = 'megapixels', valeur = 4 } } })
end)

test("2.5 : aperçus dynamiques créés, puis retirés sauf si l'original manque", function()
    local a, b = deuxPhotosALivrer()
    local c = photoFuji()
    c.absente = true
    local cree = Commandes.executer('apercusDynamiques', { photos = { 1, 2, 4 } })
    egal(#cree.crees, 2)
    egal(cree.sans_original[1], 'XH2S0320.RAF (Copie 1)')
    egal(cree.taille_mo, 4)
    egal(#Commandes.executer('apercusDynamiques', { photos = { 1 } }).existants, 1)
    c.absente = false
    c:buildSmartPreview()
    c.absente = true
    local retire = Commandes.executer('apercusDynamiques', { photos = { 1, 4 }, retirer = true })
    egal(retire.retires[1], 'DSC_0412.NEF')
    egal(retire.sans_original[1], 'XH2S0320.RAF (Copie 1)', "l'aperçu d'une photo sans original est gardé")
    egal(c.brut.smartPreviewInfo.smartPreviewPath ~= nil, true)
end)

test("2.5 : dossier choisi dans une fenêtre, en attente puis relu ; annulé", function()
    S.dossierChoisi = { '/Volumes/Photos/Envoi Gaspesie' }
    local choix = Commandes.executer('choisirDossier', { depart = '/Volumes/Photos' })
    egal(choix.dossier, '/Volumes/Photos/Envoi Gaspesie')
    egal(S.panneaux[1].canChooseDirectories, true)
    egal(S.panneaux[1].canChooseFiles, false)
    S.differerTaches, S.reprendreTachesA = true, S.horloge + 60
    egal(Commandes.executer('choisirDossier', {}).en_attente, true, "l'utilisateur n'a pas encore choisi")
    egal(#S.panneaux, 1, "la fenêtre attend l'utilisateur")
    local relu = Commandes.executer('choisirDossier', {})
    egal(relu.dossier, '/Volumes/Photos/Envoi Gaspesie', "la commande suivante relit le choix")
    egal(#S.panneaux, 2, "une seule fenêtre ouverte pour les deux commandes")
    S.differerTaches = false
    S.dossierChoisi = nil
    egal(Commandes.executer('choisirDossier', {}).annule, true)
end)

test("2.5 : noms exacts calculés par Lightroom avec un modèle", function()
    deuxPhotosALivrer()
    S.modelesNoms = { ['Nom personnalisé - Séquence'] = 'id-sequence' }
    S.nomsModeles = { ['id-sequence'] = '{texte}-{numero}' }
    local noms = Commandes.executer('nomsFichiers', { photos = { 1, 2 }, modele = 'nom personnalisé - séquence', texte_perso = 'Gaspesie', sequence = 7 })
    egal(noms.modele, 'Nom personnalisé - Séquence')
    egal(noms.noms[1].nom, 'Gaspesie-7')
    egal(noms.noms[2].nom, 'Gaspesie-8')
    echoue(function() Commandes.executer('nomsFichiers', { photos = { 1 }, modele = 'Inconnu' }) end, "introuvable")
end)

test("2.5 : les réglages des services Disque dur se lisent clé par clé", function()
    S.Service('Lightroom Export 5 Megapixels', 'com.adobe.ag.export.file', {
        LR_format = 'JPEG', LR_jpeg_quality = 1, LR_size_doConstrain = true, LR_size_resizeType = 'megapixels', LR_size_megapixels = 5,
        LR_export_destinationPathPrefix = '/Volumes/Photos/Lightroom Export 5 Megapixels' })
    S.Service('Flickr', 'com.adobe.lightroom.export.flickr', { LR_format = 'JPEG' })
    local options = Commandes.executer('livraison', {})
    local disque = options.services_publication[1].reglages
    egal(disque.LR_size_megapixels, 5, "lu malgré une table que pairs ne parcourt pas (constaté en 2.3)")
    egal(disque.LR_export_destinationPathPrefix, '/Volumes/Photos/Lightroom Export 5 Megapixels')
    egal(options.services_publication[2].reglages, nil, "seulement les services Disque dur")
end)

-- Photo agrandie par l'ancienne version (agrandissement génératif de Camera Raw) ------
-- Le module n'agrandit pas, mais de telles photos restent au catalogue : la garde les protège.

local function rawAgrandie()
    local photo = photoFuji()
    photo.brut.path = '/Volumes/Photos/2026/XH2S0320.RAF'
    return photo
end

local REGLAGES_AGRANDIS = {
    CropLeft = -0.2, CropTop = 0, CropRight = 1, CropBottom = 1, CropAngle = 0, CropConstrainToUnitSquare = 0,
    FilterList = { Filters = { { FilterID = 9, Name = 'Generative Expand' } } }, Exposure2012 = 0,
}

test("photo agrandie : elle refuse le recadrage de Claude (constaté : crop.angle perdait l'agrandissement)", function()
    local photo = rawAgrandie()
    for cle, valeur in pairs(REGLAGES_AGRANDIS) do photo.reglages[cle] = valeur end
    echoue(function() appliquer({ photos = { 4 }, recadrage = { angle = 1 } }) end, "Photo agrandie")
    proche(photo.reglages.CropLeft, -0.2, "cadre gardé")
end)

test("photo agrandie : copier le recadrage vers elle ne l'efface pas", function()
    local source = rawAgrandie()
    source.reglages.CropLeft, source.reglages.CropRight = 0.1, 0.9
    local cible = S.Photo(7, {}, { fileName = 'XH2S0320-agrandi.dng', fileFormat = 'DNG' }, { path = '/Volumes/Photos/2026/XH2S0320-agrandi.dng' })
    for cle, valeur in pairs(REGLAGES_AGRANDIS) do cible.reglages[cle] = valeur end
    local resultat = Commandes.executer('copier', { source = 4, photos = { 7 }, cles = {}, inclure = { recadrage = true }, etape = 'copie' })
    proche(cible.reglages.CropLeft, -0.2, "agrandissement gardé")
    egal(contient(resultat.resultats[1].remarques or {}, "Recadrage non copié"), true, "dit pourquoi")
end)

-- Version 1.1 : notation ---------------------------------------------------------------

local function proposer(propositions, params)
    params = params or {}
    params.action = 'proposer'
    params.propositions = Json.tableau(propositions)
    return Commandes.executer('notation', params)
end

local CRITERES = { impact = "Arrête l'œil", qualites = "Lumière rasante", plancher = "Nette (52)" }

local function etapes(photo)
    return #Json.decode(photo.proprietes.etapesClaude or '[]')
end

test("notation : proposer range les propositions sans rien écrire ; au-delà de 5 étoiles refusées ; photo absente isolée", function()
    local a, b = photoRaw(), photoJpeg()
    a.brut.rating, b.brut.pickStatus = 2, 1
    local ecritures, privees = #S.ecritures, S.ecrituresPrivees
    local r = proposer({
        { photo = 1, note = 3, drapeau = 'aucun', criteres = { impact = "Arrête l'œil", qualites = "Lumière", plancher = "Nette", finition = "" },
            plafond = 4, raison = "Sujet clair, fond calme.", a_verifier = false },
        { photo = 2, note = 0, drapeau = 'rejetee', criteres = CRITERES, raison = "Floue." },
        { photo = 777, note = 2, criteres = CRITERES, raison = "?" },
    })
    egal(#S.ecritures, ecritures, "rien d'écrit dans le catalogue")
    egal(S.ecrituresPrivees, privees, "ni dans la mémoire des photos")
    egal(a.brut.rating, 2)
    egal(r.seance, nil, "plus de séance de notation (1.1.1)")
    egal(#r.propositions, 2)
    egal(r.propositions[1].photo, 1)
    egal(r.propositions[1].fichier, 'DSC_0412.NEF')
    egal(r.propositions[1].note_avant, 2)
    egal(r.propositions[1].drapeau_avant, 'aucun')
    egal(r.propositions[2].drapeau_avant, 'retenue')
    egal(r.propositions[1].etat, 'a_verifier', "toute proposition commence à vérifier (1.1.1)")
    egal(#r.refusees, 1, "la photo absente ne bloque pas les autres")
    egal(r.refusees[1].photo, 777)
    egal(r.refusees[1].raison:find("777", 1, true) ~= nil, true, r.refusees[1].raison)
    local p = Notation.proposition(1)
    egal(getmetatable(p), nil, "copie neuve")
    egal(p.note, 3)
    egal(p.uuid, 'uuid-1')
    egal(p.criteres.impact, "Arrête l'œil")
    egal(p.criteres.finition, nil, "critère vide")
    egal(p.plafond, 4)
    egal(p.raison, "Sujet clair, fond calme.")
    egal(p.seance, nil)
    p.note = 0
    egal(Notation.proposition(1).note, 3, "la copie ne touche pas le registre")
    local rejet = Notation.proposition(2)
    egal(rejet.drapeau, 'rejetee')
    egal(rejet.note, nil, "un rejet sans note (le serveur envoie 0)")
    egal(Liaison.journal[#Liaison.journal]:find("Notation : 2 propositions", 1, true) ~= nil, true, Liaison.journal[#Liaison.journal])
    -- view_photo dit l'évaluation gardée : une photo déjà évaluée ne se renote pas.
    egal(Commandes.executer('apercu', { photo = 1, taille = 512, cles = {}, point_af = true }).evaluation,
        "3 ★ proposée par Claude, à vérifier")
    egal(Commandes.executer('apercu', { photo = 2, taille = 512, cles = {} }).evaluation, nil, "seulement pour view_photo")

    local version = Notation.version
    -- Correctif 1.3.2 : Claude propose de 0 à 5 étoiles ; au-delà, tout est refusé.
    echoue(function() proposer({ { photo = 2, note = 6, criteres = CRITERES } }) end, "un entier de 0 à 5")
    echoue(function() proposer({ { photo = 1, note = 5 }, { photo = 2, note = 6 } }) end, "un entier de 0 à 5")
    egal(Notation.proposition(1).note, 3, "rien de rangé quand une note est refusée")
    egal(Notation.version, version)
    echoue(function() proposer({ { photo = 1, note = 2.5 } }) end, "Note invalide")
    echoue(function() proposer({ { photo = 1, note = -1 } }) end, "Note invalide")
    echoue(function() proposer({ { note = 2, criteres = CRITERES } }) end, "Proposition sans photo")
    echoue(function() proposer({ { photo = 1, note = 3, drapeau = 'retenue' } }) end, "Drapeau invalide")
    echoue(function() proposer({ { photo = 1 } }) end, "le drapeau « rejetee »")
    echoue(function() proposer({}) end, "Aucune proposition")
    echoue(function() proposer({ { photo = 1, note = 2, criteres = CRITERES } }, { passe = 5 }) end, "Passe invalide")
    egal(Notation.proposition(1).note, 3, "rien de rangé")
    egal(Notation.version, version, "registre inchangé par les refus")
    echoue(function() Commandes.executer('notation', { action = 'effacer' }) end, "Action de notation inconnue")
    local sansRefus = Json.encode(proposer({ { photo = 1, note = 3, criteres = CRITERES } }))
    egal(sansRefus:find('"refusees":[]', 1, true) ~= nil, true, sansRefus)
    -- 5 étoiles, à la passe 4 (monter à 5, après le développement) : rangées « à vérifier ».
    local cinq = proposer({ { photo = 1, note = 5, criteres = CRITERES, raison = "Parmi les meilleures." } }, { passe = 4 })
    egal(cinq.propositions[1].etat, 'a_verifier')
    egal(Notation.proposition(1).note, 5)
    egal(Notation.proposition(1).passe, 4)
    egal(#S.ecritures, ecritures, "toujours rien d'écrit dans le catalogue")
end)

test("notation : une nouvelle proposition remplace l'ancienne ; passe gardée", function()
    photoRaw(); photoJpeg(); photoFuji()
    local r = proposer({ { photo = 1, note = 3, criteres = CRITERES }, { photo = 4, note = 2, criteres = CRITERES } }, { passe = 2 })
    egal(r.seance, nil)
    egal(r.propositions[2].hors_seance, nil)
    egal(Notation.proposition(1).passe, 2)
    egal(Notation.proposition(1).seance, nil)
    proposer({ { photo = 1, note = 4, criteres = CRITERES, raison = "Meilleure vue de son moment." } })
    local p = Notation.proposition(1)
    egal(p.note, 4, "la nouvelle proposition remplace l'ancienne")
    egal(p.raison, "Meilleure vue de son moment.")
    egal(p.passe, nil, "sans passe donnée")
    proposer({ { photo = 2, note = 1, criteres = CRITERES, a_verifier = true } })
    egal(Notation.proposition(2).etat, 'a_verifier', "un cas douteux attend « à vérifier »")
    echoue(function() proposer({ { photo = 1, note = 2 } }, { passe = 7 }) end, "Passe invalide")
    egal(Notation.ouvrirSeance, nil, "plus de séance de notation (1.1.1)")
    egal(Notation.compter, nil)
end)

test("notation : lire et décisions de l'utilisateur ; plus d'action seance", function()
    photoRaw(); photoJpeg(); photoFuji()
    echoue(function() Commandes.executer('notation', { action = 'seance' }) end, "Action de notation inconnue")
    proposer({ { photo = 1, note = 3, criteres = CRITERES }, { photo = 2, drapeau = 'rejetee', criteres = CRITERES },
        { photo = 4, note = 2, criteres = CRITERES } })
    egal(Notation.decider(4, 'ecartee', { commentaire = "Doublon de la 1" }), true)
    egal(Notation.decider(2, 'a_verifier'), true)
    local ok, raison = Notation.decider(99, 'ecartee')
    egal(ok, nil)
    egal(raison:find("Aucune proposition", 1, true) ~= nil, true)
    egal((Notation.decider(1, 'acceptee')), nil, "accepter passe par poser")
    local l = Commandes.executer('notation', { action = 'lire' })
    egal(l.seance_active, nil)
    egal(l.seances, nil)
    egal(#l.propositions, 3)
    egal(l.propositions[3].etat, 'ecartee')
    egal(l.propositions[3].commentaire, "Doublon de la 1")
    egal(l.propositions[1].uuid, nil, "l'uuid reste dans le module")
    egal(Json.decode(Json.encode(l)).propositions[2].drapeau, 'rejetee')
    egal(#Commandes.executer('notation', { action = 'lire', photos = Json.tableau({ 2 }) }).propositions, 1)
    -- Une photo retirée du catalogue, ou dont l'identifiant désigne une autre photo : proposition perdue.
    S.photos[4] = nil
    S.photos[2].brut.uuid = 'uuid-autre'
    local l2 = Commandes.executer('notation', { action = 'lire' })
    egal(l2.perdues, 2)
    egal(#l2.propositions, 1)
    egal(Notation.proposition(4), nil)
    egal(Notation.proposition(2), nil)
end)

test("notation : poser des propositions acceptées et changées, une écriture, une étape par photo, undo_last sur une photo", function()
    local a, b, c = photoRaw(), photoJpeg(), photoFuji()
    local d = S.Photo(5, {}, { fileName = 'DSC_0500.NEF', fileFormat = 'RAW' }, { pickStatus = -1 })
    a.brut.pickStatus, b.brut.rating = 1, 2
    proposer({ { photo = 1, note = 3, criteres = CRITERES, raison = "Sujet clair." }, { photo = 2, note = 0, drapeau = 'rejetee', criteres = CRITERES },
        { photo = 4, note = 2, criteres = CRITERES }, { photo = 5, note = 2, criteres = CRITERES } })
    local vus = {}
    Notation.abonner('essai', function(quoi) vus[#vus + 1] = quoi end)
    local version = Notation.version
    local ecritures = #S.ecritures
    local r = Notation.poser({ { photo = 1 }, { photo = 2 }, { photo = 4, note = 5, drapeau = 'retenue' }, { photo = 5 } })
    egal(r.ok, true, tostring(r.erreur))
    egal(#S.ecritures, ecritures + 1, "une seule écriture")
    egal(S.ecritures[#S.ecritures], "Claude · notation")
    egal(a.brut.rating, 3)
    egal(a.brut.pickStatus, 1, "le drapeau Retenue de l'utilisateur reste")
    egal(b.brut.pickStatus, -1)
    egal(b.brut.rating, 2, "un rejet accepté laisse les étoiles")
    egal(c.brut.rating, 5, "5 étoiles posées par l'utilisateur")
    egal(c.brut.pickStatus, 1)
    egal(d.brut.rating, 2)
    egal(d.brut.pickStatus, 0, "accepter une note retire un rejet déjà posé")
    egal(Notation.proposition(1).etat, 'acceptee')
    egal(Notation.proposition(2).etat, 'acceptee')
    egal(Notation.proposition(5).etat, 'acceptee')
    local changee = Notation.proposition(4)
    egal(changee.etat, 'changee')
    egal(changee.note_choisie, 5)
    egal(changee.drapeau_choisi, 'retenue')
    egal(changee.note, 2, "la proposition de Claude reste lisible")
    egal(r.resultats[3].etat, 'changee')
    egal(r.resultats[3].note, 5)
    egal(#r.resultats[1].changements, 1)
    egal(Notation.version, version + 1)
    egal(vus[#vus], 'pose')
    egal(etapes(a), 1)
    egal(etapes(c), 1)
    egal(a.proprietes.retoucheeParClaude, nil, "une note n'est pas une retouche")
    local journal = Commandes.executer('journal', { photos = { 1 } }).photos[1].entrees
    egal(journal[#journal].type, 'classement')
    egal(journal[#journal].raison, "Sujet clair.", "la raison de Claude au journal")
    Commandes.executer('annuler', { photos = { 4 } })
    egal(c.brut.rating, nil)
    egal(c.brut.pickStatus, 0)
    egal(a.brut.rating, 3, "les autres photos gardent leur note")
    -- Changer… de nouveau, à la note que Claude proposait : acceptée.
    egal(Notation.poser({ { photo = 4, note = 2, drapeau = 'aucun' } }).resultats[1].etat, 'acceptee')
    egal(Notation.proposition(4).note_choisie, nil)
    -- Changer… une photo sans proposition : écrite, sans état.
    local e = S.Photo(6, {}, { fileName = 'X.JPG' })
    local sans = Notation.poser({ { photo = 6, note = 1 } })
    egal(sans.ok, true)
    egal(e.brut.rating, 1)
    egal(sans.resultats[1].etat, nil)
    egal(Notation.proposition(6), nil)
    egal(Notation.poser({ { photo = 6 } }).erreur:find("Aucune proposition", 1, true) ~= nil, true, "rien à accepter")
    -- Erreurs par photo : introuvable, sans bloquer les autres.
    local manque = Notation.poser({ { photo = 777 }, { photo = 1, note = 4 } })
    egal(manque.ok, true)
    egal(manque.resultats[1].erreur:find("777", 1, true) ~= nil, true)
    egal(a.brut.rating, 4)
    version = Notation.version
    egal(Notation.poser({ { photo = 777 } }).ok, false)
    egal(Notation.poser({}).ok, false)
    egal(Notation.version, version, "rien de changé")
    -- La photo n'est plus celle que Claude a notée (autre uuid) : rien d'écrit, proposition retirée.
    proposer({ { photo = 1, note = 2, criteres = CRITERES } })
    a.brut.uuid = 'uuid-autre'
    local autre = Notation.poser({ { photo = 1 } })
    egal(autre.ok, false)
    egal(autre.erreur:find("n'est plus celle", 1, true) ~= nil, true)
    egal(a.brut.rating, 4)
    egal(Notation.proposition(1), nil)
end)

test("notation : poser lève la pause et « Proposer d'abord », jamais les garde-fous", function()
    local a = photoRaw()
    proposer({ { photo = 1, note = 3, criteres = CRITERES } })
    Liaison.pause = true
    S.prefs.mode, S.prefs.accordDansLightroom = 'proposer', true
    local r = Notation.poser({ { photo = 1 } })
    egal(r.ok, true, tostring(r.erreur))
    egal(a.brut.rating, 3)
    egal(Liaison.propositionEnAttente, nil, "aucun accord demandé dans la fenêtre de suivi")
    local Bibliotheque = require 'Bibliotheque'
    echoue(function() Bibliotheque.noter({ notes = { { photo = 1, note = 2 } } }) end, "pause")
    Liaison.pause = false
    echoue(function() Bibliotheque.noter({ notes = { { photo = 1, note = 2 } } }) end, "Proposer d'abord")
    S.prefs.mode, S.prefs.accordDansLightroom = nil, nil

    proposer({ { photo = 1, note = 4, criteres = CRITERES } })
    S.prefs.copiesSeulement = true
    local refus = Notation.poser({ { photo = 1 } })
    egal(refus.ok, false)
    egal(refus.erreur:find("pas une copie virtuelle", 1, true) ~= nil, true, refus.erreur)
    egal(refus.resultats[1].erreur, refus.erreur)
    egal(a.brut.rating, 3, "rien d'écrit")
    egal(Notation.proposition(1).etat, 'a_verifier', "rien de marqué")
    S.prefs.copiesSeulement = false
    S.prefs.rejeteesProtegees = true
    a.brut.pickStatus = -1
    egal(Notation.poser({ { photo = 1, note = 5 } }).erreur:find("rejetée", 1, true) ~= nil, true)
    S.prefs.rejeteesProtegees = false
    a.brut.pickStatus = 0
    S.prefs.libelleProtege, a.meta.label = 'rouge', 'Rouge'
    egal(Notation.poser({ { photo = 1 } }).erreur:find("libellé rouge protégé", 1, true) ~= nil, true)
    S.prefs.libelleProtege, a.meta.label = 'aucun', nil

    -- Plafond de photos : Tout accepter est l'accord de l'utilisateur ; sans lui, refusé.
    local ids = plusieurs(21)
    local liste, notes = {}, {}
    for i, id in ipairs(ids) do
        liste[i] = { photo = id, note = 2, criteres = CRITERES }
        notes[i] = { photo = id, note = 2 }
    end
    echoue(function() Bibliotheque.noter({ notes = notes, depuisLightroom = true }) end, "plafond de 20")
    proposer(liste)
    local ecritures = #S.ecritures
    local tout = Notation.poser((function() local l = {} for i, id in ipairs(ids) do l[i] = { photo = id } end return l end)())
    egal(tout.ok, true, tostring(tout.erreur))
    egal(#S.ecritures, ecritures + 1, "21 photos en une écriture")
    egal(S.photos[521].brut.rating, 2)
    echoue(function() Bibliotheque.noter({ notes = { { photo = 1, note = 7 } }, depuisLightroom = true }) end, "Note invalide")
    echoue(function() Bibliotheque.noter({ notes = { { photo = 1, drapeau = 'jaune' } }, depuisLightroom = true }) end, "Drapeau invalide")
    echoue(function() Bibliotheque.noter({ notes = { { photo = 1 } }, depuisLightroom = true }) end, "Rien à poser")
    echoue(function() Bibliotheque.noter({ notes = { { note = 2 } }, depuisLightroom = true }) end, "Note sans photo")
    echoue(function() Bibliotheque.noter({ notes = {}, depuisLightroom = true }) end, "Aucune note")
end)

-- 1.1.1 : « note ces photos » (propose_ratings avec apply) : Claude pose aussi les notes, comme
-- Accepter, « à vérifier » comprises (demandé par Dany le 20 octobre 2026).
test("notation : proposer avec poser pose les notes, à vérifier comprises ; la pause l'arrête, pas « Proposer d'abord »", function()
    local a, b = photoRaw(), photoJpeg()
    local ecritures = #S.ecritures
    local r = proposer({
        { photo = 1, note = 3, criteres = CRITERES, raison = "Tient seule." },
        { photo = 2, note = 2, criteres = CRITERES, raison = "Douteuse.", a_verifier = true },
        { photo = 777, note = 2, criteres = CRITERES },
    }, { poser = true })
    egal(#S.ecritures, ecritures + 1, "une écriture pour les deux photos")
    egal(S.ecritures[#S.ecritures], "Claude · notation")
    egal(a.brut.rating, 3)
    egal(b.brut.rating, 2, "à vérifier comprise : Dany a demandé de noter")
    egal(#r.posees, 2)
    egal(r.posees[1].etat, 'acceptee')
    egal(r.posees[2].etat, 'acceptee')
    egal(r.posees[1].note, 3)
    egal(r.erreur_pose, nil)
    egal(#r.refusees, 1, "la photo absente reste refusée, sans bloquer la pose")
    egal(Notation.proposition(1).etat, 'acceptee')
    egal(etapes(a), 1, "une étape par photo, que undo_last défait")
    Commandes.executer('annuler', { photos = { 1 } })
    egal(a.brut.rating, nil)
    -- Sans poser : rangées seulement.
    ecritures = #S.ecritures
    local seul = proposer({ { photo = 1, note = 4, criteres = CRITERES } })
    egal(#S.ecritures, ecritures)
    egal(seul.posees, nil)
    egal(a.brut.rating, nil)
    -- « Proposer d'abord » : la demande explicite vaut accord.
    S.prefs.mode = 'proposer'
    proposer({ { photo = 1, note = 4, criteres = CRITERES } }, { poser = true })
    egal(a.brut.rating, 4)
    -- Avec « Confirmer dans Lightroom » : l'accord se donne dans la fenêtre de suivi, puis Claude
    -- rappelle propose_ratings avec apply (pas set_metadata, qui laisserait le registre en arrière).
    S.prefs.accordDansLightroom = true
    local attente = proposer({ { photo = 1, note = 3, criteres = CRITERES } }, { poser = true })
    egal(a.brut.rating, 4, "rien posé sans l'accord")
    egal(attente.erreur_pose and attente.erreur_pose:find("rappeler propose_ratings avec apply = true", 1, true) ~= nil, true,
        tostring(attente.erreur_pose))
    egal(attente.erreur_pose:find("set_metadata", 1, true), nil)
    egal(Liaison.propositionEnAttente and Liaison.propositionEnAttente.outil, 'propose_ratings')
    Liaison.propositionEnAttente, Liaison.accord = nil, nil
    S.prefs.accordDansLightroom = nil
    S.prefs.mode = nil
    -- La pause de la liaison arrête la pose (elle n'arrête pas un clic dans la fenêtre).
    Liaison.pause = true
    local pause = proposer({ { photo = 1, note = 1, criteres = CRITERES } }, { poser = true })
    Liaison.pause = false
    egal(a.brut.rating, 4, "rien posé pendant la pause")
    egal(pause.erreur_pose and pause.erreur_pose:find("pause", 1, true) ~= nil, true, tostring(pause.erreur_pose))
    egal(Notation.proposition(1).etat, 'a_verifier', "la proposition reste à décider")
    -- Jamais plus de 5 étoiles proposées, même avec poser.
    echoue(function() proposer({ { photo = 1, note = 6, criteres = CRITERES } }, { poser = true }) end, "un entier de 0 à 5")
end)

test("notation : Tout accepter par lots d'écritures ; au plus 500 photos par écriture", function()
    local ids = plusieurs(5)
    local liste, accepter = {}, {}
    for i, id in ipairs(ids) do
        liste[i] = { photo = id, note = 2, criteres = CRITERES }
        accepter[i] = { photo = id }
    end
    proposer(liste)
    local lot = Notation.LOT
    Notation.LOT = 2
    local ecritures = #S.ecritures
    local r = Notation.poser(accepter)
    Notation.LOT = lot
    egal(r.ok, true, tostring(r.erreur))
    egal(#S.ecritures, ecritures + 3, "5 photos par lots de 2")
    egal(S.photos[505].brut.rating, 2)
    egal(Notation.proposition(505).etat, 'acceptee')
    local trop = {}
    for i, id in ipairs(plusieurs(501)) do
        trop[i] = { photo = id, note = 1 }
    end
    echoue(function() require('Bibliotheque').noter({ notes = trop, depuisLightroom = true, confirme = true }) end, "au plus 500")
end)

test("notation : une photo donnée deux fois ne compte qu'une fois, avec sa dernière note", function()
    local a = photoRaw()
    local Bibliotheque = require 'Bibliotheque'
    local r = Bibliotheque.noter({ notes = { { photo = 1, note = 2 }, { photo = '1', note = 4, raison = "Finalement." } },
        etape = 'notation', depuisLightroom = true, confirme = true })
    egal(#r.resultats, 1)
    egal(a.brut.rating, 4)
    egal(contient(r.resultats[1].remarques, "plusieurs fois"), true)
    egal(etapes(a), 1, "une seule étape")
    local journal = Json.decode(a.proprietes.journalClaude)
    egal(journal[#journal].raison, "Finalement.")
    Commandes.executer('annuler', { photos = { 1 } })
    egal(a.brut.rating, nil, "l'annulation remet la note d'avant")
    proposer({ { photo = 1, note = 3, criteres = CRITERES } })
    local p = Notation.poser({ { photo = 1 }, { photo = 1 } })
    egal(p.ok, true)
    egal(etapes(a), 1)
    egal(a.brut.rating, 3)
end)

test("notation : une note posée par l'utilisateur reste au retour à l'origine ; undo_last la défait", function()
    local a, b = photoRaw(), photoJpeg()
    S.active = a
    appliquer({ reglages = { Exposure2012 = 0.5 } })
    proposer({ { photo = 1, note = 3, criteres = CRITERES }, { photo = 2, note = 2, criteres = CRITERES } })
    local r = Notation.poser({ { photo = 1 }, { photo = 2, note = 4 } })
    egal(r.ok, true, tostring(r.erreur))
    egal(a.brut.rating, 3)
    egal(b.brut.rating, 4)
    egal(Json.decode(a.proprietes.avantClaude).Bibliotheque, nil, "la note de l'utilisateur n'entre pas dans l'état d'avant Claude")
    egal(Json.decode(a.proprietes.avantClaude).Exposure2012, 0, "la retouche de Claude, si")
    egal(b.proprietes.avantClaude, nil, "rien d'écrit pour une photo que Claude n'a pas retouchée")
    egal(etapes(a), 2)
    -- Revenir à « Avant Claude » (ou revert_to_original) : la retouche part, la note reste.
    local remise = {}
    for _, resultat in ipairs(Commandes.executer('revenir', { photos = { 1, 2 } }).resultats) do
        remise[resultat.photo.id] = resultat
    end
    egal(remise[1].remise, true)
    egal(a.reglages.Exposure2012, 0, "la retouche de Claude est défaite")
    egal(a.brut.rating, 3, "la note posée par l'utilisateur reste")
    egal(remise[2].sans_retouche, true, "une note seule n'est pas une retouche à défaire")
    egal(b.brut.rating, 4)
    -- undo_last défait la note, étape par étape.
    Commandes.executer('annuler', { photos = { 2 } })
    egal(b.brut.rating, nil, "undo_last remet la note d'avant")
    egal(etapes(b), 0)
end)

test("notation : recaler le registre sur la note réelle après undo_last (constaté) ; une écriture pour plusieurs photos", function()
    local a, b, c = photoRaw(), photoJpeg(), photoFuji()
    local d = S.Photo(5, {}, { fileName = 'DSC_0500.NEF', fileFormat = 'RAW' })
    proposer({ { photo = 1, note = 3, criteres = CRITERES }, { photo = 2, note = 0, drapeau = 'rejetee', criteres = CRITERES },
        { photo = 4, note = 2, criteres = CRITERES }, { photo = 5, note = 2, criteres = CRITERES } })
    local r = Notation.poser({ { photo = 1 }, { photo = 2 }, { photo = 4, note = 5, drapeau = 'retenue' }, { photo = 5 } })
    egal(r.ok, true, tostring(r.erreur))
    -- Ce qu'une fenêtre lit dans Lightroom : note (nil sans étoiles) et drapeau (pickStatus).
    local function releves(...)
        local liste = {}
        for _, photo in ipairs({ ... }) do
            liste[#liste + 1] = { photo = photo.localIdentifier, note = tonumber(photo.brut.rating) or 0, drapeau = tonumber(photo.brut.pickStatus) or 0 }
        end
        return liste
    end
    local Fichiers = require 'Fichiers'
    local ecrire, ecrits = Fichiers.ecrire, 0
    Fichiers.ecrire = function(chemin, ...)
        if chemin == Notation.fichier() then
            ecrits = ecrits + 1
        end
        return ecrire(chemin, ...)
    end
    local vus = {}
    Notation.abonner('essai', function(quoi) vus[#vus + 1] = quoi end)
    -- Les notes posées sont toujours là : rien ne change, rien n'est écrit.
    local version = Notation.version
    egal(Notation.recaler(releves(a, b, c, d)), 0)
    egal(Notation.version, version)
    egal(ecrits, 0, "rien d'écrit sans changement")
    -- undo_last sur trois photos (constaté le 20 octobre 2026 : la note quitte le catalogue, le
    -- registre restait « acceptée ») : une seule écriture du registre pour les trois.
    Commandes.executer('annuler', { photos = { 1, 2, 4 } })
    egal(a.brut.rating, nil)
    egal(tonumber(b.brut.pickStatus) or 0, 0, "le rejet accepté est défait")
    egal(c.brut.rating, nil)
    egal(Notation.recaler(releves(a, b, c, d), Notation.version), 3)
    egal(ecrits, 1, "une écriture pour toute la page")
    egal(Notation.version, version + 1)
    egal(vus[#vus], 'recalage')
    for _, id in ipairs({ 1, 2, 4 }) do
        local p = Notation.proposition(id)
        egal(p.etat, 'a_verifier', "photo " .. id .. " : de nouveau à décider")
        egal(p.note_choisie, nil)
        egal(p.drapeau_choisi, nil)
        egal(p.decide_le, nil)
    end
    egal(Notation.proposition(4).note, 2, "la proposition de Claude reste")
    egal(Notation.proposition(5).etat, 'acceptee', "une note toujours posée reste acceptée")
    egal(Json.decode(S.fichiers[Notation.fichier()]).propositions['1'].etat, 'a_verifier', "rangé dans notation.json")
    -- Relue de nouveau : plus rien à recaler.
    egal(Notation.recaler(releves(a, b, c, d)), 0)
    egal(ecrits, 1)
    -- Une autre note posée à la main remplace l'acceptée ; un Retenue de l'utilisateur sur une note
    -- acceptée ne la défait pas ; un rejet accepté ne regarde que le drapeau.
    egal(Notation.poser({ { photo = 1 }, { photo = 2 } }).ok, true)
    a.brut.pickStatus, b.brut.rating = 1, 4
    egal(Notation.recaler(releves(a, b)), 0)
    a.brut.rating = 4
    egal(Notation.recaler(releves(a, b)), 1)
    egal(Notation.proposition(1).etat, 'a_verifier')
    egal(Notation.proposition(2).etat, 'acceptee')
    -- Une changée : sa note et son drapeau choisis.
    egal(Notation.poser({ { photo = 4, note = 1, drapeau = 'aucun' } }).resultats[1].etat, 'changee')
    egal(Notation.recaler({ { photo = 4, note = 1, drapeau = 'aucun' } }), 0)
    egal(Notation.recaler({ { photo = 4, note = 1, drapeau = 'retenue' } }), 1, "drapeau changé")
    egal(Notation.proposition(4).etat, 'a_verifier')
    -- Rien de recalé : une note illisible, un drapeau inconnu, une proposition à décider, une photo
    -- sans proposition, ou un registre changé depuis la lecture (une note posée entre-temps).
    egal(Notation.poser({ { photo = 5, note = 3 } }).ok, true)
    egal(Notation.recaler({ { photo = 5, note = nil, drapeau = 0 }, { photo = 5, note = 0, drapeau = 'jaune' },
        { photo = 1, note = 0, drapeau = 0 }, { photo = 777, note = 0, drapeau = 0 } }), 0)
    egal(Notation.recaler({ { photo = 5, note = 0, drapeau = 0 } }, Notation.version - 1), 0, "relevé plus vieux que le registre")
    egal(Notation.proposition(5).etat, 'changee')
    egal(Notation.recaler({ { photo = 5, note = 0, drapeau = 'aucun' } }, Notation.version), 1)
    -- Pendant une écriture (Tout accepter), une fenêtre a pu relever une photo avant que sa note y
    -- soit posée : rien ne se recale tant qu'elle dure, même avec la version du moment.
    egal(Notation.proposition(1).etat, 'a_verifier')
    egal(Notation.proposition(5).etat, 'a_verifier')
    local avant = Notation.version
    local lire, recales = d.getRawMetadata, 0
    d.getRawMetadata = function(self, cle)
        if cle == 'rating' then
            recales = recales + Notation.recaler({ { photo = 1, note = 0, drapeau = 0 } }, avant)
        end
        return lire(self, cle)
    end
    local pose = Notation.poser({ { photo = 1 }, { photo = 5 } })
    d.getRawMetadata = lire
    egal(pose.ok, true, tostring(pose.erreur))
    egal(recales, 0, "rien de recalé pendant l'écriture")
    egal(Notation.proposition(1).etat, 'acceptee')
    egal(Notation.proposition(5).etat, 'acceptee')
    egal(Notation.recaler({ { photo = 1, note = 0, drapeau = 0 } }, avant), 0, "relevé d'avant l'écriture")
    egal(Notation.proposition(1).etat, 'acceptee')
    Fichiers.ecrire = ecrire
    Notation.desabonner('essai')
end)

-- Constaté le 21 octobre 2026 : après l'étape de notation de la recette (proposée, posée avec apply,
-- défaite par undo_last), la proposition de 53709912 restait « acceptee » dans notation.json, et
-- le recalage n'y voyait rien (la photo avait déjà 2 ★). La recette remet le registre comme elle
-- l'a trouvé (action remettre), sans écrire au catalogue.
test("notation remettre : la recette remet la proposition qu'elle a trouvée, ou la retire ; rien d'écrit au catalogue", function()
    local a = photoRaw()
    photoJpeg()
    a.brut.rating = 2
    proposer({ { photo = 1, note = 3, criteres = CRITERES, raison = "D'avant la recette." } })
    local function lire1()
        return Commandes.executer('notation', { action = 'lire', photos = Json.tableau({ 1 }) }).propositions[1]
    end
    local avant = lire1()
    -- Comme le serveur la renvoie : relue du JSON.
    local avantJson = Json.decode(Json.encode(avant))
    -- L'étape de la recette : proposée, posée avec apply (2 ★, déjà la note de la photo), défaite.
    proposer({ { photo = 1, note = 2, criteres = CRITERES, a_verifier = true, raison = "Recette." } }, { poser = true })
    egal(Notation.proposition(1).etat, 'acceptee')
    Commandes.executer('annuler', { photos = { 1 } })
    egal(a.brut.rating, 2)
    egal(Notation.recaler({ { photo = 1, note = 2, drapeau = 0 } }, Notation.version), 0, "rien à recaler : la note est là")
    egal(Notation.proposition(1).etat, 'acceptee', "le registre ne voit pas l'annulation (constaté)")
    local ecritures, privees = #S.ecritures, S.ecrituresPrivees
    local r = Commandes.executer('notation', { action = 'remettre', photo = 1, proposition = avantJson })
    egal(#S.ecritures, ecritures, "rien d'écrit au catalogue")
    egal(S.ecrituresPrivees, privees)
    egal(r.proposition.etat, 'a_verifier')
    egal(Json.encode(lire1()), Json.encode(avant), "la proposition d'avant, telle quelle")
    local p = Notation.proposition(1)
    egal(p.uuid, 'uuid-1', "avec l'uuid de la photo")
    egal(getmetatable(p.criteres), nil, "tables neuves")
    egal(Json.decode(S.fichiers[Notation.fichier()]).propositions['1'].raison, "D'avant la recette.", "rangée dans notation.json")
    -- Aucune proposition au départ : retirée.
    Commandes.executer('notation', { action = 'remettre', photo = 1, proposition = Json.null })
    egal(Notation.proposition(1), nil)
    egal(Commandes.executer('notation', { action = 'remettre', photo = 1 }).proposition, Json.null)
    -- Refus, sans rien changer.
    local version = Notation.version
    echoue(function() Commandes.executer('notation', { action = 'remettre', photo = 1, proposition = { photo = 1, etat = 'a_verifier', note = 6 } }) end,
        "Note au-delà de 5")
    echoue(function() Commandes.executer('notation', { action = 'remettre', photo = 1, proposition = { photo = 2, etat = 'a_verifier', note = 1 } }) end,
        "invalide")
    echoue(function() Commandes.executer('notation', { action = 'remettre', photo = 1, proposition = { photo = 1, etat = 'posee', note = 1 } }) end,
        "invalide")
    echoue(function() Commandes.executer('notation', { action = 'remettre', proposition = Json.null }) end, "Photo manquante")
    echoue(function() Commandes.executer('notation', { action = 'remettre', photo = 777, proposition = Json.null }) end, "777")
    egal(Notation.version, version)
    egal(Notation.proposition(1), nil)
end)

test("notation : registre gardé dans notation.json, propre au catalogue ouvert", function()
    photoRaw()
    proposer({ { photo = 1, note = 3, criteres = CRITERES } })
    local fichier = Notation.fichier()
    egal(fichier, S.home .. '/Library/Application Support/Developpeur/notation.json')
    local relu = Json.decode(S.fichiers[fichier])
    egal(relu.catalogue, '/Users/test/Images/Catalogue.lrcat')
    egal(relu.propositions['1'].note, 3, "clés des photos en texte")
    Notation.oublier()
    egal(Notation.proposition(1).note, 3, "relue du fichier")
    egal(Notation.proposition('1').note, 3)
    egal(getmetatable(Notation.proposition(1).criteres), nil, "relue : copie neuve sans métatable")
    egal(relu.seances, nil, "plus de séances (1.1.1)")
    -- Un registre d'avant la 1.1.1 : ses séances sont oubliées, ses propositions gardées.
    S.fichiers[fichier] = Json.encode({ format = 1, catalogue = '/Users/test/Images/Catalogue.lrcat', seanceActive = 's1',
        seances = { s1 = { id = 's1', titre = 'Vieille', photos = { 1 } } },
        propositions = { ['1'] = { photo = 1, note = 2, drapeau = 'aucun', etat = 'proposee', seance = 's1' } } })
    Notation.oublier()
    egal(Notation.proposition(1).note, 2)
    egal(Notation.proposition(1).seance, nil)
    -- Un autre catalogue : registre vide, et le fichier ne change pas avant sa première proposition.
    S.cheminCatalogue = '/Users/test/Images/Autre.lrcat'
    egal(Notation.proposition(1), nil)
    Notation.oublier()
    egal(Notation.proposition(1), nil, "relu, toujours pour l'autre catalogue")
    egal(S.fichiers[fichier]:find('Catalogue.lrcat', 1, true) ~= nil, true)
    S.cheminCatalogue = '/Users/test/Images/Catalogue.lrcat'
    egal(Notation.proposition(1).note, 2, "le premier catalogue retrouve son registre")
    S.cheminCatalogue = '/Users/test/Images/Autre.lrcat'
    proposer({ { photo = 1, note = 1, criteres = CRITERES } })
    egal(Json.decode(S.fichiers[fichier]).catalogue, '/Users/test/Images/Autre.lrcat')
    S.fichiers[fichier] = '{ pas du JSON'
    Notation.oublier()
    egal(Notation.proposition(1), nil, "fichier illisible : registre vide")
end)

test("notation : abonnés prévenus à chaque changement ; registre élagué", function()
    photoRaw(); photoJpeg(); photoFuji()
    local vus = {}
    Notation.abonner('essai', function(quoi) vus[#vus + 1] = quoi end)
    Notation.abonner('casse', function() error("fenêtre fermée") end)
    local version = Notation.version
    proposer({ { photo = 1, note = 3, criteres = CRITERES } })
    egal(Notation.version, version + 1)
    egal(vus[1], 'propositions', "un abonné qui échoue ne gêne pas les autres")
    Notation.decider(1, 'a_verifier')
    egal(vus[2], 'decision')
    Notation.desabonner('essai')
    Notation.decider(1, 'ecartee')
    egal(#vus, 2)
    local maxP = Notation.MAX_PROPOSITIONS
    Notation.MAX_PROPOSITIONS = 2
    proposer({ { photo = 1, note = 3, criteres = CRITERES }, { photo = 2, note = 3, criteres = CRITERES }, { photo = 4, note = 3, criteres = CRITERES } })
    egal(Notation.proposition(1), nil, "la plus ancienne sort")
    egal(Notation.proposition(4).note, 3)
    Notation.MAX_PROPOSITIONS = maxP
end)

test("notation : Notation se charge sans l'interface ni la Bibliothèque (la fenêtre s'en sert)", function()
    local f = assert(io.open(dossierModule .. 'Notation.lua', 'r'))
    local source = f:read('*a')
    f:close()
    for ligne in source:gmatch('[^\n]+') do
        local module = ligne:match("^local%s+[%w_]+%s*=%s*require%s*%(?%s*'([%w_]+)'") or ligne:match("^local%s+[%w_]+%s*=%s*import%s*'([%w_]+)'")
        if module then
            egal(module == 'Bibliotheque' or module == 'LrApplicationView' or module == 'LrView' or module == 'LrDialogs', false, ligne)
        end
    end
end)

-- Version 1.2 : bilan de view_photo (étapes de Claude dans l'aperçu) -------------------------

test("apercu : point_af donne les étapes de Claude, pour le bilan de view_photo (1.2)", function()
    local photo = photoRaw()
    S.active = photo
    local resultat = Commandes.executer('apercu', { taille = 1344, cles = {}, point_af = true })
    egal(resultat.etapes_claude.nombre, 0, "aucune étape de Claude")
    egal(resultat.etapes_claude.derniere, Json.null, "pas de dernière étape (null en JSON)")

    appliquer({ reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } }, etape = 'passe 1 : lumière' })
    local ecritures, appliques = #S.ecritures, #photo.appliques
    resultat = Commandes.executer('apercu', { taille = 1344, cles = {}, point_af = true })
    egal(resultat.etapes_claude.nombre, 1)
    egal(resultat.etapes_claude.derniere, 'Claude · passe 1 : lumière')
    egal(#S.ecritures, ecritures, "l'aperçu lit les étapes sans écrire dans le catalogue")
    egal(#photo.appliques, appliques)
    local relu = Json.decode(Json.encode(resultat))
    egal(relu.etapes_claude.nombre, 1, "passe en JSON")

    appliquer({ reglages = { Vibrance = 10 }, plages = { Vibrance = { -100, 100 } }, etape = 'passe 2 : couleur' })
    egal(Commandes.executer('apercu', { taille = 1344, cles = {}, point_af = true }).etapes_claude.derniere, 'Claude · passe 2 : couleur')
    Commandes.executer('annuler', {})
    resultat = Commandes.executer('apercu', { taille = 1344, cles = {}, point_af = true })
    egal(resultat.etapes_claude.nombre, 1, "l'annulation retire l'étape : le serveur le dit « retouche défaite »")
    egal(resultat.etapes_claude.derniere, 'Claude · passe 1 : lumière')

    -- Sans point_af (aperçus d'analyse, avant/après) : rien de plus.
    egal(Commandes.executer('apercu', { taille = 1344, cles = {} }).etapes_claude, nil)
end)

-- Garde de l'étape « éclaircir et assombrir » (1.2) : trois dégradés en une étape, dont un radial
-- inversé (constaté le 20 octobre 2026 : il n'agit que hors de l'ellipse), puis son avant/après
-- par view_photo avec compare = previous_step.
test("apercu : avant/après de l'étape éclaircir et assombrir (etapePrecedente)", function()
    local photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', {
        masques = Json.tableau({
            { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.45, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.125 } },
            { type = 'radial', centre_x = 0.45, centre_y = 0.4, rayon_x = 0.2, fondu = 90, nom = 'Claude · Sujet', locaux = { LocalExposure2012 = 0.075 } },
            { type = 'radial', centre_x = 0.45, centre_y = 0.4, rayon_x = 0.7, rayon_y = 0.7, fondu = 90, inverser = true,
              nom = 'Claude · Bords', locaux = { LocalExposure2012 = -0.1 } },
        }),
        etape = 'éclaircir et assombrir', raison = "Mener l'œil au sujet.",
    })
    local masques = photo.reglages.MaskGroupBasedCorrections
    egal(#masques, 3, "les trois dégradés en une étape")
    local bords = masques[3].CorrectionMasks[1]
    egal(bords.What, 'Mask/CircularGradient')
    egal(bords.MaskInverted, true, "radial inversé : il agit hors de l'ellipse")
    egal(bords.Flipped, true, "forme constatée : Flipped avec MaskInverted")
    egal(bords.Feather, 90)
    local etapes = Json.decode(photo.proprietes.etapesClaude)
    egal(etapes[#etapes].nom, "Claude · éclaircir et assombrir")

    local nombre = #photo.appliques
    local resultat = Commandes.executer('apercu', { comparer = 'etapePrecedente', taille = 1344, cles = {} })
    egal(resultat.chemin_avant ~= nil, true, "l'image d'avant l'étape")
    local avant = photo.appliques[nombre + 1]
    egal(avant.nom, "Claude · comparaison (avant)")
    egal(#(avant.reglages.MaskGroupBasedCorrections or {}), 0, "l'avant ne porte aucun des trois dégradés")
    egal(photo.appliques[nombre + 2].nom, "Claude · comparaison (retour)")
    egal(#photo.reglages.MaskGroupBasedCorrections, 3, "les trois sont remis ensuite")
    egal(photo.reglages.MaskGroupBasedCorrections[3].CorrectionMasks[1].MaskInverted, true)
    egal(resultat.etapes_claude, nil, "un avant/après ne donne pas les étapes : il ne touche pas au bilan des vues")
end)

-- Radial inversé (1.2, constaté le 20 octobre 2026 dans Lightroom Classic 15.6) : la forme qu'écrit
-- Locaux.radial (Mask/CircularGradient, Flipped = true, l'inversion par MaskInverted seul) agit hors
-- de l'ellipse quand elle est inversée, dans l'ellipse sinon. Ces essais la figent clé par clé, puis
-- vérifient que la simulation refuse toute autre forme, par les deux chemins d'écriture du module.
local FORME_RADIAL = {
    What = 'Mask/CircularGradient', MaskActive = true, MaskBlendMode = 0, MaskValue = 1,
    Angle = 15, Feather = 80, Midpoint = 50, Roundness = 0, Flipped = true, Version = 2,
}
local CLES_RADIAL = { 'What', 'MaskActive', 'MaskBlendMode', 'MaskID', 'MaskInverted', 'MaskName', 'MaskSyncID', 'MaskValue',
    'Left', 'Top', 'Right', 'Bottom', 'Angle', 'Feather', 'Midpoint', 'Roundness', 'Flipped', 'Version' }

test("Locaux.radial : la forme constatée, Flipped avec MaskInverted, clé par clé", function()
    local connues = {}
    for _, cle in ipairs(CLES_RADIAL) do
        connues[cle] = true
    end
    for _, inverse in ipairs({ true, false }) do
        local m = Locaux.radial(0.1, 0.2, 0.9, 0.8, 15, 80, 'Claude · Bords', inverse)
        for cle in pairs(m) do
            egal(connues[cle], true, "clé de plus dans le radial (forme non constatée) : " .. tostring(cle))
        end
        for _, cle in ipairs(CLES_RADIAL) do
            egal(m[cle] ~= nil, true, "clé du radial constaté : " .. cle)
        end
        for cle, valeur in pairs(FORME_RADIAL) do
            egal(m[cle], valeur, "radial " .. (inverse and "inversé" or "droit") .. ", " .. cle)
        end
        egal(m.MaskInverted, inverse, "l'inversion passe par MaskInverted seul")
        proche(m.Left, 0.1) proche(m.Top, 0.2) proche(m.Right, 0.9) proche(m.Bottom, 0.8)
        egal(m.MaskName, 'Claude · Bords')
    end
    local defaut = Locaux.radial(0.2, 0.2, 0.8, 0.8)
    egal(defaut.Flipped, true, "Flipped même sans inversion demandée")
    egal(defaut.MaskInverted, false)
    egal(defaut.Angle, 0) egal(defaut.Feather, 50)
end)

test("simulation : un radial sans la forme constatée est refusé (Flipped, MaskInverted)", function()
    local photo = photoRaw()
    local function radial(champ, valeur)
        local m = Locaux.radial(0.2, 0.2, 0.8, 0.8, 0, 80, 'Claude · Bords', true)
        m[champ] = valeur
        return { MaskGroupBasedCorrections = { Locaux.correction('Claude · Bords', 1, { LocalExposure2012 = -0.075 }, { m }) } }
    end
    local refus = {
        { 'Flipped', nil, "Flipped = true" }, { 'Flipped', false, "Flipped = true" }, { 'Flipped', 'true', "Flipped = true" },
        { 'MaskInverted', nil, "MaskInverted vrai ou faux" }, { 'MaskInverted', 1, "MaskInverted vrai ou faux" },
    }
    for _, cas in ipairs(refus) do
        S.ecritureEnCours = true
        echoue(function() photo:applyDevelopSettings(radial(cas[1], cas[2]), 'essai') end, cas[3])
        echoue(function() photo:applyDevelopPreset({ nom = 'essai', reglages = radial(cas[1], cas[2]) }) end, cas[3])
        S.ecritureEnCours = false
    end
    -- Un composant d'un masque combiné est vérifié de même.
    local sujet = Locaux.masqueIA(1, nil, 'Claude · Sujet', false)
    local bords = Locaux.combiner(Locaux.radial(0.2, 0.2, 0.8, 0.8, 0, 80, nil, false), 'intersecter', true)
    bords.Flipped = nil
    S.ecritureEnCours = true
    echoue(function()
        photo:applyDevelopSettings({ MaskGroupBasedCorrections = { Locaux.correction('x', 1, {}, { sujet, bords }) } }, 'essai')
    end, "Flipped = true")
    -- La forme de Locaux.radial passe, inversée ou non.
    photo:applyDevelopSettings(radial('Flipped', true), 'essai')
    photo:applyDevelopSettings(radial('MaskInverted', false), 'essai')
    S.ecritureEnCours = false
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].Flipped, true)
end)

test("masquer : le radial inversé garde la forme constatée, par applyDevelopSettings et par un paramètre prédéfini", function()
    local bords = { type = 'radial', centre_x = 0.5, centre_y = 0.5, rayon_x = 0.7, rayon_y = 0.7, fondu = 80, inverser = true,
        nom = 'Claude · Bords', locaux = { LocalExposure2012 = -0.075 } }
    local photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', { masques = Json.tableau({ bords }), etape = 'bords' })
    egal(#photo.appliques > 0, true, "le radial est écrit")
    for _, applique in ipairs(photo.appliques) do
        egal(applique.preset, nil, "un radial seul : par applyDevelopSettings, sans paramètre prédéfini")
    end
    local m = photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1]
    egal(m.What, 'Mask/CircularGradient') egal(m.Flipped, true) egal(m.MaskInverted, true)

    photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', {
        masques = Json.tableau({ { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.15 }, quantite = 1 }, bords }),
        etape = 'ciel et bords',
    })
    egal(photo.appliques[#photo.appliques].preset ~= nil, true, "avec un masque IA : par un paramètre prédéfini")
    m = photo.reglages.MaskGroupBasedCorrections[2].CorrectionMasks[1]
    egal(m.What, 'Mask/CircularGradient') egal(m.Flipped, true) egal(m.MaskInverted, true)

    -- Si Locaux.radial changeait de forme (ici sans Flipped), la simulation refuserait l'écriture.
    local radial = Locaux.radial
    Locaux.radial = function(...)
        local r = radial(...)
        r.Flipped = nil
        return r
    end
    photo = photoFuji()
    S.active = photo
    local ok, erreur = pcall(Commandes.executer, 'masquer', { masques = Json.tableau({ bords }), etape = 'bords' })
    Locaux.radial = radial
    egal(ok, false, "un radial sans Flipped est refusé")
    egal(tostring(erreur):find('Flipped = true', 1, true) ~= nil, true, "la raison : " .. tostring(erreur))
end)

-- Les autres chemins qui posent ou inversent un radial (plan du tireur : recopie, edit_mask
-- dupliquer inversé, composant d'un masque combiné) gardent la forme constatée : Flipped vrai,
-- l'inversion par MaskInverted seul. S'ils basculaient Flipped, la simulation refuserait l'écriture.
test("radial : composant intersecté, dupliqué inversé et copié, toujours Flipped avec MaskInverted", function()
    local photo = photoFuji()
    S.active = photo
    -- Le ciel limité à l'ellipse (intersection = soustraction du radial inversé, Locaux.combiner).
    Commandes.executer('masquer', {
        masques = Json.tableau({ {
            type = 'ia', soustype = 2, nom = 'Claude · Ciel au centre', locaux = { LocalExposure2012 = -0.1 },
            composants = Json.tableau({
                { mode = 'intersecter', type = 'radial', centre_x = 0.5, centre_y = 0.4, rayon_x = 0.3, fondu = 80, nom = 'Centre' },
            }),
        } }),
        etape = 'ciel au centre',
    })
    local composant = photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[2]
    egal(composant.What, 'Mask/CircularGradient')
    egal(composant.Flipped, true, "composant intersecté : Flipped gardé")
    egal(composant.MaskBlendMode, 1) egal(composant.MaskInverted, true, "l'intersection passe par MaskInverted")

    -- edit_mask, dupliquer inversé : la copie d'un radial s'inverse par MaskInverted seul.
    photo = photoFuji()
    S.active = photo
    Commandes.executer('masquer', {
        masques = Json.tableau({ { type = 'radial', centre_x = 0.5, centre_y = 0.5, rayon_x = 0.3, fondu = 80,
            nom = 'Claude · Sujet', locaux = { LocalExposure2012 = 0.075 } } }),
        etape = 'sujet',
    })
    Commandes.executer('masques', { action = 'dupliquer', masque = 1, inverser = true, nom = 'Bords' })
    local masques = photo.reglages.MaskGroupBasedCorrections
    egal(#masques, 2)
    egal(masques[1].CorrectionMasks[1].Flipped, true) egal(masques[1].CorrectionMasks[1].MaskInverted, false)
    egal(masques[2].CorrectionName, 'Claude · Bords')
    egal(masques[2].CorrectionMasks[1].Flipped, true, "la copie inversée garde Flipped")
    egal(masques[2].CorrectionMasks[1].MaskInverted, true, "la copie s'inverse par MaskInverted")

    -- Copie des masques vers une autre photo : le radial inversé arrive tel quel.
    local cible = photoFuji()
    cible.localIdentifier = 5
    S.photos[5] = cible
    local source = photoFuji()
    source.reglages.MaskGroupBasedCorrections = {
        Locaux.correction('Claude · Bords', 1, { LocalExposure2012 = -0.075 }, { Locaux.radial(0.1, 0.1, 0.9, 0.9, 0, 80, 'Bords', true) }),
    }
    S.active = cible
    Commandes.executer('copier', { source = 4, photos = { 5 }, cles = {}, inclure = { masques = true }, etape = 'copie' })
    local copie = cible.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1]
    egal(copie.What, 'Mask/CircularGradient')
    egal(copie.Flipped, true, "copié : Flipped gardé") egal(copie.MaskInverted, true, "copié : toujours inversé")
end)

A.bilan()
