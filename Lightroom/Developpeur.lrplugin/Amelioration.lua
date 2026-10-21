-- Amelioration.lua : débruitage, détails bruts et super résolution, calculés par Lightroom dans
-- le module Développement (commande ameliorer), et leur remise à l'annulation.
--
-- Débruitage, détails bruts et super résolution : Lightroom les calcule et range le résultat dans
-- FilterList, avec des données d'image ; aucun réglage ne peut les poser. Le module les lance par
-- LrDevelopController, comme un clic dans le panneau Amélioration. Relevé dans le code de
-- Lightroom Classic 15.6 :
--   setEnhance(nom, actif, intensite) : nom = 'denoise', 'rawDetails' ou 'superRes', intensité du
--     débruitage de 1 à 100 ; refus (assert) hors du module Développement, ou quand <nom>Enabled
--     est faux, avec la raison de Lightroom (<nom>InfoText) ; le calcul se fait en arrière-plan,
--     et son résultat arrive dans FilterList à la fin ;
--   getEnhancePanelState() : <nom>State, <nom>Enabled, <nom>InfoText, denoiseAmount ; nil hors
--     du module Développement ;
--   changeDenoiseAmount(intensite) : seulement si le débruitage est actif.
-- Ces fonctions agissent sur la photo affichée dans le module Développement : le module l'y
-- affiche, puis remet la vue d'avant. Elles passent hors de withWriteAccessDo (Lightroom écrit
-- lui-même son étape d'historique). L'état d'avant va dans la mémoire sous la clé Amelioration,
-- qui n'est pas un réglage : l'annulation et le retour à l'origine le remettent par les mêmes
-- fonctions.

local LrApplication = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'

local Bibliotheque = require 'Bibliotheque'
local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Photos = require 'Photos'
local Plans = require 'Plans'
local Preferences = require 'Preferences'
local Reglages = require 'Reglages'

local catalogue, decrire, garder = Photos.catalogue, Photos.decrire, Photos.garder
local lireJson, nomFichier, photoVisee = Photos.lireJson, Photos.nomFichier, Photos.photoVisee
local egal, pourLightroom = Reglages.egal, Reglages.pourLightroom
local noter = Plans.noter
local ajouterJournal, creerInstantane = Ecriture.ajouterJournal, Ecriture.creerInstantane
local ecrire, ecrireMemoire = Ecriture.ecrire, Ecriture.ecrireMemoire
local modeTexte, nouvelleEtape = Ecriture.modeTexte, Ecriture.nouvelleEtape
local nomEtape, resultatsPlans = Ecriture.nomEtape, Ecriture.resultatsPlans
local sansRetouche, verifierAccord, verifierPause = Ecriture.sansRetouche, Ecriture.verifierAccord, Ecriture.verifierPause
local verifierProtection = Ecriture.verifierProtection

local Amelioration = {}

local function echouer(message)
    error(message, 0)
end

local AMELIORATIONS = { 'denoise', 'rawDetails', 'superRes' }
-- Ordre de lancement : les détails bruts en dernier. Constaté dans Lightroom Classic 15.6 : le
-- débruitage et la super résolution les cochent aussi, les retirent avec eux, et Lightroom refuse
-- d'y toucher tant que l'un des deux est actif (« Appliqué automatiquement lors de l'utilisation
-- de la super-résolution ou de la réduction de bruit »).
local ORDRE_AMELIORATIONS = { 'denoise', 'superRes', 'rawDetails' }
local NOMS_AMELIORATION = { denoise = "le débruitage", rawDetails = "les détails bruts", superRes = "la super résolution" }
local DUREE_AFFICHAGE = 10        -- secondes pour que Lightroom affiche la photo dans le module Développement
local DELAI_CHARGEMENT = 1.5      -- secondes laissées au module Développement pour charger une autre photo
local DUREE_QUALITE = 20          -- secondes pour que Lightroom charge la photo en pleine qualité
local DUREE_AMELIORATION = 180    -- secondes de calcul au plus par traitement
local PAUSE_AMELIORATION = 0.5

