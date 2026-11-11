-- Suppression.lua : suppression des reflets (Suppression des distractions › Reflets), calculée
-- par Lightroom sur ce Mac, et des passants (› Personnes, Lightroom Classic 16, remplissage
-- génératif d'Adobe) (commande supprimer), et leur remise à l'annulation.
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
-- mémoire sous la clé Suppression ({reflets, intensite} et {personnes, filtre, filtres}), qui
-- n'est pas un réglage, écrite avant le calcul.
--
-- Passants (relevé dans le code de Lightroom Classic 16.0, rien encore constaté par un module :
-- lectures défensives ; voir docs/SPEC.md, Passants) :
--   detectDistractingPeople() (outil Supprimer ouvert) ouvre la section Personnes ; la détection
--     suit en arrière-plan (modèle local), sans rappel de fin : le module l'attend par
--     countAllSpots('distractingPeopleRemoval') (supposé), ou en réessayant la suppression ;
--   applyRemovalOnDetectedDistractingPeople(rappel, argument) refuse « Detected distracting people
--     are already removed. » ou « No distracting people spots are present for removal. », sinon
--     lance la suppression en arrière-plan (fenêtre de progression annulable) et appelle
--     rappel(argument) à la fin ; le résultat est un filtre remove_people de FilterList (supposé :
--     le module tient pour fait tout filtre ajouté hors débruitage, reflets et poussière, et garde
--     son nom, filtre, et les noms d'avant, filtres, pour le retirer à l'annulation).

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
    original.Suppression = type(original.Suppression) == 'table' and original.Suppression or {}
    if original.Suppression.reflets == nil then
        original.Suppression.reflets, original.Suppression.intensite = avant.actif, avant.intensite
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

-- Passants (Suppression des distractions › Personnes) -------------------------------------------

Suppression.FILTRE_PERSONNES = 'remove_people'           -- nom pour hasFilterWithName (supposé ; rangé : « Distracting People Removal »)
Suppression.MODE_PERSONNES = 'distractingPeopleRemoval'  -- mode de countAllSpots (supposé)
Suppression.VERSION_PERSONNES = 16
Suppression.DUREE_DETECTION = 60     -- secondes d'attente de la détection au plus
Suppression.DUREE_PERSONNES = 240    -- secondes de suppression au plus
Suppression.ESSAI_SANS_COMPTE = 5    -- secondes entre deux essais quand le compte ne se lit pas
Suppression.ATTENTE_SANS_COMPTE = 20 -- secondes avant le premier essai quand le compte ne se lit pas
Suppression.DUREE_ZERO = 15          -- secondes d'un compte lisible resté à 0 : aucun passant
Suppression.DUREE_STABLE = 2         -- secondes d'un compte de passants inchangé : détection finie
local DEJA_RETIRES = 'already removed'
local AUCUN_PASSANT = 'No distracting people'

-- Noms de filtre des passants vus dans ce processus (le nom exact reste à constater).
local nomsAppris = {}

-- Le module LrDevelopController, s'il offre la suppression des passants (Lightroom Classic 16.0 ou
-- plus récent, et ses deux fonctions).
local function controleurPersonnes()
    local version = tostring(LrApplication.versionString())
    local majeure = tonumber(version:match('^(%d+)'))
    if majeure and majeure < Suppression.VERSION_PERSONNES then
        echouer("Lightroom " .. version .. " ne retire pas les passants pour un module : il faut Lightroom Classic 16.0 ou plus récent. Rien n'a été fait.")
    end
    local ok, module = pcall(import, 'LrDevelopController')
    if not ok or type(module) ~= 'table' or type(module.detectDistractingPeople) ~= 'function'
        or type(module.applyRemovalOnDetectedDistractingPeople) ~= 'function' or type(module.goToRemove) ~= 'function'
        or type(module.getEnhancePanelState) ~= 'function' then
        echouer("Lightroom " .. version .. " n'offre pas aux modules la suppression des passants (detectDistractingPeople, applyRemovalOnDetectedDistractingPeople) : rien n'a été fait. La faire à la main : Développement › Supprimer › Personnes.")
    end
    return module
end

-- Un filtre connu qui n'est pas celui des passants : débruitage (Enhance), reflets, poussière.
local function autreFiltre(filtre)
    local id = tonumber(filtre.FilterID)
    return filtre.Name == 'Enhance' or filtre.Name == 'Reflections' or filtre.Name == Locaux.NOM_POUSSIERE
        or id == 1 or id == 3 or id == 6
        or tostring(filtre.Title or ''):find('ReflectionRemoval', 1, true) ~= nil
