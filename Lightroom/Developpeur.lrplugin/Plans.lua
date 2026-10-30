-- Plans.lua : ce qu'une retouche changera sur une photo, préparé avant toute écriture :
-- réglages, profil, recadrage, balance des blancs, paramètres prédéfinis, masques, taches,
-- copie. Rien n'y écrit dans le catalogue : Ecriture.lua applique les plans.

local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'

local Geometrie = require 'Geometrie'
local Json = require 'Json'
local Locaux = require 'Locaux'
local Photos = require 'Photos'
local Recadrage = require 'Recadrage'
local Recalage = require 'Recalage'
local Reglages = require 'Reglages'

local dimensionsAffichees, meta = Photos.dimensionsAffichees, Photos.meta
local orientationAffichage = Photos.orientationAffichage
local afficher, arrondir, bornes = Reglages.afficher, Reglages.arrondir, Reglages.bornes
local cleReelle, CLES_CADRE = Reglages.cleReelle, Reglages.CLES_CADRE
local CLES_COURBES, clesBalance = Reglages.CLES_COURBES, Reglages.clesBalance
local COURBE_LINEAIRE, DEFAUTS, egal = Reglages.COURBE_LINEAIRE, Reglages.DEFAUTS, Reglages.egal
local estRaw, lookVide, memeProfil = Reglages.estRaw, Reglages.lookVide, Reglages.memeProfil
local minuscules, nomProfil, pluriel = Reglages.minuscules, Reglages.nomProfil, Reglages.pluriel
local pourLightroom, resume = Reglages.pourLightroom, Reglages.resume
local valeurActuelle, valeurNumerique = Reglages.valeurActuelle, Reglages.valeurNumerique
local contexteGeometrie = Recalage.contexteGeometrie
local empreinteGeometrie, geometrieActive = Recalage.empreinteGeometrie, Recalage.geometrieActive
local transformationActive, zoneImage = Recalage.transformationActive, Recalage.zoneImage

local Plans = {}

local function echouer(message)
    error(message, 0)
end

-- Ce que la tonalité automatique de Lightroom peut changer : mémorisé pour l'annuler.
local CLES_TONALITE_AUTO = {
    'Exposure2012', 'Contrast2012', 'Highlights2012', 'Shadows2012', 'Whites2012', 'Blacks2012',
    'Vibrance', 'Saturation', 'Texture', 'Clarity2012', 'Dehaze',
}

local function nouveauPlan(photo)
    local actuels = photo:getDevelopSettings()
    return {
        photo = photo,
        actuels = actuels,
        raw = estRaw(photo, actuels),
        nouveaux = {},
        avant = {},
        -- Paramètres prédéfinis appliqués avant les réglages (celui de l'utilisateur, les modes
        -- automatiques) et après (masques avec des masques IA, qui remplacent ceux de la photo).
        presets = {},
        presetsApres = {},
        changements = Json.tableau(),
        notes = Json.tableau(),
    }
end

-- horsEcriture : Lightroom a déjà fait le changement par sa propre commande (rotation, version de
-- processus) ; l'étape garde de quoi le défaire.
local function aDesChangements(plan)
    return next(plan.nouveaux) ~= nil or #plan.presets > 0 or #plan.presetsApres > 0 or plan.horsEcriture == true
end

