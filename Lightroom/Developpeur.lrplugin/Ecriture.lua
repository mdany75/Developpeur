-- Ecriture.lua : l'écriture dans le catalogue (toujours par withWriteAccessDo, dans ecrire),
-- les étapes et le journal de Claude, l'application des plans et la réponse des commandes
-- d'écriture.
--
-- Identité des étapes (1.3, « Pourquoi ? ») : chaque étape de Claude reçoit un identifiant
-- (idEtape), gardé dans la mémoire (etapesClaude : { id, nom, avant, le }), dans l'entrée du
-- journal (etape_id) et dans la réponse de la commande (etape_id de chaque résultat, null sans
-- étape). Toute étape se crée par nouvelleEtape. La fenêtre Claude relie ainsi une ligne du fil, sa
-- raison et l'avant/après gardé par Etapes.lua. Une étape d'avant la 1.3, sans id, reste lisible :
-- l'annulation dépile toujours par rang.

local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'

local Json = require 'Json'
local Liaison = require 'Liaison'
local Locaux = require 'Locaux'
local Photos = require 'Photos'
local Plans = require 'Plans'
local Recadrage = require 'Recadrage'
local Reglages = require 'Reglages'

local brut, catalogue, decrire = Photos.brut, Photos.catalogue, Photos.decrire
local dimensionsAffichees, garder = Photos.dimensionsAffichees, Photos.garder
local lireJson, nomFichier, orientationAffichage = Photos.lireJson, Photos.nomFichier, Photos.orientationAffichage
local libelle = Photos.libelle
local afficher, CLES_CADRE = Reglages.afficher, Reglages.CLES_CADRE
local clesBalance, libererProfil = Reglages.clesBalance, Reglages.libererProfil
local cumulerRotation, valeurActuelle = Reglages.cumulerRotation, Reglages.valeurActuelle
local egalReglage = Reglages.egal
local aDesChangements, cadreARecadrer = Plans.aDesChangements, Plans.cadreARecadrer
local noter = Plans.noter

local Ecriture = {}

local function echouer(message)
    error(message, 0)
end

local MAX_ETAPES = 20
local MAX_JOURNAL = 200

-- Identifiant d'une étape : un texte unique (Lightroom n'a pas de générateur d'UUID), l'heure, un
-- tirage et un compteur, comme Conversation.identifiant. Il sert aussi de nom de fichier
-- (Etapes/<uuid>/<id>-avant.jpg) : seulement des chiffres hexadécimaux et des tirets.
local compteurEtapes = 0

local function idEtape()
    compteurEtapes = compteurEtapes + 1
    return string.format('%X-%04X-%d', math.floor(LrDate.currentTime()), math.random(0, 0xFFFF), compteurEtapes)
end