end

local function dansListe(liste, nom)
    for _, element in ipairs(type(liste) == 'table' and liste or {}) do
        if element == nom then
            return true
        end
    end
    return false
end

-- Le filtre des passants dans FilterList, ou nil. Son nom exact reste à constater : remove_people
-- (relevé dans le code), un nom ou un titre qui parle de personnes, un nom déjà vu, ou ce que la
-- mémoire en garde (garde) : filtre, le nom rangé par Lightroom ; filtres, les noms des filtres
-- d'avant la suppression (un filtre ajouté depuis, hors débruitage, reflets et poussière).
function Suppression.filtrePersonnes(reglages, garde)
    local liste = type(reglages) == 'table' and type(reglages.FilterList) == 'table' and reglages.FilterList.Filters
    garde = type(garde) == 'table' and garde or {}
    for _, filtre in ipairs(type(liste) == 'table' and liste or {}) do
        if type(filtre) == 'table' then
            local brut = tostring(filtre.Name or '')
            local nom = brut:lower()
            local titre = tostring(filtre.Title or ''):lower()
            if nom == Suppression.FILTRE_PERSONNES or nom:find('people', 1, true) or titre:find('people', 1, true)
                or nomsAppris[brut] or (garde.filtre ~= nil and brut == garde.filtre)
                or (type(garde.filtres) == 'table' and not dansListe(garde.filtres, brut) and not autreFiltre(filtre)) then
                return filtre
            end
        end
    end
    return nil
end

