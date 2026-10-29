-- Rendu.lua : les aperçus que voit Claude (commande apercu), la comparaison avec l'état d'avant,
-- les propositions rendues puis défaites (essayer, qui range aussi les variantes) et les deux
-- rendus du recalage (geometrie).
-- Composition lue (1.3) : apercu avec entier rend l'image entière, sans son cadre (retiré le
-- temps du rendu, puis remis, comme pour le recalage), et dit le cadre actuel vu dans cette image
-- (read_composition) ; essayer avec entier rend aussi l'image entière d'une proposition de
-- recadrage, avec le cadre que Lightroom a gardé (preview_settings le dessine dessus).
-- Rendu.rendre sert aussi l'avant/après des étapes (Etapes.lua, 1.3), qui garde une copie de
-- l'image de view_photo (la vue) : seulement l'image entière de l'état actuel, jamais l'image sans
-- cadre d'apercu avec entier.

local LrDate = import 'LrDate'
local LrExportSession = import 'LrExportSession'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Ecriture = require 'Ecriture'
local Etapes = require 'Etapes'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Locaux = require 'Locaux'
local Photos = require 'Photos'
local Plans = require 'Plans'
local Preferences = require 'Preferences'
local Profils = require 'Profils'
local Recadrage = require 'Recadrage'
local Recalage = require 'Recalage'
local Reglages = require 'Reglages'
local Notation = require 'Notation'
local Variantes = require 'Variantes'
local Vignettes = require 'Vignettes'

local catalogue, decrire, lireJson = Photos.catalogue, Photos.decrire, Photos.lireJson
local meta, photosVisees, photoVisee = Photos.meta, Photos.photosVisees, Photos.photoVisee
local dimensionsAffichees, orientationAffichage = Photos.dimensionsAffichees, Photos.orientationAffichage
local aRemettre, DEFAUTS, estRaw = Reglages.aRemettre, Reglages.DEFAUTS, Reglages.estRaw
local libererProfil, lireReglages = Reglages.libererProfil, Reglages.lireReglages
local pourLightroom, valeurActuelle = Reglages.pourLightroom, Reglages.valeurActuelle
local valeurNumerique = Reglages.valeurNumerique
local empreinteGeometrie, geometrieActive = Recalage.empreinteGeometrie, Recalage.geometrieActive
local NEUTRE_GEOMETRIE = Recalage.NEUTRE_GEOMETRIE
local transformationActive = Recalage.transformationActive
local aDesChangements, noter, preparer = Plans.aDesChangements, Plans.noter, Plans.preparer
local preparerMasques, preparerTaches = Plans.preparerMasques, Plans.preparerTaches
local appliquerPlan, ecrire, modeTexte = Ecriture.appliquerPlan, Ecriture.ecrire, Ecriture.modeTexte
local calculerAvantRendu, calculerIA = Ecriture.calculerAvantRendu, Ecriture.calculerIA
local nomEtape, verifierPause = Ecriture.nomEtape, Ecriture.verifierPause
local verifierProtection = Ecriture.verifierProtection
local attendreProfils, essayerVariantes = Profils.attendreProfils, Profils.essayerVariantes
local texteProfilRefuse = Profils.texteProfilRefuse
local verifierProfilsRemis = Profils.verifierProfilsRemis

local Rendu = {}

local function echouer(message)
    error(message, 0)
end

-- Masques IA posés par un paramètre prédéfini du module : Lightroom les calcule peu après sur la
-- photo affichée (la photo active), et jamais de lui-même sur les autres, que l'exportation calcule
-- (constaté dans Lightroom Classic 15.6). Exporter la photo affichée avant ce calcul a ouvert la
-- fenêtre « Mises à jour IA recommandées », qui attend un clic et bloque la réponse : pour elle
-- seule, on attend le calcul, une dizaine de secondes au plus. Faux si le délai est passé. Passé
-- ce délai, la fenêtre attend la réponse de l'utilisateur (Exporter, case « Mettre à jour » cochée) :
-- Lightroom ne calcule pas toujours de lui-même, même la photo affichée dans Développement (constaté
-- le 16 octobre 2026 après une fenêtre fermée sans réponse : rien après 30 s). Depuis la 1.8,
-- calculerAvantRendu (photo:updateAISettings) calcule d'abord : la fenêtre ne s'ouvre plus que si
-- Lightroom n'a pas pu (modèles IA absents) ; le veilleur, qui y répondait, est retiré depuis la 2.6.
local ATTENTES_CALCULS_IA = 40
local function attendreCalculsIA(photo)
    local active = catalogue():getTargetPhoto()
    if not active or active.localIdentifier ~= photo.localIdentifier then
        return true
    end
    for _ = 1, ATTENTES_CALCULS_IA do
        local reglages = photo:getDevelopSettings()
        if not Locaux.calculsEnAttente(reglages) then
            return true
        end
        -- Un profil adaptatif seul : rien à attendre, Lightroom ne le calcule pas de lui-même.
        if not Locaux.calculsSpontanes(reglages) then
            break
        end
        LrTasks.sleep(0.25)
    end
    Liaison.noter("Réglages IA pas encore calculés (masques, profondeur, profil adaptatif) : Lightroom peut demander de les mettre à jour")
    return false
