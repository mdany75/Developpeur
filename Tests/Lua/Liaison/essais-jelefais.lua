-- essais-jelefais.lua : « Je le fais » côté liaison (1.3), hors de Lightroom (LuaJIT, Lightroom
-- simulé par Simulation.lua). L'exercice : la proposition de Claude rangée en instantané
-- « Claude · ma version » sans rien appliquer (essayer avec exercice et sans_rendu), son état de
-- départ et la version de Claude dans la mémoire de la variante (variantesClaude), l'entrée
-- 'exercice' du journal, l'état d'après Claude (apresClaude : le départ) ; la comparaison
-- (apercu, comparer = versionClaude) : la version de Claude rendue le temps d'un rendu, puis
-- l'état de Dany remis tel quel, les écarts réglage par réglage ; les refus ; choose_variant
-- « ma version » puis undo_last ; l'entrée du journal d'une variante choisie, avec ses
-- changements (relecture du lot 4) ; les fonctions pures d'Ecriture et de Variantes.
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, proche, echoue, contient = A.test, A.egal, A.proche, A.echoue, A.contient
local photoRaw, photoJpeg, photoFuji = A.photoRaw, A.photoJpeg, A.photoFuji

local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'
local Ecriture = require 'Ecriture'
local Reglages = require 'Reglages'
local Variantes = require 'Variantes'

-- Aides ------------------------------------------------------------------------------------------

-- La proposition de Claude, faite par Dany : comme preview_settings avec my_turn (lot 8).
local function jeLeFais(reglages, extra)
    local params = { action = 'appliquer', reglages = reglages, libelles = {}, instantane = 'ma version', exercice = true,
        sans_rendu = true, etape = 'ma version (je le fais)', raison = "Un peu sombre, couleurs ternes.", taille = 1344 }
    for cle, valeur in pairs(extra or {}) do
        params[cle] = valeur
    end
    return Commandes.executer('essayer', params)
end

-- Dany change des réglages à la main, dans le module Développement.
local function aLaMain(photo, reglages)
    S.ecritureEnCours = true
    photo:applyDevelopSettings(reglages)
    S.ecritureEnCours = false
end

local function comparer(extra)
    local params = { comparer = 'versionClaude', taille = 800, cles = {} }
    for cle, valeur in pairs(extra or {}) do
        params[cle] = valeur
    end
    return Commandes.executer('apercu', params)
end

local function memoire(photo, champ)
    local texte = photo:getPropertyForPlugin(nil, champ)
    return texte and Json.decode(texte) or nil
end

local function ecart(exercice, cle)
    for _, e in ipairs(exercice.ecarts) do
        if e.cle == cle then
            return e
        end
    end
    return nil
end

local function changement(changements, cle)
    for _, c in ipairs(changements or {}) do
        if c.cle == cle then
            return c
        end
    end
    return nil
end

local function sansMetatable(valeur, chemin)
    if type(valeur) ~= 'table' then
        return
    end
    if getmetatable(valeur) ~= nil then
        error("table avec métatable : " .. chemin, 2)
    end
    for cle, element in pairs(valeur) do
        sansMetatable(element, chemin .. '.' .. tostring(cle))
    end
end

local function instantaneNomme(photo, nom)
    for _, snap in ipairs(photo.snapshots) do
        if snap.name == nom then
            return snap
        end
    end
    return nil
end

-- Un masque fait à la main (dégradé linéaire : rien à calculer par Lightroom).
local function masqueDeDany(nom)
    return { What = 'Correction', CorrectionName = nom, CorrectionActive = true, LocalExposure2012 = -0.3,
        CorrectionMasks = { { What = 'Mask/Gradient', ZeroX = 0.5, ZeroY = 0, FullX = 0.5, FullY = 0.4 } } }
end

local function photoDEssai()
    local photo = photoRaw()
    photo.reglages.Clarity2012 = 0
    photo.reglages.ToneCurvePV2012 = { 0, 0, 255, 255 }
    S.active, S.selection = photo, { photo }
    return photo
end

-- Exercice rangé -----------------------------------------------------------------------------------