-- Un traitement calculé à la fois (débruitage, détails bruts, super résolution, et la suppression
-- des reflets de Suppression.lua) : une deuxième commande (Claude qui réessaie après un délai
-- dépassé, le menu Revenir) trouverait la vue et la mémoire au milieu du premier.
local ameliorationEnCours = false

local function avecVerrou(fonction)
    if ameliorationEnCours then
        echouer("Lightroom calcule déjà un traitement pour Claude (débruitage, détails bruts, super résolution ou reflets) : réessayer quand ce sera fini.")
    end
    ameliorationEnCours = true
    local ok, erreur = LrTasks.pcall(fonction)
    ameliorationEnCours = false
    if not ok then
        error(erreur, 0)
    end
end

local function controleur()
    local ok, module = pcall(import, 'LrDevelopController')
    if not ok or type(module) ~= 'table' or type(module.setEnhance) ~= 'function' or type(module.getEnhancePanelState) ~= 'function' then
        echouer("Lightroom " .. tostring(LrApplication.versionString()) .. " n'offre pas aux modules le débruitage, les détails bruts ni la super résolution : il faut Lightroom Classic 15.3 ou plus récent.")
    end
    return module
end

-- État du panneau Amélioration de la photo affichée, ou nil hors du module Développement.
local function etatAmelioration(dc)
    local ok, etat = LrTasks.pcall(dc.getEnhancePanelState)
    if not ok or type(etat) ~= 'table' then
        return nil
    end
    return {
        denoise = etat.denoiseState == true,
        rawDetails = etat.rawDetailsState == true,
        superRes = etat.superResState == true,
        denoiseAmount = tonumber(etat.denoiseAmount),
        possibles = { denoise = etat.denoiseEnabled == true, rawDetails = etat.rawDetailsEnabled == true, superRes = etat.superResEnabled == true },
        raisons = { denoise = etat.denoiseInfoText, rawDetails = etat.rawDetailsInfoText, superRes = etat.superResInfoText },
        pret = etat.denoiseEnabled == true or etat.rawDetailsEnabled == true or etat.superResEnabled == true,
    }
end

-- Lightroom ne dit ce qui est possible qu'une fois la photo chargée en pleine qualité (relevé dans
-- DevelopEnhance : <nom>Enabled = negative:isFinalQuality() and …) : avant, les trois sont faux et
-- <nom>InfoText n'est que la description du traitement. Constaté dans Lightroom Classic 15.6 au
-- premier passage au module Développement après sa relance, sur une photo en super résolution.
-- Attend qu'un traitement au moins soit possible, delai secondes au plus.
local function etatPret(dc, delai)
    local debut = LrDate.currentTime()
    local etat = etatAmelioration(dc)
    while etat and not etat.pret and LrDate.currentTime() - debut < delai do
        LrTasks.sleep(0.25)
        etat = etatAmelioration(dc)
    end
    return etat
end

local PAS_PRETE = "Lightroom n'a pas chargé la photo en pleine qualité dans le module Développement (original hors ligne ?) : "
    .. "il ne permet encore aucun traitement"

-- Ce que la mémoire garde de cet état.
local function memoireAmelioration(etat)
    return { denoise = etat.denoise, rawDetails = etat.rawDetails, superRes = etat.superRes, denoiseAmount = etat.denoiseAmount }
end

-- Valeur montrée dans les changements : l'intensité du débruitage (0 = sans), oui ou non sinon.
local function valeurAmelioration(etat, nom)
    if nom == 'denoise' then
        return etat.denoise and (etat.denoiseAmount or "oui") or 0
    end
    return etat[nom] and "oui" or "non"
end

-- Les détails bruts sont imposés par un débruitage ou une super résolution actifs.
local function detailsImposes(etat, nom)
    return nom == 'rawDetails' and (etat.denoise or etat.superRes) and true or false
end

-- Le traitement est-il déjà dans l'état voulu ?
local function dejaFait(etat, nom, actif, intensite)
    return etat[nom] == actif and (nom ~= 'denoise' or not actif or not intensite or etat.denoiseAmount == intensite)
end

local function refusAmelioration(nom, etat)
    if not etat.pret then
        return PAS_PRETE .. "."
    end
    local raison = etat.raisons and etat.raisons[nom]
    return string.format("Lightroom ne permet pas %s sur cette photo%s", NOMS_AMELIORATION[nom],
        (type(raison) == 'string' and raison ~= '') and (" : " .. raison) or ".")
