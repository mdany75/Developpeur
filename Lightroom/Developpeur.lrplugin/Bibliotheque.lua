-- Bibliotheque.lua : ce qu'un retoucheur fait dans la Bibliothèque : copies virtuelles, note,
-- drapeau, libellé de couleur, titre, légende, droits d'auteur, mots-clés, collections, recherche,
-- et la photo montrée dans Lightroom.
--
-- Les écritures passent par ecrire, entrent au journal et gardent ce qu'elles remplacent dans la
-- mémoire de la photo, sous la clé Bibliotheque (comme Amelioration, ce n'est pas un réglage : elle
-- ne part jamais dans applyDevelopSettings). undo_last et revert_to_original la remettent par
-- Bibliotheque.remettre (Annulation.lua). Une copie virtuelle ne se défait pas : le SDK ne
-- supprime pas de photo.
--
-- Relevé dans Lightroom Classic 15.6 (commande diagnostic) : la note (rating, nil sans note) et le
-- drapeau (pickStatus : 1 retenue, 0 aucun, −1 rejetée) se lisent par getRawMetadata ; le titre,
-- la légende, les droits d'auteur et le libellé, par getFormattedMetadata seulement
-- (getRawMetadata les refuse). Le libellé est rangé comme un texte, celui du jeu de libellés actif
-- (« Rouge » dans un catalogue en français) ; colorNameForLabel en donne la couleur.
--
-- Recherche : catalog:findPhotos prend la description d'une collection dynamique (searchDesc).
-- Sa forme vient des collections dynamiques qu'installe Lightroom Classic 15.6 (« Colored Red » :
-- labelColor == 1 ; « Five Stars » : rating >= 5 ; « Past Month » : captureTime inLast 1 months ;
-- « Without Keywords » : keywords empty) ; les opérations sur un texte (any, all, words, noneOf,
-- beginsWith, endsWith, empty, notEmpty) et le critère « sdktext: » des champs d'un module, de
-- son code. Les dates exactes, le dossier et les copies virtuelles sont filtrés après coup.

local LrApplication = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDate = import 'LrDate'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Photos = require 'Photos'
local Preferences = require 'Preferences'
local Reglages = require 'Reglages'

local brut, catalogue, decrire, garder = Photos.brut, Photos.catalogue, Photos.decrire, Photos.garder
local lireJson, meta, nomFichier, photoParId = Photos.lireJson, Photos.meta, Photos.nomFichier, Photos.photoParId
local photosVisees = Photos.photosVisees
local minuscules, pluriel = Reglages.minuscules, Reglages.pluriel
local ajouterJournal, ecrire, nouvelleEtape = Ecriture.ajouterJournal, Ecriture.ecrire, Ecriture.nouvelleEtape
local modeTexte, nomEtape, resultatsPlans = Ecriture.modeTexte, Ecriture.nomEtape, Ecriture.resultatsPlans
local verifierPause, verifierProtection = Ecriture.verifierPause, Ecriture.verifierProtection

local Bibliotheque = {}

local function echouer(message)
    error(message, 0)
end

local MAX_RESULTATS = 500
-- Secondes au plus pour sélectionner une photo dans le dossier que le module vient d'afficher.
local DELAI_SOURCE = 3
-- Photos au plus pour trier ou filtrer après la recherche de Lightroom (dates, dossier, copies).
local MAX_TRI = 5000
local ENSEMBLE_CLAUDE = "Claude"

-- Couleurs des libellés : numéro dans une recherche (labelColor), nom que donne
-- colorNameForLabel, et textes du jeu de libellés par défaut, en français puis en anglais.
local COULEURS = {
    rouge = { numero = 1, couleur = 'red', textes = { 'Rouge', 'Red' } },
    jaune = { numero = 2, couleur = 'yellow', textes = { 'Jaune', 'Yellow' } },
    vert = { numero = 3, couleur = 'green', textes = { 'Vert', 'Green' } },
    bleu = { numero = 4, couleur = 'blue', textes = { 'Bleu', 'Blue' } },
    violet = { numero = 5, couleur = 'purple', textes = { 'Violet', 'Purple' } },
}
local DRAPEAUX = { retenue = 1, aucun = 0, rejetee = -1 }
local NOMS_DRAPEAU = { [1] = 'retenue', [0] = 'aucun', [-1] = 'rejetée' }
-- Champs de texte : nom dans la commande, clé de Lightroom.
local TEXTES = { { 'titre', 'title' }, { 'legende', 'caption' }, { 'droits', 'copyright' } }

-- Mode « Proposer d'abord » : un classement est une écriture, comme une retouche.
local function verifierAccord(prefs, params, outil)
    if prefs.mode == 'proposer' and not params.confirme then
        echouer("Mode « Proposer d'abord » actif dans Lightroom : rien n'a été écrit. Présenter ces changements à l'utilisateur, attendre son accord, puis rappeler "
            .. outil .. " avec confirm = true.")
    end
    Ecriture.accordDansLightroom(prefs, params, outil)
end

local function liste(valeur)
    if type(valeur) == 'table' then
        return valeur
    elseif valeur ~= nil then
        return { valeur }
    end
    return {}
end