-- Ajoute une étape à la mémoire de la photo (liste etapesClaude lue par lireJson) : { id, nom,
-- avant (valeurs remplacées), le (LrDate) }, les MAX_ETAPES dernières seulement. Rend son id.
local function nouvelleEtape(etapes, nom, avant)
    local id = idEtape()
    etapes[#etapes + 1] = { id = id, nom = nom, avant = avant, le = LrDate.currentTime() }
    while #etapes > MAX_ETAPES do
        table.remove(etapes, 1)
    end
    return id
end

local function horodatage()
    local ok, texte = pcall(LrDate.timeToUserFormat, LrDate.currentTime(), '%Y-%m-%d %H:%M')
    return ok and texte or ''
end

local function ajouterJournal(journal, entree)
    entree.date = horodatage()
    journal[#journal + 1] = entree
    while #journal > MAX_JOURNAL do
        table.remove(journal, 1)
    end
end

-- createDevelopSnapshot attend Lightroom : sous pcall, il échouait sans bruit (« Yielding is not
-- allowed within a C or metamethod call », relevé dans le journal de Lightroom Classic 15.6).
-- nom : « Avant Claude » par défaut ; un instantané du même nom est remplacé.
local function creerInstantane(photo, nom)
    nom = nom or "Avant Claude"
    local ok, fonction = pcall(function() return photo.createDevelopSnapshot end)
    if ok and type(fonction) == 'function' then
        local cree, erreur = LrTasks.pcall(fonction, photo, nom, true)
        if not cree then
            Liaison.noter("Instantané « " .. nom .. " » non créé : " .. tostring(erreur))
        end
        return cree
    end
    return false
end

-- Écriture dans le catalogue : une seule étape d'annulation (⌘Z) pour toute la commande.
local function ecrire(nom, fonction)
    Photos.nouvelleEcriture()
    local statut = catalogue():withWriteAccessDo(nom, fonction, { timeout = 30 })
    if statut == 'aborted' then
        echouer("Lightroom est occupé (une autre opération écrit dans le catalogue) : réessayer dans un instant.")
    end
end

-- Écriture de la mémoire seule (champs du module, rien d'autre) : privée (withPrivateWriteAccessDo,
-- SDK 9.0), donc sans opération dans Édition › Annuler, comme noterEtatFinal. Une écriture
-- ordinaire pour la seule mémoire faisait qu'un ⌘Z de l'utilisateur défaisait d'abord cette
-- écriture invisible, avant la retouche (constaté en 2.1). Sans écriture privée (Lightroom ancien),
-- une écriture ordinaire.
local function ecrireMemoire(nom, fonction)
    local cat = catalogue()
    local ok, privee = pcall(function() return cat.withPrivateWriteAccessDo end)
    if not ok or type(privee) ~= 'function' then
        return ecrire(nom, fonction)
    end
    Photos.nouvelleEcriture()
    local statut = privee(cat, fonction, { timeout = 30 })
    if statut == 'aborted' then
        echouer("Lightroom est occupé (une autre opération écrit dans le catalogue) : réessayer dans un instant.")
    end
end

local function verifierPause(params)
    if Liaison.pause and not params.depuisLightroom then
        echouer("La liaison est en pause dans Lightroom : Claude peut regarder les photos mais pas les retoucher. Reprendre dans la fenêtre de suivi.")
    end
end

-- Vrai si la mémoire d'avant Claude ne porte aucune retouche du développement : un classement
-- (note, mots-clés…, clé Bibliotheque) ne compte pas pour l'instantané « Avant Claude ».
local function sansRetouche(original)
    for cle in pairs(original) do
        if cle ~= 'Bibliotheque' then
            return false
        end
    end
    return true
end

-- Accord véritable (préférence « Confirmer dans Lightroom ») : en mode « Proposer d'abord »,
-- l'accord se donne dans la fenêtre de suivi (bouton Accepter), hors de Claude ; confirm = true
-- ne suffit pas. Un accord vaut pour une écriture, dans les 10 minutes.
local DUREE_ACCORD = 600

-- Comment rappeler l'outil une fois l'accord donné : propose_ratings n'a pas de confirm, apply =
-- true y vaut accord.
local function rappel(outil)
    if outil == 'propose_ratings' then
        return "propose_ratings avec apply = true"
    end
    return outil .. " avec confirm = true"
end

local function accordDansLightroom(prefs, params, outil)
    if prefs.mode ~= 'proposer' or not prefs.accordDansLightroom or params.depuisLightroom then
        return
    end
    local accord = Liaison.accord
    if accord and accord.accepte and LrDate.currentTime() - accord.le < DUREE_ACCORD then
        Liaison.accord = nil
        return
    end
    if accord and accord.accepte == false then
        Liaison.accord = nil
        echouer("L'utilisateur a refusé la proposition dans la fenêtre de suivi de Lightroom : rien n'a été écrit. Lui demander ce qu'il veut changer.")
    end
    -- La raison donnée par Claude s'affiche avec la proposition, dans la fenêtre de suivi.
    Liaison.demanderAccord(outil, params.etape, type(params.raison) == 'string' and params.raison ~= '' and params.raison or nil)
    echouer(Liaison.EN_ATTENTE .. " : rien n'a été écrit. L'utilisateur accepte la proposition dans la fenêtre de suivi "
        .. "de Lightroom (bouton Accepter, ouverte pour lui) ; ensuite, rappeler " .. rappel(outil) .. ".")
end

local function verifierAccord(prefs, params, outil)
    if prefs.mode == 'proposer' and not params.confirme then
        echouer("Mode « Proposer d'abord » actif dans Lightroom : rien n'a été appliqué. Présenter ces valeurs à l'utilisateur (preview_settings, ou preview = true, lui montre le rendu), attendre son accord, puis rappeler "
            .. outil .. " avec confirm = true.")
    end
    accordDansLightroom(prefs, params, outil)
end

-- Garde-fous des photos (Gestionnaire de modules externes) : plafond de photos par écriture (sans
-- accord explicite, confirm = true), copies virtuelles seulement, libellé de couleur protégé,
-- photos rejetées protégées. Toutes les commandes qui écrivent sur des photos y passent
-- (propositions comprises : elles écrivent le temps d'un rendu) ; annuler et revenir non, qui
-- défont ce que Claude a fait.
local function verifierProtection(photos, prefs, params, outil)
    local plafond = tonumber(prefs.plafondPhotos) or 0
    if plafond > 0 and #photos > plafond and not params.confirme then
        echouer(string.format("%d photos visées : plus que le plafond de %d par écriture (Gestionnaire de modules externes). Rien n'a été écrit. "
            .. "Dire à l'utilisateur combien de photos seraient touchées, attendre son accord explicite, puis rappeler %s avec confirm = true.",
            #photos, plafond, outil))
    end
    local refusees = {}
    for _, photo in ipairs(photos) do
        local raison
        if prefs.copiesSeulement and brut(photo, 'isVirtualCopy') ~= true then
            raison = "pas une copie virtuelle"
        elseif prefs.libelleProtege and prefs.libelleProtege ~= 'aucun' and libelle(photo) == prefs.libelleProtege then
            raison = "libellé " .. prefs.libelleProtege .. " protégé"
        elseif prefs.rejeteesProtegees and tonumber(brut(photo, 'pickStatus')) == -1 then
            raison = "photo rejetée, protégée"
        end
        if raison then
            refusees[#refusees + 1] = nomFichier(photo) .. " (" .. raison .. ")"
        end
    end
    if #refusees > 0 then
        echouer("Photos protégées dans Lightroom (Gestionnaire de modules externes) : rien n'a été écrit. "
            .. table.concat(refusees, ", ") .. ". Les retoucher sur une copie virtuelle (create_virtual_copy), ou demander à l'utilisateur de lever la protection.")
    end
end

-- Balance personnalisée attendue à la fin du plan (photo, paramètre prédéfini de l'utilisateur,
-- puis réglages), à reposer après un paramètre prédéfini du module (voir noterPresetDuModule).
-- Un préréglage (Auto, Lumière du jour…) n'est pas une balance personnalisée : rien à reposer.
local function balanceAReposer(plan)
    if not plan.presetDuModule or plan.balanceMode then
        return nil
    end
    local cles = clesBalance(plan.raw)
    local noms = { 'WhiteBalance', cles[1], cles[2] }
    local balance = {}
    for _, source in ipairs({ plan.actuels, plan.balancePreset or {}, plan.nouveaux }) do
        for _, cle in ipairs(noms) do
            if source[cle] ~= nil then
                balance[cle] = source[cle]
            end
        end
    end
    if balance.WhiteBalance ~= 'Custom' then
        return nil
    end
    return balance
end

-- Applique un plan sur sa photo (dans une écriture) : paramètres prédéfinis, réglages, masques
-- IA, puis la balance personnalisée qu'un paramètre prédéfini du module a fait tomber.
local function appliquerPlan(plan, etape)
    local photo = plan.photo
    for _, preset in ipairs(plan.presets) do
        if preset == plan.presetUtilisateur and plan.quantitePreset then
            -- Quantité prédéfinie, en % (voir Plans.preparerPreset).
            photo:applyDevelopPreset(preset, _PLUGIN, plan.quantitePreset)
        else
            photo:applyDevelopPreset(preset, _PLUGIN)
        end
    end
    local balance = balanceAReposer(plan)
    local nouveaux = plan.nouveaux
    if balance and #plan.presetsApres == 0 then
        -- Avec les réglages : une seule étape de l'historique.
        nouveaux = {}
        for cle, valeur in pairs(plan.nouveaux) do
            nouveaux[cle] = valeur
        end
        for cle, valeur in pairs(balance) do
            nouveaux[cle] = valeur
        end
        balance = nil
    end
    if next(nouveaux) then
        photo:applyDevelopSettings(libererProfil(nouveaux), etape)
    end
    for _, preset in ipairs(plan.presetsApres) do
        photo:applyDevelopPreset(preset, _PLUGIN)
    end
    if balance then
        photo:applyDevelopSettings(balance, etape)
    end
end

-- Écrit les plans : instantané « Avant Claude » la première fois, mémoire des valeurs
-- remplacées, paramètre prédéfini puis réglages, journal. Une seule écriture pour toutes les
-- photos.
local function ecrirePlans(plans, etape, prefs, params)
    for _, plan in ipairs(plans) do
        plan.original = lireJson(plan.photo, 'avantClaude', {})
        plan.etapes = lireJson(plan.photo, 'etapesClaude', {})
        plan.journal = lireJson(plan.photo, 'journalClaude', {})
    end
    ecrire(etape, function()
        for _, plan in ipairs(plans) do
            if aDesChangements(plan) then
                if sansRetouche(plan.original) and prefs.instantane then
                    creerInstantane(plan.photo)
                end
                -- Instantané demandé, de l'état d'avant cette retouche (panneau Instantanés).
                if plan.instantane then
                    local nom = "Claude · " .. tostring(plan.instantane)
                    if creerInstantane(plan.photo, nom) then
                        noter(plan, "Instantané « " .. nom .. " » : l'état d'avant cette retouche (panneau Instantanés).")
                    end
                end
                for cle, valeur in pairs(plan.avant) do
                    if cle == 'Rotation' then
                        -- Les rotations s'additionnent jusqu'à l'état d'avant Claude.
                        plan.original.Rotation = cumulerRotation(plan.original.Rotation, valeur.quarts)
                    elseif plan.original[cle] == nil then
                        plan.original[cle] = valeur
                    end
                end
                plan.etapeId = nouvelleEtape(plan.etapes, etape, plan.avant)
                appliquerPlan(plan, etape)
                -- Gardée pour verifierProfils, qui peut retirer un profil que Lightroom n'a pas pris.
                plan.entreeJournal = { etape = etape, etape_id = plan.etapeId, type = 'retouche', raison = params.raison,
                    changements = plan.changements }
                ajouterJournal(plan.journal, plan.entreeJournal)
                garder(plan.photo, 'avantClaude', Json.encode(plan.original))
                garder(plan.photo, 'etapesClaude', Json.encode(Json.tableau(plan.etapes)))
                garder(plan.photo, 'journalClaude', Json.encode(Json.tableau(plan.journal)))
                garder(plan.photo, 'retoucheeParClaude', 'oui')
            end
        end
    end)
end

-- Réglages IA calculés par le SDK (Lightroom Classic 13.3 et suivants). Relevé dans le code de
-- Lightroom Classic 15.6 (LrPhoto, AgCameraRawBatchPixelMaskUpdate, SdkApplyDevelopPreset) :
-- photo:updateAISettings() lance la mise à jour que fait la case « Mettre à jour les photos
-- concernées » de la fenêtre « Mises à jour IA recommandées » (masques IA, profil adaptatif, flou
-- d'objectif, outil Supprimer, débruitage…), sans ouvrir de fenêtre, et ne rend la main qu'à la fin ;
-- elle écrit par une commande de Lightroom (étape d'historique « Mettre à jour les paramètres IA »),
-- pas dans withWriteAccessDo ; sans rien à mettre à jour, elle ne fait rien ; sans les modèles IA
-- téléchargés, elle n'en fait pas plus, sans erreur. photo:needsUpdateAISettings() dit s'il reste
-- à calculer. Le 4ᵉ argument d'applyDevelopPreset est ignoré pour un paramètre prédéfini du
-- module : la mise à jour vient donc après l'écriture. Ce qu'elle ne calcule pas (modèles IA absents)
-- ouvre au rendu la fenêtre « Mises à jour IA recommandées », qui attend la réponse de l'utilisateur.
local DUREE_CALCUL_IA = 90   -- secondes de calcul au plus par commande ; le reste attend le rendu

local function methode(objet, nom)
    local ok, fonction = pcall(function() return objet[nom] end)
    return ok and type(fonction) == 'function' and fonction or nil
end

local function adaptatif(reglages)
    return type(reglages.Look) == 'table' and reglages.Look.isAdobeAdaptive == true
end

-- Changements qui touchent un calcul IA de Lightroom : paramètres prédéfinis (masques IA, profil
-- adaptatif, flou d'objectif, ceux de l'utilisateur), masques, profil, taches, cadre et géométrie
-- (l'aide d'Adobe demande de mettre à jour un profil adaptatif après des taches, une rotation ou un
-- flou d'objectif).
local function toucheIA(plan)
    if #plan.presets > 0 or #plan.presetsApres > 0 then
        return true
    end
    for cle in pairs(plan.nouveaux) do
        if cle == 'MaskGroupBasedCorrections' or cle == 'Look' or cle == 'AILook' or cle == 'LensBlur' or cle == 'RetouchAreas'
            or cle == 'RemoveAreas' or cle == 'FilterList' or cle == 'DepthBasedCorrections' or cle:match('^Crop')
            or cle:match('^Perspective') or cle:match('^Lens') or cle:match('^Upright') then
            return true
        end
    end
    return false
end

-- Vrai si Lightroom dit qu'il reste à calculer pour la photo (faux sans needsUpdateAISettings).
local function aMettreAJour(photo)
    local besoin = methode(photo, 'needsUpdateAISettings')
    if not besoin then
        return false
    end
    local ok, oui = LrTasks.pcall(besoin, photo)
    return ok and oui == true
end

-- Met à jour les réglages IA d'une photo ; renvoie si c'est fait, la durée et la raison sinon.
-- Deux passages au plus : constaté le 17 octobre 2026, un flou d'objectif posé sur une photo à profil
-- adaptatif laissait encore un calcul en attente après le premier.
local function mettreAJourIA(photo)
    local mettreAJour = methode(photo, 'updateAISettings')
    if not mettreAJour then
        return false, 0, nil
    end
    local debut = LrDate.currentTime()
    local fait = false
    for _ = 1, 2 do
        local ok, erreur = LrTasks.pcall(mettreAJour, photo)
        if not ok then
            return false, LrDate.currentTime() - debut, Liaison.messageErreur(erreur)
        end
        fait = not Locaux.calculsEnAttente(photo:getDevelopSettings()) and not aMettreAJour(photo)
        if fait then
            break
        end
    end
    return fait, LrDate.currentTime() - debut, nil
end

-- Profil adaptatif d'une photo dont la retouche touche les taches, la rotation ou le flou d'objectif
-- (l'aide d'Adobe demande alors de le mettre à jour), relu après le calcul. Constaté dans Lightroom
-- Classic 15.6 (17 octobre 2026, copie d'essai RAW sous Adaptive Color) : après une tache ou un flou
-- d'objectif, updateAISettings le recalcule (InputDigest changé) ; après une rotation, il le laisse,
-- et le reposer de force redonne la même empreinte et le même calcul : Lightroom le calcule sur la
-- photo entière, avant le recadrage.
local function relireAdaptatif(plan, avant)
    local calcul = type(avant.AILook) == 'table' and avant.AILook or {}
    local recalcul = plan.photo:getDevelopSettings().AILook or {}
    if calcul.InputDigest == nil or recalcul.InputDigest ~= calcul.InputDigest then
        noter(plan, "Profil adaptatif recalculé par Lightroom pour cette retouche.")
    elseif plan.nouveaux.RetouchAreas == nil and plan.nouveaux.RemoveAreas == nil and plan.nouveaux.LensBlur == nil and #plan.presets == 0 then
        noter(plan, "Profil adaptatif inchangé : Lightroom le calcule sur la photo entière, avant le recadrage, qu'une rotation ne change pas.")
    else
        noter(plan, "Profil adaptatif pas recalculé par Lightroom pour cette retouche ; « Mettre à jour » dans Réglages de base le force à la main.")
    end
end

-- Après l'écriture des plans : les réglages IA de chaque photo que la retouche touche, calculés
-- tout de suite (DUREE_CALCUL_IA secondes au plus pour la commande), et le profil adaptatif relu.
local function calculerIA(plans)
    local debut = LrDate.currentTime()
    for _, plan in ipairs(plans) do
        local photo = plan.photo
        if methode(photo, 'updateAISettings') and aDesChangements(plan) and toucheIA(plan) then
            local avant = photo:getDevelopSettings()
            local lookPose = plan.lookParPreset or plan.nouveaux.Look ~= nil
            local perime = adaptatif(avant) and not lookPose and (plan.nouveaux.CropAngle ~= nil or plan.nouveaux.RetouchAreas ~= nil
                or plan.nouveaux.RemoveAreas ~= nil or plan.nouveaux.LensBlur ~= nil or #plan.presets > 0)
            -- needsUpdateAISettings peut ouvrir la photo : passé le délai, on ne le demande plus.
            local horsDelai = LrDate.currentTime() - debut > DUREE_CALCUL_IA
            if Locaux.calculsEnAttente(avant) or perime or (not horsDelai and aMettreAJour(photo)) then
                if horsDelai then
                    noter(plan, "Réglages IA laissés à Lightroom (trop de photos à calculer dans une commande) : il les calcule au prochain rendu, ou par « Mettre à jour » dans le module Développement.")
                else
                    local fait, duree, raison = mettreAJourIA(photo)
                    plan.calculIA = fait
                    Liaison.noter(string.format("Réglages IA de %s : %s en %.1f s", tostring(photo.localIdentifier),
                        fait and "calculés" or "pas calculés", duree))
                    if raison then
                        noter(plan, "Lightroom n'a pas mis à jour les réglages IA : " .. raison .. " ; il les calcule au prochain rendu.")
                    elseif not fait then
                        noter(plan, "Lightroom n'a pas encore calculé tous les réglages IA (calcul en cours, ou modèles IA à télécharger) : "
                            .. "il les calcule au prochain rendu, ou par « Mettre à jour » dans le module Développement ; au rendu, "
                            .. "la fenêtre « Mises à jour IA recommandées » peut s'ouvrir : y répondre Exporter, case « Mettre à jour » cochée.")
                    end
                    if perime then
                        relireAdaptatif(plan, avant)
                    end
                end
            end
        end
    end
end

-- Avant un rendu : ce que Lightroom dit rester à calculer pour la photo (masques IA, profil
-- adaptatif, flou d'objectif, ou des réglages faits à la main), calculé sans la fenêtre « Mises à
-- jour IA recommandées » que l'exportation ouvrirait. Comme la case cochée de cette fenêtre.
local function calculerAvantRendu(photo)
    if not methode(photo, 'updateAISettings') then
        return
    end
    if Locaux.calculsEnAttente(photo:getDevelopSettings()) or aMettreAJour(photo) then
        local fait, duree, raison = mettreAJourIA(photo)
        Liaison.noter(string.format("Réglages IA mis à jour avant le rendu : %s en %.1f s%s", fait and "calculés" or "pas calculés",
            duree, raison and (" (" .. raison .. ")") or ""))
    end
end

-- Réponse d'une commande d'écriture, et fenêtre de suivi.
local function resultatsPlans(plans, etape, params)
    local libelles = type(params.libelles) == 'table' and params.libelles or {}
    local resultats = Json.tableau()
    for _, plan in ipairs(plans) do
        local description = decrire(plan.photo, false)
        resultats[#resultats + 1] = {
            photo = description,
            etape = etape,
            -- L'étape écrite (ou complétée) pour cette photo ; null sans étape (rien n'a changé).
            etape_id = plan.etapeId or Json.null,
            changements = plan.changements,
            remarques = plan.notes,
        }
        if #plan.changements > 0 then
            local lignes = {}
            for _, changement in ipairs(plan.changements) do
                lignes[#lignes + 1] = string.format("%s : %s → %s", libelles[changement.cle] or changement.cle,
                    changement.avant == Json.null and "?" or afficher(changement.avant), afficher(changement.apres))
            end
            Liaison.dernierePhotoId = plan.photo.localIdentifier
            Liaison.dernierePhoto = description.fichier .. " — " .. etape
            Liaison.derniersReglages = table.concat(lignes, "\n")
        end
        Liaison.noter(string.format("%s : %d changement(s) sur %s", etape, #plan.changements, description.fichier), plan.photo.localIdentifier)
    end
    local total = 0
    for _, plan in ipairs(plans) do
        total = total + #plan.changements
    end
    if total > 0 then
        Liaison.retourVisuel(#plans > 1 and string.format("%s : %d changements sur %d photos", etape, total, #plans)
            or string.format("%s : %d changement%s", etape, total, total > 1 and "s" or ""))
    end
    return resultats
end

-- Le cadre que Lightroom a gardé, quand la case « Contraindre le recadrage » est cochée (voir
-- preparerContrainte) : il le resserre lui-même, peut-être un instant après l'écriture. La réponse
-- et le journal donnent celui-là, depuis la valeur d'avant l'étape.
local function relireCadres(plans)
    local suivis = {}
    for _, plan in ipairs(plans) do
        if plan.cadreContraint and aDesChangements(plan) then
            suivis[#suivis + 1] = plan
        end
    end
    local function ecrit(plan, cle)
        local valeur = plan.nouveaux[cle]
        if valeur == nil then
            valeur = valeurActuelle(plan.actuels, cle)
        end
        return valeur
    end
    local function relire(plan)
        plan.cadreRelu = plan.photo:getDevelopSettings()
        for _, cle in ipairs(CLES_CADRE) do
            if math.abs(valeurActuelle(plan.cadreRelu, cle) - ecrit(plan, cle)) > 1e-6 then
                return true
            end
        end
        return false
    end
    local attendre = false
    for _, plan in ipairs(suivis) do
        plan.cadreChange = relire(plan)
        attendre = attendre or not plan.cadreChange
    end
    if attendre then
        LrTasks.sleep(0.3)
        for _, plan in ipairs(suivis) do
            plan.cadreChange = plan.cadreChange or relire(plan)
        end
    end
    local journaux = {}
    for _, plan in ipairs(suivis) do
        if plan.cadreChange then
            local gardes = Json.tableau()
            for _, changement in ipairs(plan.changements) do
                if not changement.cle:match('^Crop') or changement.cle == 'CropConstrainToWarp' then
                    gardes[#gardes + 1] = changement
                end
            end
            for _, cle in ipairs(CLES_CADRE) do
                local avant, apres = valeurActuelle(plan.actuels, cle), valeurActuelle(plan.cadreRelu, cle)
                if math.abs(apres - avant) > 1e-6 then
                    local depuis = plan.avantEtape and tonumber(plan.avantEtape[cle]) or avant
                    gardes[#gardes + 1] = { cle = cle, avant = depuis, apres = apres }
                end
            end
            for i = #plan.changements, 1, -1 do
                plan.changements[i] = nil
            end
            for i, changement in ipairs(gardes) do
                plan.changements[i] = changement
            end
            -- Un cadre demandé sans grille sera placé ensuite (commande recadrer) : il le dira.
            local largeur, hauteur = dimensionsAffichees(plan.photo)
            local orientation = orientationAffichage(plan.photo, plan.raw, largeur, hauteur)
            local lu = largeur and hauteur and Recadrage.lire(plan.cadreRelu, largeur, hauteur, orientation)
            local aPlacer = plan.demandeRecadrage and not plan.demandeRecadrage.retirer and not plan.recadrageDansZone
            if lu and not aPlacer then
                noter(plan, string.format("Cadre resserré par Lightroom (« Contraindre le recadrage ») pour ne laisser aucun coin vide : "
                    .. "%d %% de la largeur de l'image, centré en (%s ; %s).", math.floor(lu.largeur / largeur * 100 + 0.5),
                    afficher(math.floor(lu.centre_x * 100 + 0.5) / 100), afficher(math.floor(lu.centre_y * 100 + 0.5) / 100)))
            end
            -- La dernière entrée du journal est celle de cette étape.
            local entree = plan.journal and plan.journal[#plan.journal]
            if type(entree) == 'table' then
                local liste = Json.tableau()
                for _, changement in ipairs(type(entree.changements) == 'table' and entree.changements or {}) do
                    if type(changement) ~= 'table' or not tostring(changement.cle):match('^Crop') or changement.cle == 'CropConstrainToWarp' then
                        liste[#liste + 1] = changement
                    end
                end
                for _, changement in ipairs(plan.changements) do
                    if changement.cle:match('^Crop') and changement.cle ~= 'CropConstrainToWarp' then
                        liste[#liste + 1] = changement
                    end
                end
                entree.changements = liste
                journaux[#journaux + 1] = plan
            end
        end
    end
    if #journaux > 0 then
        ecrireMemoire("Claude · journal", function()
            for _, plan in ipairs(journaux) do
                garder(plan.photo, 'journalClaude', Json.encode(Json.tableau(plan.journal)))
            end
        end)
    end
end

-- Photos dont le cadre demandé reste à placer sur la géométrie obtenue (voir cadreARecadrer) : le
-- serveur envoie ensuite « recadrer » pour elles ; etape_ecrite dit si la commande a écrit une
-- étape que « recadrer » doit compléter.
local function signalerARecadrer(plans, resultats)
    for i, plan in ipairs(plans) do
        if cadreARecadrer(plan) then
            resultats[i].a_recadrer = true
            resultats[i].etape_ecrite = aDesChangements(plan)
        end
    end
    return resultats
end

-- Complète la dernière étape de Claude, du même nom, par les changements des plans : valeurs
-- d'avant des réglages qu'elle ne touchait pas, réglages, entrée du journal (ses changements du
-- même réglage sont remplacés, depuis la valeur d'avant l'étape). Une photo dont la dernière étape
-- n'a pas ce nom reçoit une étape à part. L'étape complétée garde son id (plan.etapeId) ; une
-- étape d'avant la 1.3, sans id, en reçoit un.
local function completerEtapes(plans, etape, prefs, params)
    local suite, seules = {}, {}
    for _, plan in ipairs(plans) do
        plan.original = lireJson(plan.photo, 'avantClaude', {})
        plan.etapes = lireJson(plan.photo, 'etapesClaude', {})
        plan.journal = lireJson(plan.photo, 'journalClaude', {})
        local derniere = plan.etapes[#plan.etapes]
        if type(derniere) == 'table' and derniere.nom == etape and type(derniere.avant) == 'table' then
            suite[#suite + 1] = plan
        else
            seules[#seules + 1] = plan
        end
    end
    if #seules > 0 then
        ecrirePlans(seules, etape, prefs, params)
    end
    if #suite == 0 then
        return
    end
    ecrire(etape, function()
        for _, plan in ipairs(suite) do
            local derniere = plan.etapes[#plan.etapes]
            if type(derniere.id) ~= 'string' or derniere.id == '' then
                derniere.id = idEtape()
            end
            plan.etapeId = derniere.id
            plan.avantEtape = derniere.avant
            for cle, valeur in pairs(plan.avant) do
                if derniere.avant[cle] == nil then
                    derniere.avant[cle] = valeur
                end
                if plan.original[cle] == nil then
                    plan.original[cle] = valeur
                end
            end
            local nouveaux = {}
            for cle, valeur in pairs(plan.nouveaux) do
                nouveaux[cle] = valeur
            end
            plan.photo:applyDevelopSettings(nouveaux, etape)
            for _, changement in ipairs(plan.changements) do
                if derniere.avant[changement.cle] ~= nil then
                    changement.avant = derniere.avant[changement.cle]
                end
            end
            local entree = plan.journal[#plan.journal]
            if type(entree) == 'table' and entree.etape == etape then
                entree.etape_id = entree.etape_id or plan.etapeId
                local changements = Json.tableau()
                for _, changement in ipairs(type(entree.changements) == 'table' and entree.changements or {}) do
                    if type(changement) ~= 'table' or plan.nouveaux[changement.cle] == nil then
                        changements[#changements + 1] = changement
                    end
                end
                for _, changement in ipairs(plan.changements) do
                    changements[#changements + 1] = changement
                end
                entree.changements = changements
            else
                ajouterJournal(plan.journal, { etape = etape, etape_id = plan.etapeId, type = 'retouche', raison = params.raison,
                    changements = plan.changements })
            end
            garder(plan.photo, 'avantClaude', Json.encode(plan.original))
            garder(plan.photo, 'etapesClaude', Json.encode(Json.tableau(plan.etapes)))
            garder(plan.photo, 'journalClaude', Json.encode(Json.tableau(plan.journal)))
        end
    end)
end

-- Corrections de l'utilisateur après Claude ------------------------------------------------
--
-- À la fin de chaque commande qui écrit, la mémoire garde l'état où Claude a laissé la photo
-- (champ apresClaude) : le nom de l'étape, editCount et lastEditTime (métadonnées brutes, des
-- nombres : constaté dans Lightroom Classic 15.6) et les réglages simples (nombres, booléens,
-- quelques textes, et le nombre d'éléments des listes). Plus tard, si editCount ou lastEditTime ont
-- changé, la différence avec les réglages actuels dit ce que l'utilisateur a corrigé à la main.
-- Un réglage automatique pas encore calculé (−999999, après la tonalité automatique) n'en est pas,
-- ni ce que Lightroom résout lui-même peu après l'écriture (constaté le 18 octobre 2026 : le nom et
-- l'origine du profil d'objectif par défaut, des réglages absents qu'il ajoute).
local TEXTES_SUIVIS = { WhiteBalance = true, CameraProfile = true, ProcessVersion = true, ToneCurveName2012 = true,
    LensProfileSetup = true }
local NON_SUIVIS = { LensProfileIsEmbedded = true }
local LISTES_SUIVIES = { 'MaskGroupBasedCorrections', 'RetouchAreas', 'PointColors', 'RedEyeInfo', 'DepthBasedCorrections' }
local EN_ATTENTE = -999999

local function etatSimple(reglages)
    local etat = {}
    for cle, valeur in pairs(reglages) do
        if type(cle) == 'string' then
            if TEXTES_SUIVIS[cle] and type(valeur) == 'string' then
                etat[cle] = valeur
            elseif (type(valeur) == 'number' or type(valeur) == 'boolean') and not NON_SUIVIS[cle]
                and not cle:match('^Upright') and not cle:match('Digest$') and not cle:match('Version$') then
                etat[cle] = valeur
            end
        end
    end
    if type(reglages.Look) == 'table' and type(reglages.Look.Name) == 'string' then
        etat['Look.Name'] = reglages.Look.Name
    end
    for _, cle in ipairs(LISTES_SUIVIES) do
        etat['#' .. cle] = type(reglages[cle]) == 'table' and #reglages[cle] or 0
    end
    return etat
end

-- Garde l'état où la commande laisse ses photos. Une écriture de la mémoire seule, privée
-- (catalog:withPrivateWriteAccessDo, réservée aux champs du module) : une écriture ordinaire serait
-- une opération de plus dans Édition › Annuler, que ⌘Z défairait avant la retouche. Sans écriture
-- privée (Lightroom ancien), rien n'est gardé.
local function noterEtatFinal(photos, etape)
    local cat = catalogue()
    local ok, privee = pcall(function() return cat.withPrivateWriteAccessDo end)
    if not ok or type(privee) ~= 'function' then
        return
    end
    local suivies = {}
    for _, photo in ipairs(photos) do
        suivies[#suivies + 1] = { photo = photo, etat = {
            etape = etape,
            editCount = tonumber(brut(photo, 'editCount')),
            lastEditTime = tonumber(brut(photo, 'lastEditTime')),
            reglages = etatSimple(photo:getDevelopSettings()),
        } }
    end
    if #suivies == 0 then
        return
    end
    Photos.nouvelleEcriture()
    local fait, erreur = LrTasks.pcall(privee, cat, function()
        for _, suivie in ipairs(suivies) do
            garder(suivie.photo, 'apresClaude', Json.encode(suivie.etat))
        end
    end, { timeout = 30 })
    if not fait then
        Liaison.noter("État après Claude non gardé : " .. tostring(erreur))
    end
end

-- Ce que l'utilisateur a changé depuis la dernière commande de Claude sur la photo, ou nil :
-- {etape, changements = {cle, claude, maintenant}}.
local function correctionsUtilisateur(photo)
    local apres = lireJson(photo, 'apresClaude', nil)
    if type(apres) ~= 'table' or type(apres.reglages) ~= 'table' then
        return nil
    end
    if tonumber(brut(photo, 'editCount')) == tonumber(apres.editCount)
        and tonumber(brut(photo, 'lastEditTime')) == tonumber(apres.lastEditTime) then
        return nil
    end
    local maintenant = etatSimple(photo:getDevelopSettings())
    local cles, vues = {}, {}
    for _, source in ipairs({ apres.reglages, maintenant }) do
        for cle in pairs(source) do
            if not vues[cle] then
                vues[cle] = true
                cles[#cles + 1] = cle
            end
        end
    end
    table.sort(cles)
    local changements = Json.tableau()
    for _, cle in ipairs(cles) do
        local claude, actuel = apres.reglages[cle], maintenant[cle]
        if claude == Json.null then
            claude = nil
        end
        if claude ~= nil and claude ~= EN_ATTENTE and actuel ~= EN_ATTENTE and not egalReglage(claude, actuel) then
            changements[#changements + 1] = { cle = cle, claude = claude == nil and Json.null or claude,
                maintenant = actuel == nil and Json.null or actuel }
        end
    end
    if #changements == 0 then
        return nil
    end
    return { etape = apres.etape, changements = changements }
end

local function modeTexte(prefs)
    return prefs.mode == 'proposer' and "proposer d'abord" or "appliquer directement"
end

-- Nom d'étape donné par Claude, sans le préfixe « Claude · » que le module ajoute lui-même.
local function sansPrefixe(texte)
    local reste = tostring(texte)
    while true do
        local suite = reste:match('^%s*[Cc][Ll][Aa][Uu][Dd][Ee]%s*·%s*(.*)$')
        if not suite then
            return reste
        end
        reste = suite
    end
end

local function nomEtape(params, defaut, prefixe)
    local nom = sansPrefixe(params.etape or defaut)
    return (prefixe or "Claude · ") .. (nom ~= '' and nom or defaut)
end

Ecriture.ajouterJournal = ajouterJournal
Ecriture.appliquerPlan = appliquerPlan
Ecriture.calculerAvantRendu = calculerAvantRendu
Ecriture.calculerIA = calculerIA
Ecriture.completerEtapes = completerEtapes
Ecriture.correctionsUtilisateur = correctionsUtilisateur
Ecriture.noterEtatFinal = noterEtatFinal
Ecriture.creerInstantane = creerInstantane
Ecriture.ecrire = ecrire
Ecriture.ecrireMemoire = ecrireMemoire
Ecriture.ecrirePlans = ecrirePlans
Ecriture.idEtape = idEtape
Ecriture.MAX_ETAPES = MAX_ETAPES
Ecriture.nouvelleEtape = nouvelleEtape
Ecriture.modeTexte = modeTexte
Ecriture.nomEtape = nomEtape
Ecriture.relireCadres = relireCadres
Ecriture.resultatsPlans = resultatsPlans
Ecriture.signalerARecadrer = signalerARecadrer
Ecriture.sansRetouche = sansRetouche
Ecriture.verifierAccord = verifierAccord
Ecriture.accordDansLightroom = accordDansLightroom
Ecriture.verifierProtection = verifierProtection
Ecriture.verifierPause = verifierPause

return Ecriture
