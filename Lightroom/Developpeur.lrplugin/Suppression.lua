-- Suppression.lua : suppression des reflets (Suppression des distractions › Reflets), calculée
-- par Lightroom sur ce Mac (commande supprimer), et sa remise à l'annulation.
--
-- Relevé dans le code de Lightroom Classic 15.6 (LrDevelopController, compilé, lu en lecture
-- seule), voir docs/SPEC.md, Suppression des reflets :
--   toggleReflectionRemoval(intensite, qualite, rappel, argument) : module Développement ; sans
--     filtre dereflect sur la photo, vérifie l'intensité (−100 à 100) et la qualité ('preview',
--     'standard', 'best'), puis lance le calcul en arrière-plan, et appelle rappel(argument) à la
--     fin ; avec le filtre, le retire. Ne fait rien, sans erreur, si la photo n'est pas chargée en
--     pleine qualité ou si Lightroom ne le permet pas pour elle (supportsDereflectFilter) ;
--   changeReflectionRemovalAmount(intensite) : seulement si le filtre est là ; constaté le 17
--     octobre 2026 qu'il ne change pas le filtre rangé (rien après 3 minutes) : le module retire
--     le filtre, puis le repose à la nouvelle intensité ;
--   hasFilterWithName(nom), resetFilterWithName(nom) : module Développement ;
--   goToRemove(), getReflectionRemovalPanelState() (outil Supprimer ouvert) : checkboxState,
--     amount, quality, enabled (pleine qualité), isSupported ; getSelectedTool, selectTool.
-- Comme le débruitage, ces fonctions agissent sur la photo affichée dans le module Développement
-- (Amelioration.afficherEnDeveloppement), hors de withWriteAccessDo. L'état d'avant va dans la
-- mémoire sous la clé Suppression, qui n'est pas un réglage, écrite avant le calcul.

local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'

local Amelioration = require 'Amelioration'
local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Locaux = require 'Locaux'
local Photos = require 'Photos'
local Plans = require 'Plans'
local Preferences = require 'Preferences'
local Reglages = require 'Reglages'

local garder, lireJson = Photos.garder, Photos.lireJson
local nomFichier, photoVisee = Photos.nomFichier, Photos.photoVisee
local egal, pourLightroom = Reglages.egal, Reglages.pourLightroom
local noter = Plans.noter
local ajouterJournal, creerInstantane = Ecriture.ajouterJournal, Ecriture.creerInstantane
local ecrire, ecrireMemoire = Ecriture.ecrire, Ecriture.ecrireMemoire
local modeTexte, nouvelleEtape = Ecriture.modeTexte, Ecriture.nouvelleEtape
local nomEtape, resultatsPlans = Ecriture.nomEtape, Ecriture.resultatsPlans
local sansRetouche, verifierAccord, verifierPause = Ecriture.sansRetouche, Ecriture.verifierAccord, Ecriture.verifierPause
local verifierProtection = Ecriture.verifierProtection
local afficherEnDeveloppement, avecVerrou = Amelioration.afficherEnDeveloppement, Amelioration.avecVerrou
local remettreVue = Amelioration.remettreVue

local Suppression = {}

local function echouer(message)
    error(message, 0)
end

local FILTRE = 'dereflect'
Suppression.QUALITES = { preview = true, standard = true, best = true }
local DUREE_CALCUL = 180   -- secondes de calcul au plus
local PAUSE = 0.5

local function controleur()
    local ok, module = pcall(import, 'LrDevelopController')
    if not ok or type(module) ~= 'table' or type(module.toggleReflectionRemoval) ~= 'function'
        or type(module.hasFilterWithName) ~= 'function' or type(module.getEnhancePanelState) ~= 'function' then
        echouer("Lightroom " .. tostring(LrApplication.versionString()) .. " n'offre pas aux modules la suppression des reflets : il faut Lightroom Classic 15 ou plus récent.")
    end
    return module
end