end

-- Rend la photo en JPEG sRGB dans un dossier temporaire propre à ce rendu (le serveur efface le
-- fichier et le dossier après lecture). Taille 0 : pleine résolution. Le second résultat est faux
-- si des réglages IA n'étaient pas encore calculés.
-- Constaté en 2.4 (Lightroom Classic 15.6) : un aperçu rendu par LrExportSession fait passer
-- isExported à vrai. Une photo qui ne l'était pas est notée apercuSeulement (écriture privée, hors
-- de Édition › Annuler), pour que la recherche des photos jamais livrées la trouve encore.
local function noterApercuSeulement(photo)
    if Photos.brut(photo, 'isExported') ~= true or photo:getPropertyForPlugin(_PLUGIN, 'apercuSeulement') == 'oui' then
        return
    end
    LrTasks.pcall(Ecriture.ecrireMemoire, "Claude · aperçu", function()
        photo:setPropertyForPlugin(_PLUGIN, 'apercuSeulement', 'oui')
    end)
end

-- Sans original ni aperçu dynamique, Lightroom n'a rien à rendre : la raison plutôt qu'un échec.
local function verifierRendable(photo)
    if Photos.originalAbsent(photo) and not Photos.apercuDynamique(photo) then
        echouer(Photos.raisonOriginalAbsent(photo, "Sans aperçu dynamique, Lightroom ne peut pas la rendre : aucun aperçu."))
    end
end