-- FilterList sans le filtre des passants, les autres filtres (débruitage, reflets…) gardés.
function Suppression.sansPersonnes(filterList, garde)
    local filtres = {}
    local liste = type(filterList) == 'table' and filterList.Filters
    for _, filtre in ipairs(type(liste) == 'table' and liste or {}) do
        if not Suppression.filtrePersonnes({ FilterList = { Filters = { filtre } } }, garde) then
            filtres[#filtres + 1] = pourLightroom(filtre)
        end
    end
    if #filtres == 0 then
        return {}
    end
    return { Filters = filtres }
end

-- Noms des filtres d'une liste FilterList (tableau neuf).
local function nomsFiltres(filterList)
    local noms = {}
    local liste = type(filterList) == 'table' and filterList.Filters
    for _, filtre in ipairs(type(liste) == 'table' and liste or {}) do
        if type(filtre) == 'table' and filtre.Name ~= nil then
            noms[#noms + 1] = tostring(filtre.Name)
        end
    end
    return noms
end

-- Le filtre ajouté à FilterList depuis `noms` (les noms d'avant), hors des filtres connus, ou nil.
local function filtreAjoute(filterList, noms)
    local liste = type(filterList) == 'table' and filterList.Filters
    for _, filtre in ipairs(type(liste) == 'table' and liste or {}) do
        if type(filtre) == 'table' and not dansListe(noms, tostring(filtre.Name or '')) and not autreFiltre(filtre) then
            return filtre
        end
    end
    return nil
end

-- Ce que la mémoire garde du filtre des passants de la photo : l'étape la plus récente qui en
-- parle, sinon l'état d'avant Claude.
local function gardeMemoire(photo)
    local etapes = lireJson(photo, 'etapesClaude', {})
    for i = #etapes, 1, -1 do
        local s = type(etapes[i]) == 'table' and type(etapes[i].avant) == 'table' and etapes[i].avant.Suppression
        if type(s) == 'table' and (s.filtre ~= nil or type(s.filtres) == 'table') then
            return { filtre = s.filtre, filtres = s.filtres }
        end
    end
    local s = lireJson(photo, 'avantClaude', {}).Suppression
    if type(s) == 'table' then
        return { filtre = s.filtre, filtres = s.filtres }
    end
    return nil
end

-- État des passants de la photo affichée : retirés ou non.
local function etatPersonnes(photo, dc, garde)
    if Suppression.filtrePersonnes(photo:getDevelopSettings(), garde) then
        return { actif = true }
    end
    if type(dc.hasFilterWithName) == 'function' then
        local ok, actif = LrTasks.pcall(dc.hasFilterWithName, Suppression.FILTRE_PERSONNES)
        return { actif = ok and actif == true }
    end
    return { actif = false }
end

-- Passants détectés par Lightroom (nil : le compte ne se lit pas).
local function compterPersonnes(dc)
    if type(dc.countAllSpots) ~= 'function' then
        return nil
    end
    local ok, nombre = LrTasks.pcall(dc.countAllSpots, Suppression.MODE_PERSONNES)
    return ok and tonumber(nombre) or nil
end

local function outilActuel(dc)
    if type(dc.getSelectedTool) ~= 'function' then
        return nil
    end
    local ok, nom = LrTasks.pcall(dc.getSelectedTool)
    return ok and nom or nil
end

local function remettreOutil(dc, outil)
    if type(dc.selectTool) == 'function' then
        LrTasks.pcall(dc.selectTool, (outil and outil ~= 'dust') and outil or 'loupe')
    end
end

-- Lance la suppression des passants détectés ; renvoie 'lance', 'deja', 'aucun' ou le refus.
local function appliquerPersonnes(dc, fin)
    local ok, retour = LrTasks.pcall(dc.applyRemovalOnDetectedDistractingPeople, function() fin.rappel = true end, nil)
    local message = (not ok) and tostring(Liaison.messageErreur(retour)) or (type(retour) == 'string' and retour or nil)
    if not message then
        return 'lance'
    end
    if message:find(DEJA_RETIRES, 1, true) then
        return 'deja'
    end
    if message:find(AUCUN_PASSANT, 1, true) then
        return 'aucun'
    end
    return 'refus', message
end

-- Détection puis suppression des passants sur la photo affichée, outil Supprimer ouvert. Renvoie
-- {fait, filtre (nom rangé), enCours, raison, lance, deja, aucun, detectes}.
local function lancerPersonnes(photo, dc, garde)
    local filtresAvant = pourLightroom(photo:getDevelopSettings().FilterList)
    local nomsAvant = nomsFiltres(filtresAvant)
    local ok, erreur = LrTasks.pcall(dc.goToRemove)
    if ok then
        ok, erreur = LrTasks.pcall(dc.detectDistractingPeople)
    end
    if not ok then
        return { raison = "Lightroom refuse la détection des passants : " .. (tostring(Liaison.messageErreur(erreur)):gsub('%.+$', '')) }
    end
    -- Détection en arrière-plan, sans rappel. Compte lisible : un nombre inchangé pendant
    -- DUREE_STABLE secondes, ou resté à 0 pendant DUREE_ZERO secondes (aucun passant). Sans compte :
    -- la suppression essayée après ATTENTE_SANS_COMPTE secondes (une détection pas finie n'en
    -- retirerait qu'une partie), puis réessayée tant que Lightroom dit n'en voir aucun.
    local fin, statut, refus = {}, nil, nil
    local precedent, depuis, detectes = nil, nil, nil
    local dernierEssai = nil
    local debut = LrDate.currentTime()
    repeat
        LrTasks.sleep(PAUSE)
        local nombre = compterPersonnes(dc)
        local maintenant = LrDate.currentTime()
        local ecoule = maintenant - debut
        if nombre then
            if nombre ~= precedent then
                precedent, depuis = nombre, maintenant
            end
            if nombre > 0 then
                detectes = nombre
                if maintenant - depuis >= Suppression.DUREE_STABLE then
                    statut, refus = appliquerPersonnes(dc, fin)
                end
            elseif maintenant - depuis >= Suppression.DUREE_ZERO then
                statut, refus = appliquerPersonnes(dc, fin)
            end
        elseif ecoule >= Suppression.ATTENTE_SANS_COMPTE
            and (not dernierEssai or ecoule - dernierEssai >= Suppression.ESSAI_SANS_COMPTE) then
            dernierEssai = ecoule
            statut, refus = appliquerPersonnes(dc, fin)
            if statut == 'aucun' then
                statut = nil
            end
        end
    until statut or LrDate.currentTime() - debut > Suppression.DUREE_DETECTION
    if not statut then
        statut, refus = appliquerPersonnes(dc, fin)
    end
    if statut == 'deja' then
        return { deja = true, detectes = detectes }
    elseif statut == 'aucun' then
        return { aucun = true, detectes = 0 }
    elseif statut == 'refus' then
        return { raison = "Lightroom refuse la suppression des passants : " .. refus:gsub('%.+$', ''), detectes = detectes }
    end
    -- Suppression en arrière-plan : finie quand FilterList porte un filtre de plus (quel que soit
    -- son nom, à constater), avec le rappel, ou deux lectures de suite sans lui.
    local stables = 0
    local rappelA
    debut = LrDate.currentTime()
    repeat
        LrTasks.sleep(PAUSE)
        local reglages = photo:getDevelopSettings()
        local change = not egal(reglages.FilterList, filtresAvant)
        local nouveau = change and (filtreAjoute(reglages.FilterList, nomsAvant)
            or Suppression.filtrePersonnes(reglages, garde)) or nil
        local fini = nouveau ~= nil or (change and etatPersonnes(photo, dc, garde).actif)
        stables = fini and stables + 1 or 0
        if stables >= 2 or (fini and fin.rappel) then
            local nom = nouveau and nouveau.Name ~= nil and tostring(nouveau.Name) or nil
            if nom then
                nomsAppris[nom] = true
            end
            return { fait = true, lance = true, detectes = detectes, filtre = nom, filtres = nomsAvant }
        end
        if fin.rappel and not rappelA then
            rappelA = LrDate.currentTime()
        end
        if rappelA and LrDate.currentTime() - rappelA > 10 then
            return { lance = true, detectes = detectes,
                raison = "Lightroom a fini sans ranger de suppression des passants (annulée dans sa fenêtre de progression, ou refusée par le service génératif d'Adobe : réseau, compte)" }
        end
    until LrDate.currentTime() - debut > Suppression.DUREE_PERSONNES
    return { lance = true, enCours = true, detectes = detectes, filtres = nomsAvant,
        raison = string.format("Lightroom retire encore les passants après %d minutes (service génératif d'Adobe) : la suppression peut encore arriver ; undo_last la retirera", Suppression.DUREE_PERSONNES / 60) }
end

-- Retire la suppression des passants de la photo affichée : resetFilterWithName, sinon la liste des
-- filtres sans elle (écriture ordinaire). Renvoie si elle est retirée, la raison sinon.
local function retirerPersonnes(photo, dc, etape, garde)
    if type(dc.resetFilterWithName) == 'function' then
        LrTasks.pcall(dc.resetFilterWithName, Suppression.FILTRE_PERSONNES)
        local debut = LrDate.currentTime()
        repeat
            LrTasks.sleep(PAUSE)
            if not etatPersonnes(photo, dc, garde).actif then
                return true
            end
        until LrDate.currentTime() - debut > 10
    end
    ecrire(etape, function()
        photo:applyDevelopSettings({ FilterList = Suppression.sansPersonnes(photo:getDevelopSettings().FilterList, garde) }, etape)
    end)
    if etatPersonnes(photo, dc, garde).actif then
        return false, "Lightroom garde la suppression des passants"
    end
    return true
end

-- La suppression des passants demandée, sur la photo affichée. La mémoire est écrite avant le
-- calcul ; le nom du filtre rangé y est ajouté après. Elle est remise telle qu'elle était si rien
-- n'a changé, mais gardée si la suppression peut encore arriver (délai dépassé).
local function supprimerPersonnesAffichee(photo, dc, voulu, vue, etape, prefs, params, plan)
    local garde = gardeMemoire(photo)
    local avant = etatPersonnes(photo, dc, garde)
    plan.apres = { personnes = avant.actif }
    if avant.actif == voulu then
        noter(plan, voulu and "Passants déjà retirés sur cette photo (Suppression des distractions › Personnes) : rien à refaire."
            or "Pas de suppression des passants sur cette photo : rien à retirer.")
        return
    end
    if voulu and not vue.pret then
        noter(plan, Amelioration.PAS_PRETE .. ".")
        return
    end

    local champs, precedent = { 'avantClaude', 'etapesClaude', 'journalClaude', 'retoucheeParClaude', 'proprietaireMemoire' }, {}
    for _, champ in ipairs(champs) do
        precedent[champ] = photo:getPropertyForPlugin(_PLUGIN, champ)
    end
    local original = lireJson(photo, 'avantClaude', {})
    local premiere = sansRetouche(original)
    local etapes = lireJson(photo, 'etapesClaude', {})
    original.Suppression = type(original.Suppression) == 'table' and original.Suppression or {}
    local nomsAvant = nomsFiltres(photo:getDevelopSettings().FilterList)
    if original.Suppression.personnes == nil then
        original.Suppression.personnes = avant.actif
        if not avant.actif then
            original.Suppression.filtres = nomsAvant
        end
    end
    local memoireEtape = { personnes = avant.actif }
    if voulu then
        memoireEtape.filtres = nomsAvant
    elseif garde then
        memoireEtape.filtre, memoireEtape.filtres = garde.filtre, garde.filtres
    end
    local etapeId = nouvelleEtape(etapes, etape, { Suppression = memoireEtape })
    plan.etapeId = etapeId
    if premiere and prefs.instantane then
        ecrire(etape, function() creerInstantane(photo) end)
    end
    ecrireMemoire(etape, function()
        garder(photo, 'avantClaude', Json.encode(original))
        garder(photo, 'etapesClaude', Json.encode(Json.tableau(etapes)))
        garder(photo, 'retoucheeParClaude', 'oui')
    end)

    local outil = outilActuel(dc)
    local resultat
    if voulu then
        resultat = lancerPersonnes(photo, dc, garde)
    else
        local fait, raison = retirerPersonnes(photo, dc, etape, garde)
        resultat = { fait = fait, raison = raison, lance = true }
    end
    remettreOutil(dc, outil)
    if resultat.deja then
        noter(plan, "Lightroom dit ces passants déjà retirés : rien à refaire.")
    elseif resultat.aucun then
        noter(plan, "Lightroom n'a détecté aucun passant sur cette photo (Suppression des distractions › Personnes) : rien n'a été fait. Un passant qu'il ne voit pas se retire par retouch_spots (mode remove) ou generative_edit.")
    elseif resultat.raison then
        noter(plan, "Passants : " .. resultat.raison .. ".")
    end
    -- Le nom du filtre rangé par Lightroom, gardé pour le retirer à l'annulation.
    if resultat.filtre then
        memoireEtape.filtre = resultat.filtre
        if original.Suppression.personnes == false then
            original.Suppression.filtre = original.Suppression.filtre or resultat.filtre
        end
    end
    local gardeApres = { filtre = resultat.filtre or (garde and garde.filtre), filtres = memoireEtape.filtres }
    local apres = etatPersonnes(photo, dc, voulu and gardeApres or garde)
    plan.apres = { personnes = apres.actif, detectes = resultat.detectes }
    if apres.actif ~= avant.actif then
        plan.changements[#plan.changements + 1] = { cle = 'Suppression.personnes',
            avant = avant.actif and "retirés" or "présents", apres = apres.actif and "retirés" or "présents" }
        if not voulu then
            noter(plan, "Annuler ce retour (undo_last) relancera la suppression des passants : nouveau résultat génératif, différent du précédent.")
        end
    elseif resultat.enCours then
        plan.changements[#plan.changements + 1] = { cle = 'Suppression.personnes', avant = "présents", apres = "en cours" }
    else
        ecrireMemoire("Claude · rien lancé", function()
            for _, champ in ipairs(champs) do
                photo:setPropertyForPlugin(_PLUGIN, champ, precedent[champ])
            end
        end)
        plan.etapeId = nil
        return
    end
    local journal = lireJson(photo, 'journalClaude', {})
    ajouterJournal(journal, { etape = etape, etape_id = etapeId, type = 'retouche', raison = params.raison, changements = plan.changements })
    ecrireMemoire(etape, function()
        if resultat.filtre then
            garder(photo, 'avantClaude', Json.encode(original))
            garder(photo, 'etapesClaude', Json.encode(Json.tableau(etapes)))
        end
        garder(photo, 'journalClaude', Json.encode(Json.tableau(journal)))
    end)
end

-- Commande « supprimer » avec personnes = true (retirer les passants) ou false (les rendre).
local function supprimerPersonnes(params, prefs)
    if type(params.personnes) ~= 'boolean' then
        echouer("Passants : personnes = true (les retirer) ou false (les rendre).")
    end
    local dc = controleurPersonnes()
    local photo = photoVisee(params)
    -- Rendre les passants retire un filtre : rien ne se calcule sur l'original.
    if params.personnes then
        Photos.exigerOriginal(photo, "La suppression des passants se calcule sur l'original : rien n'a été fait.")
    end
    verifierProtection({ photo }, prefs, params, 'remove_distractions')
    local etape = nomEtape(params, "passants")
    local plan = { photo = photo, changements = Json.tableau(), notes = Json.tableau() }
    avecVerrou(function()
        local vue = afficherEnDeveloppement(photo, dc)
        local ok, erreur = LrTasks.pcall(supprimerPersonnesAffichee, photo, dc, params.personnes, vue, etape, prefs, params, plan)
        remettreVue(vue)
        if not ok then
            error(erreur, 0)
        end
    end)
    if #plan.changements > 0 then
        Ecriture.noterEtatFinal({ photo }, etape)
    end
    local resultats = resultatsPlans({ plan }, etape, params)
    resultats[1].personnes = plan.apres
    Liaison.noter("Passants : " .. etape .. " sur " .. nomFichier(photo))
    return { mode = modeTexte(prefs), resultats = resultats }
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
-- qualite ('preview', 'standard', 'best')} ; personnes = true ou false ; poussiere = {actif}. Voir
-- l'en-tête de ce fichier.
function Suppression.supprimer(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'remove_distractions')
    if params.personnes ~= nil then
        if type(params.reflets) == 'table' or type(params.poussiere) == 'table' then
            echouer("Passants, reflets et poussière : un appel chacun.")
        end
        return supprimerPersonnes(params, prefs)
    end
    if type(params.poussiere) == 'table' and type(params.reflets) ~= 'table' then
        local photo = photoVisee(params)
        verifierProtection({ photo }, prefs, params, 'remove_distractions')
        local etape = nomEtape(params, "poussière")
        local plan = supprimerPoussiere(photo, params.poussiere, etape, prefs, params)
        return { mode = modeTexte(prefs), resultats = resultatsPlans({ plan }, etape, params) }
    end
    local demande = type(params.reflets) == 'table' and params.reflets or nil
    if not demande then
        echouer("Rien à supprimer : reflets, personnes ou poussiere.")
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

-- Remet l'état des passants gardé en mémoire (annulation, retour à l'origine), sur la photo
-- affichée. Échoue si Lightroom ne suit pas.
local function remettrePersonnes(photo, dc, vue, voulu, garde)
    if etatPersonnes(photo, dc, garde).actif == voulu then
        return
    end
    local outil = outilActuel(dc)
    local fait, raison
    if voulu then
        if not vue.pret then
            echouer(string.format("Lightroom n'a pas remis la suppression des passants (%s) : %s.", nomFichier(photo), Amelioration.PAS_PRETE))
        end
        local resultat = lancerPersonnes(photo, dc, garde)
        fait = resultat.fait or resultat.deja
        raison = resultat.raison or (resultat.aucun and "Lightroom n'y détecte plus de passant")
    else
        fait, raison = retirerPersonnes(photo, dc, "Claude · passants rendus", garde)
    end
    remettreOutil(dc, outil)
    if not fait then
        echouer(string.format("Lightroom n'a pas remis les passants comme avant (%s) : %s.", nomFichier(photo), tostring(raison)))
    end
end

-- Remet l'état des reflets et des passants gardé en mémoire (annulation, retour à l'origine).
-- Échoue si Lightroom ne suit pas.
function Suppression.remettre(photo, voulue)
    if type(voulue) ~= 'table' then
        return
    end
    local garde = { filtre = voulue.filtre, filtres = type(voulue.filtres) == 'table' and voulue.filtres or nil }
    voulue = { reflets = voulue.reflets, intensite = voulue.intensite, personnes = voulue.personnes }
    -- Passants à laisser sans suppression, et la photo n'en a pas : rien à demander à Lightroom
    -- (Lightroom avant la 16.0 compris).
    if voulue.personnes == false and not Suppression.filtrePersonnes(photo:getDevelopSettings(), garde) then
        voulue.personnes = nil
    end
    if voulue.reflets == nil and voulue.personnes == nil then
        return
    end
    avecVerrou(function()
        -- Les passants vérifient leur version et leurs fonctions même quand les reflets sont remis
        -- aussi (sinon le refus serait celui d'un appel à nil, moins clair).
        local dcPersonnes = voulue.personnes ~= nil and controleurPersonnes() or nil
        local dc = voulue.reflets ~= nil and controleur() or dcPersonnes
        local vue = afficherEnDeveloppement(photo, dc)
        local ok, erreur = LrTasks.pcall(function()
            if voulue.reflets ~= nil then
                local voulu = { actif = voulue.reflets == true, intensite = tonumber(voulue.intensite) }
                local avant = etatReflets(photo, dc)
                if not dejaFait(avant, voulu) then
                    if voulu.actif and not avant.actif and not vue.pret then
                        echouer(string.format("Lightroom n'a pas remis la suppression des reflets (%s) : %s.", nomFichier(photo), Amelioration.PAS_PRETE))
                    end
                    local fait, raison = lancer(photo, dc, voulu, avant)
                    if not fait then
                        echouer(string.format("Lightroom n'a pas remis les reflets comme avant (%s) : %s.", nomFichier(photo), raison))
                    end
                end
            end
            if voulue.personnes ~= nil then
                remettrePersonnes(photo, dcPersonnes, vue, voulue.personnes == true, garde)
            end
        end)
        remettreVue(vue)
        if not ok then
            error(erreur, 0)
        end
    end)
end

return Suppression
