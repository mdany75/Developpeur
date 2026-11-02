-- Retouche.lua : les commandes qui écrivent des réglages : appliquer, recadrer, masquer,
-- retoucher, copier.

local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'

local Conversions = require 'Conversions'
local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Locaux = require 'Locaux'
local Masques = require 'Masques'
local Photos = require 'Photos'
local Plans = require 'Plans'
local Preferences = require 'Preferences'
local Profils = require 'Profils'
local Recadrage = require 'Recadrage'
local Recalage = require 'Recalage'
local Reglages = require 'Reglages'

local brut, decrire, dimensionsAffichees = Photos.brut, Photos.decrire, Photos.dimensionsAffichees
local orientationAffichage, photoParId = Photos.orientationAffichage, Photos.photoParId
local photosVisees, photoVisee = Photos.photosVisees, Photos.photoVisee
local afficher, CLES_CADRE, estRaw = Reglages.afficher, Reglages.CLES_CADRE, Reglages.estRaw
local pluriel = Reglages.pluriel
local pourLightroom, valeurActuelle = Reglages.pourLightroom, Reglages.valeurActuelle
local transformationActive, zoneImage = Recalage.transformationActive, Recalage.zoneImage
local aDesChangements, noter = Plans.aDesChangements, Plans.noter
local noterChangement, nouveauPlan = Plans.noterChangement, Plans.nouveauPlan
local preparer, preparerContrainte = Plans.preparer, Plans.preparerContrainte
local preparerCopie, preparerMasques = Plans.preparerCopie, Plans.preparerMasques
local preparerTaches = Plans.preparerTaches
local calculerIA, ecrire = Ecriture.calculerIA, Ecriture.ecrire
local completerEtapes, ecrirePlans = Ecriture.completerEtapes, Ecriture.ecrirePlans
local modeTexte, nomEtape, noterEtatFinal = Ecriture.modeTexte, Ecriture.nomEtape, Ecriture.noterEtatFinal
local relireCadres, resultatsPlans = Ecriture.relireCadres, Ecriture.resultatsPlans
local signalerARecadrer, verifierAccord = Ecriture.signalerARecadrer, Ecriture.verifierAccord
local verifierPause, verifierProtection = Ecriture.verifierPause, Ecriture.verifierProtection
local verifierProfils = Profils.verifierProfils

local Retouche = {}

local function echouer(message)
    error(message, 0)
end