-- Le filtre des reflets dans FilterList, tel que Lightroom Classic 15.6 le range (relevé le
-- 17 octobre 2026 sur une copie d'essai) : Name = 'Reflections', FilterID = 3, Title =
-- '$$$/CRaw/Filter/ReflectionRemoval/FilterPanelTitle=Reflection Removal', avec
-- EnableDistractionRemoval = true dans les réglages ; ou nil.
local function filtreReflets(reglages)
    local liste = type(reglages.FilterList) == 'table' and reglages.FilterList.Filters
    for _, filtre in ipairs(type(liste) == 'table' and liste or {}) do
        if type(filtre) == 'table' and (filtre.Name == 'Reflections'
            or tostring(filtre.Title or ''):find('ReflectionRemoval', 1, true)) then
            return filtre
        end
    end
    return nil
end

-- Intensité rangée dans le filtre : le premier BlendParams de son image, une fraction « n/d »
-- (relevé : 858993459/1073741824 = 0,8 pour une intensité de 80).
function Suppression.intensite(filtre)
    local image = type(filtre) == 'table' and type(filtre.Images) == 'table' and filtre.Images[1]
    local melange = type(image) == 'table' and type(image.BlendParams) == 'table' and image.BlendParams[1]
    local n, d = tostring(melange or ''):match('^(%-?%d+)/(%d+)$')
    if not n or tonumber(d) == 0 then
        return nil
    end
    return math.floor(tonumber(n) / tonumber(d) * 100 + 0.5)
end

-- État des reflets de la photo affichée : actif, et l'intensité rangée.
local function etatReflets(photo, dc)
    local ok, actif = LrTasks.pcall(dc.hasFilterWithName, FILTRE)
    local filtre = filtreReflets(photo:getDevelopSettings())
    if not ok then
        actif = filtre ~= nil
    end
    return { actif = actif == true, intensite = Suppression.intensite(filtre) }
end

local function memoire(etat)
    return { reflets = etat.actif, intensite = etat.intensite }
end

local function valeurReflets(etat)
    if not etat.actif then
        return 0
    end
    return etat.intensite or "oui"
end

-- Panneau Reflets de l'outil Supprimer : ouvert le temps de savoir si Lightroom permet la
-- suppression des reflets pour cette photo (isSupported, enabled) ; l'outil d'avant est remis.
local function panneauReflets(dc)
    if type(dc.goToRemove) ~= 'function' or type(dc.getReflectionRemovalPanelState) ~= 'function' then
        return nil
    end
    local outil
    if type(dc.getSelectedTool) == 'function' then
        local ok, nom = LrTasks.pcall(dc.getSelectedTool)
        outil = ok and nom or nil
    end
    local etat
    if LrTasks.pcall(dc.goToRemove) then
        local ok, valeur = LrTasks.pcall(dc.getReflectionRemovalPanelState)
        etat = ok and type(valeur) == 'table' and valeur or nil
    end
    if type(dc.selectTool) == 'function' then
        LrTasks.pcall(dc.selectTool, (outil and outil ~= 'dust') and outil or 'loupe')
    end
    return etat
end

-- Lance le changement voulu sur la photo affichée et attend que Lightroom l'ait rangé : l'état
-- voulu et FilterList changé, deux fois de suite. Renvoie s'il est fini, la raison sinon, et si
-- Lightroom l'a accepté.
local function lancer(photo, dc, voulu, avant)
    if voulu.actif and avant.actif then
        -- Autre intensité : retirer le filtre, puis le reposer.
        local retire, raison, lance = lancer(photo, dc, { actif = false }, avant)
        if not retire then
            return false, raison, lance
        end
        return lancer(photo, dc, voulu, { actif = false })
    end
    local filtresAvant = pourLightroom(photo:getDevelopSettings().FilterList)
    local fin = {}
    local ok, erreur
    if voulu.actif then
        ok, erreur = LrTasks.pcall(dc.toggleReflectionRemoval, voulu.intensite, voulu.qualite, function() fin.rappel = true end, nil)
    elseif type(dc.resetFilterWithName) == 'function' then
        ok, erreur = LrTasks.pcall(dc.resetFilterWithName, FILTRE)
    else
        ok, erreur = LrTasks.pcall(dc.toggleReflectionRemoval, nil, nil, function() fin.rappel = true end, nil)
    end
    if not ok then
        return false, "Lightroom refuse : " .. (tostring(Liaison.messageErreur(erreur)):gsub('%.+$', '')), false
    end
    local stables = 0
    local debut = LrDate.currentTime()
    repeat
        LrTasks.sleep(PAUSE)
        local etat = etatReflets(photo, dc)
        local fini = etat.actif == voulu.actif
            and not egal(photo:getDevelopSettings().FilterList, filtresAvant)
            and (not voulu.actif or not voulu.intensite or not etat.intensite or etat.intensite == voulu.intensite)
        stables = fini and stables + 1 or 0
        if stables >= 2 then
            return true, nil, true
        end
    until LrDate.currentTime() - debut > DUREE_CALCUL
    return false, string.format("Lightroom calcule encore après %d minutes", DUREE_CALCUL / 60), true
end

-- Le changement voulu est-il déjà l'état de la photo ?
local function dejaFait(etat, voulu)
    return etat.actif == voulu.actif and (not voulu.actif or not voulu.intensite or etat.intensite == voulu.intensite)
end

-- La suppression des reflets demandée, sur la photo affichée. La mémoire est écrite avant le
-- calcul, et remise telle qu'elle était si Lightroom n'a rien lancé.
local function supprimerAffichee(photo, dc, voulu, vue, etape, prefs, params, plan)
    local avant = etatReflets(photo, dc)
    plan.apres = memoire(avant)
    if dejaFait(avant, voulu) then
        noter(plan, "Rien à changer pour les reflets : c'est déjà l'état de la photo.")
        return
    end
    if voulu.actif and not avant.actif then
        local panneau = panneauReflets(dc)
        if panneau and panneau.isSupported == false then
            noter(plan, "Lightroom ne permet pas la suppression des reflets sur cette photo.")
            return
        end
        if (panneau and panneau.enabled == false) or not vue.pret then
            noter(plan, Amelioration.PAS_PRETE .. ".")
            return
        end
    end

    local champs, precedent = { 'avantClaude', 'etapesClaude', 'journalClaude', 'retoucheeParClaude', 'proprietaireMemoire' }, {}
    for _, champ in ipairs(champs) do
        precedent[champ] = photo:getPropertyForPlugin(_PLUGIN, champ)
    end
    local original = lireJson(photo, 'avantClaude', {})
    local premiere = sansRetouche(original)
    local etapes = lireJson(photo, 'etapesClaude', {})
    if original.Suppression == nil then
        original.Suppression = memoire(avant)
    end
    -- L'étape et son id (1.3) : repris par resultatsPlans (etape_id de la réponse) et le journal.
    local etapeId = nouvelleEtape(etapes, etape, { Suppression = memoire(avant) })
    plan.etapeId = etapeId
    if premiere and prefs.instantane then
        ecrire(etape, function() creerInstantane(photo) end)
    end
    -- Mémoire seule : écriture privée, hors de Édition › Annuler (Lightroom écrit l'étape du calcul).
    ecrireMemoire(etape, function()
        garder(photo, 'avantClaude', Json.encode(original))
        garder(photo, 'etapesClaude', Json.encode(Json.tableau(etapes)))
        garder(photo, 'retoucheeParClaude', 'oui')
    end)

    local fait, raison, lance = lancer(photo, dc, voulu, avant)
    if not fait then
        noter(plan, "Reflets : " .. raison .. ".")
    end
    local apres = etatReflets(photo, dc)
    plan.apres = memoire(apres)
    if valeurReflets(avant) ~= valeurReflets(apres) then
        plan.changements[#plan.changements + 1] = { cle = 'Suppression.reflets', avant = valeurReflets(avant), apres = valeurReflets(apres) }
    end
    if not lance or dejaFait(avant, apres) then
        if lance then
            noter(plan, "Lightroom n'a pas changé les reflets de cette photo (photo pas prise en charge, ou pas chargée en pleine qualité).")
        end
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
    local journal = lireJson(photo, 'journalClaude', {})
    ajouterJournal(journal, { etape = etape, etape_id = etapeId, type = 'retouche', raison = params.raison, changements = plan.changements })
    ecrireMemoire(etape, function()
        garder(photo, 'journalClaude', Json.encode(Json.tableau(journal)))
    end)
end

-- Poussière du capteur (Suppression des distractions › Poussière) : le module ne fait que la
-- retirer (la liste des filtres sans elle ; l'étape garde FilterList d'avant : undo_last le remet).
-- Constaté dans Lightroom Classic 15.6 (18 octobre 2026) : aucune fonction du SDK ne la lance ;
-- un filtre « Dust Removal » posé sans résultat est refusé sans ses cadres (« Invalid parameters for
-- constructing an AgRect »), puis vidé par Lightroom avec eux ; copié d'une autre photo, il est gardé
-- tel quel quand les réglages se ressemblent et colle les taches de la source (le Coller de
-- Lightroom, lui, invalide la référence et refait la recherche).
local function supprimerPoussiere(photo, demande, etape, prefs, params)
    local plan = Plans.nouveauPlan(photo)
    local actuel = Locaux.filtrePoussiere(plan.actuels)
    if demande.actif ~= false then
        echouer("Lightroom ne cherche la poussière que dans son interface (Supprimer › Poussière) : un module ne peut pas la lancer.")
    end
    if not actuel then
        noter(plan, "Pas de suppression de la poussière sur cette photo : rien à retirer.")
        return plan
    end
    plan.nouveaux.FilterList = Locaux.avecFiltrePoussiere(plan.actuels.FilterList, nil)
    plan.avant.FilterList = pourLightroom(plan.actuels.FilterList) or {}
    plan.changements[#plan.changements + 1] = { cle = 'Suppression.poussiere', avant = "appliquée", apres = "retirée" }
    Ecriture.ecrirePlans({ plan }, etape, prefs, params)
    Ecriture.noterEtatFinal({ photo }, etape)
    return plan
end

-- Suppression des reflets (commande « supprimer ») : reflets = {actif, intensite (1 à 100),
-- qualite ('preview', 'standard', 'best')} ; poussiere = {actif}. Voir l'en-tête de ce fichier.
function Suppression.supprimer(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'remove_distractions')
    if type(params.poussiere) == 'table' and type(params.reflets) ~= 'table' then
        local photo = photoVisee(params)
        verifierProtection({ photo }, prefs, params, 'remove_distractions')
        local etape = nomEtape(params, "poussière")
        local plan = supprimerPoussiere(photo, params.poussiere, etape, prefs, params)
        return { mode = modeTexte(prefs), resultats = resultatsPlans({ plan }, etape, params) }
    end
    local demande = type(params.reflets) == 'table' and params.reflets or nil
    if not demande then
        echouer("Rien à supprimer : reflets ou poussiere.")
    end
    local voulu = { actif = demande.actif ~= false, intensite = tonumber(demande.intensite), qualite = demande.qualite }
    if voulu.intensite and (voulu.intensite < 1 or voulu.intensite > 100) then
        echouer("Intensité des reflets : de 1 à 100.")
    end
    if voulu.qualite ~= nil and not Suppression.QUALITES[voulu.qualite] then
        echouer("Qualité des reflets : preview, standard ou best.")
    end
    local dc = controleur()
    local photo = photoVisee(params)
    Photos.exigerOriginal(photo, "La suppression des reflets se calcule sur l'original : rien n'a été fait.")
    verifierProtection({ photo }, prefs, params, 'remove_distractions')
    local etape = nomEtape(params, "reflets")
    local plan = { photo = photo, changements = Json.tableau(), notes = Json.tableau() }
    avecVerrou(function()
        local vue = afficherEnDeveloppement(photo, dc)
        local ok, erreur = LrTasks.pcall(supprimerAffichee, photo, dc, voulu, vue, etape, prefs, params, plan)
        remettreVue(vue)
        if not ok then
            error(erreur, 0)
        end
    end)
    if #plan.changements > 0 then
        Ecriture.noterEtatFinal({ photo }, etape)
    end
    local resultats = resultatsPlans({ plan }, etape, params)
    resultats[1].reflets = plan.apres
    Liaison.noter("Reflets : " .. etape .. " sur " .. nomFichier(photo))
    return { mode = modeTexte(prefs), resultats = resultats }
end

-- Remet l'état des reflets gardé en mémoire (annulation, retour à l'origine). Échoue si
-- Lightroom ne suit pas.
function Suppression.remettre(photo, voulue)
    if type(voulue) ~= 'table' or voulue.reflets == nil then
        return
    end
    avecVerrou(function()
        local dc = controleur()
        local vue = afficherEnDeveloppement(photo, dc)
        local ok, erreur = LrTasks.pcall(function()
            local voulu = { actif = voulue.reflets == true, intensite = tonumber(voulue.intensite) }
            local avant = etatReflets(photo, dc)
            if dejaFait(avant, voulu) then
                return
            end
            if voulu.actif and not avant.actif and not vue.pret then
                echouer(string.format("Lightroom n'a pas remis la suppression des reflets (%s) : %s.", nomFichier(photo), Amelioration.PAS_PRETE))
            end
            local fait, raison = lancer(photo, dc, voulu, avant)
            if not fait then
                echouer(string.format("Lightroom n'a pas remis les reflets comme avant (%s) : %s.", nomFichier(photo), raison))
            end
        end)
        remettreVue(vue)
        if not ok then
            error(erreur, 0)
        end
    end)
end

return Suppression