local function rendre(photo, taille)
    local dejaExportee = Photos.brut(photo, 'isExported') == true
    verifierRendable(photo)
    calculerAvantRendu(photo)
    local calcules = attendreCalculsIA(photo)
    taille = math.floor(tonumber(taille) or 1568)
    local pleine = taille <= 0
    taille = math.max(256, math.min(taille, 4096))

    local racine = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), 'Developpeur')
    local dossier = LrPathUtils.child(racine, string.format('apercu-%d-%d', photo.localIdentifier,
        math.floor(LrDate.currentTime() * 1000) % 1000000000))
    LrFileUtils.createAllDirectories(dossier)

    local session = LrExportSession {
        photosToExport = { photo },
        exportSettings = {
            LR_export_destinationType = 'specificFolder',
            LR_export_destinationPathPrefix = dossier,
            LR_export_useSubfolder = false,
            LR_collisionHandling = 'overwrite',
            LR_renamingTokensOn = false,
            LR_format = 'JPEG',
            LR_jpeg_quality = pleine and 0.92 or 0.85,
            LR_jpeg_useLimitSize = false,
            LR_export_colorSpace = 'sRGB',
            LR_size_doConstrain = not pleine,
            LR_size_doNotEnlarge = true,
            LR_size_resizeType = 'wh',
            LR_size_maxWidth = taille,
            LR_size_maxHeight = taille,
            LR_size_units = 'pixels',
            LR_size_resolution = 72,
            LR_outputSharpeningOn = false,
            LR_removeLocationMetadata = true,
            LR_useWatermark = false,
            LR_reimportExportedPhoto = false,
            LR_includeVideoFiles = false,
        },
    }

    local chemin, raison
    local fini, erreur = LrTasks.pcall(function()
        for _, rendu in session:renditions() do
            local ok, cheminOuMessage = rendu:waitForRender()
            if ok then
                chemin = cheminOuMessage
            else
                raison = cheminOuMessage
            end
        end
    end)
    if not dejaExportee then
        noterApercuSeulement(photo)
    end
    if not fini then
        error(erreur, 0)
    end
    if not chemin then
        echouer("Lightroom n'a pas pu rendre l'aperçu : " .. tostring(raison or "raison inconnue"))
    end
    -- « Exporter » dans la fenêtre, case cochée (l'utilisateur), calcule avant le rendu ; ce qui reste
    -- à calculer après l'exportation (un profil adaptatif sans fenêtre) manque à l'aperçu.
    local reste = Locaux.calculsEnAttente(photo:getDevelopSettings())
    if not calcules and not reste then
        Liaison.noter("Réglages IA mis à jour pendant l'exportation")
    end
    return chemin, not reste
end

-- Écrit une copie neuve de ces valeurs (une étape de l'Historique, nommée).
local function poser(photo, nom, valeurs)
    local copie = {}
    for cle, valeur in pairs(valeurs) do copie[cle] = valeur end
    ecrire(nom, function() photo:applyDevelopSettings(copie, nom) end)
end

-- Ce qu'il faut poser pour rendre l'image entière d'une photo recadrée ou contrainte : le cadre
-- retiré (tout le fichier, sans angle) et la case « Contraindre le recadrage » décochée (cochée,
-- Lightroom resserrerait l'image entière sur l'image transformée) ; vide pour une photo ni
-- recadrée ni contrainte. Puis les valeurs à remettre ensuite : celles de la photo, sinon leurs
-- valeurs par défaut.
local function sansRecadrage(actuels)
    local recadree = valeurActuelle(actuels, 'CropConstrainToWarp') ~= 0
    for cle, valeur in pairs(Recadrage.AUCUN) do
        if (valeurNumerique(actuels[cle]) or valeur) ~= valeur then
            recadree = true
        end
    end
    local sansCadre, retour = {}, {}
    if recadree then
        for cle, valeur in pairs(Recadrage.AUCUN) do
            sansCadre[cle] = valeur
        end
        sansCadre.CropConstrainToWarp = 0
    end
    for cle in pairs(sansCadre) do
        local actuel = actuels[cle]
        if actuel ~= nil then
            retour[cle] = pourLightroom(actuel)
        else
            retour[cle] = DEFAUTS[cle]
        end
    end
    return sansCadre, retour
end

-- Deux rendus non recadrés pour le recalage : tel quel, puis sans corrections géométriques ; la
-- photo revient ensuite comme avant. Comme une comparaison, l'Historique de Lightroom garde les
-- étapes « Claude · recalage ».
local function rendreGeometrie(photo, actuels, taille)
    -- La grille porte sur l'image entière : cadre retiré et case décochée le temps des rendus.
    local sansCadre, retour = sansRecadrage(actuels)
    for cle in pairs(NEUTRE_GEOMETRIE) do
        local actuel = actuels[cle]
        if actuel ~= nil then
            retour[cle] = pourLightroom(actuel)
        elseif DEFAUTS[cle] ~= nil then
            retour[cle] = DEFAUTS[cle]
        else
            retour[cle] = NEUTRE_GEOMETRIE[cle]
        end
    end
    local corrige, origine
    local ok, erreur = LrTasks.pcall(function()
        if next(sansCadre) then
            poser(photo, "Claude · recalage (sans recadrage)", sansCadre)
        end
        corrige = rendre(photo, taille)
        local neutre = {}
        for cle, valeur in pairs(sansCadre) do neutre[cle] = valeur end
        for cle, valeur in pairs(NEUTRE_GEOMETRIE) do neutre[cle] = valeur end
        poser(photo, "Claude · recalage (sans correction)", neutre)
        origine = rendre(photo, taille)
    end)
    poser(photo, "Claude · recalage (retour)", retour)
    if not ok then
        error(erreur, 0)
    end
    return corrige, origine
end

-- Composition lue (1.3) ---------------------------------------------------------------------------

Rendu.ETAPE_ENTIERE = "Claude · composition (image entière)"
Rendu.ETAPE_ENTIERE_RETOUR = "Claude · composition (retour)"
Rendu.ETAPE_ESSAI_ENTIERE = "Claude · essai : image entière"

-- Photo agrandie par l'ancien connecteur (Reglages.estAgrandie : cadre hors de [0, 1]) : Claude ne
-- la recadre pas (Plans.preparerRecadrage), et n'en retire pas le cadre le temps d'un rendu.
local PHOTO_AGRANDIE = "Photo agrandie (agrandissement génératif) : Claude ne la recadre pas, et ne lit pas sa composition "
    .. "sur l'image entière (le cadre retiré le temps du rendu pourrait lui faire perdre l'agrandissement, comme un recadrage "
    .. "de Claude, constaté) ; rien n'a été écrit. Recadrer à la main dans Lightroom, ou lire la composition de l'original, "
    .. "celle d'avant l'agrandissement (souvent juste au-dessous dans la pile)."

-- Le cadre de ces réglages (Crop*) vu dans l'image affichée entière (Recadrage.lire : { ratio,
-- angle, centre_x, centre_y, largeur en pixels }, nil sans recadrage) et les dimensions de cette
-- image ({ largeur, hauteur }, en pixels) ; nil et nil si elles sont inconnues.
local function cadreAffiche(photo, reglages)
    local largeur, hauteur = dimensionsAffichees(photo)
    if not largeur or not hauteur or largeur <= 0 or hauteur <= 0 then
        return nil, nil
    end
    local orientation = orientationAffichage(photo, estRaw(photo, reglages), largeur, hauteur)
    return Recadrage.lire(reglages, largeur, hauteur, orientation), { largeur = largeur, hauteur = hauteur }