end

-- Remet la vue d'avant afficherEnDeveloppement : la source affichée, puis la photo active et la
-- sélection (Bibliotheque.remettreSelection : la sélection se refait le temps que Lightroom affiche
-- la source remise ; sans cette attente, la photo active d'avant ne revenait pas, constaté le
-- 21 octobre 2026), puis le module.
local function remettreVue(vue)
    if vue.sourceChangee or vue.selectionChangee then
        Bibliotheque.remettreSelection(vue.active, vue.selection, vue.sourceChangee and vue.sources or nil)
    end
    if vue.module and vue.module ~= 'develop' then
        LrTasks.pcall(LrApplicationView.switchToModule, vue.module)
    end
end

-- Affiche la photo, seule sélectionnée, dans le module Développement ; renvoie de quoi remettre
-- la vue d'avant (module, photo active, sélection, source affichée). Seule : avec plusieurs photos
-- sélectionnées et la synchronisation automatique, Lightroom pourrait appliquer le traitement à
-- toutes. Une photo hors du film fixe (autre dossier ou collection) fait afficher son dossier, le
-- temps du traitement, comme show_photo (Bibliotheque.selectionnerAvecSource).
local function afficherEnDeveloppement(photo, dc)
    local cat = catalogue()
    local vue = { module = LrApplicationView.getCurrentModuleName(), active = cat:getTargetPhoto(), selection = cat:getTargetPhotos() }
    if not vue.active or vue.active.localIdentifier ~= photo.localIdentifier or #(vue.selection or {}) > 1 then
        cat:setSelectedPhotos(photo, {})
        vue.selectionChangee = true
        local cible = cat:getTargetPhoto()
        if not cible or cible.localIdentifier ~= photo.localIdentifier then
            local _, changee, sources = Bibliotheque.selectionnerAvecSource({ photo })
            if changee then
                vue.sourceChangee, vue.sources = true, sources
            end
        end
    end
    if vue.module ~= 'develop' then
        LrApplicationView.switchToModule('develop')
    end
    -- Le module Développement met un moment à charger une autre photo : getEnhancePanelState
    -- donnerait encore l'état de la précédente.
    if vue.selectionChangee or vue.module ~= 'develop' then
        LrTasks.sleep(DELAI_CHARGEMENT)
    end
    local debut = LrDate.currentTime()
    repeat
        local cible, selection = cat:getTargetPhoto(), cat:getTargetPhotos()
        if cible and cible.localIdentifier == photo.localIdentifier and #selection == 1
            and LrApplicationView.getCurrentModuleName() == 'develop' and etatAmelioration(dc) then
            vue.pret = (etatPret(dc, DUREE_QUALITE) or {}).pret
            return vue
        end
        LrTasks.sleep(0.25)
    until LrDate.currentTime() - debut > DUREE_AFFICHAGE
    remettreVue(vue)
    echouer("Lightroom n'a pas affiché « " .. nomFichier(photo) .. " » dans le module Développement : elle n'est peut-être pas "
        .. "visible dans le film fixe (filtre, collection). L'y afficher, puis réessayer.")
end

-- Lance un traitement sur la photo affichée et attend que Lightroom l'ait rangé : l'état voulu
-- dans le panneau et FilterList changé (le résultat arrive à la fin du calcul), deux fois de
-- suite. Renvoie s'il est fini, la raison sinon, et si Lightroom l'a accepté.
local function lancerAmelioration(photo, dc, nom, actif, intensite)
    local filtresAvant = pourLightroom(photo:getDevelopSettings().FilterList)
    local avant = etatAmelioration(dc) or {}
    local ok, erreur
    if nom == 'denoise' and actif and avant.denoise then
        ok, erreur = LrTasks.pcall(dc.changeDenoiseAmount, intensite)
    else
        ok, erreur = LrTasks.pcall(dc.setEnhance, nom, actif, (actif and nom == 'denoise') and intensite or nil)
    end
    if not ok then
        -- Sans le point final de Lightroom : la raison est reprise dans une phrase.
        return false, "Lightroom refuse : " .. (tostring(Liaison.messageErreur(erreur)):gsub('%.+$', '')), false
    end
    local stables = 0
    local debut = LrDate.currentTime()
    repeat
        LrTasks.sleep(PAUSE_AMELIORATION)
        local etat = etatAmelioration(dc)
        local fini = etat ~= nil and etat[nom] == actif
            and not egal(photo:getDevelopSettings().FilterList, filtresAvant)
            and (nom ~= 'denoise' or not actif or not intensite or etat.denoiseAmount == intensite)
        stables = fini and stables + 1 or 0
        if stables >= 2 then
            return true, nil, true
        end
    until LrDate.currentTime() - debut > DUREE_AMELIORATION
    return false, string.format("Lightroom calcule encore après %d minutes", DUREE_AMELIORATION / 60), true