local function noter(plan, texte)
    plan.notes[#plan.notes + 1] = texte
end

-- Note un réglage numérique à changer, avec sa valeur d'avant (pour annuler).
local function noterChangement(plan, actuels, reelle, cle, actuel, cible)
    if actuel == nil or math.abs(cible - actuel) > 1e-6 then
        plan.nouveaux[reelle] = cible
        if actuels[reelle] == nil then
            plan.avant[reelle] = actuel
        else
            plan.avant[reelle] = actuels[reelle]
        end
        plan.changements[#plan.changements + 1] = { cle = cle, avant = actuel or Json.null, apres = cible }
    end
end

-- Note une valeur rangée en table (courbe, masques, taches…) ; `vide` tient lieu de valeur
-- d'avant quand Lightroom n'en a pas. Renvoie faux si rien ne change.
local function noterTable(plan, cle, valeur, vide)
    local actuel = plan.actuels[cle]
    if actuel == nil then
        actuel = vide
    end
    if egal(actuel, valeur) then
        return false
    end
    plan.nouveaux[cle] = valeur
    if plan.avant[cle] == nil then
        plan.avant[cle] = pourLightroom(actuel)
    end
    plan.changements[#plan.changements + 1] = { cle = cle, avant = resume(cle, actuel), apres = resume(cle, valeur) }
    return true
end

-- Valeur d'avant d'un réglage que touche une opération globale (paramètre prédéfini, tonalité
-- automatique), si elle n'est pas déjà notée.
local function memoriser(plan, cle, vide)
    if plan.avant[cle] ~= nil then
        return
    end
    local actuel = plan.actuels[cle]
    if actuel ~= nil then
        plan.avant[cle] = pourLightroom(actuel)
    elseif DEFAUTS[cle] ~= nil then
        plan.avant[cle] = DEFAUTS[cle]
    elseif vide ~= nil then
        plan.avant[cle] = vide
    end
end

-- Paramètres prédéfinis du module : invisibles dans Lightroom, ils passent par applyDevelopPreset,
-- le chemin des paramètres prédéfinis d'Adobe. Posés par applyDevelopSettings, la tonalité
-- automatique, la balance des blancs automatique et les masques IA restent inertes (constaté dans
-- Lightroom Classic 15.6 : le mode est rangé, rien n'est calculé).
local presetsDuModule = {}

local function presetDuModule(nom, reglages)
    local ok, preset = LrTasks.pcall(LrApplication.addDevelopPresetForPlugin, _PLUGIN, nom, reglages)
    if not ok or not preset then
        echouer("Lightroom n'a pas créé le paramètre prédéfini « " .. nom .. " » : " .. tostring(preset or "raison inconnue"))
    end
    return preset
end

-- Paramètre prédéfini du module toujours identique (mode automatique) : créé une fois par session.
local function presetFixe(nom, reglages)
    if not presetsDuModule[nom] then
        presetsDuModule[nom] = presetDuModule(nom, reglages)
    end
    return presetsDuModule[nom]
end

-- Paramètre prédéfini du module dont le contenu varie (masques, flou d'objectif) : son nom porte
-- l'empreinte de son contenu. Lightroom range un fichier par nom ; le même contenu reprend donc le
-- même fichier au lieu d'en ajouter un (install.sh les efface quand Lightroom est fermé).
local function presetContenu(prefixe, reglages)
    return presetFixe(prefixe .. " " .. Locaux.empreinte(Json.encode(reglages)), reglages)
end

-- Un paramètre prédéfini du module sans balance des blancs (tonalité automatique, masques IA) fait
-- tomber une balance personnalisée aux butées, 2000 K et −150 (constaté dans Lightroom Classic
-- 15.6 ; ceux d'Adobe la gardent) : appliquerPlan la repose, et l'annulation la connaît.
local function noterPresetDuModule(plan)
    plan.presetDuModule = true
    if plan.actuels.WhiteBalance == 'Custom' then
        memoriser(plan, 'WhiteBalance')
        for _, cle in ipairs(clesBalance(plan.raw)) do
            memoriser(plan, cle)
        end
    end
end

-- Profil adaptatif (Adaptive Color, Adaptive B&W) : sa Look, marquée isAdobeAdaptive, son profil
-- de base et AILook actif passent par un paramètre prédéfini du module. Posé par
-- applyDevelopSettings, ou sans l'un des deux, Lightroom le range sans jamais le calculer (constaté
-- dans Lightroom Classic 15.6, voir docs/SPEC.md, Profil). AILook est mémorisé pour l'annulation.
local function poserAdaptatif(plan, reglages, nom)
    for cle, valeur in pairs(reglages) do
        memoriser(plan, cle, type(valeur) == 'table' and {} or nil)
    end
    memoriser(plan, 'AILook', {})
    plan.presets[#plan.presets + 1] = presetContenu("Claude · profil " .. nom, reglages)
    noterPresetDuModule(plan)
    plan.lookParPreset = true
end

-- Profil d'appareil : RAW seulement, et de la bonne marque. Une « Look » (Adobe Color…) posée
-- sur l'ancien profil est retirée ; l'annulation la remet telle quelle. ACROS et MONOCHROME
-- passent la photo en noir et blanc.
local function preparerProfil(plan, photo, params)
    local actuels, raw = plan.actuels, plan.raw
    local profil = tostring(params.profil)
    if not raw then
        noter(plan, string.format("Profil « %s » non appliqué : les profils d'appareil ne s'appliquent qu'aux fichiers RAW.", profil))
        return
    end
    local marque = params.profil_marque
    if type(marque) == 'string' then
        local fabricant = meta(photo, 'cameraMake') or ''
        if not fabricant:upper():find(marque:upper(), 1, true) then
            noter(plan, string.format("Profil « %s » non appliqué : il est réservé aux appareils %s (photo prise avec : %s).",
                profil, marque, fabricant ~= '' and fabricant or "appareil inconnu"))
            return
        end
    end
    -- Constaté en 2.4 : pour un X-T20, Lightroom range ETERNA et REALA ACE sous leur nom mais rend
    -- Adobe Standard ; le serveur donne ces modèles (profil_absent_sur) et le profil est refusé.
    if type(params.profil_absent_sur) == 'table' then
        local modele = tostring(meta(photo, 'cameraModel') or '')
        for _, absent in ipairs(params.profil_absent_sur) do
            if modele ~= '' and modele:upper() == tostring(absent):upper() then
                noter(plan, string.format("Profil « %s » non disponible pour cet appareil (%s %s) : Lightroom le range sous ce nom "
                    .. "mais le rend comme Adobe Standard. Profil d'avant gardé.", profil, meta(photo, 'cameraMake') or '', modele))
                return
            end
        end
    end
    -- Lightroom range « Camera Monochrome » pour « Camera MONOCHROME » (constaté, voir memeProfil).
    local gris = profil:upper():find('ACROS', 1, true) ~= nil or profil:upper():find('MONOCHROME', 1, true) ~= nil
    if memeProfil(actuels.CameraProfile, profil) and lookVide(actuels.Look) and (actuels.ConvertToGrayscale == true) == gris then
        return
    end
    plan.nouveaux.CameraProfile = profil
    plan.avant.CameraProfile = actuels.CameraProfile
    if not lookVide(actuels.Look) then
        plan.nouveaux.Look = {}
        plan.avant.Look = pourLightroom(actuels.Look)
    end
    if (actuels.ConvertToGrayscale == true) ~= gris then
        plan.nouveaux.ConvertToGrayscale = gris
        plan.avant.ConvertToGrayscale = actuels.ConvertToGrayscale == true
    end
    plan.changements[#plan.changements + 1] = { cle = 'CameraProfile', avant = nomProfil(actuels) or Json.null, apres = profil }
    -- Relu après l'écriture (verifierProfils) : sans Look ; les autres orthographes du nom, à
    -- essayer s'il n'est pas gardé, viennent du catalogue du serveur.
    plan.profilVoulu = { CameraProfile = profil, Look = false, nom = profil,
        variantes = type(params.profil_variantes) == 'table' and params.profil_variantes or nil }
end

-- « Fujifilm X-H2S » convient à FUJIFILM X-H2S (même règle que LookProfile.matches côté serveur).
local function restrictionConvient(restriction, marque, modele)
    local voulu = tostring(restriction or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if voulu == '' then
        return true
    end
    modele = tostring(modele or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if modele == '' then
        return false
    end
    local fabricant = tostring(marque or ''):lower():match('^(%S+)') or ''
    if voulu == modele then
        return true
    end
    local fin = ' ' .. modele
    return voulu:sub(-#fin) == fin and (fabricant == '' or voulu:sub(1, #fabricant) == fabricant)
end

-- Profil à base de Look : la Look du fichier de profil qui convient à l'appareil de la photo,
-- son profil de base et, pour un profil noir et blanc, le traitement noir et blanc.
local function preparerProfilLook(plan, photo, demande)
    local actuels, raw = plan.actuels, plan.raw
    local nom = tostring(demande.nom)
    local marque, modele = meta(photo, 'cameraMake'), meta(photo, 'cameraModel')
    local choisi
    for _, candidat in ipairs(type(demande.candidats) == 'table' and demande.candidats or {}) do
        if restrictionConvient(candidat.restriction, marque, modele) then
            choisi = candidat
            break
        end
    end
    if not choisi then
        noter(plan, string.format("Profil « %s » non disponible pour cet appareil (%s).", nom,
            table.concat({ marque or "marque inconnue", modele or "" }, ' ')))
        return
    end
    if choisi.raw_seulement and not raw then
        noter(plan, string.format("Profil « %s » non appliqué : il ne s'applique qu'aux fichiers RAW.", nom))
        return
    end
    local look = pourLightroom(choisi.look)
    if tonumber(demande.intensite) and look.SupportsAmount then
        look.Amount = tonumber(demande.intensite)
    end
    local parametres = type(look.Parameters) == 'table' and look.Parameters or {}
    if not lookVide(actuels.Look) and actuels.Look.UUID == look.UUID
        and math.abs((tonumber(actuels.Look.Amount) or 1) - (tonumber(look.Amount) or 1)) < 1e-6 then
        return
    end
    -- Profil adaptatif : la Look, son profil de base et ce qui les accompagne (par_preset, du
    -- serveur) passent par un paramètre prédéfini du module, que Lightroom calcule pour la photo
    -- (AILook) ; posé par applyDevelopSettings, il est rangé mais jamais calculé.
    local parPreset = type(choisi.par_preset) == 'table' and pourLightroom(choisi.par_preset) or nil
    local reglages = parPreset or plan.nouveaux
    reglages.Look = look
    plan.avant.Look = pourLightroom(actuels.Look) or {}
    local base = parametres.CameraProfile
    if parPreset then
        base, parPreset.CameraProfile = parPreset.CameraProfile, nil
    end
    if raw and type(base) == 'string' and not memeProfil(base, actuels.CameraProfile) then
        reglages.CameraProfile = base
        plan.avant.CameraProfile = actuels.CameraProfile
    end
    local gris = parametres.ConvertToGrayscale == true
    if (actuels.ConvertToGrayscale == true) ~= gris then
        reglages.ConvertToGrayscale = gris
        plan.avant.ConvertToGrayscale = actuels.ConvertToGrayscale == true
    end
    if parPreset then
        poserAdaptatif(plan, parPreset, nom)
    end
    local apres = tostring(look.Name)
    if look.SupportsAmount and math.abs((tonumber(look.Amount) or 1) - 1) > 1e-6 then
        apres = string.format('%s (%d %%)', apres, math.floor(look.Amount * 100 + 0.5))
    end
    plan.changements[#plan.changements + 1] = { cle = 'CameraProfile', avant = nomProfil(actuels) or Json.null, apres = apres }
    -- Relu après l'écriture (verifierProfils) : la Look, et le profil de base s'il change.
    plan.profilVoulu = { CameraProfile = reglages.CameraProfile, Look = tostring(look.Name), nom = apres,
        adaptatif = parPreset ~= nil }
end

-- « Contraindre le recadrage » (CropConstrainToWarp). Constaté dans Lightroom Classic 15.6 : posé à 1
-- par applyDevelopSettings, avec Upright ou après, Lightroom resserre aussitôt le cadre pour
-- qu'Upright, la perspective ou la distorsion manuelle n'y laissent aucun coin vide, et de nouveau
-- à chaque écriture du cadre ou de la géométrie tant que la case reste cochée ; un cadre qui ne
-- montre que la photo reste tel quel. Le module coche donc la case dès qu'une retouche touche la
-- géométrie ou le cadre d'une photo transformée, et mémorise le cadre : Lightroom le change sans
-- qu'on l'écrive (relireCadres le relit).
local function preparerContrainte(plan)
    -- Ce que la photo aura : ses réglages, ceux du paramètre prédéfini de l'utilisateur, puis ceux du plan.
    local final, touche = {}, false
    for _, source in ipairs({ plan.actuels, plan.balancePreset or {}, plan.nouveaux }) do
        for cle, valeur in pairs(source) do
            final[cle] = valeur
            if source ~= plan.actuels and (cle:match('^Crop') or cle:match('^Perspective') or cle:match('^Lens')) then
                touche = true
            end
        end
    end
    if not transformationActive(final) then
        return
    end
    if not touche then
        return
    end
    -- Sur une photo agrandie, Lightroom resserrerait le cadre dans l'image d'origine : la case
    -- reste telle quelle (l'agrandissement couvre déjà les bords).
    if Reglages.estAgrandie(plan.actuels) then
        noter(plan, "« Contraindre le recadrage » laissé tel quel : la photo est agrandie, le cadre se resserrerait dans l'image d'origine.")
        return
    end
    plan.cadreContraint = true
    for _, cle in ipairs(CLES_CADRE) do
        memoriser(plan, cle)
    end
    if valeurActuelle(final, 'CropConstrainToWarp') ~= 1 then
        noterChangement(plan, plan.actuels, 'CropConstrainToWarp', 'CropConstrainToWarp', valeurActuelle(plan.actuels, 'CropConstrainToWarp'), 1)
    end
end

local function preparerRecadrage(plan, photo, demande, params)
    if Reglages.estAgrandie(plan.actuels) then
        echouer("Photo agrandie (agrandissement génératif) : le recadrage de Claude la ramènerait dans l'image d'origine "
            .. "et perdrait l'agrandissement (constaté) ; rien n'a été écrit. Recadrer à la main dans Lightroom, ou "
            .. "recadrer l'original, celle d'avant l'agrandissement (souvent juste au-dessous dans la pile).")
    end
    local largeur, hauteur = dimensionsAffichees(photo)
    local orientation = orientationAffichage(photo, plan.raw, largeur, hauteur)
    local zone = not demande.retirer and zoneImage(photo, plan.actuels, params) or nil
    local cadre, remarque = Recadrage.calculer(demande, largeur, hauteur, orientation, zone)
    if remarque then
        noter(plan, remarque)
    end
    plan.demandeRecadrage = demande
    plan.recadrageDansZone = zone ~= nil
    if not demande.retirer then
        plan.ratioAttendu = tonumber(demande.ratio) or (largeur / hauteur)
    end
    for _, cle in ipairs(CLES_CADRE) do
        noterChangement(plan, plan.actuels, cle, cle, valeurActuelle(plan.actuels, cle), cadre[cle])
    end
end

local function preparerCourbes(plan, courbes)
    local change = false
    for _, cle in ipairs(CLES_COURBES) do
        if type(courbes[cle]) == 'table' then
            change = noterTable(plan, cle, pourLightroom(courbes[cle]), COURBE_LINEAIRE) or change
        end
    end
    if change and plan.actuels.ToneCurveName2012 ~= 'Custom' then
        plan.nouveaux.ToneCurveName2012 = 'Custom'
        plan.avant.ToneCurveName2012 = plan.actuels.ToneCurveName2012 or 'Linear'
    end
end

-- Préréglage de balance des blancs (Auto, Lumière du jour…) : la température et la teinte
-- d'avant sont mémorisées pour l'annulation.
local function preparerBalance(plan, balance)
    local actuels = plan.actuels
    balance = tostring(balance)
    if not plan.raw and balance ~= 'As Shot' and balance ~= 'Auto' then
        noter(plan, string.format("Balance des blancs « %s » non appliquée : un JPEG n'a que « Telle quelle » et « Auto ».", balance))
        return
    end
    if actuels.WhiteBalance == balance then
        return
    end
    plan.presets[#plan.presets + 1] = presetFixe("Claude · balance des blancs " .. balance, { WhiteBalance = balance })
    plan.balanceMode = balance
    plan.avant.WhiteBalance = actuels.WhiteBalance
    for _, cle in ipairs(clesBalance(plan.raw)) do
        memoriser(plan, cle)
    end
    plan.changements[#plan.changements + 1] = { cle = 'WhiteBalance', avant = actuels.WhiteBalance or Json.null, apres = balance }
end

local function noterTransformation(plan, ctx)
    if ctx.recalage then
        local ecart = Geometrie.ecart(ctx)
        if ecart >= 1 then
            noter(plan, string.format("Positions recalées sur la correction d'objectif et la perspective (déplacement jusqu'à %d px).",
                math.floor(ecart + 0.5)))
        end
    elseif geometrieActive(plan.actuels) then
        noter(plan, "Correction d'objectif, Upright ou perspective active, sans recalage : les positions peuvent être décalées, "
            .. "surtout près des bords ; vérifier avec view_photo et region.")
    end
end

-- Points d'un trait donné dans l'aperçu, ramenés dans le repère du fichier, avec son rayon rapporté
-- au grand côté du fichier (comme le pinceau des masques), et leur centre.
local function traitsFichier(ctx, traits, options)
    local grand = math.max(ctx.lf, ctx.hf)
    local liste, sx, sy, n = {}, 0, 0, 0
    for _, t in ipairs(type(traits) == 'table' and traits or {}) do
        local points = {}
        for _, p in ipairs(type(t.points) == 'table' and t.points or {}) do
            local x, y = Geometrie.point(ctx, tonumber(p[1]), tonumber(p[2]))
            points[#points + 1] = { x, y }
            sx, sy, n = sx + x, sy + y, n + 1
        end
        local rayon = Geometrie.pixels(ctx, tonumber(t.rayon) or 0.02) / grand
        local trait = { points = points, rayon = rayon, flux = tonumber(t.flux) or 1, durete = tonumber(t.durete) or 0 }
        if options then
            trait.dabs = Locaux.touches(points, rayon, ctx.lf, ctx.hf, { flux = trait.flux, durete = trait.durete, auto = options.auto })
        end
        liste[#liste + 1] = trait
    end
    if n == 0 then
        return liste, nil, nil
    end
    return liste, sx / n, sy / n
end

-- Flou d'objectif : par un paramètre prédéfini du module, comme les masques IA, pour que Lightroom
-- calcule la carte de profondeur. Le retirer = le désactiver (la table vide est ignorée). Les traits
-- du pinceau d'affinage (demande.affinage) se donnent dans l'aperçu : ctx les ramène dans le repère
-- du fichier. Pas de cadre de mise au point : constaté le 18 octobre 2026, Lightroom ne mesure la
-- profondeur d'un cadre (SampledRange) que dans son interface ; SampledArea et FocalRangeSource = 2
-- posés par un module restent sans mesure, et la zone passe en manuelle (FocalRangeSource = 3).
local function preparerFlou(plan, demande, ctx)
    local actuel = plan.actuels.LensBlur
    local avant = (type(actuel) == 'table' and next(actuel) ~= nil) and pourLightroom(actuel) or Locaux.flouInactif()
    plan.avant.LensBlur = avant
    local apres
    if demande.retirer then
        apres = pourLightroom(avant)
        apres.Active = false
        plan.nouveaux.LensBlur = apres
    else
        apres = Locaux.flouObjectif(demande, actuel)
        plan.presets[#plan.presets + 1] = presetContenu("Claude · flou d'objectif", { LensBlur = apres })
        noterPresetDuModule(plan)
    end
    local texte = resume('LensBlur', apres)
    if type(demande.bokeh) == 'table' and demande.bokeh.nom then
        texte = texte .. ", bokeh " .. tostring(demande.bokeh.nom)
    end
    plan.changements[#plan.changements + 1] = { cle = 'LensBlur', avant = resume('LensBlur', actuel), apres = texte }
    -- Pinceau d'affinage : une correction par groupe de traits, ajoutée à celles de la photo.
    if not demande.retirer and type(demande.affinage) == 'table' and #demande.affinage > 0 and ctx then
        local existantes = type(plan.actuels.DepthBasedCorrections) == 'table' and plan.actuels.DepthBasedCorrections or {}
        local liste = pourLightroom(existantes)
        for _, groupe in ipairs(demande.affinage) do
            local traits, cx, cy = traitsFichier(ctx, groupe.traits, {})
            if cx then
                liste[#liste + 1] = Locaux.affinageProfondeur(traits, groupe.mode == 'net', cx, cy)
            end
        end
        noterTable(plan, 'DepthBasedCorrections', liste, {})
        noterTransformation(plan, ctx)
    end
end

local function preparerTonaliteAuto(plan)
    plan.presets[#plan.presets + 1] = presetFixe("Claude · tonalité automatique", { AutoTone = true })
    noterPresetDuModule(plan)
    if plan.avant.AutoTone == nil then
        plan.avant.AutoTone = plan.actuels.AutoTone == true
    end
    for _, cle in ipairs(CLES_TONALITE_AUTO) do
        memoriser(plan, cle)
    end
    plan.changements[#plan.changements + 1] = { cle = 'AutoTone', avant = "non", apres = "oui" }
end

-- Paramètre prédéfini par son UUID, son nom ou « Dossier/Nom ».
local function trouverPreset(texte)
    texte = tostring(texte)
    local cible = minuscules(texte)
    local trouves = {}
    for _, dossier in ipairs(LrApplication.developPresetFolders()) do
        local nomDossier = dossier:getName()
        for _, preset in ipairs(dossier:getDevelopPresets()) do
            local nom = preset:getName()
            if preset:getUuid() == texte or minuscules(nom) == cible or minuscules(nomDossier .. '/' .. nom) == cible then
                trouves[#trouves + 1] = { preset = preset, dossier = nomDossier, nom = nom }
            end
        end
    end
    if #trouves == 0 then
        echouer("Paramètre prédéfini introuvable : « " .. texte .. " ». Voir list_presets.")
    end
    if #trouves > 1 then
        local dossiers = {}
        for _, trouve in ipairs(trouves) do
            dossiers[#dossiers + 1] = trouve.dossier
        end
        echouer("Plusieurs paramètres prédéfinis s'appellent « " .. texte .. " » (dossiers : " .. table.concat(dossiers, ", ")
            .. ") : préciser « Dossier/Nom ».")
    end
    return trouves[1]
end

-- quantite : la Quantité prédéfinie de Lightroom, en % (0 à 200, 100 par défaut). Relevé dans le
-- code de Lightroom Classic 15.6 (LrPhoto, SdkApplyDevelopPreset) : applyDevelopPreset(preset,
-- module, quantité, calculIA) ; la quantité, arrondie, est divisée par 100 et ignorée hors de 0 à 2.
local function preparerPreset(plan, texte, quantite)
    local trouve = trouverPreset(texte)
    local ok, reglages = LrTasks.pcall(trouve.preset.getSetting, trouve.preset)
    if not ok or type(reglages) ~= 'table' then
        echouer("Impossible de lire le paramètre prédéfini « " .. trouve.nom .. " ».")
    end
    table.insert(plan.presets, 1, trouve.preset)
    plan.balancePreset = reglages
    for cle, valeur in pairs(reglages) do
        memoriser(plan, cle, type(valeur) == 'table' and {} or nil)
    end
    if reglages.Look ~= nil then
        memoriser(plan, 'CameraProfile')
    end
    local apres = trouve.dossier .. " / " .. trouve.nom
    quantite = tonumber(quantite)
    if quantite and math.abs(quantite - 100) > 1e-6 then
        plan.presetUtilisateur = trouve.preset
        plan.quantitePreset = math.floor(math.min(math.max(quantite, 0), 200) + 0.5)
        apres = string.format("%s (%d %%)", apres, plan.quantitePreset)
    end
    plan.changements[#plan.changements + 1] = { cle = 'Preset', avant = "—", apres = apres }
end

-- Mélange noir et blanc automatique (bouton Auto du panneau Noir et blanc). Comme la tonalité
-- automatique, AutoGrayscaleMix posé par applyDevelopSettings serait rangé sans être calculé : il
-- passe par un paramètre prédéfini du module, après les réglages de la commande (le noir et blanc
-- qu'elle pose doit l'être avant). Seulement pour une photo en noir et blanc.
local CLES_MELANGE_NB = { 'GrayMixerRed', 'GrayMixerOrange', 'GrayMixerYellow', 'GrayMixerGreen', 'GrayMixerAqua',
    'GrayMixerBlue', 'GrayMixerPurple', 'GrayMixerMagenta' }

local function preparerMelangeAuto(plan)
    local gris = plan.nouveaux.ConvertToGrayscale
    if gris == nil then
        gris = plan.actuels.ConvertToGrayscale == true
    end
    if gris ~= true then
        noter(plan, "Mélange noir et blanc automatique non appliqué : la photo n'est pas en noir et blanc (ConvertToGrayscale = 1 dans la même retouche).")
        return
    end
    plan.presetsApres[#plan.presetsApres + 1] = presetFixe("Claude · mélange noir et blanc automatique", { AutoGrayscaleMix = true })
    noterPresetDuModule(plan)
    memoriser(plan, 'AutoGrayscaleMix', false)
    for _, cle in ipairs(CLES_MELANGE_NB) do
        memoriser(plan, cle, 0)
    end
    plan.changements[#plan.changements + 1] = { cle = 'AutoGrayscaleMix', avant = "non", apres = "oui" }
end

-- Profil d'objectif choisi (panneau Corrections de l'objectif › Profil). Relevé le 17 octobre 2026
-- dans Lightroom Classic 15.6, sur un profil choisi à la main : LensProfileSetup = 'Custom',
-- LensProfileName (le ProfileName du fichier .lcp), LensProfileFilename (le nom du fichier),
-- LensProfileIsEmbedded = false, et l'empreinte du profil (LensProfileDigest), que Lightroom calcule.
-- Par défaut : LensProfileSetup = 'LensDefaults' (profil de l'appareil ou celui que Lightroom trouve).
-- demande : {nom, fichier} ou {auto = true}.
-- applyDevelopSettings ne remet pas LensProfileSetup à 'LensDefaults' : il reste 'Custom' (constaté,
-- pour un retour au profil par défaut comme pour une annulation) ; un paramètre prédéfini du module
-- le pose, avec LensProfileEnable, comme ceux d'Adobe (« Adobe Vivid + Lens ») : sans lui, Lightroom
-- le met à 0.
local function presetObjectifParDefaut(actif)
    local enable = actif == false and 0 or 1
    return presetFixe("Claude · profil d'objectif par défaut" .. (enable == 0 and " (désactivé)" or ""),
        { LensProfileSetup = 'LensDefaults', LensProfileEnable = enable })
end

local CLES_PROFIL_OBJECTIF = { 'LensProfileEnable', 'LensProfileSetup', 'LensProfileName', 'LensProfileFilename',
    'LensProfileIsEmbedded', 'LensProfileDigest' }

local function preparerProfilObjectif(plan, demande)
    local actuels = plan.actuels
    local avantNom = actuels.LensProfileName or actuels.LensProfileSetup or Json.null
    if demande.auto then
        if actuels.LensProfileSetup == 'LensDefaults' and valeurActuelle(actuels, 'LensProfileEnable') == 1 then
            return
        end
        for _, cle in ipairs(CLES_PROFIL_OBJECTIF) do
            memoriser(plan, cle, cle == 'LensProfileEnable' and 0 or '')
        end
        plan.nouveaux.LensProfileEnable = 1
        plan.presetsApres[#plan.presetsApres + 1] = presetObjectifParDefaut()
        noterPresetDuModule(plan)
        plan.changements[#plan.changements + 1] = { cle = 'LensProfileName', avant = avantNom, apres = "par défaut" }
        return
    end
    -- Lightroom a souvent deux fichiers du même nom, pour les RAW et pour les autres formats.
    local nom, fichier = tostring(demande.nom or ''), tostring(demande.fichier or '')
    if plan.raw and type(demande.fichier_raw) == 'string' then
        fichier = demande.fichier_raw
    elseif not plan.raw and type(demande.fichier_non_raw) == 'string' then
        fichier = demande.fichier_non_raw
    end
    if actuels.LensProfileSetup == 'Custom' and actuels.LensProfileFilename == fichier and actuels.LensProfileName == nom
        and valeurActuelle(actuels, 'LensProfileEnable') == 1 then
        return
    end
    for _, cle in ipairs(CLES_PROFIL_OBJECTIF) do
        memoriser(plan, cle, cle == 'LensProfileEnable' and 0 or '')
    end
    plan.nouveaux.LensProfileSetup = 'Custom'
    plan.nouveaux.LensProfileName = nom
    plan.nouveaux.LensProfileFilename = fichier
    plan.nouveaux.LensProfileIsEmbedded = false
    plan.nouveaux.LensProfileEnable = 1
    plan.profilObjectifVoulu = { nom = nom, fichier = fichier }
    plan.changements[#plan.changements + 1] = { cle = 'LensProfileName', avant = avantNom, apres = nom }
end

-- Upright avec repères (mode « Avec repères » du panneau Transformation). Relevé le 17 octobre 2026
-- dans Lightroom Classic 15.6 sur des repères tracés à la main : PerspectiveUpright = 5,
-- UprightFourSegmentsCount = le nombre de repères (2 à 4), UprightFourSegments_0… = « x1,y1,x2,y2 »
-- (%0.9f, comme Lightroom les écrit), dans le repère du fichier entier, avant l'orientation (un repère
-- vertical d'une photo « DA » y devient horizontal) ; Lightroom calcule UprightTransform_5. Les
-- repères se donnent dans l'aperçu : Geometrie.lua les ramène dans le fichier, grille de recalage
-- comprise (l'aperçu peut montrer une transformation déjà posée). Constaté le 18 octobre : posés par
-- applyDevelopSettings ou par un paramètre prédéfini (même avec UprightVersion = 0), les repères
-- sont rangés sans que Lightroom calcule UprightTransform_5, ni au rendu, ni à l'ouverture de
-- l'outil ; le bouton « Mettre à jour » de la section Upright (ag.develop.
-- reanalyzeUprightImageSettings, qui vide les clés de getUprightTransformKeys, hors de portée d'un
-- module) la calcule d'après ces repères.
local function neuf(x)
    return (Locaux.decimal(x, 9))
end

local function preparerReperes(plan, ctx, reperes)
    local actuels = plan.actuels
    local ancien = math.floor(valeurActuelle(actuels, 'UprightFourSegmentsCount') or 0)
    memoriser(plan, 'PerspectiveUpright')
    memoriser(plan, 'UprightFourSegmentsCount', 0)
    local textes = {}
    for _, r in ipairs(reperes) do
        local x1, y1 = Geometrie.point(ctx, tonumber(r.x1), tonumber(r.y1))
        local x2, y2 = Geometrie.point(ctx, tonumber(r.x2), tonumber(r.y2))
        textes[#textes + 1] = table.concat({ neuf(x1), neuf(y1), neuf(x2), neuf(y2) }, ',')
    end
    for i = 0, math.max(ancien, #textes) - 1 do
        local cle = 'UprightFourSegments_' .. i
        memoriser(plan, cle, '')
        plan.nouveaux[cle] = textes[i + 1] or ''
    end
    plan.nouveaux.UprightFourSegmentsCount = #textes
    plan.nouveaux.PerspectiveUpright = 5
    noter(plan, "Repères posés, mais Lightroom ne calcule la transformation qu'au clic sur « Mettre à jour » (panneau Transformation, "
        .. "section Upright ; constaté : ni les réglages ni un paramètre prédéfini ne la font calculer) : le demander à l'utilisateur, "
        .. "la photo affichée dans le module Développement, puis vérifier avec view_photo.")
    plan.changements[#plan.changements + 1] = { cle = 'PerspectiveUpright', avant = valeurActuelle(actuels, 'PerspectiveUpright') or 0, apres = 5 }
    plan.changements[#plan.changements + 1] = { cle = 'UprightFourSegments', avant = pluriel(ancien, "repère", "repères"),
        apres = pluriel(#textes, "repère", "repères") }
    noterTransformation(plan, ctx)
end

-- Version de processus (demande : valeur, nom, noms des valeurs, anciennes). Relevé dans Lightroom
-- Classic 15.6 : ProcessVersion passé à applyDevelopSettings est écrit tel quel, sans la conversion
-- des curseurs que fait le module Développement ; elle ne compte pas pour les versions 3 à 6, qui
-- ont les mêmes clés (*2012). Les versions 1 et 2 (2003, 2010) restent à mettre à jour à la main :
-- aucun chemin d'un module ne convertit leurs curseurs (voir Conversions.lua).
local function preparerVersion(plan, demande)
    local actuelle = plan.actuels.ProcessVersion
    local noms = type(demande.noms) == 'table' and demande.noms or {}
    if actuelle == demande.valeur then
        return
    end
    for _, ancienne in ipairs(type(demande.anciennes) == 'table' and demande.anciennes or {}) do
        if actuelle == ancienne then
            noter(plan, string.format("Version de processus non changée : la photo est en %s, dont les réglages ne se convertissent pas par un module ; "
                .. "la mettre à jour à la main dans Lightroom (Paramètres › Mettre à jour vers la version de processus actuelle).", tostring(noms[actuelle] or actuelle)))
            return
        end
    end
    plan.nouveaux.ProcessVersion = demande.valeur
    plan.avant.ProcessVersion = actuelle
    plan.changements[#plan.changements + 1] = { cle = 'ProcessVersion', avant = noms[actuelle] or actuelle or Json.null,
        apres = noms[demande.valeur] or demande.valeur }
end

-- Traitement noir et blanc : Lightroom ne l'applique pas sous une Look couleur comme Adobe Color
-- (constaté : le traitement est rangé, le rendu reste en couleur). Comme son interface, on passe
-- alors à Adobe Monochrome, et inversement à Adobe Color en revenant à la couleur.
local function preparerTraitement(plan, looks)
    local gris = plan.nouveaux.ConvertToGrayscale
    if gris == nil or plan.nouveaux.Look ~= nil or plan.lookParPreset or type(looks) ~= 'table' or not plan.raw then
        return
    end
    local look = plan.actuels.Look
    if lookVide(look) then
        return
    end
    local lookGris = type(look.Parameters) == 'table' and look.Parameters.ConvertToGrayscale == true
    local remplacement
    if gris == true and not lookGris and look.SupportsMonochrome ~= true then
        remplacement = looks.monochrome
    elseif gris == false and lookGris then
        remplacement = looks.couleur
    end
    if type(remplacement) ~= 'table' then
        return
    end
    local nouvelle = pourLightroom(remplacement)
    plan.nouveaux.Look = nouvelle
    plan.avant.Look = pourLightroom(look)
    plan.changements[#plan.changements + 1] = { cle = 'CameraProfile', avant = nomProfil(plan.actuels) or Json.null, apres = tostring(nouvelle.Name) }
end

-- Mélangeur noir et blanc sous un profil d'appareil monochrome (ACROS, MONOCHROME de Fujifilm) :
-- constaté en 2.3 (Lightroom Classic 15.6, RAF de X-H2S), GrayMixerBlue −80 ne change rien sous
-- Camera ACROS (ciel à L* 79,0 avant et après) quand il assombrit le ciel sous Adobe Monochrome
-- (79 → 30) : le profil rend déjà du gris. Les valeurs sont rangées ; la remarque le dit.
local function noterMelangeSansEffet(plan, demandeAuto)
    local touche = demandeAuto == true
    for _, cle in ipairs(CLES_MELANGE_NB) do
        if plan.nouveaux[cle] ~= nil then
            touche = true
        end
    end
    if not touche then
        return
    end
    local profil = plan.nouveaux.CameraProfile or plan.actuels.CameraProfile
    local look = plan.nouveaux.Look
    if look == nil then
        look = plan.actuels.Look
    end
    if type(profil) ~= 'string' or not lookVide(look) then
        return
    end
    local majuscules = profil:upper()
    if majuscules:find('^CAMERA ') and (majuscules:find('ACROS', 1, true) or majuscules:find('MONOCHROME', 1, true)) then
        noter(plan, string.format("Mélangeur noir et blanc sans effet sous le profil « %s » : le profil rend déjà du gris "
            .. "(constaté). Pour assombrir un ciel ou éclaircir une peau, prendre un filtre du profil (ACROS+R Filter, "
            .. "+Ye, +G) ou Adobe Monochrome, puis le mélangeur.", profil))
    end
end

-- Retouche globale (commande « appliquer »).
local function preparer(photo, params, prefs)
    local plan = nouveauPlan(photo)
    local actuels, raw = plan.actuels, plan.raw
    local plages = type(params.plages) == 'table' and params.plages or {}
    local booleens = {}
    for _, cle in ipairs(type(params.booleens) == 'table' and params.booleens or {}) do
        booleens[cle] = true
    end

    -- Le paramètre prédéfini d'abord : les autres réglages de la commande passent par-dessus.
    if params.preset then
        preparerPreset(plan, params.preset, params.quantite_preset)
    end
    -- Positions données dans l'aperçu (repères d'Upright, cadre et pinceau du flou d'objectif).
    local flou = type(params.flou_objectif) == 'table' and params.flou_objectif or {}
    local ctx
    if type(params.reperes) == 'table' or type(flou.affinage) == 'table' then
        ctx = contexteGeometrie(photo, plan, params)
    end
    -- Instantané demandé (panneau Instantanés), pris avant la retouche ; un aussi avant une mise à
    -- jour de la version de processus, comme le conseille Adobe.
    if type(params.instantane_avant) == 'string' and params.instantane_avant ~= '' then
        plan.instantane = params.instantane_avant
    end
    if type(params.version_processus) == 'table' then
        preparerVersion(plan, params.version_processus)
    end

    local cles = {}
    for cle in pairs(type(params.reglages) == 'table' and params.reglages or {}) do
        cles[#cles + 1] = cle
    end
    table.sort(cles)

    for _, cle in ipairs(cles) do
        local demande = tonumber(params.reglages[cle])
        if demande == nil then
            echouer("Valeur invalide pour " .. cle .. " : un nombre est attendu.")
        end
        local reelle = cleReelle(cle, raw)
        local actuel = valeurActuelle(actuels, reelle)
        local base = actuel or 0
        local cible = params.relatif and (base + demande) or demande

        local mini, maxi = bornes(cle, plages, raw)
        local bornee = math.min(math.max(cible, mini), maxi)
        if bornee ~= cible then
            noter(plan, string.format("%s : %s ramené à %s (plage %s à %s pour cette photo).",
                cle, afficher(cible), afficher(bornee), afficher(mini), afficher(maxi)))
            cible = bornee
        end

        if cle == 'Exposure2012' then
            local ecart = tonumber(prefs.variationExpositionMax) or 2
            if math.abs(cible - base) > ecart then
                local limitee = cible > base and base + ecart or base - ecart
                noter(plan, string.format("Exposure2012 : variation limitée à ±%s IL par retouche (réglage du module) ; %s au lieu de %s.",
                    afficher(ecart), afficher(limitee), afficher(cible)))
                cible = limitee
            end
        elseif cle == 'Saturation' then
            local maximum = tonumber(prefs.saturationMax) or 30
            if math.abs(cible) > maximum then
                local limitee = cible > 0 and maximum or -maximum
                noter(plan, string.format("Saturation : limitée à ±%s (réglage du module) ; %s au lieu de %s.",
                    afficher(maximum), afficher(limitee), afficher(cible)))
                cible = limitee
            end
        end

        cible = arrondir(cle, cible)
        noterChangement(plan, actuels, reelle, cle, actuel, cible)
        if booleens[cle] and plan.nouveaux[reelle] ~= nil then
            plan.nouveaux[reelle] = cible ~= 0
        end
    end

    if params.profil then
        preparerProfil(plan, photo, params)
    elseif type(params.profil_look) == 'table' then
        preparerProfilLook(plan, photo, params.profil_look)
    end
    preparerTraitement(plan, params.looks_traitement)
    if type(params.recadrage) == 'table' then
        preparerRecadrage(plan, photo, params.recadrage, params)
    end
    if type(params.courbes) == 'table' then
        preparerCourbes(plan, params.courbes)
    end
    if type(params.couleurs_ponctuelles) == 'table' then
        noterTable(plan, 'PointColors', pourLightroom(params.couleurs_ponctuelles), {})
    end
    if params.balance then
        preparerBalance(plan, params.balance)
    end
    if params.auto_ton then
        preparerTonaliteAuto(plan)
    end
    if type(params.flou_objectif) == 'table' then
        preparerFlou(plan, params.flou_objectif, ctx)
    end
    if type(params.profil_objectif) == 'table' then
        preparerProfilObjectif(plan, params.profil_objectif)
    end
    if type(params.reperes) == 'table' and #params.reperes > 0 then
        preparerReperes(plan, ctx, params.reperes)
    end
    if params.melange_nb_auto then
        preparerMelangeAuto(plan)
    end
    noterMelangeSansEffet(plan, params.melange_nb_auto)
    if plan.nouveaux.ProcessVersion ~= nil and not plan.instantane then
        plan.instantane = "avant version de processus"
    end

    -- Une température ou une teinte imposée fait passer la balance des blancs en « Personnalisée ».
    local balance = plan.nouveaux.Temperature or plan.nouveaux.Tint
        or plan.nouveaux.IncrementalTemperature or plan.nouveaux.IncrementalTint
    if balance and actuels.WhiteBalance ~= 'Custom' then
        plan.nouveaux.WhiteBalance = 'Custom'
        if plan.avant.WhiteBalance == nil then
            plan.avant.WhiteBalance = actuels.WhiteBalance
        end
    end
    preparerContrainte(plan)
    return plan
end

-- Après l'écriture d'un plan : un cadre demandé reste-t-il à calculer sur la géométrie obtenue ?
-- Oui si Upright, la perspective ou la distorsion manuelle sont actifs et qu'il n'a pas eu de grille
-- pour elle (la même retouche les pose ou les change) : Lightroom l'a resserré (« Contraindre le
-- recadrage »), quitte à le déplacer, et la commande recadrer le place au centre et à la taille
-- demandés. Un recadrage retiré reste retiré.
local function cadreARecadrer(plan)
    local demande = plan.demandeRecadrage
    if not demande or demande.retirer then
        return false
    end
    local apres = plan.photo:getDevelopSettings()
    if not transformationActive(apres) then
        return false
    end
    return not plan.recadrageDansZone or empreinteGeometrie(plan.photo, plan.actuels) ~= empreinteGeometrie(plan.photo, apres)
end

-- Masques posés par un paramètre prédéfini du module, seul chemin où Lightroom calcule les masques
-- IA. Il remplace tous les masques de la photo par les siens (constaté dans Lightroom Classic
-- 15.6) : il porte donc la liste entière.
local function masquesParPreset(plan, preset)
    plan.nouveaux.MaskGroupBasedCorrections = nil
    plan.presetsApres[#plan.presetsApres + 1] = preset
    noterPresetDuModule(plan)
end

local function presetMasques(nom, liste)
    return presetContenu(nom, { MaskGroupBasedCorrections = liste })
end

-- Cadres des personnes (de Vision, dans l'aperçu) ramenés dans le repère du fichier, ou nil.
local function bornesPersonnes(ctx, cadres)
    if type(cadres) ~= 'table' or #cadres == 0 then
        return nil
    end
    local function borne(v)
        return math.floor(math.min(math.max(v, 0), 1) * 1000000 + 0.5) / 1000000
    end
    local bornes = {}
    for _, c in ipairs(cadres) do
        local x1, y1 = Geometrie.point(ctx, tonumber(c.Left) or 0, tonumber(c.Top) or 0)
        local x2, y2 = Geometrie.point(ctx, tonumber(c.Right) or 1, tonumber(c.Bottom) or 1)
        bornes[#bornes + 1] = { Left = borne(math.min(x1, x2)), Top = borne(math.min(y1, y2)),
            Right = borne(math.max(x1, x2)), Bottom = borne(math.max(y1, y2)) }
    end
    return bornes
end

-- Un composant de masque (IA, dégradé, plage de luminance), positions ramenées dans le repère du
-- fichier. Renvoie aussi s'il est calculé par IA et s'il a une position.
local function composant(ctx, m, nom)
    if m.type == 'ia' then
        return Locaux.masqueIA(tonumber(m.soustype), tonumber(m.categorie), nom, m.inverser == true), true, false
    elseif m.type == 'personne' then
        -- Une personne précise (ou l'une de ses parties) : son numéro dans les cadres de toutes les
        -- personnes (InstanceBounds), sans lesquels Lightroom ne la reconnaît pas (constaté le
        -- 18 octobre 2026 ; le serveur les tire de Vision) ; cadres et point ramenés de l'aperçu
        -- dans le fichier. La personne seule d'une photo (`seule`, Vision n'en trouve qu'une) n'a
        -- ni numéro ni cadres, comme faite à la main (constaté le 20 octobre 2026).
        local x, y
        if tonumber(m.x) and tonumber(m.y) then
            x, y = Geometrie.point(ctx, tonumber(m.x), tonumber(m.y))
        end
        local seule = m.seule == true
        local masque = Locaux.personne(tonumber(m.numero) or 1, tonumber(m.categorie), x, y, nom, m.inverser == true, seule)
        if not seule then
            masque.InstanceBounds = bornesPersonnes(ctx, m.cadres)
        end
        return masque, true, true
    elseif m.type == 'lineaire' then
        local fx, fy = Geometrie.point(ctx, tonumber(m.de_x), tonumber(m.de_y))
        local zx, zy = Geometrie.point(ctx, tonumber(m.a_x), tonumber(m.a_y))
        return Locaux.lineaire(zx, zy, fx, fy, nom, m.inverser == true), false, true
    elseif m.type == 'radial' then
        local cx, cy = Geometrie.point(ctx, tonumber(m.centre_x), tonumber(m.centre_y))
        local largeur, hauteur = Geometrie.apercu(ctx)
        local rx = tonumber(m.rayon_x) * largeur
        local ry = tonumber(m.rayon_y) and tonumber(m.rayon_y) * hauteur or rx
        local ex, ey = Geometrie.axes(ctx, rx, ry)
        return Locaux.radial(cx - ex / ctx.lf, cy - ey / ctx.hf, cx + ex / ctx.lf, cy + ey / ctx.hf,
            (tonumber(m.angle) or 0) + ctx.angle, tonumber(m.fondu) or 50, nom, m.inverser == true), false, true
    elseif m.type == 'luminance' then
        return Locaux.luminance(tonumber(m.min), tonumber(m.max), tonumber(m.fondu) or 0.1, nom, m.inverser == true), false, false
    elseif m.type == 'profondeur' then
        return Locaux.profondeur(tonumber(m.min), tonumber(m.max), tonumber(m.fondu) or 0.1, nom, m.inverser == true), false, false
    elseif m.type == 'couleur' then
        -- Couleurs prélevées dans l'aperçu : leur modèle (calculé par le serveur) et leur position,
        -- ramenée dans le repère du fichier.
        local points = {}
        for _, p in ipairs(type(m.prelevements) == 'table' and m.prelevements or {}) do
            local x, y = Geometrie.point(ctx, tonumber(p.x), tonumber(p.y))
            local modele = type(p.modele) == 'table' and p.modele or {}
            points[#points + 1] = { tonumber(modele[1]) or 0, tonumber(modele[2]) or 0, tonumber(modele[3]) or 0, x, y }
        end
        if #points == 0 then
            echouer("Masque « " .. nom .. " » sans couleur prélevée.")
        end
        return Locaux.couleur(points, tonumber(m.etendue) or 0.5, nom, m.inverser == true), false, true
    elseif m.type == 'objet' and type(m.rectangle) == 'table' then
        -- Objet désigné par son cadre : les quatre coins, dans le repère du fichier.
        local r = m.rectangle
        local coins = {}
        for _, c in ipairs({ { r.x, r.y }, { r.x + r.largeur, r.y }, { r.x + r.largeur, r.y + r.hauteur }, { r.x, r.y + r.hauteur } }) do
            local x, y = Geometrie.point(ctx, tonumber(c[1]), tonumber(c[2]))
            coins[#coins + 1] = { x, y }
        end
        return Locaux.objetRectangle(coins, nom, m.inverser == true), true, true
    elseif m.type == 'pinceau' or m.type == 'objet' then
        -- Traits donnés dans l'aperçu : points et rayon (part de la largeur de l'aperçu) ramenés
        -- dans le repère du fichier, rayon rapporté à son grand côté, comme pour les taches.
        local grand = math.max(ctx.lf, ctx.hf)
        local traits, sx, sy, n = {}, 0, 0, 0
        for _, t in ipairs(type(m.traits) == 'table' and m.traits or {}) do
            local points = {}
            for _, p in ipairs(type(t.points) == 'table' and t.points or {}) do
                local x, y = Geometrie.point(ctx, tonumber(p[1]), tonumber(p[2]))
                points[#points + 1] = { x, y }
                sx, sy, n = sx + x, sy + y, n + 1
            end
            local rayon = Geometrie.pixels(ctx, tonumber(t.rayon) or 0.02) / grand
            traits[#traits + 1] = { points = points, rayon = rayon, flux = tonumber(t.flux) or 1, durete = tonumber(t.durete) or 0 }
        end
        if #traits == 0 or n == 0 then
            echouer("Masque « " .. nom .. " » sans trait.")
        end
        if m.type == 'objet' then
            local dabs = {}
            for _, t in ipairs(traits) do
                for _, d in ipairs(Locaux.touches(t.points, t.rayon, ctx.lf, ctx.hf)) do
                    dabs[#dabs + 1] = d
                end
            end
            return Locaux.objet(dabs, sx / n, sy / n, nom, m.inverser == true), true, true
        end
        for _, t in ipairs(traits) do
            t.dabs = Locaux.touches(t.points, t.rayon, ctx.lf, ctx.hf, { flux = t.flux, durete = t.durete, auto = m.auto == true })
        end
        return Locaux.pinceau(traits, nom, m.inverser == true), false, true
    end
    echouer("Type de masque inconnu : " .. tostring(m.type))
end

-- Un masque déjà sur la photo, désigné par son nom exact (casse indifférente) : le masque que Dany a
-- peint lui-même dans le panneau Masquage, que generative_edit (mask.existing) reprend comme zone.
-- Ses composants (CorrectionMasks) sont copiés tels quels (pourLightroom : des tables neuves, sans
-- métatable), avec de nouveaux identifiants, dans le masque témoin, une correction nouvelle : le
-- masque de Dany n'est ni changé ni retiré (son effet est dans l'état actuel comme dans le témoin, et
-- seule la différence du témoin compte). Absent, ou porté par deux masques : refusé, avec les noms.
local function composantsExistants(existants, designation)
    local voulu = minuscules(tostring(designation or ''):match('^%s*(.-)%s*$'))
    local trouves, noms = {}, {}
    for i, correction in ipairs(existants) do
        local nom = tostring(correction.CorrectionName or '')
        noms[#noms + 1] = '« ' .. (nom ~= '' and nom or 'sans nom') .. ' »'
        if minuscules(nom:match('^%s*(.-)%s*$')) == voulu then
            trouves[#trouves + 1] = i
        end
    end
    local liste = #noms > 0 and ('ses masques : ' .. table.concat(noms, ', ')) or "elle n'a aucun masque"
    if #trouves == 0 then
        echouer("Aucun masque « " .. tostring(designation) .. " » sur cette photo (" .. liste .. ").")
    end
    if #trouves > 1 then
        echouer(#trouves .. " masques s'appellent « " .. tostring(designation) .. " » sur cette photo (" .. liste
            .. ") : en renommer un dans le panneau Masquage de Lightroom.")
    end
    local copie = pourLightroom(existants[trouves[1]].CorrectionMasks or {})
    if #copie == 0 then
        echouer("Le masque « " .. tostring(designation) .. " » n'a aucun composant.")
    end
    Locaux.nouveauxIdentifiants(copie)
    return copie
end

-- Masques (commande « masquer ») : ajoutés à ceux de la photo, dans l'ordre demandé. Avec un
-- masque IA, le paramètre prédéfini porte aussi les masques existants, tels que Lightroom les a
-- rangés : leurs empreintes (MaskDigest…) sont celles de cette photo, il n'a pas à les recalculer.
-- Un masque combiné porte ses autres composants dans `composants` (mode ajouter, soustraire ou
-- intersecter), comme Lightroom les range (Locaux.combiner).
local function preparerMasques(photo, params)
    local plan = nouveauPlan(photo)
    local ctx = contexteGeometrie(photo, plan, params)
    local existants = type(plan.actuels.MaskGroupBasedCorrections) == 'table' and plan.actuels.MaskGroupBasedCorrections or {}
    local liste = pourLightroom(existants)
    local ia = false
    local ajoutes, geometriques = {}, false
    for _, m in ipairs(type(params.masques) == 'table' and params.masques or {}) do
        local nom = tostring(m.nom or "Claude · masque")
        if m.type == 'existant' then
            -- Le masque peint par Dany, repris tel quel dans une correction nouvelle (rien à calculer :
            -- ses empreintes de masque IA restent, comme une copie d'edit_mask).
            liste[#liste + 1] = Locaux.correction(nom, tonumber(m.quantite) or 1, pourLightroom(m.locaux),
                composantsExistants(existants, m.masque))
            ajoutes[#ajoutes + 1] = nom
        else
            local premier, estIA, positionne = composant(ctx, m, nom)
            local masques = { premier }
            ia = ia or estIA
            geometriques = geometriques or positionne
            -- Contour d'un masque IA (affinage) : celui du masque, ou celui d'un composant.
            local function affiner(cible, affinage)
                if type(affinage) == 'table' then
                    Locaux.affiner(cible, tonumber(affinage.contour), tonumber(affinage.decalage))
                end
            end
            affiner(premier, m.affinage)
            for _, c in ipairs(type(m.composants) == 'table' and m.composants or {}) do
                local autre
                autre, estIA, positionne = composant(ctx, c, tostring(c.nom or nom))
                masques[#masques + 1] = Locaux.combiner(autre, c.mode, c.inverser == true)
                affiner(autre, c.affinage or m.affinage)
                ia = ia or estIA
                geometriques = geometriques or positionne
            end
            local correction = Locaux.correction(nom, tonumber(m.quantite) or 1, pourLightroom(m.locaux), masques)
            if type(m.couleurs_ponctuelles) == 'table' and #m.couleurs_ponctuelles > 0 then
                correction.LocalPointColors, correction.LocalColorVariance = Locaux.couleursPonctuelles(m.couleurs_ponctuelles)
            end
            -- Personnes précises : vérifiées après le calcul (Retouche.verifierPersonnes).
            local sources = { m }
            for _, c in ipairs(type(m.composants) == 'table' and m.composants or {}) do
                sources[#sources + 1] = c
            end
            for k, source in ipairs(sources) do
                local mk = masques[k]
                if source.type == 'personne' and mk then
                    local numero = Locaux.numeroPersonne(mk) or 1
                    local bornes = bornesPersonnes(ctx, source.cadres) or {}
                    plan.personnes = plan.personnes or {}
                    plan.personnes[#plan.personnes + 1] = { correctionID = correction.CorrectionID, composant = k, numero = numero,
                        cadre = bornes[numero], trouvees = #bornes }
                end
            end
            liste[#liste + 1] = correction
            ajoutes[#ajoutes + 1] = nom
        end
    end
    if geometriques then
        noterTransformation(plan, ctx)
    end
    if ia then
        masquesParPreset(plan, presetMasques("Claude · masques IA", liste))
    elseif #liste > #existants then
        plan.nouveaux.MaskGroupBasedCorrections = liste
    end
    if #ajoutes > 0 then
        plan.avant.MaskGroupBasedCorrections = pourLightroom(existants)
        plan.changements[#plan.changements + 1] = {
            cle = 'MaskGroupBasedCorrections',
            avant = resume('MaskGroupBasedCorrections', existants),
            apres = pluriel(#existants + #ajoutes, "masque", "masques") .. " (+ " .. table.concat(ajoutes, ", ") .. ")",
        }
    end
    return plan
end

-- Taches et yeux rouges (commande « retoucher ») : ajoutés à ceux de la photo.
local function preparerTaches(photo, params)
    local plan = nouveauPlan(photo)
    local ctx = contexteGeometrie(photo, plan, params)
    local grand = math.max(ctx.lf, ctx.hf)
    local taches = type(params.taches) == 'table' and params.taches or {}
    local yeux = type(params.yeux) == 'table' and params.yeux or {}
    if #taches > 0 then
        local liste = pourLightroom(type(plan.actuels.RetouchAreas) == 'table' and plan.actuels.RetouchAreas or {})
        -- Relevé dans Lightroom Classic 15.6 (AgCameraRawController, getRetouchKey) : une photo qui
        -- porte RemoveAreas (taches de l'outil Supprimer à détection d'objet) est lue par là, et
        -- RetouchAreas en est dérivé ; les taches y vont donc aussi (voir docs/SPEC.md, Suppression
        -- des distractions).
        local supprimer = plan.actuels.RemoveAreas
        if type(supprimer) == 'table' and next(supprimer) ~= nil then
            supprimer = pourLightroom(supprimer)
        else
            supprimer = nil
        end
        for _, t in ipairs(taches) do
            local px, py, rayon = tonumber(t.x), tonumber(t.y), tonumber(t.rayon)
            local sx, sy = tonumber(t.source_x), tonumber(t.source_y)
            if not sx then
                -- Source par défaut : à côté, du côté du centre de l'image.
                sx = math.min(math.max(px + (px < 0.5 and 1 or -1) * 2.5 * rayon, 0), 1)
                sy = py
            end
            local x, y = Geometrie.point(ctx, px, py)
            local xs, ys = Geometrie.point(ctx, sx, sy)
            local taille = Geometrie.pixels(ctx, rayon) / grand
            liste[#liste + 1] = Locaux.tache(x, y, taille, xs, ys, t.mode, tonumber(t.fondu))
            if supprimer then
                supprimer[#supprimer + 1] = pourLightroom(liste[#liste])
            end
        end
        if noterTable(plan, 'RetouchAreas', liste, {}) and supprimer then
            plan.nouveaux.RemoveAreas = supprimer
            plan.avant.RemoveAreas = pourLightroom(plan.actuels.RemoveAreas)
        end
    end
    if #yeux > 0 then
        local liste = pourLightroom(type(plan.actuels.RedEyeInfo) == 'table' and plan.actuels.RedEyeInfo or {})
        for _, o in ipairs(yeux) do
            local x, y = Geometrie.point(ctx, tonumber(o.x), tonumber(o.y))
            local rayon = Geometrie.pixels(ctx, tonumber(o.rayon))
            liste[#liste + 1] = Locaux.oeilRouge(x, y, rayon / ctx.lf, rayon / ctx.hf, tonumber(o.pupille), tonumber(o.assombrir))
        end
        noterTable(plan, 'RedEyeInfo', liste, {})
    end
    noterTransformation(plan, ctx)
    return plan
end

-- Copie des réglages d'une photo source (commande « copier »).
local function preparerCopie(source, photo, params)
    local plan = nouveauPlan(photo)
    local actuels, raw = plan.actuels, plan.raw
    local inclure = type(params.inclure) == 'table' and params.inclure or {}
    local deSource = source.reglages
    local balanceSautee = false

    local function copierValeur(reelleSource, reelleCible, cle)
        local valeur = deSource[reelleSource]
        if valeur == nil or type(valeur) == 'table' or egal(valeur, actuels[reelleCible]) then
            return
        end
        plan.nouveaux[reelleCible] = valeur
        local actuel = actuels[reelleCible]
        if actuel == nil then
            actuel = DEFAUTS[reelleCible]
        end
        plan.avant[reelleCible] = actuel
        plan.changements[#plan.changements + 1] = {
            cle = cle,
            avant = valeurNumerique(actuel) or (actuel ~= nil and tostring(actuel)) or Json.null,
            apres = valeurNumerique(valeur) or tostring(valeur),
        }
    end

    for _, cle in ipairs(type(params.cles) == 'table' and params.cles or {}) do
        if (cle == 'Temperature' or cle == 'Tint') and source.raw ~= raw then
            balanceSautee = true
        else
            copierValeur(cleReelle(cle, source.raw), cleReelle(cle, raw), cle)
            if cle == 'Temperature' then
                copierValeur('WhiteBalance', 'WhiteBalance', 'WhiteBalance')
            end
        end
    end
    if balanceSautee then
        noter(plan, "Balance des blancs non copiée : l'une des photos est un RAW, l'autre non (échelles différentes).")
    end

    if inclure.profil then
        if source.raw == raw then
            copierValeur('CameraProfile', 'CameraProfile', 'CameraProfile')
            noterTable(plan, 'Look', pourLightroom(deSource.Look or {}), {})
            if plan.nouveaux.CameraProfile ~= nil or plan.nouveaux.Look ~= nil then
                local voulu = { CameraProfile = plan.nouveaux.CameraProfile, nom = nomProfil(deSource) or "?" }
                if plan.nouveaux.Look ~= nil then
                    voulu.Look = false
                    if not lookVide(plan.nouveaux.Look) then
                        voulu.Look = tostring(plan.nouveaux.Look.Name)
                    end
                end
                plan.profilVoulu = voulu
            end
            -- Profil adaptatif de la source : recalculé pour cette photo (ses empreintes ne valent
            -- que pour la source, AILook n'est pas copié).
            local look = plan.nouveaux.Look
            if type(look) == 'table' and look.isAdobeAdaptive == true then
                local reglages = { Look = look, CameraProfile = plan.nouveaux.CameraProfile, AILook = { Active = true } }
                plan.nouveaux.Look, plan.nouveaux.CameraProfile = nil, nil
                poserAdaptatif(plan, reglages, tostring(look.Name))
                plan.profilVoulu.adaptatif = true
            end
        else
            noter(plan, "Profil non copié : l'une des photos est un RAW, l'autre non.")
        end
    end
    if inclure.courbes then
        preparerCourbes(plan, {
            ToneCurvePV2012 = deSource.ToneCurvePV2012, ToneCurvePV2012Red = deSource.ToneCurvePV2012Red,
            ToneCurvePV2012Green = deSource.ToneCurvePV2012Green, ToneCurvePV2012Blue = deSource.ToneCurvePV2012Blue,
        })
    end
    if inclure.couleurs then
        noterTable(plan, 'PointColors', pourLightroom(deSource.PointColors or {}), {})
    end
    if inclure.recadrage and (Reglages.estAgrandie(actuels) or Reglages.estAgrandie(deSource)) then
        -- Le cadre d'une photo agrandie sort de l'image : copié vers une autre, Lightroom le rabat ;
        -- copié vers une photo agrandie, il effacerait son agrandissement.
        noter(plan, "Recadrage non copié : l'une des photos est agrandie (agrandissement génératif), son cadre ne vaut pas pour l'autre.")
    elseif inclure.recadrage then
        for _, cle in ipairs(CLES_CADRE) do
            copierValeur(cle, cle, cle)
        end
    end
    if inclure.masques then
        -- Sans leurs empreintes, les masques IA sont recalculés pour la photo, mais seulement
        -- posés par un paramètre prédéfini du module (un pour toutes les photos de la copie).
        local masques = Locaux.sansCalculsIA(pourLightroom(deSource.MaskGroupBasedCorrections or {}))
        if noterTable(plan, 'MaskGroupBasedCorrections', masques, {}) and Locaux.aDesMasquesIA(masques) then
            source.presetMasques = source.presetMasques or presetMasques("Claude · masques copiés", masques)
            masquesParPreset(plan, source.presetMasques)
        end
    end
    if inclure.taches then
        noterTable(plan, 'RetouchAreas', pourLightroom(deSource.RetouchAreas or {}), {})
    end
    -- Upright exact (« Transformations Upright » de la fenêtre Copier de Lightroom) : les matrices que
    -- Lightroom a calculées pour la source (UprightTransform_*) et ce qui les accompagne, au lieu du
    -- seul mode, recalculé pour chaque photo. Pour un bracketing ou une série prise du même endroit.
    if inclure.upright_exact then
        local cles = {}
        for cle, valeur in pairs(deSource) do
            -- Sans les empreintes, que le Copier de Lightroom retire aussi (relevé dans
        -- AgCameraRawNamedSettingsCopyPaste) : elles lient les matrices à la photo de départ.
        if cle:match('^Upright') and type(valeur) ~= 'table' and cle ~= 'UprightDependentDigest' and cle ~= 'UprightGuidedDependentDigest' then
                cles[#cles + 1] = cle
            end
        end
        cles[#cles + 1] = 'PerspectiveUpright'
        table.sort(cles)
        local copiees = 0
        for _, cle in ipairs(cles) do
            local valeur = deSource[cle]
            if valeur ~= nil and not egal(valeur, actuels[cle]) then
                memoriser(plan, cle, type(valeur) == 'string' and '' or 0)
                plan.nouveaux[cle] = valeur
                copiees = copiees + 1
            end
        end
        if copiees > 0 then
            plan.changements[#plan.changements + 1] = { cle = 'UprightTransform', avant = "calculées pour la photo",
                apres = "celles de la source (" .. tostring(valeurActuelle(deSource, 'PerspectiveUpright')) .. ")" }
            plan.uprightExact = true
        end
    end
    -- Suppression de la poussière de la source : son filtre, que Lightroom refait pour chaque photo
    -- (« Update Removal: Dust » de la mise à jour des réglages IA, Ecriture.calculerIA).
    preparerContrainte(plan)
    return plan
end

-- Les personnes précises d'un plan de masques, lues dans les masques calculés (liste : les
-- MaskGroupBasedCorrections relues après le calcul) : celles que Lightroom n'a pas reconnues (sans
-- numéro, ou d'un autre sous-type : il retire InstanceIDs et calcule un sous-type 3, constaté le
-- 18 octobre 2026), et celles qu'il a calculées hors du cadre de Vision. En lecture seule :
-- Retouche.verifierPersonnes retire ensuite les premières, Rendu.essayer (un rendu témoin) les dit.
local function lirePersonnes(plan, liste)
    local nonReconnues, horsCadre = {}, {}
    if type(plan.personnes) ~= 'table' then
        return nonReconnues, horsCadre
    end
    for _, p in ipairs(plan.personnes) do
        for _, correction in ipairs(liste or {}) do
            local m = correction.CorrectionID == p.correctionID and type(correction.CorrectionMasks) == 'table'
                and correction.CorrectionMasks[p.composant]
            if type(m) == 'table' and m.MaskDigest ~= nil then
                local nom = tostring(correction.CorrectionName)
                if not Locaux.numeroPersonne(m) or tonumber(m.MaskSubType) ~= 0 then
                    nonReconnues[#nonReconnues + 1] = { correctionID = correction.CorrectionID, nom = nom,
                        numero = p.numero, trouvees = p.trouvees }
                elseif type(p.cadre) == 'table' then
                    local px, py = tostring(m.ReferencePoint or ''):match('^(%S+)%s+(%S+)$')
                    px, py = tonumber(px), tonumber(py)
                    local c, marge = p.cadre, 0.02
                    if px and py and not (px >= c.Left - marge and px <= c.Right + marge and py >= c.Top - marge and py <= c.Bottom + marge) then
                        horsCadre[#horsCadre + 1] = { nom = nom, numero = p.numero }
                    end
                end
            end
        end
    end
    return nonReconnues, horsCadre
end

Plans.aDesChangements = aDesChangements
Plans.cadreARecadrer = cadreARecadrer
Plans.lirePersonnes = lirePersonnes
Plans.masquesParPreset = masquesParPreset
Plans.presetMasques = presetMasques
Plans.noter = noter
Plans.noterChangement = noterChangement
Plans.nouveauPlan = nouveauPlan
Plans.preparer = preparer
Plans.preparerContrainte = preparerContrainte
Plans.preparerCopie = preparerCopie
Plans.preparerMasques = preparerMasques
Plans.preparerTaches = preparerTaches
Plans.presetObjectifParDefaut = presetObjectifParDefaut

return Plans
