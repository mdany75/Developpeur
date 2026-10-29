-- essais-generatif.lua : la retouche générative (Fibo 2, outil generative_edit du connecteur,
-- demandée par Dany le 29 octobre 2026), côté module, hors de Lightroom (LuaJIT, Lightroom simulé
-- par Simulation.lua) : la commande importerGeneree (le TIFF final de Temporaire/Fibo copié à côté
-- de l'original, ajouté au catalogue par catalog:addPhoto dans une écriture, empilé au-dessus de lui,
-- devenu la photo active), ses refus (pause, « Proposer d'abord », chemin hors du dossier de Fibo,
-- original introuvable, fichier refusé par Lightroom), l'accord de l'exportation qui vaut pour
-- l'importation, le ménage de Temporaire/Fibo et la puce des consignes de la fenêtre ; depuis la
-- relecture du 29 octobre 2026, l'exportation vers Fibo (accord au nom de generative_edit avec
-- l'étape et la consigne, pas une livraison : apercuSeulement), les garde-fous des photos, la copie
-- virtuelle sous « Copies virtuelles seulement » et la photo d'essai (Essais, sans pile).
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, echoue = A.test, A.egal, A.echoue

local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'
local Livraison = require 'Livraison'
local Menage = require 'Menage'
local Consignes = require 'Consignes'

-- La mémoire des exportations vers Fibo repart de zéro avant chaque essai.
A.remiseAZero('Livraison', function(module) module.exportsFibo = {} end)

local FIBO = S.home .. '/Library/Application Support/Developpeur/Temporaire/Fibo'
local DOSSIER = '/Volumes/Photos/2026/10'
local ORIGINAL = DOSSIER .. '/DSCF2402.RAF'
local CONSIGNE = "replace the trousers with a knee-length navy skirt"

-- L'original sur le disque, photo active et seule sélectionnée.
local function original()
    local photo = S.Photo(7, { Exposure2012 = 0.35, ProcessVersion = '15.4' },
        { fileName = 'DSCF2402.RAF', fileFormat = 'RAW', cameraModel = 'X-H2S' }, { path = ORIGINAL })
    S.fichiers[DOSSIER] = 'dossier'
    S.fichiers[ORIGINAL] = 'raw'
    S.active, S.selection = photo, { photo }
    return photo
end

-- Le TIFF final que le connecteur laisse dans un dossier neuf de Temporaire/Fibo.
local function sortieFibo(nom)
    local dossier = FIBO .. '/A1B2C3'
    S.fichiers[S.home .. '/Library/Application Support/Developpeur/Temporaire'] = 'dossier'
    S.fichiers[FIBO] = 'dossier'
    S.fichiers[dossier] = 'dossier'
    local chemin = dossier .. '/' .. (nom or 'final.tif')
    S.fichiers[chemin] = 'TIFF 16 bits de Fibo 2'
    return chemin
end

local function importer(params)
    params = params or {}
    params.photo = params.photo or 7
    params.chemin = params.chemin or sortieFibo()
    if params.nom == nil then
        params.nom = 'DSCF2402-Fibo'
    elseif params.nom == false then
        params.nom = nil
    end
    params.consigne = params.consigne or CONSIGNE
    return Commandes.executer('importerGeneree', params)
end

local function journalDe(photo)
    return Json.decode(photo.proprietes.journalClaude or '[]')
end