end

-- Vrai si ces réglages ne recadrent pas : tout le fichier, sans angle.
local function cadreNeutre(reglages)
    for cle, valeur in pairs(Recadrage.AUCUN) do
        if math.abs((valeurNumerique(reglages[cle]) or valeur) - valeur) > 1e-6 then
            return false
        end
    end
    return true
end

-- Avant l'image entière d'apercu (entier) : les refus, avant toute écriture, et ce que la réponse
-- en dira, lu avant d'écrire : l'état de la photo, son cadre vu dans l'image entière et les
-- dimensions de cette image.
local function preparerEntier(photo, params)
    if params.comparer or params.point_af then
        echouer("entier (l'image entière, sans son cadre) ne va ni avec comparer ni avec point_af : rien n'a été rendu.")
    end
    local actuels = photo:getDevelopSettings()
    if Reglages.estAgrandie(actuels) then
        echouer(PHOTO_AGRANDIE)
    end
    local cadre, dimensions = cadreAffiche(photo, actuels)
    if not dimensions and not cadreNeutre(actuels) then
        echouer("Dimensions de la photo inconnues : son cadre ne peut pas se lire dans l'image entière ; rien n'a été écrit.")
    end
    return { actuels = actuels, cadre = cadre, dimensions = dimensions }
end

-- L'image entière, sans son cadre (apercu avec entier) : comme le premier rendu du recalage, le
-- cadre retiré et la case « Contraindre le recadrage » décochée le temps du rendu, puis remis, même
-- si le rendu échoue ; l'Historique de Lightroom garde les deux étapes « Claude · composition ».
-- Une photo ni recadrée ni contrainte se rend telle quelle, sans écriture. La pause et la
-- protection des photos (copies virtuelles seulement, libellé protégé, photos rejetées) n'arrêtent
-- que les écritures : elles ne sont vérifiées que s'il faut écrire. Comme pour une proposition
-- (essayer), une photo protégée ne reçoit aucune écriture, même le temps d'un rendu. Rend le
-- chemin, et faux si des réglages IA n'étaient pas encore calculés (comme rendre).
local function rendreEntier(photo, actuels, taille, params)
    local retire, retour = sansRecadrage(actuels)
    if next(retire) == nil then
        return rendre(photo, taille)
    end
    verifierPause(params)
    verifierProtection({ photo }, Preferences.lire(), { confirme = true }, 'read_composition')
    verifierRendable(photo)
    poser(photo, Rendu.ETAPE_ENTIERE, retire)
    local ok, chemin, calcules = LrTasks.pcall(rendre, photo, taille)
    poser(photo, Rendu.ETAPE_ENTIERE_RETOUR, retour)
    if not ok then
        error(chemin, 0)
    end
    return chemin, calcules
end

-- L'image entière d'une proposition de recadrage (essayer avec entier), après le rendu de la
-- proposition : d'abord le cadre que Lightroom a gardé, relu (case « Contraindre le recadrage »
-- cochée, il le resserre lui-même, un instant après l'écriture : le rendu a pris ce temps-là,
-- comme le constate relireCadres), puis l'image entière, ce cadre retiré, dans une troisième étape
-- « Claude · essai : image entière ». Le cadre est relu avant : un rendu entier qui échoue (ou son
-- écriture) n'empêche ni la proposition ni le cadre, seulement le dessin, et la remarque le dit.
-- Rend le cadre gardé (nil si Lightroom n'en garde aucun), les dimensions de l'image affichée
-- entière, le chemin de l'image entière (nil si elle n'a pas pu se rendre) et les valeurs posées
-- le temps de ce rendu (essayer les remet avec la proposition).
local function rendreEntierPropose(photo, plan, taille)
    local relus = photo:getDevelopSettings()
    local cadre, dimensions = cadreAffiche(photo, relus)
    local retire = sansRecadrage(relus)
    local ok, chemin = LrTasks.pcall(function()
        if next(retire) ~= nil then
            poser(photo, Rendu.ETAPE_ESSAI_ENTIERE, retire)
        end
        return (rendre(photo, taille))
    end)
    if not ok then
        -- La raison sans l'emplacement d'une erreur Lua ni son point final (« … occupé : réessayer
        -- dans un instant. ; le cadre… » se lirait mal).
        local raison = Liaison.messageErreur(chemin):gsub('%.+$', '')
        noter(plan, "Image entière non rendue : " .. raison .. " ; le cadre n'est pas dessiné.")
        chemin = nil
    end
    return cadre, dimensions, chemin, retire