end

-- Remet l'état d'amélioration gardé en mémoire (annulation, retour à l'origine), pour les seuls
-- traitements que Claude a changés : d'abord ce qui doit être retiré, puis ce qui doit être
-- remis, les détails bruts en dernier (ORDRE_AMELIORATIONS). Des détails bruts qu'un traitement
-- resté actif impose restent avec lui. Échoue si Lightroom ne suit pas.
local function remettreAmelioration(photo, voulue)
    avecVerrou(function()
        local dc = controleur()
        local vue = afficherEnDeveloppement(photo, dc)
        local ok, erreur = LrTasks.pcall(function()
            for _, remettre in ipairs({ false, true }) do
                for _, nom in ipairs(ORDRE_AMELIORATIONS) do
                    if voulue[nom] ~= nil and (voulue[nom] == true) == remettre then
                        local etat = etatPret(dc, vue.pret and DUREE_QUALITE or 0) or {}
                        local intensite = nom == 'denoise' and tonumber(voulue.denoiseAmount) or nil
                        if not dejaFait(etat, nom, remettre, intensite) and not (not remettre and detailsImposes(etat, nom)) then
                            if not etat.pret then
                                echouer(string.format("Lightroom n'a pas remis %s comme avant (%s) : %s.", NOMS_AMELIORATION[nom], nomFichier(photo), PAS_PRETE))
                            end
                            local fait, raison = lancerAmelioration(photo, dc, nom, remettre, intensite)
                            if not fait then
                                echouer(string.format("Lightroom n'a pas remis %s comme avant (%s) : %s.", NOMS_AMELIORATION[nom], nomFichier(photo), raison))
                            end
                        end
                    end
                end
            end
        end)
        remettreVue(vue)
        if not ok then
            error(erreur, 0)
        end
    end)
end

-- État d'amélioration de la photo si elle est affichée dans le module Développement (seul cas où
-- Lightroom le donne).
local function ameliorationAffichee(photo)
    local cible = catalogue():getTargetPhoto()
    if not cible or cible.localIdentifier ~= photo.localIdentifier or LrApplicationView.getCurrentModuleName() ~= 'develop' then
        return nil
    end
    local ok, dc = pcall(import, 'LrDevelopController')
    if not ok or type(dc) ~= 'table' or type(dc.getEnhancePanelState) ~= 'function' then
        return nil
    end
    local etat = etatAmelioration(dc)
    return etat and memoireAmelioration(etat)
end