test("essayer avec exercice : version de Claude rangée en instantané, photo remise, aucun rendu, départ gardé", function()
    local photo = photoDEssai()
    local r = jeLeFais({ Exposure2012 = 0.35, Vibrance = 10 })
    egal(photo.reglages.Exposure2012, 0, "la photo revient comme avant")
    egal(photo.reglages.Vibrance, 0)
    egal(#S.rendus, 0, "sans_rendu : aucun rendu")
    egal(r.chemin, nil)
    egal(r.exercice.instantane, 'Claude · ma version')
    egal(r.instantane, 'Claude · ma version')
    egal(r.raw, true, "un RAW : le serveur dit la température en kelvins")
    egal(#photo.appliques, 2)
    egal(photo.appliques[1].nom, 'Claude · essai : ma version (je le fais)')
    egal(photo.appliques[2].nom, "Claude · fin de l'essai")
    local snap = instantaneNomme(photo, 'Claude · ma version')
    egal(snap ~= nil, true, "l'instantané « Claude · ma version »")
    proche(snap.reglages.Exposure2012, 0.35, "l'instantané porte la proposition")
    egal(snap.reglages.Vibrance, 10)
    egal(#photo.snapshots, 1, "aucun autre instantané (rien n'est appliqué : pas d'« Avant Claude »)")

    -- La mémoire de la variante : départ et version de Claude.
    local variantes = memoire(photo, 'variantesClaude')
    local ex = variantes['Claude · ma version'].exercice
    egal(ex.depart.Exposure2012, 0)
    egal(ex.depart.Vibrance, 0)
    egal(ex.depart.Temperature, 5200)
    proche(ex.claude.Exposure2012, 0.35)
    egal(ex.claude.Vibrance, 10)
    egal(type(ex.le), 'string')
    egal(contient(variantes['Claude · ma version'].cles, 'Exposure2012'), true)
    -- Relue par Variantes.exercice : des tables neuves, sans métatable (Lightroom bloque sinon).
    local relu = Variantes.exercice(photo)
    egal(#relu.depart.ToneCurvePV2012, 4, "la courbe de départ, gardée entière")
    sansMetatable(relu, 'exercice')
    egal(relu.instantane, 'Claude · ma version')
    proche(relu.claude.Exposure2012, 0.35)

    -- Le journal : une entrée 'exercice', la forme que lit la leçon (Lecon.correctionsNettes).
    local journal = memoire(photo, 'journalClaude')
    egal(#journal, 1)
    local entree = journal[1]
    egal(entree.type, 'exercice')
    egal(entree.etape, 'Claude · je le fais')
    egal(entree.raison, "Un peu sombre, couleurs ternes.")
    egal(entree.note:find("non appliquée", 1, true) ~= nil, true, "export_journal le dit")
    egal(entree.etape_id, nil, "pas une étape : rien à défaire")
    local c = changement(entree.changements, 'Exposure2012')
    egal(c.avant, 0)
    proche(c.apres, 0.35)
    egal(changement(entree.changements, 'Vibrance').apres, 10)
    -- Rien de ce qu'une étape écrit : pas d'étape, pas d'état d'avant Claude.
    egal(photo.proprietes.etapesClaude, nil, "aucune étape : undo_last n'a rien à défaire")
    egal(photo.proprietes.avantClaude, nil)

    -- L'état d'après Claude est le départ : juste après, aucune correction ; ensuite, exactement
    -- ce que Dany fait.
    egal(Commandes.executer('reglages', { cles = {} }).corrections_utilisateur, nil, "rien de changé depuis le départ")
    aLaMain(photo, { Exposure2012 = 0.8 })
    local corrections = Commandes.executer('reglages', { cles = {} }).corrections_utilisateur
    egal(corrections.etape, 'Claude · essai : ma version (je le fais)')
    egal(#corrections.changements, 1)
    egal(corrections.changements[1].cle, 'Exposure2012')
    egal(corrections.changements[1].claude, 0)
    proche(corrections.changements[1].maintenant, 0.8)

    -- Un JPEG : raw faux (température relative). Avec comparer aussi, rien n'est rendu.
    local jpeg = photoJpeg()
    S.active = jpeg
    local r2 = jeLeFais({ Exposure2012 = 0.2 }, { comparer = true })
    egal(r2.raw, false)
    egal(r2.chemin_actuel, nil)
    egal(#S.rendus, 0, "sans_rendu : pas même l'état actuel")
end)

test("version de Claude : le profil tel que Lightroom l'a rangé ; la Look qu'il retire, dans les écarts", function()
    local photo = photoFuji()
    photo.profils = { 'Camera CLASSIC CHROME', 'Camera Monochrome' }
    S.active, S.selection = photo, { photo }
    jeLeFais({}, { profil = 'camera classic chrome' })
    egal(photo.reglages.CameraProfile, 'Adobe Standard', "remise")
    egal(photo.reglages.Look.Name, 'Adobe Color')
    local ex = Variantes.exercice(photo)
    egal(ex.claude.CameraProfile, 'Camera CLASSIC CHROME', "le nom rangé par Lightroom, pas celui de la proposition")
    local r = comparer()
    egal(S.rendus[#S.rendus - 1].reglagesRendus.CameraProfile, 'Camera CLASSIC CHROME')
    local look = ecart(r.exercice, 'Look')
    egal(look.depart, 'Adobe Color')
    egal(look.claude, 'aucune', "Claude retire la Look avec le profil")
    egal(look.vous, 'Adobe Color')
    egal(ecart(r.exercice, 'CameraProfile').claude, 'Camera CLASSIC CHROME')
    egal(photo:getDevelopSettings().CameraProfile, 'Adobe Standard', "l'état de Dany remis")
end)

test("écarts : l'intensité du profil compte, celle de Claude comme celle de Dany (même Look)", function()
    -- Claude garde Adobe Color à 60 % : la liste a_faire le dit (« Adobe Color (60 %) »), la
    -- comparaison aussi.
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    jeLeFais({}, { profil_look = { nom = 'Adobe Color', intensite = 0.6, candidats = Json.tableau({
        { restriction = '', raw_seulement = false, look = { Name = 'Adobe Color', UUID = photo.reglages.Look.UUID, SupportsAmount = true,
            Parameters = { CameraProfile = 'Adobe Standard' } } } }) } })
    egal(photo.reglages.Look.Amount, 1, "remise")
    local r = comparer()
    proche(S.rendus[#S.rendus - 1].reglagesRendus.Look.Amount, 0.6, "la version de Claude, à 60 %")
    local look = ecart(r.exercice, 'Look')
    egal(look ~= nil, true, "une intensité changée est un écart, même profil")
    egal(look.depart, 'Adobe Color')
    egal(look.claude, 'Adobe Color (60 %)')
    egal(look.vous, 'Adobe Color', "Dany ne l'a pas fait")
    egal(r.exercice.rien_change, true)

    -- Dany ne change que l'intensité : un écart, et il a changé quelque chose.
    local autre = photoFuji()
    S.active, S.selection = autre, { autre }
    jeLeFais({ Vibrance = 15 })
    local sienne = Reglages.pourLightroom(autre.reglages.Look)
    sienne.Amount = 1.5
    aLaMain(autre, { Look = sienne })
    r = comparer()
    egal(S.rendus[#S.rendus - 1].reglagesRendus.Look.Amount, 1, "la version de Claude garde l'intensité de départ")
    look = ecart(r.exercice, 'Look')
    egal(look ~= nil, true)
    egal(look.claude, 'Adobe Color')
    egal(look.vous, 'Adobe Color (150 %)')
    egal(r.exercice.rien_change, false)
    egal(autre.reglages.Look.Amount, 1.5, "l'état de Dany remis")
end)

test("écarts d'un JPEG : la balance sous les noms que voit Claude (Temperature, Tint), comme a_faire", function()
    local photo = photoJpeg()
    photo.reglages.Shadows2012 = 0
    S.active, S.selection = photo, { photo }
    local r = jeLeFais({ Temperature = 12, Tint = -4 }, { plages = { Temperature = { -100, 100 }, Tint = { -100, 100 } } })
    egal(changement(r.changements, 'Temperature') ~= nil, true, "les changements (la liste a_faire) disent Temperature")
    aLaMain(photo, { IncrementalTemperature = 20, WhiteBalance = 'Custom', Shadows2012 = 15 })
    local ex = comparer().exercice
    local temperature = ecart(ex, 'Temperature')
    egal(temperature ~= nil, true, "Temperature, pas IncrementalTemperature")
    egal(temperature.claude, 12)
    egal(temperature.vous, 20)
    egal(ecart(ex, 'Tint').claude, -4)
    egal(ecart(ex, 'Tint').vous, 0, "Dany ne l'a pas fait")
    egal(ecart(ex, 'IncrementalTemperature'), nil)
    egal(ecart(ex, 'IncrementalTint'), nil)
    egal(ecart(ex, 'Shadows2012').vous, 15)
    -- Triés par le nom que voit Claude (Shadows2012 avant Temperature et Tint).
    for i = 2, #ex.ecarts do
        egal(ex.ecarts[i - 1].cle < ex.ecarts[i].cle, true, "écarts triés")
    end
end)

test("comparaison : une mémoire d'exercice sans réglage est refusée avec sa raison", function()
    local photo = photoDEssai()
    photo.proprietes.variantesClaude = Json.encode({ ['Claude · ma version'] = { cles = Json.tableau(), le = '',
        exercice = { depart = Variantes.departExercice(photo:getDevelopSettings()), claude = {}, le = '' } } })
    egal(Variantes.exercice(photo) ~= nil, true)
    echoue(function() comparer() end, "ne change aucun réglage")
    egal(#photo.appliques, 0)
end)

test("essayer sans exercice : rien de l'exercice (ni état d'après Claude, ni entrée au journal)", function()
    local photo = photoDEssai()
    local r = Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.5 }, libelles = {},
        etape = 'plus clair', taille = 800 })
    egal(r.exercice, nil)
    egal(r.raw, nil)
    egal(#S.rendus, 1, "une proposition ordinaire est rendue")
    egal(photo.proprietes.apresClaude, nil, "noterEtatFinal : seulement pour un exercice")
    egal(photo.proprietes.journalClaude, nil)
    -- Une variante (compare_variants) non plus : la mémoire de la variante, sans exercice.
    Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.5 }, libelles = {},
        etape = 'variante claire', instantane = 'claire', taille = 800 })
    egal(memoire(photo, 'variantesClaude')['Claude · claire'].exercice, nil)
    egal(photo.proprietes.journalClaude, nil)
    egal(Variantes.exercice(photo), nil)
end)

test("version de Claude : relue après l'application (un paramètre prédéfini de l'utilisateur compte)", function()
    local photo = photoDEssai()
    S.presets = { { nom = 'Mes réglages', presets = { { nom = 'Chaud', uuid = 'U1', reglages = { Exposure2012 = 1, Vibrance = 40 } } } } }
    jeLeFais({ Clarity2012 = 10 }, { preset = 'Chaud' })
    egal(photo.reglages.Exposure2012, 0, "remise")
    local ex = Variantes.exercice(photo)
    egal(ex.claude.Exposure2012, 1, "la valeur que le paramètre prédéfini a posée, absente des nouvelles valeurs du plan")
    egal(ex.claude.Vibrance, 40)
    egal(ex.claude.Clarity2012, 10)
    local r = comparer()
    local claude = S.rendus[#S.rendus - 1].reglagesRendus
    egal(claude.Exposure2012, 1, "la comparaison rend la version de Claude entière")
    egal(claude.Vibrance, 40)
    egal(ecart(r.exercice, 'Exposure2012').claude, 1)
    egal(ecart(r.exercice, 'Exposure2012').vous, 0)

    -- Une valeur automatique pas encore calculée (−999999) n'est pas une valeur de Claude.
    local autre = photoFuji()
    S.active, S.selection = autre, { autre }
    S.presets[1].presets[2] = { nom = 'Auto', uuid = 'U2', reglages = { Exposure2012 = Ecriture.EN_ATTENTE, Vibrance = 12 } }
    jeLeFais({}, { preset = 'Auto' })
    local auto = Variantes.exercice(autre)
    egal(auto.claude.Exposure2012, nil, "pas calculée : pas dans la version de Claude")
    egal(auto.claude.Vibrance, 12)
end)

test("version de Claude : une table que le départ ne garde pas (flou d'objectif) a sa valeur de départ", function()
    local photo = photoDEssai()
    jeLeFais({}, { flou_objectif = { intensite = 40 } })
    egal(photo.reglages.LensBlur.Active, false, "remise : le flou inactif")
    local ex = Variantes.exercice(photo)
    egal(ex.claude.LensBlur.Active, true, "la version de Claude, flou posé par un paramètre prédéfini du module")
    egal(ex.depart.LensBlur.Active, false, "son départ : la valeur d'avant de la proposition")
    local r = comparer()
    egal(S.rendus[#S.rendus - 1].reglagesRendus.LensBlur.Active, true)
    local flou = ecart(r.exercice, 'LensBlur')
    egal(flou.depart, 'inchangée')
    egal(flou.claude, 'changée')
    egal(flou.vous, 'inchangée', "Dany ne l'a pas fait")
    egal(photo.reglages.LensBlur.Active, false, "l'état de Dany remis")
end)

-- Comparaison ------------------------------------------------------------------------------------

test("comparaison : version de Claude rendue, puis l'état de Dany remis tel quel (masque compris) ; écarts", function()
    local photo = photoDEssai()
    jeLeFais({ Exposure2012 = 0.35 })
    -- Dany : plus d'exposition que Claude, de la clarté, et un masque.
    aLaMain(photo, { Exposure2012 = 0.8, Clarity2012 = 20, MaskGroupBasedCorrections = { masqueDeDany('Ciel') } })
    local deDany = photo:getDevelopSettings()
    local variantes, journal = photo.proprietes.variantesClaude, photo.proprietes.journalClaude
    local appliques = #photo.appliques

    local r = comparer()
    egal(#S.rendus, 2, "la version de Claude, puis l'état actuel")
    local claude = S.rendus[1].reglagesRendus
    proche(claude.Exposure2012, 0.35, "la version de Claude")
    egal(claude.Clarity2012, 0, "la clarté de départ : Claude n'y touchait pas")
    egal(#claude.MaskGroupBasedCorrections, 0, "le départ n'avait aucun masque : celui de Dany retiré le temps du rendu")
    proche(S.rendus[2].reglagesRendus.Exposure2012, 0.8, "puis l'état de Dany")
    egal(#S.rendus[2].reglagesRendus.MaskGroupBasedCorrections, 1)
    egal(Reglages.egal(photo:getDevelopSettings(), deDany), true, "la photo revient exactement à l'état de Dany")
    egal(photo.appliques[appliques + 1].nom, "Claude · comparaison (avant)")
    egal(photo.appliques[appliques + 2].nom, "Claude · comparaison (retour)")
    egal(r.chemin_avant ~= nil and r.chemin ~= nil, true)
    -- view_photo reste en lecture seule : ni la mémoire ni le journal ne changent.
    egal(photo.proprietes.variantesClaude, variantes)
    egal(photo.proprietes.journalClaude, journal)

    local ex = r.exercice
    egal(ex.instantane, 'Claude · ma version')
    egal(type(ex.le), 'string')
    local e = ecart(ex, 'Exposure2012')
    egal(e.depart, 0)
    proche(e.claude, 0.35)
    proche(e.vous, 0.8)
    e = ecart(ex, 'Clarity2012')
    egal(e.depart, 0)
    egal(e.claude, 0)
    egal(e.vous, 20)
    egal(ecart(ex, 'Vibrance'), nil, "un réglage que personne n'a changé n'est pas un écart")
    egal(ex.listes.masques.depart, 0)
    egal(ex.listes.masques.vous, 1)
    egal(ex.listes.taches.vous, 0)
    egal(ex.listes.yeux_rouges.vous, 0)
    egal(#ex.restent, 0)
    egal(ex.rien_change, false)
    -- La réponse passe en JSON : des tableaux, même vides.
    egal(Json.encode(ex.restent), '[]')
    egal(r.corrections_utilisateur ~= nil, true, "ce que Dany a fait depuis le départ")

    -- Dany n'a rien changé : rien_change, et la version de Claude seule.
    local autre = photoFuji()
    S.active, S.selection = autre, { autre }
    jeLeFais({ Vibrance = 15 })
    local rien = comparer().exercice
    egal(rien.rien_change, true)
    egal(#rien.ecarts, 1)
    egal(rien.ecarts[1].cle, 'Vibrance')
    egal(rien.ecarts[1].claude, 15)
    egal(rien.ecarts[1].vous, 0)
end)

test("comparaison : profil, Look, courbe et yeux rouges de Dany remis au départ ; masques ajoutés à un départ qui en avait : restent", function()
    local photo = photoFuji()
    photo.reglages.ToneCurvePV2012 = { 0, 0, 255, 255 }
    photo.reglages.MaskGroupBasedCorrections = { masqueDeDany('Premier') }
    S.active, S.selection = photo, { photo }
    jeLeFais({ Vibrance = 15 })
    aLaMain(photo, { CameraProfile = 'Camera Classic Chrome', Look = {}, ToneCurvePV2012 = { 0, 0, 128, 150, 255, 255 },
        MaskGroupBasedCorrections = { masqueDeDany('Premier'), masqueDeDany('Second') },
        RedEyeInfo = { { What = 'RedEye', X = 0.4, Y = 0.3 } } })
    local deDany = photo:getDevelopSettings()
    local r = comparer()
    local claude = S.rendus[#S.rendus - 1].reglagesRendus
    egal(claude.Vibrance, 15)
    egal(claude.CameraProfile, 'Adobe Standard', "le profil de départ")
    egal(claude.Look.Name, 'Adobe Color', "avec sa Look")
    egal(Reglages.egal(claude.ToneCurvePV2012, { 0, 0, 255, 255 }), true, "la courbe de départ")
    egal(#claude.RedEyeInfo, 0, "les yeux rouges ajoutés à une photo qui n'en avait pas : retirés le temps du rendu")
    egal(#claude.MaskGroupBasedCorrections, 2, "le départ avait un masque : celui de Dany reste dans les deux images")
    egal(Reglages.egal(photo:getDevelopSettings(), deDany), true, "l'état de Dany remis, profil et Look compris")
    local ex = r.exercice
    egal(ex.restent[1], 'MaskGroupBasedCorrections')
    egal(#ex.restent, 1)
    local look = ecart(ex, 'Look')
    egal(look.depart, 'Adobe Color')
    egal(look.claude, 'Adobe Color')
    egal(look.vous, 'aucune')
    local profil = ecart(ex, 'CameraProfile')
    egal(profil.depart, 'Adobe Standard')
    egal(profil.claude, 'Adobe Standard')
    egal(profil.vous, 'Camera Classic Chrome')
    local courbe = ecart(ex, 'ToneCurvePV2012')
    egal(courbe.depart, 'inchangée')
    egal(courbe.claude, 'inchangée')
    egal(courbe.vous, 'changée')
    egal(ex.listes.masques.depart, 1)
    egal(ex.listes.masques.vous, 2)
    egal(ex.listes.yeux_rouges.vous, 1)
end)

test("comparaison : taches de Dany retirées le temps du rendu, RetouchInfo remis au retour", function()
    local photo = photoDEssai()
    photo.reglages.RetouchInfo = { 'ancienne forme' }
    jeLeFais({ Exposure2012 = 0.3 })
    aLaMain(photo, { RetouchAreas = { { What = 'RetouchArea', Method = 'heal' } } })
    local deDany = photo:getDevelopSettings()
    comparer()
    local claude = S.rendus[#S.rendus - 1].reglagesRendus
    egal(#claude.RetouchAreas, 0, "la tache de Dany retirée (le départ n'en avait pas)")
    egal(#claude.RetouchInfo, 0, "liste vide : l'ancienne forme vidée aussi le temps du rendu")
    egal(Reglages.egal(photo:getDevelopSettings(), deDany), true, "RetouchInfo revient avec le reste")
    egal(photo.reglages.RetouchInfo[1], 'ancienne forme')
end)

-- Refus --------------------------------------------------------------------------------------------

test("refus : aucune version rangée, pause, photo protégée, rien à faire, instantané manquant", function()
    local photo = photoDEssai()
    echoue(function() comparer() end, "preview_settings avec my_turn = true la prépare")
    egal(#photo.appliques, 0, "rien d'écrit")

    -- Rien à faire : la proposition est l'état actuel.
    echoue(function() jeLeFais({ Exposure2012 = 0 }) end, "Rien à faire : la proposition est l'état actuel")
    egal(#photo.appliques, 0)
    egal(#photo.snapshots, 0)
    egal(photo.proprietes.variantesClaude, nil)
    egal(photo.proprietes.journalClaude, nil)

    -- Sans nom d'instantané.
    echoue(function()
        Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.3 }, exercice = true, sans_rendu = true,
            etape = 'x' })
    end, "le nom de l'instantané manque")
    egal(#photo.appliques, 0)

    -- Pause de la liaison : ni l'exercice, ni la comparaison (elle écrit le temps d'un rendu).
    Liaison.pause = true
    echoue(function() jeLeFais({ Exposure2012 = 0.3 }) end, "en pause")
    egal(#photo.appliques, 0)
    Liaison.pause = false
    jeLeFais({ Exposure2012 = 0.3 })
    Liaison.pause = true
    echoue(function() comparer() end, "en pause")
    Liaison.pause = false
    egal(#S.rendus, 0)

    -- Photo protégée (copies virtuelles seulement).
    local autre = photoJpeg()
    S.active = autre
    S.prefs.copiesSeulement = true
    echoue(function() jeLeFais({ Exposure2012 = 0.3 }) end, "Photos protégées")
    egal(#autre.appliques, 0)
    egal(#autre.snapshots, 0)
end)

-- Choisir « ma version » ----------------------------------------------------------------------------

test("choose_variant « ma version » : posée comme une étape ; undo_last rend à Dany ses réglages hors de la proposition", function()
    local photo = photoDEssai()
    jeLeFais({ Exposure2012 = 0.35, Vibrance = 10 })
    aLaMain(photo, { Exposure2012 = 0.8, Shadows2012 = 20, MaskGroupBasedCorrections = { masqueDeDany('Ciel') },
        RemoveAreas = { { What = 'RetouchArea', Masks = { { What = 'Mask/Ellipse' } } } }, ToneCurvePV2012 = { 0, 0, 128, 150, 255, 255 } })
    egal(#photo.reglages.RetouchAreas, 1, "Lightroom dérive RetouchAreas des taches de l'outil Supprimer")
    local choix = Commandes.executer('variantes', { action = 'choisir', nom = 'ma version', etape = 'ma version' })
    egal(#photo.reglages.ToneCurvePV2012, 4, "la courbe de départ")
    egal(S.modulesOuverts[1], 'develop', "posée photo affichée dans le module Développement")
    proche(photo.reglages.Exposure2012, 0.35, "la version de Claude")
    egal(photo.reglages.Vibrance, 10)
    egal(photo.reglages.Shadows2012, 0, "l'instantané garde le départ hors de la proposition")
    egal(#(photo.reglages.MaskGroupBasedCorrections or {}), 0)
    egal(changement(choix.changements, 'Shadows2012') ~= nil, true, "les réglages de Dany font partie de l'étape")
    egal(changement(choix.changements, 'MaskGroupBasedCorrections') ~= nil, true)
    -- L'entrée du journal porte ses changements (écrite avant la pose, réécrite après).
    local journal = memoire(photo, 'journalClaude')
    local entree = journal[#journal]
    egal(entree.type, 'retouche')
    egal(entree.etape, 'Claude · ma version')
    egal(entree.etape_id, choix.etape_id)
    egal(changement(entree.changements, 'Exposure2012') ~= nil, true, "export_journal et la leçon voient la variante choisie")
    egal(journal[1].type, 'exercice', "l'exercice reste au journal")

    local annule = Commandes.executer('annuler', {})
    egal(annule.resultats[1].annulee, true)
    proche(photo.reglages.Exposure2012, 0.8, "undo_last rend les valeurs de Dany")
    egal(photo.reglages.Shadows2012, 20, "y compris hors de la proposition")
    egal(photo.reglages.Vibrance, 0)
    egal(#photo.reglages.MaskGroupBasedCorrections, 1, "et son masque")
    egal(#photo.reglages.RemoveAreas, 1, "et ses taches de l'outil Supprimer, d'où Lightroom dérive RetouchAreas")
    egal(#photo.reglages.RetouchAreas, 1)
    egal(#photo.reglages.ToneCurvePV2012, 6, "et sa courbe")

    -- L'instantané reste effaçable ; effacé, l'exercice n'est plus là.
    local efface = Commandes.executer('variantes', { action = 'effacer', noms = { 'ma version' } })
    egal(efface.effaces[1], 'Claude · ma version')
    egal(instantaneNomme(photo, 'Claude · ma version'), nil)
    egal(Variantes.exercice(photo), nil)
    echoue(function() comparer() end, "Aucune version de Claude rangée")
end)

test("choose_variant : l'entrée du journal d'une variante porte ses changements ; une pose qui ne prend pas n'en laisse aucune", function()
    local photo = photoDEssai()
    Commandes.executer('essayer', { action = 'appliquer', reglages = { Temperature = 6200, Vibrance = 15 }, libelles = {},
        etape = 'variante chaude', instantane = 'chaude', taille = 800 })
    Commandes.executer('variantes', { action = 'choisir', nom = 'chaude', etape = 'variante chaude' })
    local entrees = Commandes.executer('journal', {}).photos[1].entrees
    local entree = entrees[#entrees]
    egal(entree.etape, 'Claude · variante chaude')
    local c = changement(entree.changements, 'Temperature')
    egal(c ~= nil, true, "Temperature au journal (il restait vide : la mémoire est écrite avant la pose)")
    egal(c.avant, 5200)
    egal(c.apres, 6200)
    egal(changement(entree.changements, 'Vibrance').apres, 15)

    -- L'instantané ne prend pas : ni étape, ni entrée au journal.
    local autre = photoJpeg()
    S.active, S.selection = autre, { autre }
    Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.4 }, libelles = {},
        etape = 'variante claire', instantane = 'claire', taille = 800 })
    S.instantaneBloque = true
    echoue(function() Commandes.executer('variantes', { action = 'choisir', nom = 'claire', etape = 'claire' }) end, "n'a pas posé")
    egal(#(memoire(autre, 'etapesClaude') or {}), 0)
    egal(#(memoire(autre, 'journalClaude') or {}), 0, "pas d'entrée pour une étape retirée")
end)

-- Avant/après des étapes ----------------------------------------------------------------------------

test("essayer (exercice) n'est pas une étape : aucune capture, même avec avant_apres", function()
    local photo = photoDEssai()
    Liaison.prise = { send = function(_, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    local ok, erreur = pcall(function()
        Liaison.recevoir(A.ligne({ id = 1, command = 'essayer', params = { action = 'appliquer', reglages = { Exposure2012 = 0.35 },
            libelles = {}, instantane = 'ma version', exercice = true, sans_rendu = true, etape = 'ma version', avant_apres = true } }))
        local reponse = Json.decode(S.envois[#S.envois])
        egal(reponse.result.exercice.instantane, 'Claude · ma version')
        egal(#S.rendus, 0, "aucun rendu : ni l'exercice, ni une capture")
        -- Témoin : une étape, elle, est capturée avec avant_apres.
        Liaison.recevoir(A.ligne({ id = 2, command = 'appliquer', params = { reglages = { Exposure2012 = 0.5 },
            plages = { Exposure2012 = { -5, 5 } }, confirme = true, etape = 'passe 1', avant_apres = true } }))
        egal(#S.rendus > 0, true, "appliquer est capturé")
        egal(photo.reglages.Exposure2012, 0.5)
    end)
    Liaison.prise, Liaison.reponsesConnectee = nil, false
    if not ok then
        error(erreur, 0)
    end
end)

-- Fonctions pures ----------------------------------------------------------------------------------

test("Ecriture.difference : clé absente de la référence, valeur en attente et null ignorées ; tables comparées", function()
    local d = Ecriture.difference(
        { Exposure2012 = 0, Vibrance = 10, Shadows2012 = Ecriture.EN_ATTENTE, Texture = Json.null, Look = { Name = 'A' },
            Clarity2012 = 5, Dehaze = 1 },
        { Exposure2012 = 0.5, Vibrance = 10, Shadows2012 = 20, Texture = 3, Look = { Name = 'B' }, Clarity2012 = Ecriture.EN_ATTENTE,
            Contrast2012 = 9 })
    egal(#d, 3)
    egal(d[1].cle, 'Dehaze')
    egal(d[1].avant, 1)
    egal(d[1].maintenant, Json.null, "une clé disparue : null")
    egal(d[2].cle, 'Exposure2012')
    egal(d[2].avant, 0)
    egal(d[2].maintenant, 0.5)
    egal(d[3].cle, 'Look')
    egal(d[3].maintenant.Name, 'B')
    egal(Json.encode(Ecriture.difference({ A = 1 }, { A = 1 })), '[]', "un tableau JSON, même vide")
    -- etatSimple exporté : nombres, booléens, textes suivis, nom de la Look, nombre des listes.
    local etat = Ecriture.etatSimple({ Exposure2012 = 0.2, CameraProfile = 'Adobe Standard', LensProfileName = 'X',
        Look = { Name = 'Adobe Color' }, MaskGroupBasedCorrections = { {}, {} }, UprightTransform_0 = 1 })
    egal(etat.Exposure2012, 0.2)
    egal(etat.CameraProfile, 'Adobe Standard')
    egal(etat.LensProfileName, nil)
    egal(etat['Look.Name'], 'Adobe Color')
    egal(etat['#MaskGroupBasedCorrections'], 2)
    egal(etat['#RetouchAreas'], 0)
    egal(etat.UprightTransform_0, nil)
end)

test("Variantes.valeursClaude et ecartsExercice : fonctions pures", function()
    local base = { Exposure2012 = 0, Vibrance = 0, CameraProfile = 'Adobe Standard', Look = { Name = 'Adobe Color', Amount = 1 },
        PointColors = { 'a' }, LensBlur = { Active = false } }
    local depart = Variantes.departExercice(base)
    egal(depart['#RemoveAreas'], 0)
    egal(depart.PointColors[1], 'a')
    egal(depart.ToneCurvePV2012, nil, "pas de courbe au départ")
    -- Vibrance : un réglage de la proposition qu'elle ne change pas (mémorisé pour un paramètre
    -- prédéfini) ; ce n'est pas un écart.
    local ex = { depart = depart, claude = { Exposure2012 = 0.4, Vibrance = 0, LensBlur = { Active = true, BlurAmount = 50 } } }
    ex.depart.LensBlur = { Active = false }

    -- Dany n'a rien changé.
    local valeurs, restent = Variantes.valeursClaude(ex, base)
    egal(valeurs.Exposure2012, 0.4)
    egal(valeurs.LensBlur.Active, true)
    egal(valeurs.CameraProfile, nil, "rien à remettre")
    egal(valeurs.Look, nil)
    egal(valeurs.PointColors, nil)
    egal(#restent, 0)
    local ecarts, listes, rien = Variantes.ecartsExercice(ex, base)
    egal(rien, true)
    egal(#ecarts, 2)
    egal(ecarts[1].cle, 'Exposure2012')
    egal(ecarts[2].cle, 'LensBlur')
    egal(ecarts[2].claude, 'changée')
    egal(ecarts[2].vous, 'inchangée', "Dany ne l'a pas fait : oublié")
    egal(listes.masques.depart, 0)

    -- Dany : le flou autrement que Claude, une courbe, d'autres couleurs ponctuelles, des taches avec
    -- l'outil Supprimer, des traits d'affinage.
    local actuels = { Exposure2012 = 0, Vibrance = 0, CameraProfile = 'Adobe Standard', Look = { Name = 'Adobe Color', Amount = 1 },
        PointColors = {}, LensBlur = { Active = true, BlurAmount = 20 }, ToneCurvePV2012 = { 0, 10, 255, 255 },
        RemoveAreas = { { What = 'RetouchArea' } }, RetouchAreas = { { What = 'RetouchArea' } },
        DepthBasedCorrections = { { What = 'Trait' } } }
    valeurs, restent = Variantes.valeursClaude(ex, actuels)
    egal(Reglages.egal(valeurs.ToneCurvePV2012, Reglages.COURBE_LINEAIRE), true, "sans courbe au départ : linéaire")
    egal(valeurs.PointColors[1], 'a', "les couleurs ponctuelles de départ")
    egal(#valeurs.DepthBasedCorrections, 0, "traits ajoutés à une photo qui n'en avait pas : retirés")
    egal(valeurs.RetouchAreas, nil, "des taches de l'outil Supprimer : Lightroom dérive RetouchAreas, elles restent")
    egal(restent[1], 'RetouchAreas')
    egal(valeurs.LensBlur.BlurAmount, 50, "la version de Claude l'emporte sur ses propres réglages")
    sansMetatable(valeurs, 'valeurs')
    ecarts, listes, rien = Variantes.ecartsExercice(ex, actuels)
    egal(rien, false)
    local flou
    for _, e in ipairs(ecarts) do
        if e.cle == 'LensBlur' then flou = e end
    end
    egal(flou.vous, 'changée autrement')
    egal(listes.taches.vous, 1)
    for _, e in ipairs(ecarts) do
        egal(e.cle ~= 'DepthBasedCorrections' and e.cle ~= 'RetouchAreas' and e.cle ~= 'RemoveAreas', true, "les listes vont à part")
    end

    -- Une tache de l'outil Supprimer à détection d'objet : Lightroom ne la dérive pas dans
    -- RetouchAreas (nombre inchangé), mais elle compte : elle reste, et undo_last la rendrait.
    local objet = {}
    for cle, valeur in pairs(base) do objet[cle] = valeur end
    objet.RemoveAreas = { { What = 'RetouchArea', Masks = { { What = 'Mask/Image' } } } }
    valeurs, restent = Variantes.valeursClaude(ex, objet)
    egal(restent[1], 'RetouchAreas')
    egal(valeurs.RetouchAreas, nil)
    ecarts, listes, rien = Variantes.ecartsExercice(ex, objet)
    egal(rien, false)
    egal(listes.taches.vous, 0)

    -- Seulement un réglage simple que Claude ne touche pas : ce n'est pas « rien changé ».
    local vibrance = {}
    for cle, valeur in pairs(base) do vibrance[cle] = valeur end
    vibrance.Vibrance = 12
    ecarts, listes, rien = Variantes.ecartsExercice(ex, vibrance)
    egal(rien, false, "un réglage changé compte")
    egal(#ecarts, 3)
    egal(ecarts[3].cle, 'Vibrance')
    egal(ecarts[3].claude, 0)
    egal(ecarts[3].vous, 12)

    -- Seulement un masque de plus : ce n'est pas « rien changé ».
    local masque = {}
    for cle, valeur in pairs(base) do masque[cle] = valeur end
    masque.MaskGroupBasedCorrections = { { What = 'Correction' } }
    ecarts, listes, rien = Variantes.ecartsExercice(ex, masque)
    egal(rien, false, "un masque ajouté compte")
    egal(listes.masques.vous, 1)
    egal(#ecarts, 2, "les seuls écarts de Claude")

    -- Un nom que Lightroom résout lui-même (profil d'objectif) n'est pas un écart ; son interrupteur, si.
    local objectif = { depart = Variantes.departExercice({ LensProfileEnable = 0 }),
        claude = { LensProfileName = 'XF16-55mm', LensProfileEnable = 1 } }
    ecarts = Variantes.ecartsExercice(objectif, { LensProfileEnable = 0 })
    egal(#ecarts, 1)
    egal(ecarts[1].cle, 'LensProfileEnable')
    egal(ecarts[1].claude, 1)

    -- Une Look de même nom et de même intensité, mais autre (un autre profil du même nom) : pas
    -- « rien changé ».
    local autreLook = {}
    for cle, valeur in pairs(base) do autreLook[cle] = valeur end
    autreLook.Look = { Name = 'Adobe Color', Amount = 1, UUID = 'AUTRE' }
    ecarts, listes, rien = Variantes.ecartsExercice(ex, autreLook)
    egal(rien, false, "une Look changée compte")
end)

A.bilan()