end

-- Les valeurs à poser le temps du rendu d'une comparaison, selon le mode : l'état d'avant la
-- première retouche de Claude (avantClaude), ou d'avant sa dernière étape (etapePrecedente, et
-- toute autre valeur ; versionClaude, la version de Claude d'un exercice « Je le fais », est
-- retiré au correctif 1.3.6).
local function valeursAComparer(photo, comparer)
    if comparer == 'avantClaude' then
        return lireJson(photo, 'avantClaude', {})
    end
    local etapes = lireJson(photo, 'etapesClaude', {})
    return etapes[#etapes] and etapes[#etapes].avant or {}
end

-- Comparaison : rend l'état d'avant (avant la première retouche de Claude, ou avant la dernière),
-- en l'appliquant le temps du rendu, puis remet les valeurs actuelles. Rend le chemin, et vrai si
-- un traitement calculé n'a pas pu être défait.
local function rendreAvant(photo, comparer, taille, params)
    verifierPause(params)
    local valeurs = valeursAComparer(photo, comparer)
    valeurs = pourLightroom(valeurs)
    -- Un traitement calculé (Amelioration, Suppression) ne se défait pas le temps d'un rendu.
    local ameliore = valeurs.Amelioration ~= nil or valeurs.Suppression ~= nil
    local classee = valeurs.Bibliotheque ~= nil
    valeurs.Amelioration = nil
    valeurs.Suppression = nil
    valeurs.Bibliotheque = nil
    if next(valeurs) == nil then
        if classee and not ameliore then
            echouer("La retouche à comparer ne touche que la Bibliothèque (note, drapeau, libellé, mots-clés…) : rien ne change à l'image.")
        end
        if ameliore then
            echouer("La retouche à comparer est un traitement calculé par Lightroom (débruitage, détails bruts, super résolution, reflets) : "
                .. "la comparaison ne peut pas le défaire le temps d'un rendu. Comparer plutôt deux zooms (region), avant et après.")
        end
        echouer("Aucune retouche de Claude sur cette photo : rien à comparer.")
    end
    local actuels = photo:getDevelopSettings()
    -- Une liste de taches vide vide aussi RetouchInfo (aRemettre) : posée d'abord, pour que le
    -- retour remette RetouchInfo comme les autres clés posées.
    aRemettre(valeurs)
    local retour, liste = {}, {}
    for cle in pairs(valeurs) do
        liste[#liste + 1] = cle
    end
    for _, cle in ipairs(liste) do
        local actuel = actuels[cle]
        if actuel ~= nil then
            retour[cle] = pourLightroom(actuel)
        elseif type(valeurs[cle]) == 'table' then
            retour[cle] = {}
        elseif DEFAUTS[cle] ~= nil then
            retour[cle] = DEFAUTS[cle]
        else
            valeurs[cle] = nil
        end
    end
    aRemettre(retour)
    ecrire("Claude · comparaison (avant)", function()
        photo:applyDevelopSettings(libererProfil(valeurs), "Claude · comparaison (avant)")
    end)
    local ok, chemin = LrTasks.pcall(rendre, photo, taille)
    ecrire("Claude · comparaison (retour)", function()
        photo:applyDevelopSettings(libererProfil(retour), "Claude · comparaison (retour)")
    end)
    if not ok then
        error(chemin, 0)
    end
    return chemin, ameliore
end

-- Géométrie des photos visées (commande « geometrie ») : correction active et son empreinte ; avec
-- `rendre`, les deux rendus du recalage. Voir Recalage.lua.
function Rendu.geometrie(params)
    local photos = params.photo and { photoVisee(params) } or photosVisees(params)
    local liste = Json.tableau()
    for _, photo in ipairs(photos) do
        local actuels = photo:getDevelopSettings()
        local info = { photo = photo.localIdentifier, active = geometrieActive(actuels), transformation = transformationActive(actuels) }
        if info.active then
            info.empreinte = empreinteGeometrie(photo, actuels)
            if params.rendre then
                verifierPause(params)
                info.chemin_corrige, info.chemin_origine = rendreGeometrie(photo, actuels, tonumber(params.taille) or 2048)
                -- Relue après les rendus : celle de la géométrie qu'ils montrent.
                info.empreinte = empreinteGeometrie(photo, photo:getDevelopSettings())
            end
        end
        liste[#liste + 1] = info
    end
    return { photos = liste }
end

function Rendu.apercu(params)
    local photo = photoVisee(params)
    local taille = tonumber(params.taille) or 1568
    -- L'image entière, sans son cadre (entier, read_composition) : refusée avant toute écriture
    -- avec comparer, point_af, sur une photo agrandie et, s'il faut écrire, en pause ou sur une
    -- photo protégée ; le cadre actuel et les dimensions lus avant d'écrire.
    local entier
    if params.entier == true then
        entier = preparerEntier(photo, params)
    end
    local cheminAvant, ameliore
    if params.comparer then
        cheminAvant, ameliore = rendreAvant(photo, params.comparer, taille, params)
    end
    -- La vue de l'avant/après des étapes (1.3) : l'image entière de l'état actuel, rendue après le
    -- retour d'une comparaison ; ni un zoom (taille 0, pleine résolution), ni l'image entière sans
    -- cadre (entier), ni l'image d'avant (chemin_avant). Empreinte relue après le rendu : un état
    -- changé pendant le rendu n'est pas gardé ; une image à qui manquent des calculs IA (a_savoir)
    -- non plus : elle ne montre pas l'état.
    local empreinteVue
    if taille > 0 and not entier then
        local lu, empreinte = LrTasks.pcall(Etapes.avantVue, photo, params)
        empreinteVue = lu and empreinte or nil
    end
    local chemin, calcules
    if entier then
        chemin, calcules = rendreEntier(photo, entier.actuels, taille, params)
    else
        chemin, calcules = rendre(photo, taille)
    end
    if empreinteVue and calcules ~= false then
        LrTasks.pcall(Etapes.garderVue, photo, chemin, empreinteVue)
    end
    local valeurs, infos = lireReglages(photo, params.cles, false)
    infos.chemin = chemin
    infos.chemin_avant = cheminAvant
    -- Composition lue : l'image rendue est l'image entière (toujours dit, même sans recadrage) ;
    -- ses dimensions (image affichée entière, en pixels) et le cadre actuel vu dans cette image
    -- (absent sans recadrage), que le serveur emploie pour ramener les points de view_photo.
    if entier then
        infos.image_entiere = true
        infos.dimensions = entier.dimensions
        infos.cadre_actuel = entier.cadre
    end
    if ameliore then
        infos.remarque_comparaison = "L'image d'avant garde le débruitage, les détails bruts, la super résolution ou la suppression des reflets : la comparaison ne défait pas ces traitements calculés."
    end
    if calcules == false then
        infos.a_savoir = "Lightroom n'avait pas fini de calculer les réglages IA de cette photo (masques IA, profil adaptatif) : l'aperçu peut les montrer incomplets. "
            .. "Pour les calculer : afficher la photo dans le module Développement et cliquer « Mettre à jour » (panneau Masquage, ou Réglages de base pour un profil adaptatif), puis refaire l'aperçu."
    end
    -- point_af (view_photo) : le chemin de l'original et la géométrie, où le serveur lit le point
    -- de mise au point (Fujifilm), dessiné sur l'image pour noter, ou en tout temps si
    -- l'utilisateur le veut.
    if params.point_af then
        infos.photo = Vignettes.decrireVignette(photo)
        infos.point_af_toujours = Preferences.lire().pointMiseAuPoint == true
        -- L'évaluation de Claude gardée dans le registre (notation.json) : une photo déjà évaluée
        -- ne se renote pas à chaque retouche.
        infos.evaluation = Notation.resume(photo.localIdentifier)
        -- Bilan de view_photo (1.2) : les étapes de Claude gardées pour la photo, pour que le
        -- serveur dise ce qui a changé (ou a été défait) depuis l'aperçu précédent. Lecture seule.
        local etapes = lireJson(photo, 'etapesClaude', {})
        infos.etapes_claude = {
            nombre = #etapes,
            derniere = etapes[#etapes] and etapes[#etapes].nom or Json.null,
        }
    else
        infos.photo = decrire(photo, true)
    end
    if Photos.originalAbsent(photo) then
        infos.original = "Introuvable (disque débranché, ou fichier déplacé) : aperçu rendu depuis l'aperçu dynamique, "
            .. "2560 px au plus. Le débruitage, la suppression des reflets et la livraison attendent l'original."
    end
    infos.reglages = valeurs
    -- Ce que l'utilisateur a changé à la main depuis la dernière commande de Claude.
    infos.corrections_utilisateur = Ecriture.correctionsUtilisateur(photo)
    Liaison.noter("Aperçu de " .. infos.photo.fichier .. " envoyé à Claude")
    return infos
end

-- Proposition visuelle : applique, rend, puis remet la photo comme avant. Rien n'est mémorisé ni
-- journalisé ; l'Historique de Lightroom garde les deux étapes. Avec instantane (compare_variants),
-- la proposition est aussi rangée en instantané (Variantes.ranger). Avec entier (Composition lue,
-- 1.3) et un recadrage proposé (pas retiré) : aussi l'image entière de la proposition, sans son
-- cadre (troisième étape « Claude · essai : image entière »), et le cadre que Lightroom a gardé
-- (cadre_propose), même si cette image ne se rend pas. essayer n'est pas une étape : Etapes.lua
-- n'en garde pas d'avant/après. (L'exercice « Je le fais », exercice et sans_rendu, est retiré au
-- correctif 1.3.6.) Avec temoin (un rendu témoin du connecteur : la carte d'un masque, le masque de
-- Lightroom de generative_edit), aucun accord n'est demandé ; taille 0 rend en pleine résolution ; et,
-- pour des masques, les personnes précises que Lightroom n'a pas reconnues sont dites
-- (personnes_non_reconnues, comme Retouche.verifierPersonnes, sans rien retirer : rien n'est gardé).
function Rendu.essayer(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    local photo = photoVisee(params)
    -- Une proposition écrit le temps d'un rendu : une photo protégée n'en reçoit pas non plus. Le
    -- plafond ne compte pas (une photo, rien de gardé).
    verifierProtection({ photo }, prefs, { confirme = true }, 'preview_settings')
    local plan
    if params.action == 'masquer' then
        plan = preparerMasques(photo, params)
    elseif params.action == 'retoucher' then
        plan = preparerTaches(photo, params)
    else
        plan = preparer(photo, params, prefs)
    end
    if params.rotation then
        noter(plan, "La rotation de 90° n'est pas montrée dans une proposition : apply_settings la fait.")
    end
    local taille = tonumber(params.taille) or 1344
    -- L'image entière d'une proposition de recadrage (preview_settings y dessine le cadre gardé) :
    -- seulement pour l'action appliquer avec un recadrage proposé, jamais pour un recadrage retiré
    -- (rien à dessiner).
    local entier = params.entier == true and params.action ~= 'masquer' and params.action ~= 'retoucher'
        and type(params.recadrage) == 'table' and params.recadrage.retirer ~= true
    local cadrePropose, dimensionsEntiere, cheminEntier, cadreRetire
    local cheminActuel, personnesNonReconnues
    if params.comparer then
        cheminActuel = rendre(photo, taille)
    end
    local etape = nomEtape(params, "proposition", "Claude · essai : ")
    local chemin, instantane
    if aDesChangements(plan) then
        for cle in pairs(plan.nouveaux) do
            if plan.avant[cle] == nil then
                noter(plan, cle .. " n'avait pas de valeur : il garde celle de la proposition.")
            end
        end
        ecrire(etape, function()
            appliquerPlan(plan, etape)
        end)
        -- Tout ce qui suit l'application, jusqu'à la remise de la photo, est protégé : une erreur
        -- (écriture refusée par Lightroom occupé, instantané impossible) laisserait sinon la photo
        -- dans l'état de la proposition, sans mémoire pour la défaire.
        local ok, resultat = LrTasks.pcall(function()
            calculerIA({ plan })
            -- Un rendu témoin d'un masque : une personne précise que Lightroom n'a pas reconnue est
            -- dite (le connecteur refuse alors le masque de Fibo 2), en lecture seule.
            if params.temoin == true and params.action == 'masquer' and type(plan.personnes) == 'table' and #plan.personnes > 0 then
                local liste = pourLightroom(photo:getDevelopSettings().MaskGroupBasedCorrections or {})
                local nonReconnues = Plans.lirePersonnes(plan, liste)
                if #nonReconnues > 0 then
                    personnesNonReconnues = {}
                    for _, p in ipairs(nonReconnues) do
                        personnesNonReconnues[#personnesNonReconnues + 1] = { numero = p.numero, trouvees = p.trouvees, masque = p.nom }
                        noter(plan, string.format("Lightroom n'a pas reconnu la personne %d (sur %d trouvées par Vision) dans le masque « %s ».",
                            p.numero, p.trouvees, p.nom))
                    end
                end
            end
            -- Un profil qui ne tient pas : ses autres orthographes, puis la remarque ; le rendu montre
            -- ce que Lightroom a gardé.
            local voulu = plan.profilVoulu
            if voulu then
                local suivi = { photo = photo, voulu = voulu }
                attendreProfils({ suivi })
                if not suivi.garde then
                    local garde, pose, relus, essayes = essayerVariantes(photo, voulu, etape, suivi.relus)
                    if garde then
                        noter(plan, string.format("Profil « %s » posé sous le nom que Lightroom lui donne pour cet appareil : « %s ».", voulu.nom, pose))
                    else
                        noter(plan, texteProfilRefuse(voulu, relus, essayes)
                            .. " ; le rendu le montre ainsi, et apply_settings ne l'appliquerait pas.")
                    end
                end
            end
            -- Une variante (compare_variants) : rangée en instantané avant le rendu et le retour.
            if params.instantane then
                local cles = {}
                for cle in pairs(plan.avant) do cles[cle] = true end
                for cle in pairs(plan.nouveaux) do cles[cle] = true end
                instantane = Variantes.ranger(photo, params.instantane, cles)
            end
            local rendu = rendre(photo, taille)
            if entier then
                cadrePropose, dimensionsEntiere, cheminEntier, cadreRetire = rendreEntierPropose(photo, plan, taille)
            end
            return rendu
        end)
        local remise = aRemettre(pourLightroom(plan.avant))
        -- Le cadre retiré pour l'image entière : chaque valeur posée que la proposition ne touchait
        -- pas reprend celle d'avant l'essai (CropConstrainToWarp compris, que Lightroom ne coche
        -- pas de lui-même), sinon sa valeur par défaut.
        for cle in pairs(cadreRetire or {}) do
            if remise[cle] == nil then
                local actuel = plan.actuels[cle]
                if actuel ~= nil then
                    remise[cle] = pourLightroom(actuel)
                else
                    remise[cle] = DEFAUTS[cle]
                end
            end
        end
        ecrire("Claude · fin de l'essai", function()
            photo:applyDevelopSettings(libererProfil(remise), "Claude · fin de l'essai")
        end)
        local probleme = verifierProfilsRemis({ { photo = photo, reglages = remise } })[photo.localIdentifier]
        if probleme then
            noter(plan, probleme)
        end
        if not ok then
            error(resultat, 0)
        end
        chemin = resultat
    else
        noter(plan, "Rien ne changerait : la proposition est l'état actuel.")
        if params.instantane then
            instantane = Variantes.ranger(photo, params.instantane, {})
        end
        chemin = rendre(photo, taille)
    end
    Liaison.noter("Proposition montrée à Claude : " .. etape, photo.localIdentifier)
    -- Accord véritable : l'utilisateur répond dans la fenêtre de la liaison (Accepter ou Refuser).
    -- Jamais pour un rendu témoin (temoin : la carte d'un masque d'add_mask, le masque de Lightroom
    -- de generative_edit) : rien n'en est gardé ni proposé, et une demande d'accord effacerait celui
    -- qu'attend la commande suivante.
    if prefs.mode == 'proposer' and prefs.accordDansLightroom and not params.instantane and params.temoin ~= true then
        local lignes = {}
        for i, changement in ipairs(plan.changements) do
            if i <= 6 then
                lignes[#lignes + 1] = tostring(changement.cle) .. " → " .. tostring(changement.apres)
            end
        end
        local outils = { masquer = 'add_mask', retoucher = 'retouch_spots' }
        Liaison.demanderAccord(outils[params.action] or 'apply_settings', etape, table.concat(lignes, "\n"))
    end
    local reponse = {
        mode = modeTexte(prefs),
        photo = decrire(photo, false),
        etape = etape,
        chemin = chemin,
        chemin_actuel = cheminActuel,
        instantane = instantane,
        changements = plan.changements,
        remarques = plan.notes,
        -- Composition lue : l'image entière (absente si elle n'a pas pu se rendre : la remarque le
        -- dit), le cadre gardé par Lightroom vu dans cette image (Recadrage.lire : absent s'il n'en
        -- garde aucun) et les dimensions de l'image affichée entière.
        chemin_entier = cheminEntier,
        cadre_propose = cadrePropose,
        dimensions = dimensionsEntiere,
        personnes_non_reconnues = personnesNonReconnues,
    }
    return reponse
end

Rendu.rendre = rendre

return Rendu