-- Les traitements demandés, sur la photo affichée dans le module Développement. La mémoire est
-- écrite avant de lancer le calcul : si l'écriture finale échouait, ou si Lightroom finissait après
-- le délai, la photo serait traitée sans étape à annuler. Elle ne garde que les traitements que
-- Claude change, et revient telle qu'elle était si Lightroom n'en a lancé aucun.
local function ameliorerAffichee(photo, dc, demandes, etape, prefs, params, plan)
    local avant = etatAmelioration(dc)
    if not avant then
        echouer("Lightroom ne donne pas l'état du panneau Amélioration de cette photo.")
    end
    plan.apres = memoireAmelioration(avant)
    local aFaire, retire = {}, false
    for _, nomOrdre in ipairs(ORDRE_AMELIORATIONS) do
        for _, demande in ipairs(demandes) do
            local nom, actif, intensite = tostring(demande.nom), demande.actif == true, tonumber(demande.intensite)
            if nom == nomOrdre then
                if dejaFait(avant, nom, actif, intensite) then
                    noter(plan, string.format("Rien à changer pour %s : c'est déjà l'état de la photo.", NOMS_AMELIORATION[nom]))
                else
                    aFaire[#aFaire + 1] = { nom = nom, actif = actif, intensite = intensite }
                    retire = retire or not actif
                end
            end
        end
    end
    -- Un traitement que Lightroom ne permet pas est refusé tout de suite, sauf si la commande en
    -- retire un autre, qui pourrait le rendre possible : il est alors jugé juste avant d'être lancé.
    local retenus = {}
    for _, traitement in ipairs(aFaire) do
        if traitement.actif and not avant.possibles[traitement.nom] and not retire then
            noter(plan, refusAmelioration(traitement.nom, avant))
        else
            retenus[#retenus + 1] = traitement
        end
    end
    if #retenus == 0 then
        return
    end

    local memoire = {}
    for _, traitement in ipairs(retenus) do
        memoire[traitement.nom] = avant[traitement.nom]
        if traitement.nom == 'denoise' then
            memoire.denoiseAmount = avant.denoiseAmount
        end
    end
    -- Tous les champs, propriétaire compris : garder efface la mémoire d'une autre photo.
    local champs, precedent = { 'avantClaude', 'etapesClaude', 'journalClaude', 'retoucheeParClaude', 'proprietaireMemoire' }, {}
    for _, champ in ipairs(champs) do
        precedent[champ] = photo:getPropertyForPlugin(_PLUGIN, champ)
    end
    local original = lireJson(photo, 'avantClaude', {})
    local premiere = sansRetouche(original)
    local etapes = lireJson(photo, 'etapesClaude', {})
    original.Amelioration = type(original.Amelioration) == 'table' and original.Amelioration or {}
    for cle, valeur in pairs(memoire) do
        if original.Amelioration[cle] == nil then
            original.Amelioration[cle] = valeur
        end
    end
    -- L'étape et son id (1.3) : repris par resultatsPlans (etape_id de la réponse) et le journal.
    local etapeId = nouvelleEtape(etapes, etape, { Amelioration = memoire })
    plan.etapeId = etapeId
    -- L'instantané demande une écriture ordinaire ; la mémoire, une écriture privée (hors de
    -- Édition › Annuler : Lightroom écrit lui-même l'étape du traitement).
    if premiere and prefs.instantane then
        ecrire(etape, function() creerInstantane(photo) end)
    end
    ecrireMemoire(etape, function()
        garder(photo, 'avantClaude', Json.encode(original))
        garder(photo, 'etapesClaude', Json.encode(Json.tableau(etapes)))
        garder(photo, 'retoucheeParClaude', 'oui')
    end)

    local lances = 0
    for _, traitement in ipairs(retenus) do
        local etat = etatPret(dc, avant.pret and DUREE_QUALITE or 0) or avant
        if dejaFait(etat, traitement.nom, traitement.actif, traitement.intensite) then
            -- Lightroom l'a fait de lui-même avec un traitement précédent (détails bruts).
        elseif not traitement.actif and detailsImposes(etat, traitement.nom) then
            noter(plan, "Les détails bruts restent : Lightroom les applique de lui-même avec le débruitage et la super résolution ; retirer ceux-ci les retire aussi.")
        elseif not etat.pret or (traitement.actif and not etat.possibles[traitement.nom]) then
            noter(plan, refusAmelioration(traitement.nom, etat))
        else
            local fait, raison, lance = lancerAmelioration(photo, dc, traitement.nom, traitement.actif, traitement.intensite)
            if lance then
                lances = lances + 1
            end
            if not fait then
                noter(plan, string.format("%s : %s.", (NOMS_AMELIORATION[traitement.nom]:gsub('^%l', string.upper)), raison))
            end
        end
    end
    local apres = etatAmelioration(dc) or avant
    plan.apres = memoireAmelioration(apres)
    for _, nom in ipairs(AMELIORATIONS) do
        local avantValeur, apresValeur = valeurAmelioration(avant, nom), valeurAmelioration(apres, nom)
        if avantValeur ~= apresValeur then
            plan.changements[#plan.changements + 1] = { cle = 'Amelioration.' .. nom, avant = avantValeur, apres = apresValeur }
        end
    end
    if lances == 0 then
        -- Par la liste des champs : pairs sauterait ceux qui étaient vides (nil).
        ecrireMemoire("Claude · rien lancé", function()
            for _, champ in ipairs(champs) do
                photo:setPropertyForPlugin(_PLUGIN, champ, precedent[champ])
            end
        end)
        -- Plus d'étape : la réponse n'en porte pas.
        plan.etapeId = nil
        return
    end
    -- Ce que Lightroom a changé de lui-même avec les traitements demandés (constaté dans Lightroom
    -- Classic 15.6 : le débruitage coche aussi les détails bruts) va aussi dans la mémoire.
    local ajouts = {}
    for _, nom in ipairs(AMELIORATIONS) do
        if memoire[nom] == nil and avant[nom] ~= apres[nom] then
            ajouts[nom] = avant[nom]
        end
    end
    if next(ajouts) then
        original = lireJson(photo, 'avantClaude', {})
        etapes = lireJson(photo, 'etapesClaude', {})
        local derniere = etapes[#etapes]
        if derniere and derniere.id == etapeId and type(derniere.avant) == 'table' and type(derniere.avant.Amelioration) == 'table' then
            for cle, valeur in pairs(ajouts) do
                derniere.avant.Amelioration[cle] = valeur
            end
        end
        original.Amelioration = type(original.Amelioration) == 'table' and original.Amelioration or {}
        for cle, valeur in pairs(ajouts) do
            if original.Amelioration[cle] == nil then
                original.Amelioration[cle] = valeur
            end
        end
    end
    local journal = lireJson(photo, 'journalClaude', {})
    ajouterJournal(journal, { etape = etape, etape_id = etapeId, type = 'retouche', raison = params.raison, changements = plan.changements })
    ecrireMemoire(etape, function()
        garder(photo, 'journalClaude', Json.encode(Json.tableau(journal)))
        if next(ajouts) then
            garder(photo, 'avantClaude', Json.encode(original))
            garder(photo, 'etapesClaude', Json.encode(Json.tableau(etapes)))
        end
    end)
end

-- Débruitage, détails bruts et super résolution (commande « ameliorer »), un traitement après
-- l'autre, chacun attendu jusqu'au bout. Voir l'en-tête de ce fichier.
function Amelioration.ameliorer(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'enhance_photo')
    local demandes = type(params.ameliorations) == 'table' and params.ameliorations or {}
    if #demandes == 0 then
        echouer("Aucun traitement demandé : débruitage, détails bruts ou super résolution.")
    end
    for _, demande in ipairs(demandes) do
        if not NOMS_AMELIORATION[tostring(demande.nom)] then
            echouer("Traitement inconnu : " .. tostring(demande.nom))
        end
    end
    local dc = controleur()
    local photo = photoVisee(params)
    Photos.exigerOriginal(photo, "Le débruitage, les détails bruts et la super résolution se calculent sur l'original : rien n'a été fait.")
    verifierProtection({ photo }, prefs, params, 'enhance_photo')
    local etape = nomEtape(params, "amélioration")
    local plan = { photo = photo, changements = Json.tableau(), notes = Json.tableau() }
    avecVerrou(function()
        local vue = afficherEnDeveloppement(photo, dc)
        local ok, erreur = LrTasks.pcall(ameliorerAffichee, photo, dc, demandes, etape, prefs, params, plan)
        remettreVue(vue)
        if not ok then
            error(erreur, 0)
        end
    end)
    if #plan.changements > 0 then
        Ecriture.noterEtatFinal({ photo }, etape)
    end
    local resultats = resultatsPlans({ plan }, etape, params)
    resultats[1].amelioration = plan.apres
    return { mode = modeTexte(prefs), resultats = resultats }
end

Amelioration.afficherEnDeveloppement = afficherEnDeveloppement
Amelioration.ameliorationAffichee = ameliorationAffichee
Amelioration.avecVerrou = avecVerrou
Amelioration.PAS_PRETE = PAS_PRETE
Amelioration.remettre = remettreAmelioration
Amelioration.remettreVue = remettreVue

return Amelioration