local function citer(noms)
    local textes = {}
    for _, nom in ipairs(noms) do
        textes[#textes + 1] = "« " .. tostring(nom) .. " »"
    end
    return table.concat(textes, ", ")
end

-- Sélection --------------------------------------------------------------------------

-- Sélectionne ces photos dans Lightroom ; faux si Lightroom ne l'a pas fait (photo hors de la source
-- affichée : dossier, collection ou filtre du film fixe).
local function selectionner(photos)
    local cat = catalogue()
    local autres = {}
    for i = 2, #photos do
        autres[#autres + 1] = photos[i]
    end
    LrTasks.pcall(cat.setSelectedPhotos, cat, photos[1], autres)
    local active, cibles = cat:getTargetPhoto(), cat:getTargetPhotos()
    return active ~= nil and active.localIdentifier == photos[1].localIdentifier and #cibles == #photos
end

-- Sélectionne ces photos, en affichant au besoin le dossier de la première ; renvoie si c'est fait,
-- si la source affichée a changé, et celle d'avant.
local function selectionnerAvecSource(photos)
    if selectionner(photos) then
        return true, false, nil
    end
    local cat = catalogue()
    local chemin = brut(photos[1], 'path')
    local ok, dossier = LrTasks.pcall(cat.getFolderByPath, cat, type(chemin) == 'string' and LrPathUtils.parent(chemin) or '')
    if not ok or not dossier then
        return false, false, nil
    end
    local _, sources = LrTasks.pcall(cat.getActiveSources, cat)
    LrTasks.pcall(cat.setActiveSources, cat, { dossier })
    -- Lightroom met un moment à afficher le dossier : aussitôt après setActiveSources,
    -- setSelectedPhotos ne sélectionne rien (constaté en 2.3). La sélection se refait donc
    -- pendant quelques secondes.
    local fin = LrDate.currentTime() + DELAI_SOURCE
    repeat
        if selectionner(photos) then
            return true, true, sources
        end
        LrTasks.sleep(0.2)
    until LrDate.currentTime() > fin
    return false, true, sources
end

-- Remet la vue d'avant une sélection faite par le module (débruitage, variantes, copie virtuelle,
-- photo réimportée retirée par la recette) : la source affichée d'abord, si elle a changé, puis la
-- photo active et la sélection. Comme pour selectionnerAvecSource, Lightroom met un moment à
-- afficher la source remise : aussitôt après setActiveSources, setSelectedPhotos ne sélectionne
-- rien (constaté en 2.3) ; la sélection se refait donc pendant DELAI_SOURCE secondes, puis la photo
-- active se relit. Constaté le 21 octobre 2026 (mesures de la 1.3, Lightroom Classic 15.6) : remise
-- sans attendre, la photo active d'avant, hors du dossier de la copie d'essai visée, ne revenait
-- pas après un débruitage, son annulation ou une variante retenue (trois fois : une autre photo est
-- restée active). Rend vrai si la photo active d'avant est revenue (ou s'il n'y en avait pas).
local function remettreSelection(active, selection, sources)
    local cat = catalogue()
    if sources then
        LrTasks.pcall(cat.setActiveSources, cat, sources)
    end
    if not active then
        return true
    end
    local photos = { active }
    for _, autre in ipairs(selection or {}) do
        if autre.localIdentifier ~= active.localIdentifier then
            photos[#photos + 1] = autre
        end
    end
    local fin = LrDate.currentTime() + DELAI_SOURCE
    while not selectionner(photos) do
        if LrDate.currentTime() > fin then
            -- La sélection entière ne revient pas (une photo filtrée entre-temps) : au moins la
            -- photo active.
            if #photos > 1 then
                selectionner({ active })
            end
            break
        end
        LrTasks.sleep(0.2)
    end
    local cible = cat:getTargetPhoto()
    local revenue = cible ~= nil and cible.localIdentifier == active.localIdentifier
    if not revenue then
        Liaison.noter("Photo active d'avant non remise : « " .. nomFichier(active) .. " » (autre photo active : "
            .. (cible and ("« " .. nomFichier(cible) .. " »") or "aucune") .. ")")
    end
    return revenue
end

-- Mots-clés ----------------------------------------------------------------------------

-- « Lieux > Canada > Montréal » (aussi avec › ou |) → { 'Lieux', 'Canada', 'Montréal' }.
local function morceaux(texte)
    local resultat = {}
    local uniforme = (tostring(texte):gsub('›', '>'):gsub('|', '>'))
    for morceau in (uniforme .. '>'):gmatch('([^>]*)>') do
        morceau = morceau:gsub('^%s+', ''):gsub('%s+$', '')
        if morceau ~= '' then
            resultat[#resultat + 1] = morceau
        end
    end
    return resultat
end

local function cheminMotCle(motCle)
    local noms, courant = {}, motCle
    while courant do
        table.insert(noms, 1, courant:getName())
        courant = courant:getParent()
    end
    return table.concat(noms, ' > ')
end

-- Tous les mots-clés du catalogue, avec leur chemin.
local function tousLesMotsCles()
    local tous = {}
    local function parcourir(enfants, parent)
        for _, motCle in ipairs(enfants or {}) do
            local nom = motCle:getName()
            local chemin = parent and (parent .. ' > ' .. nom) or nom
            tous[#tous + 1] = { motCle = motCle, chemin = chemin, morceaux = morceaux(chemin) }
            parcourir(motCle:getChildren(), chemin)
        end
    end
    parcourir(catalogue():getKeywords(), nil)
    return tous
end

-- Le mot-clé que désignent ces noms : le chemin complet d'abord, sinon la fin d'un chemin (un nom
-- seul, « Canada > Montréal »), s'il n'y en a qu'un. Nil s'il n'existe pas.
local function trouverMotCle(voulus, tous)
    local exacts, fins = {}, {}
    for _, m in ipairs(tous) do
        if #m.morceaux >= #voulus then
            local decalage, correspond = #m.morceaux - #voulus, true
            for i = 1, #voulus do
                if minuscules(m.morceaux[decalage + i]) ~= minuscules(voulus[i]) then
                    correspond = false
                    break
                end
            end
            if correspond then
                local cible = decalage == 0 and exacts or fins
                cible[#cible + 1] = m
            end
        end
    end
    if #exacts == 1 then
        return exacts[1]
    end
    local candidats = #exacts > 1 and exacts or fins
    if #candidats > 1 then
        local chemins = {}
        for _, m in ipairs(candidats) do
            chemins[#chemins + 1] = m.chemin
        end
        echouer("Plusieurs mots-clés répondent à « " .. table.concat(voulus, ' > ') .. " » : " .. citer(chemins)
            .. ". Donner le chemin, par exemple « " .. chemins[1] .. " ».")
    end
    return candidats[1]
end

-- Les mots-clés qui manquent, à créer dans l'écriture du classement : chaque niveau absent d'un
-- chemin demandé, une seule fois, les parents avant leurs enfants. Constaté en 2.3 (Lightroom
-- Classic 15.6) : un mot-clé créé dans une écriture y sert de parent au suivant et se pose sur une
-- photo (addKeyword), mais ne s'y lit pas (getName : « attempt to index a nil value ») ; tout tient
-- donc dans la même écriture, une seule opération pour ⌘Z, sans rien lire de ce qui est créé.
local function motsClesACreer(textes, tous, synonymes)
    local noeuds, parCle = {}, {}
    for _, texte in ipairs(textes) do
        local voulus = morceaux(texte)
        if #voulus == 0 then
            echouer("Mot-clé vide.")
        end
        if not trouverMotCle(voulus, tous) then
            -- Sous le plus long début qui existe.
            local parent, cheminParent, premier = nil, nil, 1
            for n = #voulus - 1, 1, -1 do
                local debut = {}
                for i = 1, n do
                    debut[i] = voulus[i]
                end
                local trouve = trouverMotCle(debut, tous)
                if trouve then
                    parent, cheminParent, premier = trouve.motCle, trouve.chemin, n + 1
                    break
                end
            end
            if #voulus - premier + 1 > 20 then
                echouer("Hiérarchie de mots-clés trop profonde (20 niveaux au plus).")
            end
            local noeudParent, chemin = nil, cheminParent
            for i = premier, #voulus do
                chemin = chemin and (chemin .. ' > ' .. voulus[i]) or voulus[i]
                local cle = minuscules(chemin)
                local noeud = parCle[cle]
                if not noeud then
                    noeud = { parent = noeudParent == nil and parent or nil, noeudParent = noeudParent, nom = voulus[i], chemin = chemin }
                    parCle[cle] = noeud
                    noeuds[#noeuds + 1] = noeud
                end
                -- Synonymes (le nom anglais d'un mot-clé de Vision) : sur le dernier niveau seulement.
                if i == #voulus and type(synonymes) == 'table' and type(synonymes[texte]) == 'table' then
                    noeud.synonymes = synonymes[texte]
                end
                noeudParent = noeud
            end
        end
    end
    return noeuds
end

-- Dans l'écriture : crée les mots-clés prévus ; `tous` les reçoit (chemins connus d'avance, rien
-- n'est lu des mots-clés créés). createKeyword rend celui qui existe déjà au même endroit.
local function creerMotsCles(noeuds, tous)
    local crees = Json.tableau()
    for _, noeud in ipairs(noeuds) do
        local parent = noeud.noeudParent and noeud.noeudParent.motCle or noeud.parent
        -- Une table simple : un tableau relu par Json.decode porte une métatable.
        local synonymes = {}
        for _, texte in ipairs(noeud.synonymes or {}) do
            synonymes[#synonymes + 1] = tostring(texte)
        end
        noeud.motCle = catalogue():createKeyword(noeud.nom, synonymes, true, parent, true)
        if not noeud.motCle then
            echouer("Lightroom n'a pas créé le mot-clé « " .. noeud.chemin .. " ».")
        end
        tous[#tous + 1] = { motCle = noeud.motCle, chemin = noeud.chemin, morceaux = morceaux(noeud.chemin) }
        crees[#crees + 1] = noeud.chemin
    end
    return crees
end

-- Mots-clés posés sur la photo, par chemin.
local function motsClesDe(photo)
    local poses = {}
    for _, motCle in ipairs(liste(brut(photo, 'keywords'))) do
        poses[#poses + 1] = { motCle = motCle, chemin = cheminMotCle(motCle) }
        poses[#poses].morceaux = morceaux(poses[#poses].chemin)
    end
    return poses
end

-- Collections ---------------------------------------------------------------------------

-- Collections et ensembles du catalogue, avec leur chemin (ensembles qui les contiennent).
local function toutesLesCollections()
    local collections, ensembles = {}, {}
    local function parcourir(parent, chemin)
        for _, c in ipairs(parent:getChildCollections() or {}) do
            collections[#collections + 1] = { collection = c, nom = c:getName(), id = c.localIdentifier,
                ensemble = chemin, dynamique = c:isSmartCollection() == true }
        end
        for _, e in ipairs(parent:getChildCollectionSets() or {}) do
            local sous = chemin and (chemin .. ' > ' .. e:getName()) or e:getName()
            ensembles[#ensembles + 1] = { ensemble = e, chemin = sous }
            parcourir(e, sous)
        end
    end
    parcourir(catalogue(), nil)
    return collections, ensembles
end

-- Une collection par son identifiant (un nombre), son nom ou « Ensemble > Nom » ; un texte fait de
-- chiffres est d'abord un nom (« 2026 »), puis un identifiant.
local function trouverCollection(designation)
    local collections = toutesLesCollections()
    local function parId(id)
        for _, c in ipairs(collections) do
            if c.id == id then
                return c
            end
        end
        return nil
    end
    if type(designation) == 'number' then
        return parId(designation) or echouer("Aucune collection n'a l'identifiant " .. tostring(designation) .. " (manage_collections, action « list »).")
    end
    local voulus = morceaux(designation)
    local trouvees = {}
    for _, c in ipairs(collections) do
        local chemin = morceaux((c.ensemble and (c.ensemble .. ' > ') or '') .. c.nom)
        local correspond = #chemin >= #voulus and #voulus > 0
        for i = 1, #voulus do
            if correspond and minuscules(chemin[#chemin - #voulus + i]) ~= minuscules(voulus[i]) then
                correspond = false
            end
        end
        if correspond then
            trouvees[#trouvees + 1] = c
        end
    end
    if #trouvees == 0 then
        local c = tonumber(designation) and parId(tonumber(designation))
        if c then
            return c
        end
        echouer("Collection introuvable : « " .. tostring(designation) .. " » (manage_collections, action « list »).")
    elseif #trouvees > 1 then
        local ids = {}
        for _, c in ipairs(trouvees) do
            ids[#ids + 1] = string.format("%s (%d)", c.nom, c.id)
        end
        echouer("Plusieurs collections s'appellent « " .. tostring(designation) .. " » : " .. table.concat(ids, ", ") .. ". Donner son identifiant.")
    end
    return trouvees[1]
end

-- L'ensemble « A > B », créé au besoin (hors d'une écriture) : chaque niveau dans sa propre
-- écriture, avant de servir de parent au suivant (une collection créée ne se lit pas dans
-- l'écriture qui l'a créée : constaté ; supposé pour un ensemble).
local function obtenirEnsemble(chemin)
    local parent = nil
    for _, nom in ipairs(morceaux(chemin)) do
        local source = parent or catalogue()
        local trouve
        for _, e in ipairs(source:getChildCollectionSets() or {}) do
            if minuscules(e:getName()) == minuscules(nom) then
                trouve = e
                break
            end
        end
        if not trouve then
            local dans = parent
            ecrire("Claude · ensemble de collections", function()
                trouve = catalogue():createCollectionSet(nom, dans, true)
            end)
            if not trouve then
                echouer("Lightroom n'a pas créé l'ensemble de collections « " .. nom .. " ».")
            end
        end
        parent = trouve
    end
    return parent
end

-- Mémoire et journal ----------------------------------------------------------------------

local function ensembleDe(valeurs)
    local ensemble = {}
    for _, valeur in ipairs(liste(valeurs)) do
        ensemble[valeur] = true
    end
    return ensemble
end

local function triee(ensemble)
    local resultat = Json.tableau()
    for valeur in pairs(ensemble) do
        resultat[#resultat + 1] = valeur
    end
    table.sort(resultat, function(a, b) return tostring(a) < tostring(b) end)
    return resultat
end

-- État d'avant Claude : la première valeur de chaque champ, et pour les mots-clés et les
-- collections ce que Claude a ajouté (à retirer) et retiré (à remettre), une opération défaisant
-- l'autre.
local CUMULS = { 'motsCles', 'collections' }

local function fusionnerOriginal(original, avant)
    local b = type(original.Bibliotheque) == 'table' and original.Bibliotheque or {}
    for cle, valeur in pairs(avant) do
        if cle ~= 'motsCles' and cle ~= 'collections' and cle ~= 'iptc' and b[cle] == nil then
            b[cle] = valeur
        end
    end
    -- Champs IPTC d'un paramètre prédéfini de métadonnées : la première valeur de chacun.
    if type(avant.iptc) == 'table' then
        local iptc = type(b.iptc) == 'table' and b.iptc or {}
        for champ, valeur in pairs(avant.iptc) do
            if iptc[champ] == nil then
                iptc[champ] = valeur
            end
        end
        b.iptc = iptc
    end
    for _, cle in ipairs(CUMULS) do
        if type(avant[cle]) == 'table' then
            local cumul = type(b[cle]) == 'table' and b[cle] or {}
            local ajoutes, retires = ensembleDe(cumul.ajoutes), ensembleDe(cumul.retires)
            for _, valeur in ipairs(liste(avant[cle].ajoutes)) do
                if retires[valeur] then retires[valeur] = nil else ajoutes[valeur] = true end
            end
            for _, valeur in ipairs(liste(avant[cle].retires)) do
                if ajoutes[valeur] then ajoutes[valeur] = nil else retires[valeur] = true end
            end
            b[cle] = { ajoutes = triee(ajoutes), retires = triee(retires) }
        end
    end
    original.Bibliotheque = b
end

-- Une étape annulée : ses ajouts et retraits de mots-clés et de collections sortent du cumul de
-- l'état d'avant Claude (un ajout annulé compte comme un retrait, et inversement) ; sans cela, un
-- retrait annulé laisserait au retour à l'origine une photo dans la collection où Claude l'avait
-- mise. Renvoie vrai si `original` a changé.
function Bibliotheque.annulerCumul(original, avant)
    if type(avant) ~= 'table' then
        return false
    end
    local inverse = {}
    for _, cle in ipairs(CUMULS) do
        if type(avant[cle]) == 'table' then
            inverse[cle] = { ajoutes = liste(avant[cle].retires), retires = liste(avant[cle].ajoutes) }
        end
    end
    if next(inverse) == nil then
        return false
    end
    fusionnerOriginal(original, inverse)
    return true
end

-- Lit la mémoire des photos avant une écriture.
local function nouveauClassement(photo)
    return {
        photo = photo,
        avant = {},
        changements = Json.tableau(),
        notes = Json.tableau(),
        original = lireJson(photo, 'avantClaude', {}),
        etapes = lireJson(photo, 'etapesClaude', {}),
        journal = lireJson(photo, 'journalClaude', {}),
    }
end

local function changer(plan, cle, avant, apres)
    plan.changements[#plan.changements + 1] = { cle = cle, avant = avant, apres = apres }
end

-- Garde l'étape, l'état d'avant Claude et l'entrée du journal (dans l'écriture). Avec
-- `sansOriginal` (une note posée par l'utilisateur, Bibliotheque.noter), l'état d'avant Claude ne
-- change pas : le retour à l'origine laisse cette note en place ; undo_last la défait toujours.
-- L'étape a son id (1.3), au journal (etape_id) et dans la réponse (resultatsPlans).
local function memoriser(plan, etape, params, sansOriginal)
    if next(plan.avant) == nil then
        return
    end
    plan.etapeId = nouvelleEtape(plan.etapes, etape, { Bibliotheque = plan.avant })
    plan.entreeJournal = { etape = etape, etape_id = plan.etapeId, type = 'classement', raison = params.raison, changements = plan.changements }
    ajouterJournal(plan.journal, plan.entreeJournal)
    if not sansOriginal then
        fusionnerOriginal(plan.original, plan.avant)
        garder(plan.photo, 'avantClaude', Json.encode(plan.original))
    end
    garder(plan.photo, 'etapesClaude', Json.encode(Json.tableau(plan.etapes)))
    garder(plan.photo, 'journalClaude', Json.encode(Json.tableau(plan.journal)))
end

-- Note, drapeau, libellé, textes --------------------------------------------------------

local function noteDe(photo)
    return tonumber(brut(photo, 'rating')) or 0
end

local function drapeauDe(photo)
    return tonumber(brut(photo, 'pickStatus')) or 0
end

local function couleurDe(photo)
    for nom, c in pairs(COULEURS) do
        if brut(photo, 'colorNameForLabel') == c.couleur then
            return nom
        end
    end
    return nil
end

local function nomLibelle(texte, couleur)
    if couleur then
        return couleur
    end
    return (texte or '') == '' and 'aucun' or ("« " .. texte .. " »")
end

-- Textes à essayer pour une couleur : celui que porte déjà une photo de cette couleur dans le
-- catalogue (le jeu de libellés actif, même personnalisé), puis ceux du jeu par défaut. Cherché à
-- chaque fois : le jeu de libellés peut changer pendant que Lightroom tourne.
-- Le texte du jeu de libellés actif pour une couleur, lu directement (getLabelMapToColorName, SDK
-- 3.0, dans une tâche). La référence du SDK dit qu'elle associe une couleur à un texte, sans dire
-- dans quel sens : les deux sont lus.
local function texteDuJeuActif(couleur)
    local cat = catalogue()
    local ok, table_ = LrTasks.pcall(cat.getLabelMapToColorName, cat)
    if not ok or type(table_) ~= 'table' then
        return nil
    end
    for cle, valeur in pairs(table_) do
        if cle == couleur and type(valeur) == 'string' and valeur ~= '' then
            return valeur
        end
        if valeur == couleur and type(cle) == 'string' and cle ~= '' then
            return cle
        end
    end
    return nil
end

-- Textes à essayer pour une couleur : celui du jeu de libellés actif (lu directement), puis celui
-- que porte déjà une photo de cette couleur dans le catalogue, puis ceux du jeu par défaut. Cherché
-- à chaque fois : le jeu de libellés peut changer pendant que Lightroom tourne.
local function textesDuLibelle(nom)
    local c = COULEURS[nom]
    local textes = {}
    local function ajouter(texte)
        for _, deja in ipairs(textes) do
            if deja == texte then
                return
            end
        end
        textes[#textes + 1] = texte
    end
    local actif = texteDuJeuActif(c.couleur)
    if actif then
        ajouter(actif)
    else
        local cat = catalogue()
        local ok, trouvees = LrTasks.pcall(cat.findPhotos, cat, {
            searchDesc = { { criteria = 'labelColor', operation = '==', value = c.numero }, combine = 'intersect' },
        })
        local appris = ok and type(trouvees) == 'table' and trouvees[1] and meta(trouvees[1], 'label')
        if appris then
            ajouter(appris)
        end
    end
    for _, texte in ipairs(c.textes) do
        ajouter(texte)
    end
    return textes
end

-- Écrit un champ de la Bibliothèque (dans une écriture). Constaté dans Lightroom Classic 15.6 : un
-- libellé ne s'efface pas par nil (« entity:__newindex(): Field "colorLabels" cannot be set to
-- nil. ») ; un texte vide l'efface. Supposé pareil pour le titre, la légende et les droits
-- d'auteur. Sans note : nil si Lightroom l'accepte, 0 sinon.
local function ecrireChamp(photo, cle, valeur)
    if cle == 'rating' and (valeur == nil or valeur == 0) then
        if not LrTasks.pcall(photo.setRawMetadata, photo, 'rating', nil) then
            photo:setRawMetadata('rating', 0)
        end
        return
    end
    if valeur == nil then
        valeur = ''
    end
    photo:setRawMetadata(cle, valeur)
end

-- Pose le libellé d'une couleur : le premier texte à essayer (textesDuLibelle). Lightroom ne dit sa
-- couleur (colorNameForLabel) qu'après l'écriture : verifierLibelles la relit, puis essaie les
-- autres textes au besoin (constaté dans Lightroom Classic 15.6 : relu dans la même écriture,
-- « Rouge », le texte des libellés rouges du catalogue, n'était pas encore rouge).
local function poserLibelle(plan, nom, textes)
    local photo = plan.photo
    local avantTexte, avantCouleur = meta(photo, 'label') or '', couleurDe(photo)
    if nom == 'aucun' then
        if avantTexte == '' then
            return
        end
        ecrireChamp(photo, 'label', '')
    else
        if avantCouleur == nom then
            return
        end
        ecrireChamp(photo, 'label', textes[1])
        plan.libelleVoulu = { nom = nom, textes = textes, essai = 1, avant = avantTexte }
    end
    plan.avant.libelle = avantTexte
    changer(plan, 'libelle', nomLibelle(avantTexte, avantCouleur), nom)
end

-- Après l'écriture du classement : la couleur que Lightroom donne au libellé posé. Pas la bonne : le
-- texte suivant, dans sa propre écriture ; aucun ne convient : le libellé d'avant revient, et la
-- réponse et le journal le disent.
local function verifierLibelles(plans, etape)
    for _ = 1, 10 do
        local aEssayer = {}
        for _, plan in ipairs(plans) do
            local v = plan.libelleVoulu
            if v and not v.fini then
                if couleurDe(plan.photo) == v.nom then
                    v.fini = true
                elseif v.essai < #v.textes then
                    v.essai = v.essai + 1
                    aEssayer[#aEssayer + 1] = plan
                else
                    v.fini, v.echec = true, true
                end
            end
        end
        if #aEssayer == 0 then
            break
        end
        ecrire(etape, function()
            for _, plan in ipairs(aEssayer) do
                ecrireChamp(plan.photo, 'label', plan.libelleVoulu.textes[plan.libelleVoulu.essai])
            end
        end)
    end
    local echecs = {}
    for _, plan in ipairs(plans) do
        if plan.libelleVoulu and plan.libelleVoulu.echec then
            echecs[#echecs + 1] = plan
        end
    end
    if #echecs == 0 then
        return
    end
    ecrire(etape, function()
        for _, plan in ipairs(echecs) do
            local v = plan.libelleVoulu
            ecrireChamp(plan.photo, 'label', v.avant)
            -- Le journal garde la même liste de changements (memoriser).
            for i = #plan.changements, 1, -1 do
                if plan.changements[i].cle == 'libelle' then
                    table.remove(plan.changements, i)
                end
            end
            local texte = string.format("Libellé %s non posé : Lightroom ne reconnaît comme cette couleur aucun des textes essayés (%s). "
                .. "Le jeu de libellés actif a d'autres noms (Métadonnées › Jeu de libellés de couleur).", v.nom, citer(v.textes))
            plan.notes[#plan.notes + 1] = texte
            if plan.entreeJournal then
                plan.entreeJournal.note = texte
                garder(plan.photo, 'journalClaude', Json.encode(Json.tableau(plan.journal)))
            end
        end
    end)
end

local function poserMotsCles(plan, ajouter, retirer, tous)
    local photo = plan.photo
    local poses = motsClesDe(photo)
    local nombreAvant = #poses
    local ajoutes, retires = Json.tableau(), Json.tableau()
    for _, texte in ipairs(ajouter) do
        -- Créé plus tôt dans la même écriture s'il manquait (creerMotsCles).
        local trouve = trouverMotCle(morceaux(texte), tous) or echouer("Mot-clé « " .. tostring(texte) .. " » introuvable.")
        local motCle, chemin = trouve.motCle, trouve.chemin
        local deja = false
        for _, p in ipairs(poses) do
            if p.chemin == chemin then
                deja = true
            end
        end
        if not deja then
            photo:addKeyword(motCle)
            ajoutes[#ajoutes + 1] = chemin
            poses[#poses + 1] = { motCle = motCle, chemin = chemin, morceaux = morceaux(chemin) }
        end
    end
    for _, texte in ipairs(retirer) do
        local trouve = trouverMotCle(morceaux(texte), poses)
        if trouve then
            photo:removeKeyword(trouve.motCle)
            retires[#retires + 1] = trouve.chemin
            for i = #poses, 1, -1 do
                if poses[i].chemin == trouve.chemin then
                    table.remove(poses, i)
                end
            end
        else
            plan.notes[#plan.notes + 1] = "Mot-clé « " .. tostring(texte) .. " » absent de cette photo : rien à retirer."
        end
    end
    if #ajoutes + #retires > 0 then
        plan.avant.motsCles = { ajoutes = ajoutes, retires = retires }
        local parties = {}
        for _, chemin in ipairs(ajoutes) do
            parties[#parties + 1] = "+ " .. chemin
        end
        for _, chemin in ipairs(retires) do
            parties[#parties + 1] = "− " .. chemin
        end
        changer(plan, 'mots_cles', pluriel(nombreAvant, "mot-clé", "mots-clés"), table.concat(parties, ", "))
    end
end

-- Paramètre prédéfini de métadonnées (droits d'auteur, créateur…) : par son nom (casse
-- indifférente) ou son identifiant, parmi LrApplication.metadataPresets().
local function presetMetadonnees(designation)
    local voulu = minuscules(tostring(designation))
    local ok, presets = LrTasks.pcall(LrApplication.metadataPresets)
    local noms = {}
    for nom, id in pairs(ok and type(presets) == 'table' and presets or {}) do
        if minuscules(tostring(nom)) == voulu or tostring(id) == tostring(designation) then
            return { nom = tostring(nom), id = tostring(id) }
        end
        noms[#noms + 1] = "« " .. tostring(nom) .. " »"
    end
    table.sort(noms)
    echouer("Paramètre prédéfini de métadonnées introuvable : « " .. tostring(designation) .. " ». "
        .. (#noms > 0 and ("Offerts : " .. table.concat(noms, ", ") .. ".") or "Ce catalogue n'en a aucun (Bibliothèque › Métadonnées › Modifier les paramètres prédéfinis)."))
end

-- Champs IPTC qu'un paramètre prédéfini de métadonnées peut remplir : leur valeur d'avant se garde
-- toute (une remise sans effet sur un champ qu'il n'a pas changé), pour les remettre en annulant.
-- Lus par getFormattedMetadata, écrits par setRawMetadata (comme le titre et les droits d'auteur).
-- copyrightState, une liste de choix, n'en fait pas partie.
local CHAMPS_IPTC = {
    'title', 'caption', 'headline', 'copyright', 'rightsUsageTerms', 'copyrightInfoUrl', 'creator',
    'creatorJobTitle', 'creatorAddress', 'creatorCity', 'creatorStateProvince', 'creatorPostalCode',
    'creatorCountry', 'creatorPhone', 'creatorEmail', 'creatorUrl', 'descriptionWriter', 'jobIdentifier',
    'instructions', 'provider', 'source', 'location', 'city', 'stateProvince', 'country', 'isoCountryCode',
    'intellectualGenre', 'scene', 'iptcSubjectCode', 'event', 'personShown',
}

-- Champs que set_metadata écrit un à un (clés de Lightroom, SDK 3.0 et 13.2 pour le texte
-- alternatif et la description longue, lus par getRawMetadata). Leur valeur d'avant va dans
-- `avant.iptc`, comme celle des champs d'un paramètre prédéfini de métadonnées.
local CHAMPS_ECRITS = {
    headline = true, event = true, personShown = true, location = true, city = true, stateProvince = true,
    country = true, isoCountryCode = true, creator = true, altTextAccessibility = true, extDescrAccessibility = true,
}
local CHAMPS_BRUTS = { altTextAccessibility = true, extDescrAccessibility = true }

local function lireTexte(photo, champ)
    local valeur
    if CHAMPS_BRUTS[champ] then
        valeur = brut(photo, champ)
    else
        valeur = meta(photo, champ)
    end
    return valeur ~= nil and tostring(valeur) or ''
end

local function lireIptc(photo)
    local valeurs = {}
    for _, champ in ipairs(CHAMPS_IPTC) do
        local ok, valeur = LrTasks.pcall(photo.getFormattedMetadata, photo, champ)
        if ok then
            valeurs[champ] = valeur ~= nil and tostring(valeur) or ''
        end
    end
    return valeurs
end

local function remettreIptc(photo, valeurs, notes)
    local actuels = lireIptc(photo)
    for champ in pairs(CHAMPS_BRUTS) do
        actuels[champ] = lireTexte(photo, champ)
    end
    for champ, valeur in pairs(valeurs) do
        local ok = actuels[champ] == tostring(valeur) or LrTasks.pcall(photo.setRawMetadata, photo, champ, tostring(valeur))
        if not ok and notes then
            notes[#notes + 1] = "Champ « " .. tostring(champ) .. " » pas remis."
        end
    end
end

-- Position GPS ------------------------------------------------------------------------------

-- Position d'une photo (gps, gpsAltitude, gpsImgDirection : SDK 4.0 et 6.0), ou nil.
local function positionDe(photo)
    local gps = brut(photo, 'gps')
    if type(gps) ~= 'table' or tonumber(gps.latitude) == nil or tonumber(gps.longitude) == nil then
        return nil
    end
    return { latitude = tonumber(gps.latitude), longitude = tonumber(gps.longitude),
        altitude = tonumber(brut(photo, 'gpsAltitude')), direction = tonumber(brut(photo, 'gpsImgDirection')) }
end

local function textePosition(p)
    if not p then
        return "aucune"
    end
    local texte = string.format("%.5f, %.5f", p.latitude, p.longitude)
    if p.altitude then
        texte = texte .. string.format(" ; %d m", math.floor(p.altitude + 0.5))
    end
    return texte
end

local function memePosition(a, b)
    if a == nil or b == nil then
        return a == b
    end
    local function proche(x, y)
        if x == nil or y == nil then
            return x == y
        end
        return math.abs(x - y) < 1e-6
    end
    return proche(a.latitude, b.latitude) and proche(a.longitude, b.longitude) and proche(a.altitude, b.altitude)
        and proche(a.direction, b.direction)
end

-- Écrit une position (dans une écriture) ; nil l'efface. D'après la référence du SDK, gps s'efface
-- par nil ; l'altitude et la direction, supposé pareil (essayé sans faire échouer l'écriture).
local function poserPosition(photo, p)
    if p == nil then
        photo:setRawMetadata('gps', nil)
        LrTasks.pcall(photo.setRawMetadata, photo, 'gpsAltitude', nil)
        LrTasks.pcall(photo.setRawMetadata, photo, 'gpsImgDirection', nil)
        return
    end
    photo:setRawMetadata('gps', { latitude = p.latitude, longitude = p.longitude })
    if p.altitude then
        photo:setRawMetadata('gpsAltitude', p.altitude)
    else
        LrTasks.pcall(photo.setRawMetadata, photo, 'gpsAltitude', nil)
    end
    if p.direction then
        photo:setRawMetadata('gpsImgDirection', p.direction)
    else
        LrTasks.pcall(photo.setRawMetadata, photo, 'gpsImgDirection', nil)
    end
end

-- Photos de référence (un téléphone à la même séance) qui ont une position et une date de prise
-- de vue (lues avant l'écriture).
local function referencesGps(ids)
    local refs = {}
    for _, id in ipairs(liste(ids)) do
        local photo = photoParId(id)
        local p = positionDe(photo)
        local t = tonumber(brut(photo, 'dateTimeOriginal'))
        if p and t then
            refs[#refs + 1] = { photo = photo, position = p, date = t, fichier = nomFichier(photo) }
        end
    end
    if #refs == 0 then
        echouer("Aucune des photos de référence n'a à la fois une position GPS et une date de prise de vue.")
    end
    return refs
end

-- La position voulue pour une photo : donnée, effacée, ou celle de la référence prise le plus près
-- dans le temps (à `ecart` secondes au plus, l'horloge de l'appareil décalée de `decalage`). Le
-- second résultat est une remarque.
local function positionVoulue(photo, d)
    if d.gps then
        return not d.gps.aucune and d.gps or nil, nil
    end
    local g = d.gpsDepuis
    local t = tonumber(brut(photo, 'dateTimeOriginal'))
    if not t then
        return false, "Pas de date de prise de vue : position non posée."
    end
    t = t + g.decalage
    local meilleure, ecart
    for _, ref in ipairs(g.refs) do
        local e = math.abs(ref.date - t)
        if ref.photo ~= photo and (not ecart or e < ecart) then
            meilleure, ecart = ref, e
        end
    end
    if not meilleure then
        return false, "C'est la seule photo de référence : position gardée."
    end
    if ecart > g.ecart then
        return false, string.format("Aucune photo de référence à moins de %d min (la plus proche, « %s », à %d min) : position non posée.",
            math.floor(g.ecart / 60 + 0.5), meilleure.fichier, math.floor(ecart / 60 + 0.5))
    end
    local p = meilleure.position
    return { latitude = p.latitude, longitude = p.longitude, altitude = p.altitude },
        string.format("Position de « %s », prise à %d s d'écart.", meilleure.fichier, math.floor(ecart + 0.5))
end

local function poserGps(plan, d)
    local photo = plan.photo
    local voulue, note = positionVoulue(photo, d)
    if note then
        plan.notes[#plan.notes + 1] = note
    end
    if voulue == false then
        return
    end
    local avant = positionDe(photo)
    if memePosition(avant, voulue) then
        return
    end
    plan.avant.gps = avant or { aucune = true }
    changer(plan, 'gps', textePosition(avant), textePosition(voulue))
    poserPosition(photo, voulue)
end

-- Ce que demande la commande « metadonnees », vérifié.
local function demandesMetadonnees(params)
    local d, rien = {}, true
    if params.note ~= nil then
        d.note = tonumber(params.note)
        if not d.note or d.note < 0 or d.note > 5 or d.note ~= math.floor(d.note) then
            echouer("Note invalide : un entier de 0 (sans note) à 5 est attendu.")
        end
        rien = false
    end
    if params.drapeau ~= nil then
        d.drapeau = DRAPEAUX[tostring(params.drapeau)]
        if d.drapeau == nil then
            echouer("Drapeau invalide : « retenue », « rejetee » ou « aucun ».")
        end
        rien = false
    end
    if params.libelle ~= nil then
        d.libelle = tostring(params.libelle)
        if d.libelle ~= 'aucun' and not COULEURS[d.libelle] then
            echouer("Libellé invalide : rouge, jaune, vert, bleu, violet ou aucun.")
        end
        rien = false
    end
    for _, champ in ipairs(TEXTES) do
        if params[champ[1]] ~= nil then
            d[champ[1]] = tostring(params[champ[1]])
            rien = false
        end
    end
    d.ajouter, d.retirer = liste(params.ajouter), liste(params.retirer)
    if #d.ajouter + #d.retirer > 0 then
        rien = false
    end
    if params.preset_metadonnees ~= nil then
        d.presetMeta = presetMetadonnees(params.preset_metadonnees)
        rien = false
    end
    if type(params.iptc) == 'table' then
        local champs = {}
        for champ, valeur in pairs(params.iptc) do
            if not CHAMPS_ECRITS[champ] then
                echouer("Champ IPTC inconnu : « " .. tostring(champ) .. " ».")
            end
            champs[#champs + 1] = { champ, tostring(valeur) }
        end
        table.sort(champs, function(a, b) return a[1] < b[1] end)
        if #champs > 0 then
            if d.presetMeta then
                echouer("Un paramètre prédéfini de métadonnées et des champs IPTC ne s'écrivent pas dans le même appel : le paramètre prédéfini d'abord, puis les champs.")
            end
            d.iptc = champs
            rien = false
        end
    end
    if params.gps == 'aucune' then
        d.gps = { aucune = true }
        rien = false
    elseif type(params.gps) == 'table' then
        local g = params.gps
        local lat, lon = tonumber(g.latitude), tonumber(g.longitude)
        if not lat or not lon or lat < -90 or lat > 90 or lon < -180 or lon > 180 then
            echouer("Position GPS invalide : latitude de −90 à 90, longitude de −180 à 180 (degrés décimaux).")
        end
        local direction = tonumber(g.direction)
        if direction and (direction < 0 or direction >= 360) then
            echouer("Direction GPS invalide : de 0 à 360 degrés.")
        end
        d.gps = { latitude = lat, longitude = lon, altitude = tonumber(g.altitude), direction = direction }
        rien = false
    elseif type(params.gps_depuis) == 'table' then
        d.gpsDepuis = {
            refs = referencesGps(params.gps_depuis.photos),
            ecart = (tonumber(params.gps_depuis.ecart_max) or 30) * 60,
            decalage = (tonumber(params.gps_depuis.decalage) or 0) * 60,
        }
        rien = false
    end
    if rien then
        echouer("Aucune métadonnée à changer : note, drapeau, libellé, titre, légende, droits d'auteur, texte alternatif, champs IPTC, position GPS, mots-clés ou paramètre prédéfini de métadonnées.")
    end
    return d
end

-- Applique les demandes à une photo (dans l'écriture).
-- Paramètre prédéfini de métadonnées (dans l'écriture) : les champs IPTC et les mots-clés d'avant
-- vont dans la mémoire ; ce qu'il a changé se relit après l'écriture (relirePresetsMetadonnees) :
-- constaté en 2.3, applyMetadataPreset n'est pas visible dans l'écriture qui l'applique
-- (setRawMetadata l'est).
local function appliquerPresetMetadonnees(plan, preset)
    local photo = plan.photo
    local avantIptc = lireIptc(photo)
    local avantMots = {}
    for _, p in ipairs(motsClesDe(photo)) do
        avantMots[p.chemin] = true
    end
    photo:applyMetadataPreset(preset.id)
    local avant = plan.avant.iptc or {}
    for champ, valeur in pairs(avantIptc) do
        if avant[champ] == nil then
            avant[champ] = valeur
        end
    end
    plan.avant.iptc = avant
    plan.presetMetadonnees = { nom = preset.nom, iptc = avantIptc, mots = avantMots }
end

-- Après l'écriture : ce que le paramètre prédéfini a changé, dans la réponse et le journal (écriture
-- privée de la mémoire, sans opération dans Édition › Annuler) ; les mots-clés qu'il a ajoutés vont
-- dans l'étape, pour que l'annulation les retire.
local function relirePresetsMetadonnees(plans, etape)
    local aGarder = {}
    for _, plan in ipairs(plans) do
        local p = plan.presetMetadonnees
        if p then
            local photo = plan.photo
            local apres = lireIptc(photo)
            local changes = 0
            for _, champ in ipairs(CHAMPS_IPTC) do
                if apres[champ] ~= nil and apres[champ] ~= p.iptc[champ] then
                    changer(plan, champ, p.iptc[champ], apres[champ])
                    changes = changes + 1
                end
            end
            -- Les mots-clés ajoutés par add_keywords dans la même commande sont déjà dans l'étape.
            local deja = {}
            for _, chemin in ipairs(type(plan.avant.motsCles) == 'table' and liste(plan.avant.motsCles.ajoutes) or {}) do
                deja[chemin] = true
            end
            local ajoutes = Json.tableau()
            for _, mc in ipairs(motsClesDe(photo)) do
                if not p.mots[mc.chemin] and not deja[mc.chemin] then
                    ajoutes[#ajoutes + 1] = mc.chemin
                end
            end
            if #ajoutes > 0 then
                local cumul = type(plan.avant.motsCles) == 'table' and plan.avant.motsCles or { ajoutes = Json.tableau(), retires = Json.tableau() }
                for _, chemin in ipairs(ajoutes) do
                    cumul.ajoutes[#cumul.ajoutes + 1] = chemin
                end
                plan.avant.motsCles = cumul
                fusionnerOriginal(plan.original, { motsCles = { ajoutes = ajoutes, retires = Json.tableau() } })
                changer(plan, 'mots_cles', "—", table.concat(ajoutes, ", "))
            end
            if changes + #ajoutes == 0 then
                plan.notes[#plan.notes + 1] = "Paramètre prédéfini « " .. p.nom .. " » appliqué ; aucun champ n'a changé (la photo avait déjà ces valeurs)."
            end
            aGarder[#aGarder + 1] = plan
        end
    end
    if #aGarder == 0 then
        return
    end
    Ecriture.ecrireMemoire(etape, function()
        for _, plan in ipairs(aGarder) do
            if plan.entreeJournal then
                garder(plan.photo, 'journalClaude', Json.encode(Json.tableau(plan.journal)))
            end
            -- L'étape porte la même table plan.avant : les mots-clés ajoutés y sont maintenant.
            if #plan.etapes > 0 then
                garder(plan.photo, 'avantClaude', Json.encode(plan.original))
                garder(plan.photo, 'etapesClaude', Json.encode(Json.tableau(plan.etapes)))
            end
        end
    end)
end

local function classer(plan, d, tous, textes)
    local photo = plan.photo
    if d.note ~= nil and noteDe(photo) ~= d.note then
        plan.avant.note = noteDe(photo)
        changer(plan, 'note', plan.avant.note, d.note)
        ecrireChamp(photo, 'rating', d.note)
    end
    if d.drapeau ~= nil and drapeauDe(photo) ~= d.drapeau then
        plan.avant.drapeau = drapeauDe(photo)
        changer(plan, 'drapeau', NOMS_DRAPEAU[plan.avant.drapeau] or tostring(plan.avant.drapeau), NOMS_DRAPEAU[d.drapeau])
        photo:setRawMetadata('pickStatus', d.drapeau)
    end
    if d.libelle ~= nil then
        poserLibelle(plan, d.libelle, textes)
    end
    for _, champ in ipairs(TEXTES) do
        local voulu = d[champ[1]]
        local actuel = meta(photo, champ[2]) or ''
        if voulu ~= nil and voulu ~= actuel then
            plan.avant[champ[1]] = actuel
            changer(plan, champ[1], actuel, voulu)
            ecrireChamp(photo, champ[2], voulu)
        end
    end
    -- Texte alternatif, description longue et champs IPTC : un texte vide les efface.
    for _, paire in ipairs(d.iptc or {}) do
        local champ, voulu = paire[1], paire[2]
        local actuel = lireTexte(photo, champ)
        if voulu ~= actuel then
            plan.avant.iptc = plan.avant.iptc or {}
            plan.avant.iptc[champ] = actuel
            changer(plan, champ, actuel, voulu)
            ecrireChamp(photo, champ, voulu)
        end
    end
    if d.gps or d.gpsDepuis then
        poserGps(plan, d)
    end
    -- Le paramètre prédéfini d'abord : il relit les mots-clés de la photo, qui ne doivent pas encore
    -- porter un mot-clé créé dans cette écriture (illisible jusqu'à sa fin).
    if d.presetMeta then
        appliquerPresetMetadonnees(plan, d.presetMeta)
    end
    if #d.ajouter + #d.retirer > 0 then
        poserMotsCles(plan, d.ajouter, d.retirer, tous)
    end
end

-- Remet ce qu'une étape de Claude avait changé dans la Bibliothèque (dans une écriture : annulation,
-- retour à l'origine). Les remarques vont dans `notes`.
function Bibliotheque.remettre(photo, avant, notes)
    if type(avant) ~= 'table' then
        return
    end
    if avant.note ~= nil then
        ecrireChamp(photo, 'rating', tonumber(avant.note) or 0)
    end
    if avant.drapeau ~= nil then
        photo:setRawMetadata('pickStatus', tonumber(avant.drapeau) or 0)
    end
    if avant.libelle ~= nil then
        ecrireChamp(photo, 'label', tostring(avant.libelle))
    end
    for _, champ in ipairs(TEXTES) do
        if avant[champ[1]] ~= nil then
            ecrireChamp(photo, champ[2], tostring(avant[champ[1]]))
        end
    end
    local motsCles = type(avant.motsCles) == 'table' and avant.motsCles or {}
    if #liste(motsCles.ajoutes) + #liste(motsCles.retires) > 0 then
        local poses = motsClesDe(photo)
        for _, chemin in ipairs(liste(motsCles.ajoutes)) do
            for _, p in ipairs(poses) do
                if p.chemin == chemin then
                    photo:removeKeyword(p.motCle)
                end
            end
        end
        local tous = tousLesMotsCles()
        for _, chemin in ipairs(liste(motsCles.retires)) do
            local trouve = trouverMotCle(morceaux(chemin), tous)
            if trouve then
                photo:addKeyword(trouve.motCle)
            elseif notes then
                notes[#notes + 1] = "Mot-clé « " .. chemin .. " » introuvable dans le catalogue : pas remis."
            end
        end
    end
    local collections = type(avant.collections) == 'table' and avant.collections or {}
    local cat = catalogue()
    for _, sens in ipairs({ { 'ajoutes', 'removePhotos' }, { 'retires', 'addPhotos' } }) do
        for _, id in ipairs(liste(collections[sens[1]])) do
            local ok, c = LrTasks.pcall(cat.getCollectionByLocalIdentifier, cat, tonumber(id))
            if ok and c then
                c[sens[2]](c, { photo })
            elseif notes then
                notes[#notes + 1] = string.format("Collection %s introuvable : %s n'y est pas remise comme avant.", tostring(id), nomFichier(photo))
            end
        end
    end
    if type(avant.iptc) == 'table' then
        remettreIptc(photo, avant.iptc, notes)
    end
    if type(avant.gps) == 'table' then
        poserPosition(photo, not avant.gps.aucune and {
            latitude = tonumber(avant.gps.latitude), longitude = tonumber(avant.gps.longitude),
            altitude = tonumber(avant.gps.altitude), direction = tonumber(avant.gps.direction),
        } or nil)
    end
end

-- Commandes ------------------------------------------------------------------------------

-- Classement d'une photo (get_settings) : note, drapeau, libellé, titre et mots-clés.
function Bibliotheque.classement(photo)
    local chemins = Json.tableau()
    for _, p in ipairs(motsClesDe(photo)) do
        chemins[#chemins + 1] = p.chemin
    end
    table.sort(chemins)
    local iptc = {}
    for champ in pairs(CHAMPS_ECRITS) do
        local valeur = lireTexte(photo, champ)
        if valeur ~= '' and not CHAMPS_BRUTS[champ] then
            iptc[champ] = valeur
        end
    end
    local position = positionDe(photo)
    return {
        note = noteDe(photo),
        drapeau = NOMS_DRAPEAU[drapeauDe(photo)] or tostring(drapeauDe(photo)),
        libelle = nomLibelle(meta(photo, 'label'), couleurDe(photo)),
        titre = meta(photo, 'title') or '',
        texte_alternatif = lireTexte(photo, 'altTextAccessibility'),
        description_longue = lireTexte(photo, 'extDescrAccessibility'),
        iptc = next(iptc) and iptc or Json.null,
        gps = position or Json.null,
        exportee = Photos.exportee(photo),
        mots_cles = chemins,
    }
end

-- Note, drapeau, libellé, titre, légende, droits d'auteur et mots-clés des photos visées, en une
-- écriture ; chaque photo garde une étape que undo_last défait.
function Bibliotheque.metadonnees(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'set_metadata')
    local d = demandesMetadonnees(params)
    local etape = nomEtape(params, "classement")
    local photos = photosVisees(params)
    verifierProtection(photos, prefs, params, 'set_metadata')
    local plans = {}
    for _, photo in ipairs(photos) do
        plans[#plans + 1] = nouveauClassement(photo)
    end
    local textes = d.libelle and d.libelle ~= 'aucun' and textesDuLibelle(d.libelle) or {}
    local tous = (#d.ajouter + #d.retirer > 0) and tousLesMotsCles() or {}
    local aCreer = #d.ajouter > 0 and motsClesACreer(d.ajouter, tous, params.synonymes) or {}
    local crees = {}
    ecrire(etape, function()
        crees = creerMotsCles(aCreer, tous)
        for _, plan in ipairs(plans) do
            classer(plan, d, tous, textes)
            memoriser(plan, etape, params)
        end
    end)
    verifierLibelles(plans, etape)
    relirePresetsMetadonnees(plans, etape)
    local resultat = { mode = modeTexte(prefs), resultats = resultatsPlans(plans, etape, params) }
    if #crees > 0 then
        resultat.mots_cles_crees = crees
    end
    return resultat
end

-- Notes posées depuis la fenêtre Claude (Notation.poser) : params.notes = { { photo, note (0 à 5)
-- ou nil, drapeau ('aucun', 'rejetee', 'retenue') ou nil, raison } }, chaque photo avec sa note,
-- en une écriture ; une étape par photo, que undo_last défait, avec sa raison au journal. Une
-- photo donnée deux fois ne compte qu'une fois, avec sa dernière valeur : dans une écriture,
-- Lightroom relit un champ du module avec sa valeur d'avant (constaté le 20 octobre 2026), la
-- seconde étape effacerait la première. Les garde-fous des photos restent (copies virtuelles
-- seulement, libellé protégé, photos rejetées), même avec depuisLightroom et confirme, qui lèvent
-- la pause, « Proposer d'abord » et le plafond de photos par écriture. Une note de l'utilisateur
-- n'entre pas dans l'état d'avant Claude : le retour à l'origine la laisse en place.
-- params.outil : l'outil de Claude à rappeler après un accord (propose_ratings, quand Claude pose
-- les notes à la demande de Dany), set_metadata sans lui.
local MAX_NOTES = 500

function Bibliotheque.noter(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    local outil = params.outil or 'set_metadata'
    verifierAccord(prefs, params, outil)
    local demandes = {}
    for _, n in ipairs(type(params.notes) == 'table' and params.notes or {}) do
        if type(n) ~= 'table' or n.photo == nil then
            echouer("Note sans photo.")
        end
        local d = { ajouter = {}, retirer = {}, raison = type(n.raison) == 'string' and n.raison ~= '' and n.raison or nil }
        if n.note ~= nil then
            d.note = tonumber(n.note)
            if not d.note or d.note < 0 or d.note > 5 or d.note ~= math.floor(d.note) then
                echouer("Note invalide : un entier de 0 (sans note) à 5 est attendu.")
            end
        end
        if n.drapeau ~= nil then
            d.drapeau = DRAPEAUX[tostring(n.drapeau)]
            if d.drapeau == nil then
                echouer("Drapeau invalide : « retenue », « rejetee » ou « aucun ».")
            end
        end
        if d.note == nil and d.drapeau == nil then
            echouer("Rien à poser pour la photo " .. tostring(n.photo) .. " : une note ou un drapeau.")
        end
        demandes[#demandes + 1] = { photo = photoParId(n.photo), d = d }
    end
    if #demandes == 0 then
        echouer("Aucune note à poser.")
    end
    local photos, plans, parId = {}, {}, {}
    for _, demande in ipairs(demandes) do
        local plan = parId[demande.photo.localIdentifier]
        if plan then
            plan.demande = demande.d
            plan.double = true
        else
            plan = nouveauClassement(demande.photo)
            plan.demande = demande.d
            parId[demande.photo.localIdentifier] = plan
            plans[#plans + 1] = plan
            photos[#photos + 1] = demande.photo
        end
    end
    if #photos > MAX_NOTES then
        echouer(string.format("%d photos à noter : au plus %d par écriture.", #photos, MAX_NOTES))
    end
    local etape = nomEtape(params, "notation")
    verifierProtection(photos, prefs, params, outil)
    ecrire(etape, function()
        for _, plan in ipairs(plans) do
            classer(plan, plan.demande, {}, {})
            memoriser(plan, etape, { raison = plan.demande.raison }, true)
        end
    end)
    for _, plan in ipairs(plans) do
        if plan.double then
            plan.notes[#plan.notes + 1] = "Photo donnée plusieurs fois : seule la dernière note compte."
        end
    end
    return { mode = modeTexte(prefs), resultats = resultatsPlans(plans, etape, params) }
end

-- Mots-clés du catalogue, par chemin, avec le nombre de photos de chacun.
function Bibliotheque.motsCles(params)
    local filtre = type(params.filtre) == 'string' and minuscules(params.filtre) or nil
    local limite = tonumber(params.limite) or 200
    local resultat, total = Json.tableau(), 0
    for _, m in ipairs(tousLesMotsCles()) do
        if not filtre or minuscules(m.chemin):find(filtre, 1, true) then
            total = total + 1
            if #resultat < limite then
                local ok, photos = LrTasks.pcall(m.motCle.getPhotos, m.motCle)
                local okS, synonymes = LrTasks.pcall(m.motCle.getSynonyms, m.motCle)
                resultat[#resultat + 1] = { chemin = m.chemin, photos = ok and type(photos) == 'table' and #photos or Json.null,
                    synonymes = okS and type(synonymes) == 'table' and #synonymes > 0 and Json.tableau({ unpack(synonymes) }) or nil }
            end
        end
    end
    return { total = total, renvoyes = #resultat, mots_cles = resultat }
end

-- Recherche -------------------------------------------------------------------------------

-- « 2026-07-21 » → texte comparable à la date d'une photo.
local function dateVoulue(texte, nom)
    if texte == nil then
        return nil
    end
    local a, m, j = tostring(texte):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not a then
        echouer(nom .. " invalide : une date AAAA-MM-JJ est attendue.")
    end
    return a .. '-' .. m .. '-' .. j
end

-- Critères → searchDesc de findPhotos, et ce qui se filtre après coup.
local function recherche(params)
    local criteres, apres = {}, {}
    local function ajouter(critere)
        criteres[#criteres + 1] = critere
    end
    if params.texte then
        ajouter({ criteria = 'all', operation = 'all', value = tostring(params.texte) })
    end
    if params.mots_cles then
        ajouter({ criteria = 'keywords', operation = 'words', value = tostring(params.mots_cles) })
    end
    if params.sans_mots_cles then
        ajouter({ criteria = 'keywords', operation = 'empty' })
    end
    if tonumber(params.note_min) then
        ajouter({ criteria = 'rating', operation = '>=', value = tonumber(params.note_min) })
    end
    if tonumber(params.note_max) then
        ajouter({ criteria = 'rating', operation = '<=', value = tonumber(params.note_max) })
    end
    if params.drapeau then
        local valeur = DRAPEAUX[tostring(params.drapeau)]
        if valeur == nil then
            echouer("Drapeau invalide : « retenue », « rejetee » ou « aucun ».")
        end
        ajouter({ criteria = 'pick', operation = '==', value = valeur })
    end
    if params.libelle then
        local nom = tostring(params.libelle)
        if nom == 'aucun' then
            apres.sansLibelle = true
        elseif COULEURS[nom] then
            ajouter({ criteria = 'labelColor', operation = '==', value = COULEURS[nom].numero })
        else
            echouer("Libellé invalide : rouge, jaune, vert, bleu, violet ou aucun.")
        end
    end
    if params.appareil then
        ajouter({ criteria = 'camera', operation = '==', value = tostring(params.appareil) })
    end
    if params.objectif then
        ajouter({ criteria = 'lens', operation = '==', value = tostring(params.objectif) })
    end
    if tonumber(params.iso_min) then
        ajouter({ criteria = 'isoSpeedRating', operation = '>=', value = tonumber(params.iso_min) })
    end
    if tonumber(params.iso_max) then
        ajouter({ criteria = 'isoSpeedRating', operation = '<=', value = tonumber(params.iso_max) })
    end
    if params.format then
        ajouter({ criteria = 'fileFormat', operation = '==', value = tostring(params.format):upper() })
    end
    if tonumber(params.depuis_jours) then
        ajouter({ criteria = 'captureTime', operation = 'inLast', value = tonumber(params.depuis_jours), value_units = 'days' })
    end
    if params.retouchee_par_claude ~= nil then
        ajouter({ criteria = 'sdktext:' .. _PLUGIN.id .. '.retoucheeParClaude',
            operation = params.retouchee_par_claude == true and 'notEmpty' or 'empty' })
    end
    apres.debut = dateVoulue(params.date_debut, "date_debut")
    apres.fin = dateVoulue(params.date_fin, "date_fin")
    if params.copies_virtuelles == 'seulement' or params.copies_virtuelles == 'exclure' then
        apres.copies = params.copies_virtuelles
    end
    -- Déjà exportée ou jamais (isExported, SDK 13.3) : filtrée après coup.
    if params.exportee ~= nil then
        apres.exportee = params.exportee == true
    end
    local desc = { combine = 'intersect' }
    for i, critere in ipairs(criteres) do
        desc[i] = critere
    end
    return desc, apres
end

local function trouverDossier(chemin)
    local cat = catalogue()
    local ok, dossier = LrTasks.pcall(cat.getFolderByPath, cat, tostring(chemin))
    if not ok or not dossier then
        echouer("Dossier introuvable dans le catalogue : « " .. tostring(chemin) .. " » (chemin complet attendu).")
    end
    return dossier
end

local function chercherPhotos(desc)
    local cat = catalogue()
    local ok, photos = LrTasks.pcall(cat.findPhotos, cat, { searchDesc = desc })
    if not ok then
        echouer("Lightroom refuse la recherche : " .. tostring(Liaison.messageErreur(photos)))
    end
    return photos or {}
end

-- Photos qui répondent à la recherche, filtrées et triées ; et les remarques.
local function resultatsRecherche(params)
    local desc, apres = recherche(params)
    local base, remarques = nil, Json.tableau()
    if params.dossier then
        base = trouverDossier(params.dossier):getPhotos(params.sous_dossiers ~= false)
    end
    if params.collection then
        local photos = trouverCollection(params.collection).collection:getPhotos()
        if base then
            local ids = {}
            for _, photo in ipairs(photos) do
                ids[photo.localIdentifier] = true
            end
            local communes = {}
            for _, photo in ipairs(base) do
                if ids[photo.localIdentifier] then
                    communes[#communes + 1] = photo
                end
            end
            base = communes
        else
            base = photos
        end
    end
    local photos
    if #desc > 0 then
        photos = chercherPhotos(desc)
        if base then
            local ids = {}
            for _, photo in ipairs(photos) do
                ids[photo.localIdentifier] = true
            end
            local communes = {}
            for _, photo in ipairs(base) do
                if ids[photo.localIdentifier] then
                    communes[#communes + 1] = photo
                end
            end
            photos = communes
        end
    elseif base then
        photos = base
    elseif next(apres) then
        echouer("Préciser la recherche : un filtre de date, de copie virtuelle ou d'exportation seul parcourrait tout le catalogue. Ajouter un critère (texte, note, drapeau, appareil, dossier, collection, depuis_jours…).")
    else
        echouer("Aucun critère de recherche.")
    end

    local tri = params.tri or 'date'
    if next(apres) or tri ~= 'aucun' then
        if #photos > MAX_TRI then
            if next(apres) then
                echouer(string.format("%d photos avant le filtre des dates, des copies virtuelles, des libellés ou de l'exportation : c'est plus que %d. Préciser la recherche.", #photos, MAX_TRI))
            end
            remarques[#remarques + 1] = string.format("%d photos : trop pour les trier (%d au plus) ; dans l'ordre de Lightroom.", #photos, MAX_TRI)
            tri = 'aucun'
        end
    end
    if next(apres) or tri ~= 'aucun' then
        local donnees = catalogue():batchGetRawMetadata(photos, { 'dateTimeOriginal', 'isVirtualCopy', 'colorNameForLabel', 'rating', 'isExported' })
        local champs = apres.exportee ~= nil and catalogue():batchGetPropertyForPlugin(photos, _PLUGIN, { 'apercuSeulement' }) or {}
        local function d(photo)
            return donnees[photo] or {}
        end
        if next(apres) then
            local gardees = {}
            for _, photo in ipairs(photos) do
                local valeurs = d(photo)
                -- Le jour de la prise de vue à l'heure locale, comme Lightroom l'affiche. Constaté en
                -- 2.4 : timeToW3CDate le donne en UTC, et une photo prise à 20 h 13 (heure de
                -- l'Est) comptait pour le lendemain.
                local t = tonumber(valeurs.dateTimeOriginal)
                local jour = t and LrDate.timeToUserFormat(t, '%Y-%m-%d') or nil
                local garde = true
                if apres.debut and (not jour or jour < apres.debut) then garde = false end
                if apres.fin and (not jour or jour > apres.fin) then garde = false end
                if apres.copies == 'seulement' and valeurs.isVirtualCopy ~= true then garde = false end
                if apres.copies == 'exclure' and valeurs.isVirtualCopy == true then garde = false end
                if apres.exportee ~= nil
                    and Photos.exportee(photo, valeurs.isExported == true, (champs[photo] or {}).apercuSeulement) ~= apres.exportee then
                    garde = false
                end
                if apres.sansLibelle and valeurs.colorNameForLabel ~= nil and valeurs.colorNameForLabel ~= '' and valeurs.colorNameForLabel ~= 'none' then
                    garde = false
                end
                if garde then
                    gardees[#gardees + 1] = photo
                end
            end
            photos = gardees
        end
        if tri ~= 'aucun' then
            local cles = {}
            for _, photo in ipairs(photos) do
                local valeurs = d(photo)
                cles[photo] = tri == 'note' and -(tonumber(valeurs.rating) or 0) or (tonumber(valeurs.dateTimeOriginal) or 0)
            end
            local inverse = tri == 'date_desc'
            table.sort(photos, function(a, b)
                if cles[a] ~= cles[b] then
                    if inverse then return cles[a] > cles[b] end
                    return cles[a] < cles[b]
                end
                return a.localIdentifier < b.localIdentifier
            end)
        end
    end
    return photos, remarques
end

function Bibliotheque.chercher(params)
    local photos, remarques = resultatsRecherche(params)
    local limite = math.min(tonumber(params.limite) or 50, MAX_RESULTATS)
    local decalage = math.max(tonumber(params.decalage) or 0, 0)
    local page = {}
    for i = decalage + 1, math.min(#photos, decalage + limite) do
        page[#page + 1] = photos[i]
    end
    local liste = Json.tableau()
    for i, d in ipairs(Photos.decrireTout(page)) do
        if params.mots_cles_details then
            local chemins = Json.tableau()
            for _, p in ipairs(motsClesDe(page[i])) do
                chemins[#chemins + 1] = p.chemin
            end
            d.mots_cles = chemins
        end
        liste[#liste + 1] = d
    end
    Liaison.noter(string.format("Recherche pour Claude : %d photo(s)", #photos))
    return { total = #photos, decalage = decalage, renvoyees = #liste, photos = liste, remarques = remarques }
end

-- Collections (commande « collections ») : lister, créer (dans l'ensemble « Claude » par défaut,
-- dynamique avec une recherche), ajouter ou retirer des photos. Ajouter et retirer gardent une
-- étape par photo, que undo_last défait ; une collection créée reste.
local function listerCollections()
    local collections, ensembles = toutesLesCollections()
    local resultat = Json.tableau()
    for _, c in ipairs(collections) do
        local ok, photos = LrTasks.pcall(c.collection.getPhotos, c.collection)
        resultat[#resultat + 1] = { id = c.id, nom = c.nom, ensemble = c.ensemble or Json.null, dynamique = c.dynamique,
            photos = ok and type(photos) == 'table' and #photos or Json.null }
    end
    local chemins = Json.tableau()
    for _, e in ipairs(ensembles) do
        chemins[#chemins + 1] = e.chemin
    end
    return { collections = resultat, ensembles = chemins }
end

local function membreDe(photo, id)
    local ok, collections = LrTasks.pcall(photo.getContainedCollections, photo)
    for _, c in ipairs(ok and collections or {}) do
        if c.localIdentifier == id then
            return true
        end
    end
    return false
end

-- Ajoute ou retire les photos d'une collection (dans l'écriture), avec leur étape.
local function changerMembres(c, photos, ajouter, etape, params)
    local plans = {}
    for _, photo in ipairs(photos) do
        local plan = nouveauClassement(photo)
        if membreDe(photo, c.id) ~= ajouter then
            if ajouter then
                c.collection:addPhotos({ photo })
            else
                c.collection:removePhotos({ photo })
            end
            plan.avant.collections = { ajoutes = Json.tableau(ajouter and { c.id } or {}), retires = Json.tableau(ajouter and {} or { c.id }) }
            changer(plan, 'collection', ajouter and "—" or c.nom, ajouter and c.nom or "—")
            memoriser(plan, etape, params)
        else
            plan.notes[#plan.notes + 1] = ajouter and ("Déjà dans « " .. c.nom .. " ».") or ("Pas dans « " .. c.nom .. " » : rien à retirer.")
        end
        plans[#plans + 1] = plan
    end
    return plans
end

-- Renommer ou déplacer une collection, changer les critères d'une collection dynamique (setName,
-- setParent, setSearchDescription, SDK 3.0) : la structure du catalogue, pas les photos ; undo_last
-- ne le défait pas (Édition › Annuler de Lightroom, oui), la réponse dit l'état d'avant. Jamais de
-- suppression.
local function reorganiser(action, params, etape, resultat)
    local c = trouverCollection(params.collection)
    local avant = { nom = c.nom, ensemble = c.ensemble or Json.null, dynamique = c.dynamique }
    local apres = { nom = c.nom, ensemble = c.ensemble or Json.null, dynamique = c.dynamique }
    if action == 'renommer' then
        local nom = tostring(params.nouveau_nom or '')
        if nom:gsub('%s', '') == '' then
            echouer("Nouveau nom manquant.")
        end
        ecrire(etape, function() c.collection:setName(nom) end)
        apres.nom = nom
        Liaison.noter("Collection « " .. c.nom .. " » renommée « " .. nom .. " » pour Claude")
    elseif action == 'deplacer' then
        local chemin = params.ensemble ~= nil and tostring(params.ensemble) or ENSEMBLE_CLAUDE
        -- L'ensemble dans sa propre écriture (créé au besoin), puis le déplacement.
        local ensemble = chemin ~= '' and obtenirEnsemble(chemin) or nil
        ecrire(etape, function() c.collection:setParent(ensemble) end)
        apres.ensemble = chemin ~= '' and chemin or Json.null
        Liaison.noter("Collection « " .. c.nom .. " » déplacée pour Claude")
    else
        if not c.dynamique then
            echouer("« " .. c.nom .. " » n'est pas une collection dynamique : ses photos s'ajoutent et se retirent (add, remove).")
        end
        local desc, apresCoup = recherche(type(params.recherche) == 'table' and params.recherche or {})
        if #desc == 0 or next(apresCoup) then
            echouer("Une collection dynamique prend les critères que Lightroom cherche lui-même : texte, mots-clés, note, drapeau, libellé de couleur, appareil, objectif, ISO, format, depuis_jours, retouchée par Claude.")
        end
        local okA, ancienne = LrTasks.pcall(c.collection.getSearchDescription, c.collection)
        ecrire(etape, function() c.collection:setSearchDescription(desc) end)
        avant.criteres = okA and type(ancienne) == 'table' and ancienne or Json.null
        apres.criteres = desc
        Liaison.noter("Critères de « " .. c.nom .. " » changés pour Claude")
    end
    resultat.collection = { id = c.id, avant = avant, apres = apres }
    resultat.a_savoir = "La structure du catalogue (nom, ensemble, critères) : undo_last ne la défait pas ; pour revenir, la même action avec les valeurs d'avant (ou Édition › Annuler dans Lightroom)."
    return resultat
end

-- Renommer un mot-clé ou changer ses synonymes (LrKeyword:setAttributes, SDK 3.0). Jamais de
-- suppression.
local function changerMotCle(params, etape, resultat)
    local textes = morceaux(params.mot_cle or '')
    if #textes == 0 then
        echouer("Mot-clé manquant.")
    end
    local trouve = trouverMotCle(textes, tousLesMotsCles()) or echouer("Mot-clé « " .. tostring(params.mot_cle) .. " » introuvable (list_keywords).")
    local okS, anciens = LrTasks.pcall(trouve.motCle.getSynonyms, trouve.motCle)
    local attributs, avant, apres = {}, { chemin = trouve.chemin }, { chemin = trouve.chemin }
    if params.nouveau_nom ~= nil then
        local nom = tostring(params.nouveau_nom)
        if nom:gsub('%s', '') == '' or nom:find('[>|›]') then
            echouer("Nouveau nom de mot-clé invalide (vide, ou avec > | ›).")
        end
        attributs.keywordName = nom
        local parents = {}
        for i = 1, #trouve.morceaux - 1 do
            parents[i] = trouve.morceaux[i]
        end
        parents[#parents + 1] = nom
        apres.chemin = table.concat(parents, ' > ')
    end
    if type(params.synonymes) == 'table' then
        local synonymes = {}
        for _, texte in ipairs(params.synonymes) do
            if tostring(texte):gsub('%s', '') ~= '' then
                synonymes[#synonymes + 1] = tostring(texte)
            end
        end
        attributs.synonyms = synonymes
        avant.synonymes = Json.tableau({ unpack(okS and type(anciens) == 'table' and anciens or {}) })
        -- Une copie : Json.tableau marque la table qu'il reçoit, et Lightroom refuse une métatable.
        apres.synonymes = Json.tableau({ unpack(synonymes) })
    end
    if next(attributs) == nil then
        echouer("Rien à changer : nouveau nom ou synonymes.")
    end
    ecrire(etape, function() trouve.motCle:setAttributes(attributs) end)
    Liaison.noter("Mot-clé « " .. trouve.chemin .. " » changé pour Claude")
    resultat.mot_cle = { avant = avant, apres = apres }
    resultat.a_savoir = "undo_last ne défait pas un mot-clé renommé : pour revenir, la même action avec les valeurs d'avant (ou Édition › Annuler dans Lightroom)."
    return resultat
end

function Bibliotheque.collections(params)
    local action = tostring(params.action or '')
    if action == 'lister' then
        return listerCollections()
    end
    local actions = { creer = true, ajouter = true, retirer = true, renommer = true, deplacer = true, criteres = true, mot_cle = true }
    if not actions[action] then
        echouer("Action inconnue : « " .. action .. " » (lister, creer, ajouter, retirer, renommer, deplacer, criteres ou mot_cle).")
    end
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'manage_collections')
    local etape = nomEtape(params, "collection")
    local resultat = { mode = modeTexte(prefs) }
    if action == 'renommer' or action == 'deplacer' or action == 'criteres' then
        return reorganiser(action, params, etape, resultat)
    elseif action == 'mot_cle' then
        return changerMotCle(params, etape, resultat)
    end

    if action == 'creer' then
        local nom = tostring(params.nom or '')
        if nom:gsub('%s', '') == '' then
            echouer("Nom de collection manquant.")
        end
        local cheminEnsemble = params.ensemble ~= nil and tostring(params.ensemble) or ENSEMBLE_CLAUDE
        local desc
        if type(params.recherche) == 'table' then
            local apres
            desc, apres = recherche(params.recherche)
            if #desc == 0 or next(apres) then
                echouer("Une collection dynamique prend les critères que Lightroom cherche lui-même : texte, mots-clés, note, drapeau, libellé de couleur, appareil, objectif, ISO, format, depuis_jours, retouchée par Claude (pas les dates exactes, le dossier ni les copies virtuelles).")
            end
        end
        local photos = (params.photos or params.selection) and photosVisees(params) or {}
        verifierProtection(photos, prefs, params, 'manage_collections')
        -- L'ensemble, la collection et ses photos, chacun dans sa propre écriture. Constaté dans
        -- Lightroom Classic 15.6 : « Can't get collection information after creating collection
        -- inside the same withWriteAccessDo function ».
        local ensemble = cheminEnsemble ~= '' and obtenirEnsemble(cheminEnsemble) or nil
        local creee, plans
        ecrire(etape, function()
            local cat = catalogue()
            if desc then
                creee = cat:createSmartCollection(nom, desc, ensemble, true)
            else
                creee = cat:createCollection(nom, ensemble, true)
            end
        end)
        if not creee then
            echouer("Lightroom n'a pas créé la collection « " .. nom .. " ».")
        end
        local id = creee.localIdentifier
        if #photos > 0 and not desc then
            ecrire(etape, function()
                plans = changerMembres({ collection = creee, id = id, nom = nom }, photos, true, etape, params)
            end)
        end
        resultat.collection = { id = id, nom = nom, ensemble = cheminEnsemble ~= '' and cheminEnsemble or Json.null, dynamique = desc ~= nil }
        if plans then
            resultat.resultats = resultatsPlans(plans, etape, params)
        end
        Liaison.noter("Collection « " .. nom .. " » créée pour Claude")
        return resultat
    end

    local c = trouverCollection(params.collection)
    if c.dynamique then
        echouer("« " .. c.nom .. " » est une collection dynamique : ses photos viennent de sa recherche, pas d'un ajout.")
    end
    local photos = photosVisees(params)
    verifierProtection(photos, prefs, params, 'manage_collections')
    local plans
    ecrire(etape, function()
        plans = changerMembres(c, photos, action == 'ajouter', etape, params)
    end)
    resultat.collection = { id = c.id, nom = c.nom, ensemble = c.ensemble or Json.null }
    resultat.resultats = resultatsPlans(plans, etape, params)
    return resultat
end

-- Copies virtuelles (commande « copieVirtuelle ») : Lightroom les crée pour les photos
-- sélectionnées ; le module les sélectionne le temps de l'opération, puis remet la sélection (ou
-- montre les copies, avec `afficher`). Constaté dans Lightroom Classic 15.6 : la copie reçoit les
-- champs du module de son original (voir « Propriétaire de la mémoire » dans Photos.lua).
local function copiesDe(photo)
    local original = brut(photo, 'masterPhoto') or photo
    local ids = {}
    for _, copie in ipairs(liste(brut(original, 'virtualCopies'))) do
        ids[copie.localIdentifier] = copie
    end
    return ids, original
end

-- Renvoie aussi si elles ont été créées hors d'une écriture (dit dans la fenêtre de la liaison).
-- Constaté en 2.3 (Lightroom Classic 15.6) : createVirtualCopies se fait dans une écriture ; le
-- second chemin reste pour une autre version.
local function creerCopies(nom)
    local cat = catalogue()
    local copies
    local ok, erreur = LrTasks.pcall(function()
        ecrire("Claude · copie virtuelle", function()
            copies = cat:createVirtualCopies(nom)
        end)
    end)
    if not ok then
        -- Hors d'une écriture, si Lightroom refuse de la faire dans withWriteAccessDo.
        local horsEcriture, resultat = LrTasks.pcall(cat.createVirtualCopies, cat, nom)
        if not horsEcriture then
            echouer("Lightroom n'a pas créé de copie virtuelle : " .. tostring(Liaison.messageErreur(erreur)))
        end
        return resultat, true
    end
    return copies, false
end

function Bibliotheque.copieVirtuelle(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'create_virtual_copy')
    local photos = photosVisees(params)
    local nom = tostring(params.nom or "Claude")
    local cat = catalogue()
    local vue = { active = cat:getTargetPhoto(), selection = cat:getTargetPhotos() }
    local avant = {}
    for _, photo in ipairs(photos) do
        avant[photo.localIdentifier] = copiesDe(photo)
    end
    local selectionnees, sourceChangee, sources = selectionnerAvecSource(photos)
    if not selectionnees then
        echouer("Lightroom n'a pas sélectionné " .. (#photos > 1 and "ces photos" or "« " .. nomFichier(photos[1]) .. " »")
            .. " : les afficher dans le film fixe (dossier ou collection), puis réessayer.")
    end
    local _, horsEcriture = creerCopies(nom)
    -- Les nouvelles copies, d'après celles de chaque original avant et après (createVirtualCopies
    -- ne les rend pas toujours).
    local nouvelles, vues = Json.tableau(), {}
    for _, photo in ipairs(photos) do
        local apres = copiesDe(photo)
        for id, copie in pairs(apres) do
            if not avant[photo.localIdentifier][id] and not vues[id] then
                vues[id] = true
                local d = decrire(copie, false)
                d.original = photo.localIdentifier
                nouvelles[#nouvelles + 1] = d
            end
        end
    end
    if params.afficher and #nouvelles > 0 then
        local copies = {}
        for _, d in ipairs(nouvelles) do
            copies[#copies + 1] = photoParId(d.id)
        end
        selectionner(copies)
    else
        remettreSelection(vue.active, vue.selection, sourceChangee and sources or nil)
    end
    Liaison.noter(string.format("%d copie(s) virtuelle(s) « %s » créée(s) %s", #nouvelles, nom,
        horsEcriture and "hors d'une écriture" or "dans une écriture"))
    local resultat = { mode = modeTexte(prefs), copies = nouvelles,
        a_savoir = "Une copie virtuelle ne s'annule pas par undo_last : la supprimer dans Lightroom au besoin (Photo › Supprimer la photo)." }
    if #nouvelles < #photos then
        resultat.remarque = string.format("%d copie(s) trouvée(s) pour %d photo(s) : vérifier dans Lightroom.", #nouvelles, #photos)
    end
    return resultat
end

-- Vues de LrApplicationView.showView (relevées dans LrApplicationView.lua de Lightroom Classic
-- 15.6) : de la Bibliothèque, et l'avant/après du module Développement.
local VUES_BIBLIOTHEQUE = { loupe = 'loupe', grille = 'grid', comparer = 'compare', ensemble = 'survey' }
local VUE_AVANT_APRES = 'develop_before_after_horiz'

-- Filtre de la Bibliothèque ----------------------------------------------------------------

-- Le filtre affiché avant le premier changement de Claude, depuis le chargement du module : celui
-- que remettre_filtre remet.
local filtreAvantClaude

-- Copie d'un filtre (ses tables imbriquées aussi) : Lightroom ne reçoit pas la table qu'il a donnée.
local function copieFiltre(valeur)
    if type(valeur) ~= 'table' then
        return valeur
    end
    local copie = {}
    for cle, v in pairs(valeur) do
        copie[cle] = copieFiltre(v)
    end
    return copie
end

-- Critères simples → valeurs d'un filtre, sur la copie du filtre actuel (getCurrentViewFilter, SDK
-- 3.0) : drapeau, note minimale, libellé de couleur, texte ; « aucun » coupe les filtres. Constaté
-- en 2.4 (Lightroom Classic 15.6) : un critère vide vaut le texte « <nil> » (comme dans les
-- paramètres prédéfinis de filtre de Lightroom), le libellé « sans » est noLabel (la référence du
-- SDK écrit nolabel), et un filtre posé sans columnBrowserDesc remet les colonnes du filtre
-- Métadonnées par défaut : la copie garde celles de l'utilisateur.
local function valeursFiltre(c, actuel)
    local f = copieFiltre(actuel)
    f.columnBrowserActive, f.searchStringActive = false, false
    if c == 'aucun' then
        f.filtersActive = false
        return f
    end
    if type(c) ~= 'table' then
        echouer("Filtre invalide : des critères (drapeau, note_min, libelle, texte) ou « aucun ».")
    end
    f.filtersActive = true
    f.pick, f.minRating, f.ratingOp, f.edit, f.export, f.whichCopies = '<nil>', '<nil>', '>=', '<nil>', '<nil>', '<nil>'
    f.label1, f.label2, f.label3, f.label4, f.label5, f.noLabel, f.customLabel = false, false, false, false, false, false, false
    if c.drapeau ~= nil then
        local picks = { retenue = 'flagged', rejetee = 'rejected', aucun = 'unflagged' }
        f.pick = picks[tostring(c.drapeau)] or echouer("Drapeau du filtre : retenue, rejetee ou aucun.")
    end
    if c.note_min ~= nil then
        local note = tonumber(c.note_min)
        if not note or note < 0 or note > 5 then
            echouer("Note minimale du filtre : de 0 à 5.")
        end
        f.minRating = note
    end
    if c.libelle ~= nil then
        if c.libelle == 'aucun' then
            f.noLabel = true
        elseif COULEURS[tostring(c.libelle)] then
            f['label' .. COULEURS[tostring(c.libelle)].numero] = true
        else
            echouer("Libellé du filtre : rouge, jaune, vert, bleu, violet ou aucun.")
        end
    end
    if c.texte ~= nil and tostring(c.texte) ~= '' then
        f.searchStringActive, f.searchString, f.searchOp, f.searchTarget = true, tostring(c.texte), 'all', 'all'
    end
    return f
end

local function presetsFiltre()
    local ok, presets = LrTasks.pcall(LrApplication.viewFilterPresets)
    return ok and type(presets) == 'table' and presets or {}
end

-- Pose le filtre demandé (critères ou paramètre prédéfini de filtre de l'utilisateur), ou remet
-- celui d'avant Claude ; le filtre d'avant est gardé au premier changement. Renvoie une phrase.
local function poserFiltre(params)
    local cat = catalogue()
    local okA, actuel, presetActuel = LrTasks.pcall(cat.getCurrentViewFilter, cat)
    if not okA or type(actuel) ~= 'table' then
        echouer("Lightroom ne donne pas le filtre de la Bibliothèque (getCurrentViewFilter).")
    end
    local cible, nom
    if params.remettre_filtre then
        local avant = filtreAvantClaude
        if not avant then
            return "Aucun filtre changé par Claude depuis le lancement de Lightroom : rien à remettre."
        end
        -- Les valeurs exactes, pas le paramètre prédéfini : constaté en 2.4, « Filtres désactivés »
        -- remet les colonnes du filtre Métadonnées par défaut.
        cible = copieFiltre(avant.valeurs)
        nom = avant.preset
    elseif params.filtre_preset ~= nil then
        local voulu = minuscules(tostring(params.filtre_preset))
        local noms = {}
        for n, id in pairs(presetsFiltre()) do
            if minuscules(tostring(n)) == voulu then
                cible, nom = id, tostring(n)
            end
            noms[#noms + 1] = "« " .. tostring(n) .. " »"
        end
        if not cible then
            table.sort(noms)
            echouer("Paramètre prédéfini de filtre introuvable : « " .. tostring(params.filtre_preset) .. " ». Offerts : " .. table.concat(noms, ", ") .. ".")
        end
    else
        cible = valeursFiltre(params.filtre, actuel)
    end
    local ok, change = LrTasks.pcall(cat.setViewFilter, cat, cible)
    if not ok then
        echouer("Lightroom refuse ce filtre : " .. tostring(Liaison.messageErreur(change)))
    end
    if change == nil then
        echouer("Lightroom ne trouve pas ce paramètre prédéfini de filtre.")
    end
    if params.remettre_filtre then
        filtreAvantClaude = nil
        return "Filtre d'avant Claude remis" .. (nom and (" (« " .. nom .. " »)") or "") .. "."
    end
    if not filtreAvantClaude then
        filtreAvantClaude = { valeurs = copieFiltre(actuel), preset = presetActuel }
    end
    return (nom and ("Filtre « " .. nom .. " » posé") or "Filtre posé") .. (change == false and " (il l'était déjà)." or ".")
end

-- Montre des photos dans Lightroom (commande « montrer ») : sélectionnées, dans la Bibliothèque
-- (loupe, grille, comparaison ou ensemble) ou le module Développement, avant/après compris. Une
-- photo hors de la source affichée fait afficher son dossier. Sans photo : une source (dossier,
-- collection) et un filtre de la Bibliothèque, en grille. Rien n'est écrit dans le catalogue.
function Bibliotheque.montrer(params)
    local avecFiltre = params.filtre ~= nil or params.filtre_preset ~= nil or params.remettre_filtre == true
    local sourceVoulue = params.source_dossier ~= nil or params.source_collection ~= nil
    if not (type(params.photos) == 'table' and #params.photos > 0) and not params.selection and (avecFiltre or sourceVoulue) then
        local resultat = { module = "Bibliothèque" }
        if params.source_dossier ~= nil then
            catalogue():setActiveSources({ trouverDossier(params.source_dossier) })
            resultat.source = tostring(params.source_dossier)
        elseif params.source_collection ~= nil then
            local c = trouverCollection(params.source_collection)
            catalogue():setActiveSources({ c.collection })
            resultat.source = (c.ensemble and (c.ensemble .. ' > ') or '') .. c.nom
        end
        if LrApplicationView.getCurrentModuleName() ~= 'library' then
            LrApplicationView.switchToModule('library')
        end
        LrTasks.pcall(LrApplicationView.showView, 'grid')
        if avecFiltre then
            resultat.filtre = poserFiltre(params)
            if not params.remettre_filtre then
                resultat.a_savoir = "Une photo que le filtre cache ne se sélectionne plus : remettre le filtre (restore_filter) avant de retoucher une autre photo."
            end
        end
        return resultat
    end
    local photos = photosVisees(params)
    local selectionnees, sourceChangee = selectionnerAvecSource(photos)
    if not selectionnees then
        echouer("Lightroom n'a pas affiché « " .. nomFichier(photos[1]) .. " » : l'afficher dans le film fixe (dossier ou collection).")
    end
    local avantApres = params.vue == 'avant_apres'
    local module = (params.module == 'developpement' or avantApres) and 'develop' or 'library'
    if LrApplicationView.getCurrentModuleName() ~= module then
        LrApplicationView.switchToModule(module)
    end
    local resultat = { module = module == 'develop' and "Développement" or "Bibliothèque", source_changee = sourceChangee }
    if avantApres then
        LrTasks.pcall(LrApplicationView.showView, VUE_AVANT_APRES)
        resultat.vue = "avant/après"
        resultat.a_savoir = "L'« Avant » de Lightroom est l'état de la photo à l'importation (ou celui qu'on y a copié), pas l'état d'avant Claude. "
            .. "view_photo avec compare = before_claude montre l'avant Claude ; dans Lightroom, l'instantané « Avant Claude » "
            .. "(s'il existe) › Copier les paramètres de l'instantané dans Avant."
    elseif module == 'library' then
        local vueVoulue = VUES_BIBLIOTHEQUE[params.vue] or (#photos > 1 and params.vue == nil and 'grid') or 'loupe'
        LrTasks.pcall(LrApplicationView.showView, vueVoulue)
    end
    if avecFiltre then
        resultat.filtre = poserFiltre(params)
    end
    local montrees = Json.tableau()
    for _, photo in ipairs(photos) do
        montrees[#montrees + 1] = decrire(photo, false)
    end
    resultat.photos = montrees
    return resultat
end


Bibliotheque.selectionnerAvecSource = selectionnerAvecSource
Bibliotheque.remettreSelection = remettreSelection

return Bibliotheque