-- Profil d'objectif choisi, relu après l'écriture : un nom ou un fichier que Lightroom ne garde pas
-- est dit, comme pour un profil d'appareil. Upright actif : Lightroom le recalcule sur l'image que
-- corrige le nouveau profil (voir docs/SPEC.md, Profil d'objectif).
local function verifierProfilsObjectif(plans)
    for _, plan in ipairs(plans) do
        local voulu = plan.profilObjectifVoulu
        if voulu then
            local relu = plan.photo:getDevelopSettings()
            if relu.LensProfileName ~= voulu.nom or relu.LensProfileFilename ~= voulu.fichier then
                noter(plan, string.format("Profil d'objectif « %s » pas gardé par Lightroom (profil relu : %s) ; undo_last remet le précédent.",
                    voulu.nom, tostring(relu.LensProfileName or relu.LensProfileSetup)))
            elseif (tonumber(relu.PerspectiveUpright) or 0) ~= 0 then
                noter(plan, "Upright actif : il porte maintenant sur l'image que corrige ce profil ; vérifier les verticales avec view_photo.")
            end
        end
    end
end

function Retouche.appliquer(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'apply_settings')
    local reglages = type(params.reglages) == 'table' and next(params.reglages) ~= nil
    if not reglages and not params.profil and type(params.profil_look) ~= 'table' and type(params.recadrage) ~= 'table'
        and type(params.courbes) ~= 'table' and type(params.couleurs_ponctuelles) ~= 'table' and not params.balance
        and not params.auto_ton and not params.preset and type(params.flou_objectif) ~= 'table'
        and type(params.version_processus) ~= 'table' and type(params.profil_objectif) ~= 'table'
        and type(params.reperes) ~= 'table' and not params.melange_nb_auto and not params.rotation then
        echouer("Aucun réglage à appliquer.")
    end

    local etape = nomEtape(params, "retouche")
    local photos = photosVisees(params)
    verifierProtection(photos, prefs, params, 'apply_settings')
    -- Rotation d'un quart de tour : avant le plan, qui se calcule sur la nouvelle orientation.
    local rotations = {}
    if params.rotation then
        for _, photo in ipairs(photos) do
            rotations[photo.localIdentifier] = Conversions.tournerPhoto(photo, params.rotation)
        end
    end
    local plans = {}
    for _, photo in ipairs(photos) do
        local plan = preparer(photo, params, prefs)
        if rotations[photo.localIdentifier] then
            Conversions.noterRotation(plan, rotations[photo.localIdentifier])
        end
        plans[#plans + 1] = plan
    end
    ecrirePlans(plans, etape, prefs, params)
    calculerIA(plans)
    verifierProfils(plans, etape)
    relireCadres(plans)

    -- Le ratio du recadrage obtenu, relu dans Lightroom : un écart trahirait un mauvais repère.
    for _, plan in ipairs(plans) do
        local d = plan.ratioAttendu and brut(plan.photo, 'croppedDimensions')
        if type(d) == 'table' and tonumber(d.width) and tonumber(d.height) and tonumber(d.height) > 0 then
            local obtenu = tonumber(d.width) / tonumber(d.height)
            if math.abs(obtenu / plan.ratioAttendu - 1) > 0.02 then
                noter(plan, string.format("Recadrage : ratio obtenu %s au lieu de %s ; vérifier avec view_photo.",
                    afficher(math.floor(obtenu * 100 + 0.5) / 100), afficher(math.floor(plan.ratioAttendu * 100 + 0.5) / 100)))
            end
        end
    end
    verifierProfilsObjectif(plans)
    noterEtatFinal(photos, etape)
    return { mode = modeTexte(prefs), resultats = signalerARecadrer(plans, resultatsPlans(plans, etape, params)) }
end

-- Cadre demandé sur une géométrie nouvelle (commande « recadrer ») : quand une retouche pose ou
-- change Upright, la perspective ou la distorsion manuelle en même temps qu'elle recadre
-- (a_recadrer), Lightroom a resserré le cadre lui-même, quitte à le déplacer ; le serveur mesure
-- la nouvelle géométrie (grille de recalage), et le cadre de `recadrage` se calcule dans la partie
-- de l'image qui montre la photo, au centre et à la taille demandés. Pour les photos de
-- `completer`, l'écriture complète la dernière étape de Claude (même nom) : l'annulation remet
-- aussi le cadre d'avant.
function Retouche.recadrer(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'apply_settings')
    local etape = nomEtape(params, "recadrage")
    local completer = {}
    for _, id in ipairs(type(params.completer) == 'table' and params.completer or {}) do
        completer[tonumber(id)] = true
    end
    local plans, aCompleter, seules = {}, {}, {}
    local photos = photosVisees(params)
    verifierProtection(photos, prefs, params, 'apply_settings')
    for _, photo in ipairs(photos) do
        local plan = nouveauPlan(photo)
        local largeur, hauteur = dimensionsAffichees(photo)
        local orientation = orientationAffichage(photo, plan.raw, largeur, hauteur)
        local zone = zoneImage(photo, plan.actuels, params)
        local demande = type(params.recadrage) == 'table' and not params.recadrage.retirer and params.recadrage or nil
        if not demande or not transformationActive(plan.actuels) then
            demande = nil
        elseif not zone then
            demande = nil
            noter(plan, "Upright, perspective ou distorsion manuelle actifs, sans recalage : Lightroom a resserré le cadre lui-même "
                .. "(« Contraindre le recadrage »), au centre qu'il a choisi ; le vérifier avec view_photo.")
        end
        if demande then
            local cadre, remarque = Recadrage.calculer(demande, largeur, hauteur, orientation, zone)
            if remarque then
                noter(plan, remarque)
            end
            for _, cle in ipairs(CLES_CADRE) do
                noterChangement(plan, plan.actuels, cle, cle, valeurActuelle(plan.actuels, cle), cadre[cle])
            end
            preparerContrainte(plan)
        end
        plans[#plans + 1] = plan
        if aDesChangements(plan) then
            local liste = completer[photo.localIdentifier] and aCompleter or seules
            liste[#liste + 1] = plan
        end
    end
    completerEtapes(aCompleter, etape, prefs, params)
    if #seules > 0 then
        ecrirePlans(seules, etape, prefs, params)
    end
    calculerIA(plans)
    relireCadres(plans)
    noterEtatFinal(photos, etape)
    return { mode = modeTexte(prefs), resultats = resultatsPlans(plans, etape, params) }
end

-- Masque d'une personne précise, une fois calculé (constaté le 18 octobre 2026) : s'il a reconnu
-- la personne, Lightroom garde InstanceIDs et le sous-type 0, et range ReferencePoint sur elle ;
-- sinon il retire InstanceIDs et calcule autre chose (sous-type 3). La personne seule d'une photo
-- n'a pas d'InstanceIDs (Locaux.numeroPersonne la compte comme la personne 1). Un masque non
-- reconnu est retiré, et dit ; un point de référence hors du cadre voulu est signalé.
local function verifierPersonnes(plan)
    if type(plan.personnes) ~= 'table' or #plan.personnes == 0 then
        return
    end
    local liste = pourLightroom(plan.photo:getDevelopSettings().MaskGroupBasedCorrections or {})
    local nonReconnues, horsCadre = Plans.lirePersonnes(plan, liste)
    local retires, nombre = {}, 0
    for _, p in ipairs(nonReconnues) do
        if not retires[p.correctionID] then
            retires[p.correctionID] = true
            nombre = nombre + 1
        end
        noter(plan, string.format("Masque « %s » retiré : Lightroom n'a pas reconnu la personne %d (sur %d trouvées par Vision) ; "
            .. "le faire à la main (Masquage › Personnes).", p.nom, p.numero, p.trouvees))
    end
    for _, p in ipairs(horsCadre) do
        noter(plan, string.format("Masque « %s » : Lightroom l'a calculé hors du cadre de la personne %d ; vérifier avec view_photo.",
            p.nom, p.numero))
    end
    if nombre > 0 then
        local reste = {}
        for _, correction in ipairs(liste) do
            if not retires[correction.CorrectionID] then
                reste[#reste + 1] = correction
            end
        end
        ecrire("Claude · personne non reconnue", function()
            plan.photo:applyDevelopSettings({ MaskGroupBasedCorrections = reste }, "Claude · personne non reconnue")
        end)
        for id in pairs(retires) do
            plan.retiresParModule[tostring(id)] = true
        end
    end
end

-- Masques relus après l'écriture (1.6) : au plus tant de lectures pour toute la commande, à
-- RELECTURE_FORMES secondes d'écart, jusqu'à deux lectures pareilles de toutes les photos. Une photo
-- encore changeante à la dernière dit « à relire ».
local LECTURES_FORMES, RELECTURE_FORMES = 4, 0.3

-- Un nombre d'une remarque, à six décimales au plus, virgule française.
local function nombreFormes(v)
    if type(v) ~= 'number' then
        return tostring(v)
    end
    local texte = Locaux.decimal(v):gsub('0+$', ''):gsub('%.$', '')
    return (texte:gsub('%.', ','))
end

-- Les formes sans IA de chaque photo (Plans.preparerMasques, formesEcrites), relues dans Lightroom et
-- comparées à l'écrit (Locaux.comparerFormes) : verdict « gardé » (aux arrondis près), « écart »,
-- « absent » (correction introuvable), ou « à relire » (masques IA pas encore calculés, ou liste
-- encore changeante : Lightroom peut la réécrire au premier rendu). Rien n'est retiré : les écarts
-- et les absents sont dits (remarques) ; les verdicts vont dans la réponse (masques_relus). Avec
-- releve_formes (développement, DEVELOPPEUR_RELEVE_FORMES du serveur), la réponse porte aussi
-- l'écrit et le relu de chaque masque de l'appel, IA compris, pour le constat.
local function relireFormes(plans, params)
    local suivis = {}
    for _, plan in ipairs(plans) do
        local aRelire = false
        for _, ecrite in ipairs(plan.formesEcrites or {}) do
            aRelire = aRelire or ecrite.formes
        end
        if aRelire or (params.releve_formes == true and #(plan.formesEcrites or {}) > 0) then
            suivis[#suivis + 1] = plan
        end
    end
    if #suivis == 0 then
        return
    end
    local function lire(plan)
        local relues = pourLightroom(plan.photo:getDevelopSettings().MaskGroupBasedCorrections or {})
        local parId = {}
        for _, correction in ipairs(relues) do
            parId[tostring(correction.CorrectionID)] = correction
        end
        local verdicts, signature = {}, {}
        for _, ecrite in ipairs(plan.formesEcrites) do
            if ecrite.formes and not plan.retiresParModule[tostring(ecrite.id)] then
                local relue = parId[tostring(ecrite.id)]
                local v = { nom = ecrite.nom, verdict = 'absent', ecarts = {} }
                if relue then
                    v.ecarts = Locaux.comparerFormes(ecrite.masques, relue.CorrectionMasks)
                    v.verdict = #v.ecarts > 0 and 'écart' or 'gardé'
                end
                verdicts[#verdicts + 1] = v
                signature[#signature + 1] = v.verdict
                for _, e in ipairs(v.ecarts) do
                    signature[#signature + 1] = e.composant .. ':' .. e.cle .. '=' .. tostring(e.relu)
                end
            end
        end
        return { verdicts = verdicts, signature = table.concat(signature, '|'), parId = parId,
            enAttente = #plan.presetsApres > 0 and Locaux.masquesIAACalculer(relues) }
    end
    local lectures, stables = {}, {}
    for _, plan in ipairs(suivis) do
        lectures[plan] = lire(plan)
    end
    for _ = 2, LECTURES_FORMES do
        LrTasks.sleep(RELECTURE_FORMES)
        local toutes = true
        for _, plan in ipairs(suivis) do
            if not stables[plan] then
                local nouvelle = lire(plan)
                stables[plan] = nouvelle.signature == lectures[plan].signature
                lectures[plan] = nouvelle
                toutes = toutes and stables[plan]
            end
        end
        if toutes then
            break
        end
    end
    for _, plan in ipairs(suivis) do
        local lecture = lectures[plan]
        local relus = Json.tableau()
        for _, v in ipairs(lecture.verdicts) do
            local entree = { nom = v.nom, verdict = v.verdict }
            if #v.ecarts > 0 then
                local details = {}
                for i, e in ipairs(v.ecarts) do
                    if i <= 3 then
                        details[#details + 1] = string.format("%s : %s écrit, %s relu", e.cle, nombreFormes(e.ecrit), nombreFormes(e.relu))
                    end
                end
                noter(plan, string.format("Masque « %s » : Lightroom ne l'a pas gardé tel qu'écrit (%s%s) ; le vérifier avec view_photo "
                    .. "et dire à l'utilisateur s'il est mal placé (rien n'est retiré).", v.nom, table.concat(details, " ; "),
                    #v.ecarts > 3 and string.format(" ; %d autres écarts", #v.ecarts - 3) or ""))
                local ecarts = Json.tableau()
                for _, e in ipairs(v.ecarts) do
                    ecarts[#ecarts + 1] = e
                end
                entree.ecarts = ecarts
            elseif v.verdict == 'absent' then
                noter(plan, string.format("Masque « %s » : absent après l'écriture, Lightroom ne l'a pas gardé ; le vérifier avec view_photo "
                    .. "(undo_last remet l'état d'avant).", v.nom))
            end
            if v.verdict ~= 'absent' and (lecture.enAttente or not stables[plan]) then
                entree.verdict = 'à relire'
            end
            relus[#relus + 1] = entree
        end
        if #relus > 0 then
            plan.masquesRelus = relus
        end
        if params.releve_formes == true then
            local releve = Json.tableau()
            for _, ecrite in ipairs(plan.formesEcrites) do
                local relue = lecture.parId[tostring(ecrite.id)]
                releve[#releve + 1] = { nom = ecrite.nom, correction_id = ecrite.id, compare = ecrite.formes,
                    ecrit = ecrite.masques, relu = relue and relue.CorrectionMasks or 'absent' }
            end
            plan.releveFormes = releve
        end
    end
end

function Retouche.masquer(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'add_mask')
    if type(params.masques) ~= 'table' or #params.masques == 0 then
        echouer("Aucun masque à ajouter.")
    end
    local etape = nomEtape(params, "masques")
    local photos = photosVisees(params)
    verifierProtection(photos, prefs, params, 'add_mask')
    local plans = {}
    for _, photo in ipairs(photos) do
        plans[#plans + 1] = preparerMasques(photo, params)
    end
    ecrirePlans(plans, etape, prefs, params)
    calculerIA(plans)
    local reponse
    for _, plan in ipairs(plans) do
        plan.retiresParModule = {}
        -- Masques IA qui n'ont rien trouvé (« Personnes » sur un paysage) : retirés par Lightroom,
        -- une fois calculés ; l'étape garde la liste d'avant (undo_last).
        if #plan.presetsApres > 0 and not Locaux.masquesIAACalculer(plan.photo:getDevelopSettings().MaskGroupBasedCorrections) then
            local avant = Masques.retirerVides(plan)
            if type(avant) == 'table' then
                local restants = {}
                for _, correction in ipairs(plan.photo:getDevelopSettings().MaskGroupBasedCorrections or {}) do
                    restants[tostring(correction.CorrectionID)] = true
                end
                for _, correction in ipairs(avant) do
                    if not restants[tostring(correction.CorrectionID)] then
                        plan.retiresParModule[tostring(correction.CorrectionID)] = true
                    end
                end
            end
        end
        verifierPersonnes(plan)
        local corrections = plan.photo:getDevelopSettings().MaskGroupBasedCorrections
        for _, nom in ipairs(Locaux.masquesIAEnEchec(corrections)) do
            noter(plan, string.format("Lightroom n'a pas su calculer le masque « %s » : pour un objet, un trait fin (size 0,005 à 0,01) "
                .. "posé sur lui seul, ou un cadre serré ; undo_last le retire.", nom))
        end
        if Locaux.masquesIAACalculer(corrections) then
            reponse = { a_savoir = "Lightroom calcule les masques IA au premier rendu : view_photo les montre appliqués." }
        end
    end
    relireFormes(plans, params)
    noterEtatFinal(photos, etape)
    reponse = reponse or {}
    reponse.mode = modeTexte(prefs)
    -- La version de Lightroom : le serveur dit quand elle n'est plus celle où les formes des
    -- masques ont été relevées (ToolHandler.versionFormesMasques).
    reponse.lightroom = LrApplication.versionString()
    reponse.resultats = resultatsPlans(plans, etape, params)
    return reponse
end

function Retouche.retoucher(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'retouch_spots')
    local etape = nomEtape(params, "taches")
    local photo = photoVisee(params)
    verifierProtection({ photo }, prefs, params, 'retouch_spots')
    local plans = { preparerTaches(photo, params) }
    ecrirePlans(plans, etape, prefs, params)
    calculerIA(plans)
    noterEtatFinal({ photo }, etape)
    return { mode = modeTexte(prefs), resultats = resultatsPlans(plans, etape, params) }
end

-- Après une copie : les matrices d'Upright copiées telles quelles sont-elles restées (Lightroom
-- pourrait les recalculer pour la photo) ; la poussière copiée, combien de taches Lightroom a-t-il
-- trouvées sur chaque photo.
local function relireCopie(plans, source)
    for _, plan in ipairs(plans) do
        local relus = plan.photo:getDevelopSettings()
        if plan.uprightExact then
            local differentes = 0
            for cle, valeur in pairs(source.reglages) do
                if cle:match('^UprightTransform_') and not Reglages.egal(valeur, relus[cle]) then
                    differentes = differentes + 1
                end
            end
            if differentes > 0 then
                noter(plan, string.format("Upright : Lightroom a recalculé %d matrice(s) pour cette photo au lieu de garder celles de la source.", differentes))
            else
                noter(plan, "Upright : les matrices de la source sont gardées telles quelles (même correction que la source).")
            end
        end
        -- Masques de personnes précises : Lightroom les reconnaît d'après les cadres de la source,
        -- qui ne vont que si les personnes sont à peu près aux mêmes places.
        for _, perdu in ipairs(Locaux.personnesPerdues(source.reglages.MaskGroupBasedCorrections, relus.MaskGroupBasedCorrections)) do
            noter(plan, string.format("Masque « %s » : Lightroom n'a pas reconnu la personne sur cette photo (les personnes n'y sont pas aux "
                .. "mêmes places) ; le refaire avec add_mask, ou retirer ce masque avec edit_mask.", perdu))
        end
    end
end

-- Copie en plan (copy_settings avec plan = true) : au plus tant de photos détaillées dans la
-- réponse ; le résumé compte toutes les photos.
local DETAIL_PLAN = 10

-- Ce que Lightroom recalcule lui-même après une copie, d'après les changements prévus : le plan ne
-- peut pas le prédire (les remarques que relireCopie fait après une vraie copie).
local function nonPredit(plans)
    local vus, liste = {}, Json.tableau()
    local function dire(cle, texte)
        if not vus[cle] then
            vus[cle] = true
            liste[#liste + 1] = texte
        end
    end
    for _, plan in ipairs(plans) do
        for _, changement in ipairs(plan.changements) do
            if changement.cle == 'MaskGroupBasedCorrections' then
                dire('masques', "Masques : Lightroom recalcule les masques IA (sujet, ciel, personnes…) sur chaque photo ; "
                    .. "une personne précise peut ne pas y être reconnue.")
            elseif changement.cle == 'UprightTransform' or changement.cle == 'PerspectiveUpright' then
                dire('upright', "Upright : Lightroom peut recalculer la correction pour chaque photo.")
            elseif changement.cle == 'RetouchAreas' then
                dire('taches', "Taches : elles tombent aux mêmes positions que sur la source, à vérifier sur chaque photo.")
            elseif changement.cle == 'CropConstrainToWarp' or tostring(changement.cle):match('^Crop') then
                dire('cadre', "Recadrage : avec « Contraindre le recadrage », Lightroom peut resserrer le cadre de chaque photo.")
            end
        end
    end
    return liste
end

-- Le plan d'une copie, sans rien écrire : par réglage, le nombre de photos où il change ; le détail
-- (avant → après, remarques) des premières photos ; ce que Lightroom recalculera. Permis en pause et
-- en « Proposer d'abord » (rien n'est écrit) ; les photos protégées sont dites, pas refusées.
local function planDeCopie(source, plans, cibles, prefs, params)
    local libelles = type(params.libelles) == 'table' and params.libelles or {}
    local parReglage, ordre = {}, {}
    local touchees = 0
    local detail = Json.tableau()
    for i, plan in ipairs(plans) do
        if #plan.changements > 0 then
            touchees = touchees + 1
        end
        for _, changement in ipairs(plan.changements) do
            local nom = libelles[changement.cle] or changement.cle
            if not parReglage[nom] then
                parReglage[nom] = 0
                ordre[#ordre + 1] = nom
            end
            parReglage[nom] = parReglage[nom] + 1
        end
        if i <= DETAIL_PLAN then
            detail[#detail + 1] = { photo = decrire(plan.photo, false), changements = plan.changements, remarques = plan.notes }
        end
    end
    local resume = Json.tableau()
    for _, nom in ipairs(ordre) do
        resume[#resume + 1] = { reglage = nom, photos = parReglage[nom] }
    end
    local protegees, raison = LrTasks.pcall(verifierProtection, cibles, prefs, params, 'copy_settings')
    return { mode = modeTexte(prefs), plan = true, rien_n_est_ecrit = true, source = decrire(source.photo, false),
        photos = #plans, photos_touchees = touchees, par_reglage = resume, resultats = detail,
        detail_limite = #plans > DETAIL_PLAN and string.format("Détail des %d premières photos sur %d ; par_reglage les compte toutes.", DETAIL_PLAN, #plans) or nil,
        non_predit = nonPredit(plans),
        protection = not protegees and Liaison.messageErreur(raison) or nil,
        suite = "Rien n'a été écrit. Pour copier : copy_settings avec les mêmes arguments, sans plan"
            .. (prefs.mode == 'proposer' and ", avec confirm = true après l'accord de l'utilisateur." or ".") }
end

function Retouche.copier(params)
    local essai = params.essai == true
    if not essai then
        verifierPause(params)
    end
    local prefs = Preferences.lire()
    if not essai then
        verifierAccord(prefs, params, 'copy_settings')
    end
    local photoSource = photoParId(params.source)
    local reglagesSource = photoSource:getDevelopSettings()
    local source = { photo = photoSource, reglages = reglagesSource, raw = estRaw(photoSource, reglagesSource) }
    local etape = nomEtape(params, "copie des réglages")
    local cibles = {}
    for _, photo in ipairs(photosVisees(params)) do
        if photo.localIdentifier ~= photoSource.localIdentifier then
            cibles[#cibles + 1] = photo
        end
    end
    if not essai then
        verifierProtection(cibles, prefs, params, 'copy_settings')
    end
    local plans = {}
    for _, photo in ipairs(cibles) do
        plans[#plans + 1] = preparerCopie(source, photo, params)
    end
    if #plans == 0 then
        echouer("Aucune photo à part la source : rien à copier.")
    end
    if essai then
        return planDeCopie(source, plans, cibles, prefs, params)
    end
    ecrirePlans(plans, etape, prefs, params)
    calculerIA(plans)
    verifierProfils(plans, etape)
    relireCadres(plans)
    relireCopie(plans, source)
    noterEtatFinal(cibles, etape)
    return { mode = modeTexte(prefs), source = decrire(photoSource, false), resultats = resultatsPlans(plans, etape, params) }
end

return Retouche
