-- Retouche.lua : les commandes qui écrivent des réglages : appliquer, recadrer, masquer,
-- retoucher, copier.

local Conversions = require 'Conversions'
local Ecriture = require 'Ecriture'
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
-- sinon il retire InstanceIDs et calcule autre chose (sous-type 3). Un masque non reconnu est
-- retiré, et dit ; un point de référence hors du cadre voulu est signalé.
local function verifierPersonnes(plan)
    if type(plan.personnes) ~= 'table' or #plan.personnes == 0 then
        return
    end
    local liste = pourLightroom(plan.photo:getDevelopSettings().MaskGroupBasedCorrections or {})
    local retires, nombre = {}, 0
    for _, p in ipairs(plan.personnes) do
        for _, correction in ipairs(liste) do
            local m = correction.CorrectionID == p.correctionID and type(correction.CorrectionMasks) == 'table'
                and correction.CorrectionMasks[p.composant]
            if type(m) == 'table' and m.MaskDigest ~= nil then
                local nom = tostring(correction.CorrectionName)
                if not Locaux.numeroPersonne(m) or tonumber(m.MaskSubType) ~= 0 then
                    if not retires[correction.CorrectionID] then
                        retires[correction.CorrectionID] = true
                        nombre = nombre + 1
                    end
                    noter(plan, string.format("Masque « %s » retiré : Lightroom n'a pas reconnu la personne %d (sur %d trouvées par Vision) ; "
                        .. "le faire à la main (Masquage › Personnes).", nom, p.numero, p.trouvees))
                elseif type(p.cadre) == 'table' then
                    local px, py = tostring(m.ReferencePoint or ''):match('^(%S+)%s+(%S+)$')
                    px, py = tonumber(px), tonumber(py)
                    local c, marge = p.cadre, 0.02
                    if px and py and not (px >= c.Left - marge and px <= c.Right + marge and py >= c.Top - marge and py <= c.Bottom + marge) then
                        noter(plan, string.format("Masque « %s » : Lightroom l'a calculé hors du cadre de la personne %d ; vérifier avec view_photo.",
                            nom, p.numero))
                    end
                end
            end
        end
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
        -- Masques IA qui n'ont rien trouvé (« Personnes » sur un paysage) : retirés par Lightroom,
        -- une fois calculés ; l'étape garde la liste d'avant (undo_last).
        if #plan.presetsApres > 0 and not Locaux.masquesIAACalculer(plan.photo:getDevelopSettings().MaskGroupBasedCorrections) then
            Masques.retirerVides(plan)
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
    noterEtatFinal(photos, etape)
    reponse = reponse or {}
    reponse.mode = modeTexte(prefs)
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

function Retouche.copier(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'copy_settings')
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
    verifierProtection(cibles, prefs, params, 'copy_settings')
    local plans = {}
    for _, photo in ipairs(cibles) do
        plans[#plans + 1] = preparerCopie(source, photo, params)
    end
    if #plans == 0 then
        echouer("Aucune photo à part la source : rien à copier.")
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