-- Rien n'a été fait : ni copie à côté de l'original, ni photo au catalogue, ni écriture.
local function rienFait(sortie)
    egal(#S.ajoutees, 0, "aucune photo ajoutée")
    egal(#S.ecritures, 0, "aucune écriture")
    egal(S.fichiers[DOSSIER .. '/DSCF2402-Fibo.tif'], nil, "aucune copie à côté de l'original")
    if sortie then
        egal(S.fichiers[sortie], 'TIFF 16 bits de Fibo 2', "le fichier de Fibo reste, le connecteur efface son dossier")
    end
end

test("importerGeneree : copiée à côté de l'original, ajoutée au catalogue dans une écriture, empilée au-dessus, photo active ; l'original intact", function()
    local photo = original()
    local sortie = sortieFibo()
    local avant = Json.encode(photo.reglages)
    local r = importer({ chemin = sortie })
    local chemin = DOSSIER .. '/DSCF2402-Fibo.tif'
    egal(r.chemin, chemin)
    egal(r.fichier, 'DSCF2402-Fibo.tif')
    egal(r.empilee, true)
    egal(r.active, true)
    egal(S.fichiers[chemin], 'TIFF 16 bits de Fibo 2', "copiée dans le dossier de l'original")
    egal(S.fichiers[sortie], nil, "le fichier temporaire effacé")
    egal(#S.ajoutees, 1)
    local nouvelle = S.ajoutees[1]
    egal(r.id, nouvelle.localIdentifier)
    egal(nouvelle.brut.path, chemin)
    egal(nouvelle.empileeAvec, photo, "empilée avec l'original")
    egal(nouvelle.positionPile, 'above', "au-dessus de lui")
    egal(S.ecritures[1], "Claude · Fibo 2", "une écriture du catalogue")
    egal(S.active, nouvelle, "la nouvelle photo devient la photo active")
    egal(#S.selection, 1, "seule sélectionnée")
    -- Son journal dit ce que Fibo 2 a fait ; elle est « retouchée par Claude » ; aucune étape à défaire.
    local journal = journalDe(nouvelle)
    egal(#journal, 1)
    egal(journal[1].etape, "Claude · Fibo 2 : " .. CONSIGNE)
    egal(journal[1].raison, CONSIGNE)
    egal(journal[1].type, 'retouche')
    egal(journal[1].origine, 7)
    egal(nouvelle.proprietes.retoucheeParClaude, 'oui')
    egal(nouvelle.proprietes.proprietaireMemoire, nouvelle.brut.uuid, "la mémoire est la sienne")
    egal(nouvelle.proprietes.etapesClaude, nil, "pas d'étape : undo_last ne la retire pas")
    -- L'original n'est pas touché : ni réglage, ni mémoire.
    egal(Json.encode(photo.reglages), avant, "réglages de l'original inchangés")
    egal(photo.proprietes.journalClaude, nil, "journal de l'original inchangé")
    egal(A.contient(Liaison.journal, "Fibo 2 : « DSCF2402-Fibo.tif » importée, empilée au-dessus de « DSCF2402.RAF »"), true)
    egal(Liaison.journalPhotos[#Liaison.journalPhotos], nouvelle.localIdentifier, "la ligne sélectionne la nouvelle photo")
end)

test("importerGeneree : un nom déjà pris donne « -2 », puis « -3 » ; jamais d'écrasement", function()
    original()
    S.fichiers[DOSSIER .. '/DSCF2402-Fibo.tif'] = 'une photo de Dany'
    local r = importer()
    egal(r.fichier, 'DSCF2402-Fibo-2.tif')
    egal(S.fichiers[DOSSIER .. '/DSCF2402-Fibo.tif'], 'une photo de Dany', "le fichier déjà là n'est pas écrasé")
    r = importer({ chemin = sortieFibo('final-2.tif') })
    egal(r.fichier, 'DSCF2402-Fibo-3.tif')
    egal(#S.ajoutees, 2)
end)

test("importerGeneree : sans nom, celui de l'original suivi de « -Fibo » ; un nom proposé perd dossiers, extension et caractères refusés", function()
    original()
    egal(importer({ nom = false }).fichier, 'DSCF2402-Fibo.tif')
    local r = importer({ chemin = sortieFibo('b.tif'), nom = '../../Jupe:marine.tif' })
    egal(r.chemin:sub(1, #DOSSIER + 1), DOSSIER .. '/', "dans le dossier de l'original")
    egal(r.fichier:find('/', 1, true), nil)
    egal(r.fichier:find(':', 1, true), nil)
    egal(r.fichier, '-..-Jupe-marine.tif')
end)

test("importerGeneree : un chemin hors du dossier de Fibo, qui en sort par « .. », ou qui n'est pas un TIFF, est refusé ; rien n'est importé", function()
    original()
    local sortie = sortieFibo()
    S.fichiers['/Users/test/Images/autre.tif'] = 'tiff'
    S.fichiers[FIBO .. '/A1B2C3/sortie.png'] = 'png'
    echoue(function() importer({ chemin = '/Users/test/Images/autre.tif' }) end, "dossier de passage de Fibo 2")
    echoue(function() importer({ chemin = FIBO .. '/../../Temporaire/x.tif' }) end, "dossier de passage de Fibo 2")
    echoue(function() importer({ chemin = FIBO .. '/A1B2C3/../../../liaison.jeton' }) end, "dossier de passage de Fibo 2")
    echoue(function() importer({ chemin = FIBO .. '/A1B2C3//final.tif' }) end, "dossier de passage de Fibo 2")
    echoue(function() importer({ chemin = FIBO .. '/' }) end, "dossier de passage de Fibo 2")
    echoue(function() importer({ chemin = 'Temporaire/Fibo/A1B2C3/final.tif' }) end, "dossier de passage de Fibo 2")
    echoue(function() importer({ chemin = FIBO .. 'X/final.tif' }) end, "dossier de passage de Fibo 2")
    echoue(function() importer({ chemin = FIBO .. '/A1B2C3/sortie.png' }) end, "n'est pas un TIFF")
    echoue(function() importer({ chemin = FIBO .. '/A1B2C3/absent.tif' }) end, "Fichier de Fibo 2 introuvable")
    rienFait(sortie)
    egal(Livraison.dansFibo(sortie), true)
end)

test("importerGeneree : la pause de la liaison l'arrête ; rien n'est importé", function()
    original()
    local sortie = sortieFibo()
    Liaison.pause = true
    echoue(function() importer({ chemin = sortie }) end, "pause")
    rienFait(sortie)
end)

test("importerGeneree : mode « Proposer d'abord » : refusée sans confirm, faite avec", function()
    original()
    local sortie = sortieFibo()
    S.prefs.mode = 'proposer'
    echoue(function() importer({ chemin = sortie }) end, "rappeler generative_edit avec confirm = true")
    rienFait(sortie)
    egal(importer({ chemin = sortie, confirme = true }).fichier, 'DSCF2402-Fibo.tif')
end)

test("importerGeneree : accord dans Lightroom : demandé sans exportation vers Fibo ; celui de l'exportation vaut pour l'importation qui la suit, une fois", function()
    local photo = original()
    local sortie = sortieFibo()
    S.prefs.mode = 'proposer'
    S.prefs.accordDansLightroom = true
    -- Sans exportation de cette photo vers Fibo dans la séance : l'accord se demande, comme ailleurs.
    echoue(function() importer({ chemin = sortie, confirme = true }) end, "rappeler generative_edit avec confirm = true")
    egal(Liaison.propositionEnAttente and Liaison.propositionEnAttente.outil, 'generative_edit')
    rienFait(sortie)
    Liaison.propositionEnAttente = nil
    -- L'exportation vers un dossier neuf de Temporaire/Fibo (créé avec ses parents : le ménage vide
    -- Fibo au chargement), acceptée dans Lightroom ; l'importation suit sans second accord.
    S.fichiers[FIBO .. '/A1B2C3'], S.fichiers[FIBO] = nil, nil
    S.fichiers[sortie] = nil
    Liaison.repondreProposition(true)
    local export = Commandes.executer('exporter', { photos = { 7 }, dossier = FIBO .. '/D4E5F6', confirme = true,
        reglages = { format = 'TIFF', profondeur = 16, espace = 'AdobeRGB', metadonnees = 'all', sans_lieu = false } })
    egal(export.fichiers[1].chemin, FIBO .. '/D4E5F6/DSCF2402.tif')
    egal(S.dernierExport.exportSettings.LR_export_bitDepth, 16)
    egal(S.dernierExport.exportSettings.LR_export_colorSpace, 'AdobeRGB')
    egal(S.dernierExport.exportSettings.LR_removeLocationMetadata, false)
    egal(type(Livraison.exportsFibo[7]), 'number', "exportation notée pour la photo")
    S.horloge = S.horloge + 14 * 60
    sortie = sortieFibo()
    local r = importer({ chemin = sortie, confirme = true })
    egal(r.empilee, true)
    egal(Liaison.propositionEnAttente, nil, "pas de second accord")
    egal(Livraison.exportsFibo[7], nil, "l'accord ne vaut qu'une fois")
    -- Une deuxième importation sans nouvelle exportation redemande l'accord.
    echoue(function() importer({ chemin = sortieFibo('autre.tif'), confirme = true }) end, "rappeler generative_edit avec confirm = true")
    -- Un long appel (4 modifications, Fibo 2 puis SeedVR2) : l'accord vaut encore après 1 h 40.
    Livraison.exportsFibo[7] = S.horloge
    S.horloge = S.horloge + 100 * 60
    Liaison.propositionEnAttente = nil
    egal(importer({ chemin = sortieFibo('long.tif'), confirme = true }).empilee, true)
    egal(Liaison.propositionEnAttente, nil, "pas de second accord après un long calcul")
    -- Une exportation trop ancienne (plus de 3 h) ne vaut plus.
    Livraison.exportsFibo[7] = S.horloge
    S.horloge = S.horloge + 181 * 60
    Liaison.propositionEnAttente = nil
    echoue(function() importer({ chemin = sortieFibo('autre.tif'), confirme = true }) end, "rappeler generative_edit avec confirm = true")
    egal(photo.brut.isExported, true)
end)

test("exporter : un dossier de Temporaire/Fibo se crée avec ses parents ; un autre dossier sans parent reste refusé", function()
    original()
    local r = Commandes.executer('exporter', { photos = { 7 }, dossier = FIBO .. '/X1', reglages = { format = 'TIFF' } })
    egal(S.fichiers[FIBO .. '/X1'], 'dossier')
    egal(r.fichiers[1].chemin, FIBO .. '/X1/DSCF2402.tif')
    echoue(function() Commandes.executer('exporter', { photos = { 7 }, dossier = '/Volumes/Absent/Livraison', reglages = { format = 'TIFF' } }) end,
        "dossier parent")
    -- Un dossier « Fibo » qui sortirait par « .. » n'est pas créé.
    echoue(function() Commandes.executer('exporter', { photos = { 7 }, dossier = FIBO .. '/../../../Ailleurs/Y', reglages = { format = 'TIFF' } }) end,
        "dossier parent")
    egal(Livraison.exportsFibo[7] ~= nil, true, "l'exportation vers Fibo est notée")
end)

test("importerGeneree : original introuvable (disque débranché, dossier absent) : refusée avec la raison ; rien n'est importé", function()
    local photo = original()
    local sortie = sortieFibo()
    photo.absente = true
    echoue(function() importer({ chemin = sortie }) end, "original introuvable")
    rienFait(sortie)
    photo.absente = false
    S.fichiers[DOSSIER] = nil
    echoue(function() importer({ chemin = sortie }) end, "se range dans son dossier")
    rienFait(sortie)
end)

test("importerGeneree : depuis une copie virtuelle, dans le dossier de son original et empilée avec lui", function()
    local photo = original()
    local copie = S.copieVirtuelle(photo, 8, 'Essai Fibo')
    S.active, S.selection = copie, { copie }
    local r = importer({ photo = 8, nom = false })
    egal(r.chemin, DOSSIER .. '/DSCF2402-Fibo.tif')
    egal(S.ajoutees[1].empileeAvec, photo, "empilée avec l'original, pas la copie")
    egal(journalDe(S.ajoutees[1])[1].origine, 8, "le journal dit la photo d'où elle vient")
    egal(copie.proprietes.journalClaude, nil, "la copie n'est pas touchée")
    egal(S.active, S.ajoutees[1])
end)

test("importerGeneree : hors de la source affichée (une collection), son dossier s'affiche et elle devient la photo active", function()
    original()
    S.invisibles[S.prochainId + 1] = true
    local r = importer()
    egal(r.active, true)
    egal(S.active.localIdentifier, r.id)
    egal(#S.sourcesChangees > 0, true, "le dossier de l'original affiché")
end)

test("importerGeneree : Lightroom refuse le fichier : la copie va à la corbeille du Finder, rien au catalogue", function()
    local photo = original()
    local sortie = sortieFibo()
    S.ajoutImpossible = "format de fichier non pris en charge"
    echoue(function() importer({ chemin = sortie }) end, "format de fichier non pris en charge")
    egal(S.fichiers[DOSSIER .. '/DSCF2402-Fibo.tif'], nil, "la copie retirée du dossier de l'original")
    egal(S.corbeille[1], DOSSIER .. '/DSCF2402-Fibo.tif', "à la corbeille, récupérable")
    egal(#S.ajoutees, 0)
    egal(S.active, photo, "la photo active ne change pas")
end)

test("Simulation : addPhoto hors d'une écriture est refusé ; la photo ajoutée ne se lit pas dans l'écriture qui l'a créée", function()
    original()
    local chemin = sortieFibo()
    local cat = (import 'LrApplication').activeCatalog()
    echoue(function() cat:addPhoto(chemin, nil) end, "addPhoto hors de withWriteAccessDo")
    echoue(function()
        cat:withWriteAccessDo('essai', function()
            local photo = cat:addPhoto(chemin, S.photos[7], 'above')
            photo:getRawMetadata('uuid')
        end)
    end, "Can't get photo information")
    echoue(function() cat:withWriteAccessDo('essai', function() cat:addPhoto(chemin, S.photos[7], 'devant') end) end, "'above' ou 'below'")
end)

test("Ménage : Temporaire/Fibo s'efface au chargement du module", function()
    local trouve = false
    for _, nom in ipairs(Menage.TEMPORAIRES) do
        trouve = trouve or nom == 'Fibo'
    end
    egal(trouve, true)
    sortieFibo()
    egal(Menage.temporaires() >= 1, true)
    egal(S.fichiers[FIBO], nil)
    egal(S.fichiers[FIBO .. '/A1B2C3'], nil)
end)

test("Consignes de la fenêtre : generative_edit, seulement sur demande, après les corrections de base, consigne en anglais traduite, plusieurs changements, l'arrière-plan par mask, la couleur par un masque ; le texte sous 7 500", function()
    local texte = Consignes.texte
    egal(texte:find("generative_edit (Fibo 2, local), seulement sur sa demande", 1, true) ~= nil, true)
    egal(texte:find("puis les finitions sur la nouvelle photo, qui devient la photo active", 1, true) ~= nil, true)
    egal(texte:find("en anglais, sa traduction montrée à Dany (instruction_fr)", 1, true) ~= nil, true)
    egal(texte:find("plusieurs changements en un appel", 1, true) ~= nil, true)
    egal(texte:find("la couleur d'un objet se change dans Lightroom par un masque, pas par generative_edit", 1, true) ~= nil, true)
    egal(texte:find("l'arrière-plan, le ciel, une personne : mask (masque de Lightroom) plutôt que region", 1, true) ~= nil, true)
    local Texte = require 'Texte'
    egal(Texte.longueur(texte) <= 7500, true, "plafond des consignes : " .. Texte.longueur(texte))
    for _, mot in ipairs({ 'photoshop', 'firefly', 'agrandissement' }) do
        egal(texte:lower():find(mot, 1, true), nil, mot)
    end
end)

-- Une exportation de passage vers Temporaire/Fibo, comme la fait generative_edit.
local function exporterVersFibo(extra)
    local params = { photos = { 7 }, dossier = FIBO .. '/E1', etape = "Claude · Fibo 2", raison = CONSIGNE,
        reglages = { format = 'TIFF', profondeur = 16, espace = 'AdobeRGB', metadonnees = 'all', sans_lieu = false } }
    for cle, valeur in pairs(extra or {}) do
        params[cle] = valeur
    end
    return Commandes.executer('exporter', params)
end

test("exporter vers Fibo : l'accord dans Lightroom se demande au nom de generative_edit, avec l'étape et la consigne ; jamais export_photos", function()
    original()
    S.prefs.mode = 'proposer'
    S.prefs.accordDansLightroom = true
    Liaison.propositionEnAttente, Liaison.accord = nil, nil
    echoue(function() exporterVersFibo({ confirme = true }) end, "rappeler generative_edit avec confirm = true")
    local proposition = Liaison.propositionEnAttente
    egal(proposition and proposition.outil, 'generative_edit')
    egal(proposition and proposition.etape, "Claude · Fibo 2")
    egal(proposition and proposition.detail, CONSIGNE, "la fenêtre de la liaison dit ce que Fibo 2 changera")
    egal(S.dernierExport, nil, "rien n'est exporté avant l'accord")
    -- Sans confirm : le refus nomme generative_edit aussi.
    Liaison.propositionEnAttente = nil
    local ok, message = pcall(exporterVersFibo)
    egal(ok, false)
    egal(tostring(message):find("rappeler generative_edit avec confirm = true", 1, true) ~= nil, true, tostring(message))
    egal(tostring(message):find("export_photos", 1, true), nil, tostring(message))
    -- Accordé : l'exportation se fait, puis l'importation suit sans second accord.
    Liaison.repondreProposition(true)
    egal(exporterVersFibo({ confirme = true }).fichiers[1].chemin, FIBO .. '/E1/DSCF2402.tif')
    egal(type(Livraison.exportsFibo[7]), 'number', "l'accord vaudra pour l'importation")
    -- Une vraie livraison garde son nom d'outil.
    Liaison.propositionEnAttente = nil
    S.fichiers['/Users/test/Livraisons'] = 'dossier'
    echoue(function() Commandes.executer('exporter', { photos = { 7 }, dossier = '/Users/test/Livraisons', confirme = true,
        reglages = { format = 'JPEG' } }) end, "rappeler export_photos avec confirm = true")
    egal(Liaison.propositionEnAttente.outil, 'export_photos')
end)

test("exporter vers Fibo : ce n'est pas une livraison ; une photo jamais exportée reste « non exportée » (apercuSeulement), une photo livrée le reste", function()
    local Photos = require 'Photos'
    local photo = original()
    egal(Photos.exportee(photo), false)
    exporterVersFibo()
    egal(photo.brut.isExported, true, "Lightroom la croit exportée")
    egal(photo.proprietes.apercuSeulement, 'oui')
    egal(Photos.exportee(photo), false, "pas une livraison")
    -- Une photo déjà notée « aperçu seulement » le reste (une vraie livraison l'efface).
    exporterVersFibo({ dossier = FIBO .. '/E2' })
    egal(photo.proprietes.apercuSeulement, 'oui')
    egal(Photos.exportee(photo), false)
    -- Une photo déjà livrée pour de bon reste exportée.
    local livree = S.Photo(9, {}, { fileName = 'DSCF0009.RAF', fileFormat = 'RAW' }, { path = DOSSIER .. '/DSCF0009.RAF', isExported = true })
    S.fichiers[DOSSIER .. '/DSCF0009.RAF'] = 'raw'
    exporterVersFibo({ photos = { 9 }, dossier = FIBO .. '/E3' })
    egal(livree.proprietes.apercuSeulement, nil)
    egal(Photos.exportee(livree), true)
end)

test("Garde-fous des photos : copies virtuelles seulement, libellé protégé, rejetées : refusés à l'exportation vers Fibo et à l'importation", function()
    local photo = original()
    local sortie = sortieFibo()
    local function refusees(texte)
        echoue(function() exporterVersFibo() end, texte)
        egal(S.dernierExport, nil, "rien n'est exporté")
        echoue(function() importer({ chemin = sortie }) end, texte)
        rienFait(sortie)
    end
    S.prefs.copiesSeulement = true
    refusees("pas une copie virtuelle")
    S.prefs.copiesSeulement = false
    S.prefs.libelleProtege, photo.meta.label = 'rouge', 'Rouge'
    refusees("libellé rouge protégé")
    S.prefs.libelleProtege, photo.meta.label = 'aucun', nil
    S.prefs.rejeteesProtegees, photo.brut.pickStatus = true, -1
    refusees("photo rejetée, protégée")
end)

test("Copies virtuelles seulement : depuis une copie virtuelle, la nouvelle photo a sa copie virtuelle, qui devient la photo active", function()
    local photo = original()
    local copie = S.copieVirtuelle(photo, 8, 'Essai Fibo')
    S.active, S.selection = copie, { copie }
    S.prefs.copiesSeulement = true
    local r = importer({ photo = 8 })
    local nouvelle = S.ajoutees[1]
    egal(r.photo_fibo, nouvelle.localIdentifier)
    egal(r.copie_virtuelle, true)
    egal(r.id ~= nouvelle.localIdentifier, true, "l'id rendu est celui de la copie")
    egal(S.active.localIdentifier, r.id, "la copie est la photo active")
    egal(S.active.brut.isVirtualCopy, true)
    egal(S.active.brut.masterPhoto, nouvelle, "copie de la photo de Fibo 2")
    egal(r.active, true)
end)

test("Photo d'essai : la nouvelle photo va dans « Développeur › Essais », sans pile avec le vrai original ; la recette peut la retirer", function()
    local photo = original()
    local copie = S.copieVirtuelle(photo, 8, 'Essai')
    local essais = S.Collection('Essais', S.Ensemble('Développeur'))
    essais.membres[copie] = true
    S.active, S.selection = copie, { copie }
    local r = importer({ photo = 8 })
    local nouvelle = S.ajoutees[1]
    egal(r.empilee, false)
    egal(r.essai, true)
    egal(nouvelle.empileeAvec, nil, "pas empilée avec le vrai original")
    egal(essais.membres[nouvelle], true, "dans la collection Essais")
    egal(require('Carnet').estPhotoDEssai(nouvelle), true, "le Suivi et le carnet la voient comme une photo d'essai")
    egal(S.active, nouvelle)
    -- La recette la retire du catalogue par son chemin (retirerReimportees).
    local retrait = Commandes.executer('retirerReimportees', { chemins = { r.chemin } })
    egal(retrait.retires[1], r.chemin)
end)

test("essayer avec temoin (masque de Lightroom de generative_edit, carte d'add_mask) : aucun accord demandé, rien de gardé ; taille 0 rend en pleine résolution", function()
    local photo = A.photoFuji()
    S.active, S.selection = photo, { photo }
    S.prefs.mode = 'proposer'
    S.prefs.accordDansLightroom = true
    -- Un accord donné dans Lightroom (celui qu'attend l'exportation qui suit) n'est pas effacé.
    Liaison.repondreProposition(true)
    local accord = Liaison.accord
    local function masqueTemoin()
        return Json.tableau({ { type = 'ia', soustype = 0, categorie = 22, inverser = false, nom = 'Claude · masque pour Fibo 2', quantite = 1,
            locaux = { LocalExposure2012 = -0.5, LocalBlacks2012 = 0.3, LocalTemperature = -0.4 } } })
    end
    local r = Commandes.executer('essayer', { action = 'masquer', masques = masqueTemoin(), etape = 'masque pour Fibo 2',
        taille = 0, comparer = true, temoin = true, photo = 4 })
    egal(Liaison.propositionEnAttente, nil, "aucun accord demandé pour un rendu témoin")
    egal(Liaison.accord, accord, "l'accord donné reste")
    egal(r.chemin ~= nil and r.chemin_actuel ~= nil, true, "l'état actuel et le témoin")
    egal(#S.rendus, 2)
    for _, rendu in ipairs(S.rendus) do
        egal(rendu.exportSettings.LR_size_doConstrain, false, "taille 0 : pleine résolution, sans borne")
    end
    egal(S.rendus[2].reglagesRendus.MaskGroupBasedCorrections[1].CorrectionName, 'Claude · masque pour Fibo 2')
    egal(photo.reglages.MaskGroupBasedCorrections and #photo.reglages.MaskGroupBasedCorrections or 0, 0, "rien n'est gardé dans la photo")
    egal(photo.proprietes.journalClaude, nil, "rien au journal")
    -- Sans temoin, la proposition attend l'accord, comme avant.
    Commandes.executer('essayer', { action = 'masquer', masques = masqueTemoin(), etape = 'ciel', taille = 800, photo = 4 })
    egal(Liaison.propositionEnAttente and Liaison.propositionEnAttente.outil, 'add_mask', "une proposition ordinaire demande l'accord")
    egal(S.rendus[3].exportSettings.LR_size_doConstrain, true)
end)

test("essayer avec temoin : une personne précise que Lightroom n'a pas reconnue est dite (personnes_non_reconnues), rien de retiré ni de gardé", function()
    local photo = A.photoFuji()
    photo.personnes = { { Left = 0.2, Right = 0.38, Top = 0.28, Bottom = 1 }, { Left = 0.35, Right = 0.46, Top = 0.34, Bottom = 1 },
        { Left = 0.45, Right = 0.57, Top = 0.35, Bottom = 1 } }
    S.active, S.selection = photo, { photo }
    local cadres = Json.tableau({ { Left = 0.21, Right = 0.37, Top = 0.29, Bottom = 0.99 }, { Left = 0.36, Right = 0.45, Top = 0.33, Bottom = 0.98 },
        { Left = 0.46, Right = 0.56, Top = 0.36, Bottom = 0.99 } })
    local function temoin(lesCadres)
        return Json.tableau({ { type = 'personne', numero = 2, cadres = lesCadres, inverser = false, nom = 'Claude · masque pour Fibo 2',
            quantite = 1, locaux = { LocalExposure2012 = -0.5, LocalTemperature = -0.4 } } })
    end
    -- Un seul cadre : Lightroom ne reconnaît pas la personne (constaté le 18 octobre 2026).
    local r = Commandes.executer('essayer', { action = 'masquer', masques = temoin(Json.tableau({ cadres[2] })), etape = 'masque pour Fibo 2',
        taille = 0, comparer = true, temoin = true, photo = 4 })
    egal(type(r.personnes_non_reconnues), 'table', "la personne non reconnue est dite")
    egal(#r.personnes_non_reconnues, 1)
    egal(r.personnes_non_reconnues[1].numero, 2)
    egal(r.personnes_non_reconnues[1].trouvees, 1)
    egal(A.contient(r.remarques, "n'a pas reconnu la personne 2"), true)
    egal(photo.reglages.MaskGroupBasedCorrections and #photo.reglages.MaskGroupBasedCorrections or 0, 0, "rien n'est gardé dans la photo")
    -- Avec les cadres de toutes les personnes : reconnue, rien à dire.
    r = Commandes.executer('essayer', { action = 'masquer', masques = temoin(cadres), etape = 'masque pour Fibo 2',
        taille = 0, comparer = true, temoin = true, photo = 4 })
    egal(r.personnes_non_reconnues, nil)
    -- Sans temoin (une proposition ordinaire d'add_mask), rien n'est dit ici : add_mask le vérifie à l'écriture.
    r = Commandes.executer('essayer', { action = 'masquer', masques = temoin(Json.tableau({ cadres[2] })), etape = 'personne', taille = 800, photo = 4 })
    egal(r.personnes_non_reconnues, nil)
end)

A.bilan()
