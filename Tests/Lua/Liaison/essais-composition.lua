-- essais-composition.lua : « Composition lue » côté liaison (1.3), hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua). L'image entière, non recadrée, que read_composition lit
-- (apercu avec entier : le cadre retiré et la case « Contraindre le recadrage » décochée le temps
-- du rendu, deux étapes « Claude · composition », photo remise ; le cadre actuel vu dans l'image
-- entière ; aucune écriture sans recadrage ; les refus, pause et photo protégée compris, seulement
-- s'il faut écrire) ; l'image entière d'une proposition de
-- recadrage (essayer avec entier : trois étapes, le cadre que Lightroom a gardé, Upright compris,
-- la photo remise, CropConstrainToWarp compris ; la proposition qui part quand même si l'image
-- entière ne se rend pas) ; en paysage (AB) et en vertical (DA) ; le contrat avec le serveur
-- (Tests/Contrats/composition.json : ses params, par la liaison, donnent exactement ses réponses ;
-- le serveur le lit dans ContratCompositionTests.swift).
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, proche, echoue, contient = A.test, A.egal, A.proche, A.echoue, A.contient
local photoRaw, photoFuji, appliquer = A.photoRaw, A.photoFuji, A.appliquer

local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'
local Etapes = require 'Etapes'
local Recadrage = require 'Recadrage'
local Rendu = require 'Rendu'

local CLES_CADRE = { 'CropAngle', 'CropLeft', 'CropTop', 'CropRight', 'CropBottom' }
local IMAGE_ENTIERE, RETOUR = "Claude · composition (image entière)", "Claude · composition (retour)"
local ESSAI_ENTIERE, FIN = "Claude · essai : image entière", "Claude · fin de l'essai"

-- Aides ------------------------------------------------------------------------------------------

-- Le RAF de X-H2S d'essai, en paysage (AB, 6240 × 4160) ou en vertical (DA : appareil tenu
-- poignée en haut, 4160 × 6240 à l'affichage), photo active.
local function photoEn(orientation)
    local photo = photoFuji()
    photo.brut.orientation = orientation
    if orientation == 'DA' then
        photo.brut.dimensions = { width = 4160, height = 6240 }
    end
    S.active, S.selection = photo, { photo }
    return photo
end

local function dimensions(photo)
    return photo.brut.dimensions.width, photo.brut.dimensions.height
end

-- Un recadrage posé à la main (Recadrage.calculer, dans l'image affichée) ; rend le cadre.
local function cadrer(photo, demande)
    local largeur, hauteur = dimensions(photo)
    local cadre = Recadrage.calculer(demande, largeur, hauteur, photo.brut.orientation)
    for cle, valeur in pairs(cadre) do
        photo.reglages[cle] = valeur
    end
    return cadre
end

-- Le cadre de ces réglages vu dans l'image affichée entière de la photo.
local function lu(photo, reglages)
    local largeur, hauteur = dimensions(photo)
    return Recadrage.lire(reglages, largeur, hauteur, photo.brut.orientation)
end

-- Deux cadres lus (Recadrage.lire) égaux, à la précision du JSON près (dix chiffres significatifs).
local function memeCadre(obtenu, attendu, message)
    egal(type(obtenu), 'table', message .. " : cadre absent")
    for _, cle in ipairs({ 'ratio', 'angle', 'centre_x', 'centre_y', 'largeur' }) do
        local a, b = tonumber(obtenu[cle]), attendu[cle]
        if not a or math.abs(a - b) > 1e-8 * math.max(1, math.abs(b)) then
            error(string.format("%s, %s : attendu %s, obtenu %s", message, cle, tostring(b), tostring(obtenu[cle])), 2)
        end
    end
end

-- Valeur d'un réglage du cadre : absente, celle que Lightroom lui donne (sans recadrage, case
-- décochée).
local function valeurCadre(reglages, cle)
    local valeur = reglages[cle]
    if valeur == nil then
        return Recadrage.AUCUN[cle] or 0
    end
    return valeur
end

local function copieCadre(reglages)
    local copie = {}
    for _, cle in ipairs(CLES_CADRE) do copie[cle] = valeurCadre(reglages, cle) end
    copie.CropConstrainToWarp = valeurCadre(reglages, 'CropConstrainToWarp')
    return copie
end

-- Le cadre de la photo est exactement celui-là (case comprise).
local function cadreRemis(photo, avant, message)
    for _, cle in ipairs(CLES_CADRE) do
        egal(valeurCadre(photo.reglages, cle), avant[cle], message .. " : " .. cle)
    end
    egal(valeurCadre(photo.reglages, 'CropConstrainToWarp'), avant.CropConstrainToWarp, message .. " : CropConstrainToWarp")
end

-- Réglages d'un rendu sans cadre ni contrainte.
local function sansCadreNiContrainte(reglages, message)
    for cle, valeur in pairs(Recadrage.AUCUN) do
        egal(reglages[cle], valeur, message .. " : " .. cle)
    end
    egal(reglages.CropConstrainToWarp, 0, message .. " : case décochée le temps du rendu")
end

-- Les écritures (withWriteAccessDo) de la commande, par leur nom, à la suite.
local function ecritures()
    return table.concat(S.ecritures, ' | ')
end

local function apercuEntier(extra)
    local params = { taille = 1344, cles = {}, entier = true }
    for cle, valeur in pairs(extra or {}) do params[cle] = valeur end
    return Commandes.executer('apercu', params)
end

-- Une proposition de recadrage, comme preview_settings avec crop (params relevés sur le serveur).
local function proposerCadre(demande, extra)
    local params = { action = 'appliquer', recadrage = demande, reglages = {}, plages = {}, libelles = {}, relatif = false,
        etape = 'cadre', taille = 1344, comparer = false, entier = true }
    for cle, valeur in pairs(extra or {}) do params[cle] = valeur end
    return Commandes.executer('essayer', params)
end

-- Remplace le temps d'un appel la méthode withWriteAccessDo du catalogue simulé : `apres(nom)`
-- après chaque écriture faite ; `refuser(nom)` vrai : Lightroom occupé (« aborted »), rien d'écrit.
local function surEcritures(apres, refuser, fonction)
    local catalogue = import('LrApplication').activeCatalog()
    local ecrire = catalogue.withWriteAccessDo
    catalogue.withWriteAccessDo = function(self, nom, f, delai)
        if refuser and refuser(nom) then
            return 'aborted'
        end
        local statut = ecrire(self, nom, f, delai)
        if apres then apres(nom) end
        return statut
    end
    local ok, resultat = pcall(fonction)
    catalogue.withWriteAccessDo = ecrire
    if not ok then
        error(resultat, 0)
    end
    return resultat
end

-- Le rendu de l'image entière échoue (disque plein), après son écriture.
local function renduEntierImpossible(fonction)
    return surEcritures(function(nom)
        if nom == ESSAI_ENTIERE or nom == IMAGE_ENTIERE then S.renduImpossible = "disque plein" end
    end, nil, fonction)
end

-- apercu avec entier ---------------------------------------------------------------------------

for _, orientation in ipairs({ 'AB', 'DA' }) do
    test("apercu entier (" .. orientation .. ") : image entière rendue sans cadre ni contrainte, cadre actuel lu, photo remise", function()
        local photo = photoEn(orientation)
        local largeur, hauteur = dimensions(photo)
        local cadre = cadrer(photo, { ratio = 0.8, angle = 2, taille = 0.7, centre_x = 0.4 })
        -- La case cochée sans transformation (Upright retiré à la main, par exemple) : décochée
        -- le temps du rendu, remise ensuite.
        photo.reglages.CropConstrainToWarp = 1
        local avant = copieCadre(photo.reglages)
        local empreinte = Etapes.empreinte(photo)
        local r = apercuEntier()
        egal(ecritures(), IMAGE_ENTIERE .. ' | ' .. RETOUR, "deux étapes dans l'Historique")
        egal(Etapes.empreinte(photo), empreinte, "même état qu'avant : l'avant/après des étapes n'y voit rien")
        egal(#S.rendus, 1)
        sansCadreNiContrainte(S.rendus[1].reglagesRendus, "rendu")
        cadreRemis(photo, avant, "photo remise")
        egal(r.image_entiere, true)
        egal(type(r.chemin), 'string')
        egal(r.dimensions.largeur, largeur) egal(r.dimensions.hauteur, hauteur)
        -- Le cadre actuel, lu avant l'écriture, dans l'image affichée entière : celui qui a été posé.
        memeCadre(r.cadre_actuel, lu(photo, cadre), "cadre_actuel")
        egal(math.abs(r.cadre_actuel.ratio - 0.8) < 1e-4, true, "ratio " .. r.cadre_actuel.ratio)
        proche(r.cadre_actuel.angle, 2)
        egal(math.abs(r.cadre_actuel.centre_x - 0.4) < 1e-5 and math.abs(r.cadre_actuel.centre_y - 0.5) < 1e-5, true, "centre")
        -- Le reste de l'aperçu, comme sans entier : le recadrage lu après le retour.
        proche(r.recadrage.angle, 2)
        egal(r.photo.id, photo.localIdentifier)
    end)
end

test("apercu entier : sans recadrage ni contrainte, rendue telle quelle, sans écriture ; la pause n'arrête que s'il faut écrire", function()
    local photo = photoEn('AB')
    Liaison.pause = true
    local r = apercuEntier()
    egal(#S.ecritures, 0, "aucune écriture")
    egal(#photo.appliques, 0)
    egal(#S.rendus, 1)
    egal(r.image_entiere, true, "toujours dit, même sans recadrage")
    egal(r.cadre_actuel, nil, "pas de cadre actuel")
    egal(r.dimensions.largeur, 6240)

    -- Recadrée, en pause : refusée, rien d'écrit ni de rendu.
    local cadre = cadrer(photo, { ratio = 1, taille = 0.5 })
    echoue(function() apercuEntier() end, "en pause")
    egal(#S.ecritures, 0) egal(#S.rendus, 1)
    Liaison.pause = false

    -- La case seule, cochée sans recadrage : décochée le temps du rendu, sans cadre actuel.
    for cle, valeur in pairs(Recadrage.AUCUN) do photo.reglages[cle] = valeur end
    photo.reglages.CropConstrainToWarp = 1
    r = apercuEntier()
    egal(ecritures(), IMAGE_ENTIERE .. ' | ' .. RETOUR)
    egal(S.rendus[2].reglagesRendus.CropConstrainToWarp, 0)
    egal(photo.reglages.CropConstrainToWarp, 1, "case remise")
    egal(r.cadre_actuel, nil)
    egal(cadre.CropLeft > 0, true)

    -- Une photo sans dimensions connues, non recadrée : rendue, sans dimensions dans la réponse.
    local raw = photoRaw()
    r = apercuEntier({ photo = raw.localIdentifier })
    egal(r.image_entiere, true)
    egal(r.dimensions, nil)
end)

test("apercu entier : une photo protégée se lit sans écriture si elle n'est pas recadrée ; recadrée, refusée sans rien écrire ni rendre", function()
    local photo = photoEn('AB')
    -- Copies virtuelles seulement, sur l'original : rendue telle quelle, rien à écrire.
    S.prefs.copiesSeulement = true
    local r = apercuEntier()
    egal(#S.ecritures, 0, "aucune écriture") egal(#S.rendus, 1)
    egal(r.image_entiere, true)

    -- Recadrée : le cadre ne se retire pas, même le temps du rendu (comme une proposition).
    cadrer(photo, { ratio = 0.8, angle = 2, taille = 0.7 })
    local avant = copieCadre(photo.reglages)
    echoue(function() apercuEntier() end, "pas une copie virtuelle")
    echoue(function() apercuEntier() end, "rien n'a été écrit")
    egal(#S.ecritures, 0, "rien d'écrit") egal(#photo.appliques, 0)
    egal(#S.rendus, 1, "rien de rendu")
    cadreRemis(photo, avant, "cadre intact")

    -- Rejetée et protégée : refusée de même.
    S.prefs.copiesSeulement = false
    S.prefs.rejeteesProtegees, photo.brut.pickStatus = true, -1
    echoue(function() apercuEntier() end, "photo rejetée, protégée")
    egal(#S.ecritures, 0)

    -- Une copie virtuelle, en copies seulement : lue, le cadre retiré puis remis.
    S.prefs.rejeteesProtegees, photo.brut.pickStatus = false, 0
    S.prefs.copiesSeulement = true
    photo.brut.isVirtualCopy = true
    r = apercuEntier()
    egal(ecritures(), IMAGE_ENTIERE .. ' | ' .. RETOUR)
    sansCadreNiContrainte(S.rendus[2].reglagesRendus, "rendu")
    cadreRemis(photo, avant, "photo remise")
    egal(type(r.cadre_actuel), 'table')
end)

test("apercu entier : refusé avec comparer ou point_af, sur une photo agrandie, ou recadrée sans dimensions connues ; rien d'écrit ni de rendu", function()
    local photo = photoEn('AB')
    cadrer(photo, { ratio = 1.5, angle = 1, taille = 0.8 })
    appliquer({ reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } } })
    local ecrites = #S.ecritures
    echoue(function() apercuEntier({ comparer = 'avantClaude' }) end, "ne va ni avec comparer ni avec point_af")
    echoue(function() apercuEntier({ point_af = true }) end, "ne va ni avec comparer ni avec point_af")
    egal(#S.ecritures, ecrites, "rien d'écrit")
    egal(#S.rendus, 0, "rien de rendu")

    -- Agrandie par l'ancien connecteur (cadre hors de [0, 1]) : comme le recadrage de Claude.
    local agrandie = photoEn('AB')
    agrandie.reglages.CropLeft, agrandie.reglages.CropRight = -0.1997, 1.1997
    agrandie.reglages.CropConstrainToUnitSquare = 0
    echoue(function() apercuEntier() end, "Photo agrandie")
    echoue(function() apercuEntier() end, "Claude ne la recadre pas")
    egal(#agrandie.appliques, 0)
    egal(agrandie.reglages.CropLeft, -0.1997)

    -- Recadrée, sans dimensions connues : le cadre ne se lirait pas dans l'image entière.
    local raw = photoRaw()
    raw.reglages.CropLeft = 0.1
    echoue(function() apercuEntier({ photo = raw.localIdentifier }) end, "Dimensions de la photo inconnues")
    egal(#raw.appliques, 0)

    -- Recadrée, original introuvable sans aperçu dynamique : rien à rendre, donc rien à écrire.
    local absente = photoEn('AB')
    cadrer(absente, { ratio = 1, taille = 0.5 })
    absente.absente = true
    echoue(function() apercuEntier() end, "original introuvable")
    egal(#absente.appliques, 0)
    egal(#S.rendus, 0)
end)

test("apercu entier : un rendu qui échoue remet quand même le cadre, puis l'erreur part", function()
    local photo = photoEn('AB')
    cadrer(photo, { ratio = 0.8, angle = -3, taille = 0.6, centre_y = 0.45 })
    photo.reglages.CropConstrainToWarp = 1
    local avant = copieCadre(photo.reglages)
    S.renduImpossible = "disque plein"
    echoue(function() apercuEntier() end, "disque plein")
    egal(ecritures(), IMAGE_ENTIERE .. ' | ' .. RETOUR)
    cadreRemis(photo, avant, "photo remise")
end)

test("apercu entier : l'image sans cadre n'est jamais la vue de l'avant/après des étapes", function()
    local photo = photoEn('AB')
    cadrer(photo, { ratio = 1, taille = 0.6 })
    Etapes.actifPour = function() return true end
    local appels = 0
    local avantVue, garderVue = Etapes.avantVue, Etapes.garderVue
    Etapes.avantVue = function(...) appels = appels + 1 return avantVue(...) end
    Etapes.garderVue = function(...) appels = appels + 1 return garderVue(...) end
    local ok, erreur = pcall(function()
        apercuEntier()
        egal(appels, 0, "ni avantVue ni garderVue avec entier")
        Commandes.executer('apercu', { taille = 1344, cles = {} })
        egal(appels > 0, true, "témoin : l'aperçu de l'état actuel passe par la vue")
    end)
    Etapes.avantVue, Etapes.garderVue = avantVue, garderVue
    if not ok then error(erreur, 0) end
end)

-- essayer avec entier ------------------------------------------------------------------------

for _, cas in ipairs({ { 'AB', { ratio = 1.5, angle = -1.4, taille = 0.82, centre_x = 0.48, centre_y = 0.52 } },
    { 'DA', { ratio = 0.8, angle = 2.5, taille = 0.75, centre_y = 0.45 } } }) do
    local orientation, demande = cas[1], cas[2]
    test("essayer avec un recadrage et entier (" .. orientation .. ") : trois étapes, image entière sans cadre, cadre gardé, photo remise", function()
        local photo = photoEn(orientation)
        local largeur, hauteur = dimensions(photo)
        -- Case cochée sans transformation : la proposition ne la touche pas (pas dans plan.avant),
        -- l'image entière la décoche ; elle doit revenir cochée.
        photo.reglages.CropConstrainToWarp = 1
        local avant = copieCadre(photo.reglages)
        local r = proposerCadre(demande)
        egal(ecritures(), "Claude · essai : cadre | " .. ESSAI_ENTIERE .. ' | ' .. FIN, "trois étapes dans l'Historique")
        egal(#S.rendus, 2, "la proposition, puis l'image entière")
        local voulu = Recadrage.calculer(demande, largeur, hauteur, orientation)
        for _, cle in ipairs(CLES_CADRE) do
            egal(S.rendus[1].reglagesRendus[cle], voulu[cle], "proposition rendue recadrée : " .. cle)
        end
        sansCadreNiContrainte(S.rendus[2].reglagesRendus, "image entière")
        -- Le cadre gardé par Lightroom (ici, tel que demandé), vu dans l'image entière.
        memeCadre(r.cadre_propose, lu(photo, voulu), "cadre_propose")
        egal(math.abs(r.cadre_propose.ratio - demande.ratio) < 1e-4, true, "ratio")
        proche(r.cadre_propose.angle, demande.angle)
        egal(r.dimensions.largeur, largeur) egal(r.dimensions.hauteur, hauteur)
        egal(type(r.chemin), 'string') egal(type(r.chemin_entier), 'string')
        egal(contient(r.remarques, "Image entière non rendue"), false)
        cadreRemis(photo, avant, "photo remise")
        egal(photo.reglages.CropConstrainToWarp, 1, "case remise cochée")
    end)
end

test("essayer avec entier, photo déjà recadrée à ce cadre : le cadre revient aussi (clés que la proposition ne touchait pas)", function()
    local photo = photoEn('AB')
    local demande = { ratio = 1.25, angle = 1, taille = 0.7, centre_x = 0.55 }
    local cadre = cadrer(photo, demande)
    local avant = copieCadre(photo.reglages)
    local r = proposerCadre(demande, { reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } } })
    egal(ecritures(), "Claude · essai : cadre | " .. ESSAI_ENTIERE .. ' | ' .. FIN)
    for _, c in ipairs(r.changements) do
        egal(c.cle:match('^Crop') == nil, true, "le cadre ne change pas : " .. c.cle)
    end
    sansCadreNiContrainte(S.rendus[2].reglagesRendus, "image entière")
    memeCadre(r.cadre_propose, lu(photo, cadre), "cadre_propose")
    cadreRemis(photo, avant, "cadre remis")
    egal(photo.reglages.Exposure2012, 0)
end)

for _, orientation in ipairs({ 'AB', 'DA' }) do
    test("essayer avec Upright (" .. orientation .. ") : cadre_propose est le cadre resserré par Lightroom, coins vides sur l'image entière seulement, case remise", function()
        local photo = photoEn(orientation)
        local largeur, hauteur = dimensions(photo)
        photo.reglages.PerspectiveUpright = 2
        local demande = { ratio = largeur / hauteur, taille = 0.95 }
        local r = proposerCadre(demande)
        egal(ecritures(), "Claude · essai : cadre | " .. ESSAI_ENTIERE .. ' | ' .. FIN)
        egal(S.rendus[1].reglagesRendus.CropConstrainToWarp, 1, "case cochée pour la proposition")
        egal(S.rendus[1].coinsVides, 0, "la proposition sans coin vide")
        egal(S.rendus[2].coinsVides > 0, true, "l'image entière, case décochée, montre les coins vides")
        sansCadreNiContrainte(S.rendus[2].reglagesRendus, "image entière")
        -- Le cadre que Lightroom a gardé (resserré par « Contraindre le recadrage »), pas la demande.
        local garde = lu(photo, S.rendus[1].reglagesRendus)
        memeCadre(r.cadre_propose, garde, "cadre_propose")
        local demandee = lu(photo, Recadrage.calculer(demande, largeur, hauteur, orientation))
        egal(r.cadre_propose.largeur < demandee.largeur * 0.99, true,
            string.format("resserré : %.1f px pour %.1f demandés", r.cadre_propose.largeur, demandee.largeur))
        egal(photo.reglages.CropConstrainToWarp, 0, "case remise à sa valeur d'avant")
        for cle, valeur in pairs(Recadrage.AUCUN) do egal(photo.reglages[cle], valeur, cle) end

        -- Upright posé par Claude, case cochée et cadre déjà resserré : tout revient tel quel.
        for cle, valeur in pairs(Recadrage.AUCUN) do photo.reglages[cle] = valeur end
        photo.reglages.PerspectiveUpright = 0
        appliquer({ reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } }, etape = 'géométrie' })
        egal(photo.reglages.CropConstrainToWarp, 1)
        local avant = copieCadre(photo.reglages)
        S.rendus, S.ecritures = {}, {}
        r = proposerCadre({ ratio = 1, taille = 0.9, centre_x = 0.45 })
        egal(S.rendus[1].coinsVides, 0) egal(S.rendus[2].coinsVides > 0, true)
        memeCadre(r.cadre_propose, lu(photo, S.rendus[1].reglagesRendus), "cadre_propose")
        cadreRemis(photo, avant, "cadre et case d'avant l'essai")
        egal(S.coinsVides(photo), 0)
    end)
end

test("essayer : sans recadrage ou recadrage retiré, entier ne rend ni n'écrit rien de plus", function()
    local photo = photoEn('AB')
    local r = proposerCadre(nil, { reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } } })
    egal(#S.rendus, 1) egal(#S.ecritures, 2, "l'essai et sa fin")
    egal(r.chemin_entier, nil) egal(r.cadre_propose, nil) egal(r.dimensions, nil)

    cadrer(photo, { ratio = 1, taille = 0.7 })
    S.rendus, S.ecritures = {}, {}
    r = proposerCadre({ retirer = true })
    egal(#S.rendus, 1) egal(#S.ecritures, 2)
    egal(r.chemin_entier, nil) egal(r.cadre_propose, nil)

    -- Une proposition de masque (add_mask n'envoie jamais entier) : ignoré, même avec un recadrage.
    S.rendus, S.ecritures = {}, {}
    r = Commandes.executer('essayer', { action = 'masquer', entier = true, recadrage = { ratio = 1.5, taille = 0.8 }, taille = 1344,
        masques = Json.tableau({ { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.4, nom = 'Dégradé', locaux = {} } }) })
    egal(#S.rendus, 1, "la proposition du masque seule")
    egal(contient(S.ecritures, ESSAI_ENTIERE), false)
    egal(r.chemin_entier, nil) egal(r.cadre_propose, nil)

    -- Rien ne change (le cadre est déjà celui-là) : la proposition seule.
    photo = photoEn('AB')
    local demande = { ratio = 1.5, angle = 1, taille = 0.8 }
    cadrer(photo, demande)
    S.rendus, S.ecritures = {}, {}
    r = proposerCadre(demande)
    egal(#S.rendus, 1) egal(#S.ecritures, 0)
    egal(r.chemin_entier, nil) egal(r.cadre_propose, nil)
end)

test("essayer : l'image entière qui ne se rend pas, ou son écriture refusée, n'empêche ni la proposition ni le cadre ; photo remise", function()
    local photo = photoEn('AB')
    photo.reglages.CropConstrainToWarp = 1
    local avant = copieCadre(photo.reglages)
    local demande = { ratio = 1.5, angle = -1.4, taille = 0.82 }
    local r = renduEntierImpossible(function() return proposerCadre(demande) end)
    egal(ecritures(), "Claude · essai : cadre | " .. ESSAI_ENTIERE .. ' | ' .. FIN)
    egal(type(r.chemin), 'string', "la proposition part")
    egal(r.chemin_entier, nil, "pas d'image entière")
    memeCadre(r.cadre_propose, lu(photo, Recadrage.calculer(demande, 6240, 4160, 'AB')), "le cadre gardé, relu avant")
    egal(r.dimensions.largeur, 6240)
    egal(contient(r.remarques, "Image entière non rendue : Lightroom n'a pas pu rendre l'aperçu : disque plein ; le cadre n'est pas dessiné."),
        true, Json.encode(r.remarques))
    cadreRemis(photo, avant, "photo remise")

    -- Lightroom occupé : l'écriture de l'image entière refusée, la proposition part quand même.
    S.renduImpossible, S.rendus, S.ecritures = nil, {}, {}
    r = surEcritures(nil, function(nom) return nom == ESSAI_ENTIERE end, function() return proposerCadre(demande) end)
    egal(ecritures(), "Claude · essai : cadre | " .. FIN)
    egal(#S.rendus, 1)
    egal(r.chemin_entier, nil)
    egal(type(r.cadre_propose), 'table')
    -- La raison sans son point final : « … dans un instant ; le cadre… », jamais « instant. ; ».
    egal(contient(r.remarques, "Image entière non rendue : Lightroom est occupé (une autre opération écrit dans le catalogue) : "
        .. "réessayer dans un instant ; le cadre n'est pas dessiné."), true, Json.encode(r.remarques))
    egal(contient(r.remarques, ". ;"), false, Json.encode(r.remarques))
    cadreRemis(photo, avant, "photo remise")

    -- Une erreur Lua (avec son emplacement, « fichier.lua:12: ») juste après l'écriture de l'image
    -- entière : la raison se lit sans l'emplacement, et le cadre écrit revient.
    S.rendus, S.ecritures = {}, {}
    r = surEcritures(function(nom)
        if nom == ESSAI_ENTIERE then error("écriture interrompue") end
    end, nil, function() return proposerCadre(demande) end)
    egal(ecritures(), "Claude · essai : cadre | " .. ESSAI_ENTIERE .. ' | ' .. FIN)
    egal(r.chemin_entier, nil)
    egal(type(r.cadre_propose), 'table')
    egal(contient(r.remarques, "Image entière non rendue : écriture interrompue ; le cadre n'est pas dessiné."), true,
        Json.encode(r.remarques))
    egal(contient(r.remarques, ".lua:"), false, Json.encode(r.remarques))
    cadreRemis(photo, avant, "photo remise")
end)

test("geometrie : les rendus du recalage passent par le même cadre retiré (sansRecadrage), photo remise", function()
    local photo = photoEn('DA')
    photo.reglages.LensProfileEnable = 1
    photo.reglages.CropConstrainToWarp = 1
    cadrer(photo, { ratio = 0.8, angle = 2, taille = 0.7 })
    local avant = copieCadre(photo.reglages)
    Commandes.executer('geometrie', { rendre = true })
    egal(ecritures(), "Claude · recalage (sans recadrage) | Claude · recalage (sans correction) | Claude · recalage (retour)")
    sansCadreNiContrainte(S.rendus[1].reglagesRendus, "rendu corrigé")
    egal(S.rendus[1].reglagesRendus.LensProfileEnable, 1)
    egal(S.rendus[2].reglagesRendus.LensProfileEnable, 0)
    cadreRemis(photo, avant, "photo remise")
    egal(photo.reglages.LensProfileEnable, 1)
    egal(Rendu.ETAPE_ENTIERE, IMAGE_ENTIERE)
end)

-- Contrat avec le serveur --------------------------------------------------------------------------

-- Tests/Contrats/composition.json fige ce qui passe sur la liaison : les params exacts que le
-- serveur envoie (read_composition : apercu avec entier ; preview_settings avec crop : essayer avec
-- entier) et les réponses exactes du module, refus compris. Le serveur les lit dans
-- ContratCompositionTests.swift ; ici, ces params passent par la liaison (une ligne JSON, comme du
-- serveur) et la réponse doit être celle du contrat, champ par champ : noms, formes (tableau ou
-- objet, nombre, texte, booléen), valeurs. Les chemins d'aperçus sont remplacés par leurs textes
-- du contrat. Un null d'objet est absent des deux côtés (Json.decode l'efface).

local CONTRAT = dossierTests .. '../../Contrats/composition.json'
local TABLEAU = getmetatable(Json.tableau())

local function lireContrat()
    local fichier = io.open(CONTRAT, 'r')
    if not fichier then
        error("contrat introuvable : " .. CONTRAT, 0)
    end
    local texte = fichier:read('*a')
    fichier:close()
    return Json.decode(texte)
end

-- La première différence entre la valeur obtenue et celle du contrat, ou nil.
local function difference(obtenu, attendu, chemin)
    if attendu == Json.null or obtenu == Json.null then
        if obtenu ~= attendu then
            return string.format("%s : attendu %s, obtenu %s", chemin, Json.encode(attendu), Json.encode(obtenu))
        end
        return nil
    end
    if type(obtenu) ~= type(attendu) then
        return string.format("%s : attendu %s, obtenu %s", chemin, Json.encode(attendu), obtenu == nil and "rien" or Json.encode(obtenu))
    end
    if type(attendu) ~= 'table' then
        if obtenu ~= attendu then
            return string.format("%s : attendu %s, obtenu %s", chemin, Json.encode(attendu), Json.encode(obtenu))
        end
        return nil
    end
    if (getmetatable(obtenu) == TABLEAU) ~= (getmetatable(attendu) == TABLEAU) then
        return string.format("%s : attendu %s, obtenu %s", chemin, getmetatable(attendu) == TABLEAU and "un tableau" or "un objet",
            Json.encode(obtenu))
    end
    if getmetatable(attendu) == TABLEAU and #obtenu ~= #attendu then
        return string.format("%s : %d éléments attendus, %d obtenus : %s", chemin, #attendu, #obtenu, Json.encode(obtenu))
    end
    local cles = {}
    for cle in pairs(attendu) do cles[#cles + 1] = cle end
    table.sort(cles, function(a, b) return tostring(a) < tostring(b) end)
    for _, cle in ipairs(cles) do
        local d = difference(obtenu[cle], attendu[cle], chemin .. '.' .. tostring(cle))
        if d then
            return d
        end
    end
    for cle, valeur in pairs(obtenu) do
        if attendu[cle] == nil then
            return string.format("%s.%s : en trop (%s)", chemin, tostring(cle), Json.encode(valeur))
        end
    end
    return nil
end

local function selonLeContrat(obtenu, attendu, nom)
    local d = difference(obtenu, attendu, nom)
    if d then
        error("écart avec Tests/Contrats/composition.json, " .. d, 2)
    end
end

-- Une commande du serveur par la liaison : la ligne JSON (avec le jeton), la réponse relue. Une
-- horloge qui avance à chaque lecture : chaque rendu a son propre dossier (apercu-<photo>-<ms>),
-- pour savoir quel aperçu va dans chemin, lequel dans chemin_entier.
local function parLaLiaison(fonction)
    local LrDate = import 'LrDate'
    local lire = LrDate.currentTime
    local pas = 0
    LrDate.currentTime = function()
        pas = pas + 0.001
        return lire() + pas
    end
    Liaison.prise = { send = function(_, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    local envoyer = function(commande, params)
        Liaison.recevoir(A.ligne({ id = #S.envois + 1, command = commande, params = params }))
        return Json.decode(S.envois[#S.envois])
    end
    local ok, erreur = pcall(fonction, envoyer)
    Liaison.prise, Liaison.reponsesConnectee = nil, false
    LrDate.currentTime = lire
    if not ok then
        error(erreur, 0)
    end
end

-- Un chemin d'aperçu de la réponse : celui du rendu n° i (son dossier), remplacé par le texte du
-- contrat.
local function cheminDuRendu(resultat, cle, i, attendu)
    local dossier = S.rendus[i].exportSettings.LR_export_destinationPathPrefix
    egal(tostring(resultat[cle]):sub(1, #dossier), dossier, cle .. " : le rendu n° " .. i)
    resultat[cle] = attendu[cle]
end

-- Les photos du contrat, comme dans Lightroom : ce qu'il tient à jour d'un recadrage (isCropped,
-- croppedDimensions), que la simulation ne suit pas.
local function photoDuContrat()
    return photoEn('AB')
end

local function recadrerCommeLightroom(photo, demande)
    local cadre = cadrer(photo, demande)
    local l = lu(photo, cadre)
    photo.brut.isCropped = true
    photo.meta.croppedDimensions = string.format('%d x %d', math.floor(l.largeur + 0.5), math.floor(l.largeur / l.ratio + 0.5))
end

test("contrat avec le serveur (lire) : apercu avec entier donne exactement la réponse de Tests/Contrats/composition.json", function()
    local exemple = lireContrat().exemples.lire
    local photo = photoDuContrat()
    recadrerCommeLightroom(photo, { ratio = 0.8, angle = 2, taille = 0.7, centre_x = 0.4 })
    local avant = copieCadre(photo.reglages)
    parLaLiaison(function(envoyer)
        local r = envoyer('apercu', exemple.apercu.params)
        egal(r.error, nil, "apercu refusé")
        egal(#S.rendus, 1)
        cheminDuRendu(r.result, 'chemin', 1, exemple.apercu.reponse)
        selonLeContrat(r.result, exemple.apercu.reponse, 'apercu')
    end)
    cadreRemis(photo, avant, "photo remise")
end)

test("contrat avec le serveur (proposer) : essayer avec entier donne exactement la réponse de Tests/Contrats/composition.json", function()
    local exemple = lireContrat().exemples.proposer
    photoDuContrat()
    parLaLiaison(function(envoyer)
        local r = envoyer('essayer', exemple.essayer.params)
        egal(r.error, nil, "essayer refusé")
        egal(#S.rendus, 2)
        cheminDuRendu(r.result, 'chemin', 1, exemple.essayer.reponse)
        cheminDuRendu(r.result, 'chemin_entier', 2, exemple.essayer.reponse)
        selonLeContrat(r.result, exemple.essayer.reponse, 'essayer')
    end)
end)

test("contrat avec le serveur (proposer, image entière non rendue) : la proposition et le cadre, sans chemin_entier, avec la remarque", function()
    local exemple = lireContrat().exemples.proposer_sans_image_entiere
    photoDuContrat()
    renduEntierImpossible(function()
        parLaLiaison(function(envoyer)
            local r = envoyer('essayer', exemple.essayer.params)
            egal(r.error, nil, "essayer refusé")
            egal(#S.rendus, 2, "le second rendu a échoué")
            cheminDuRendu(r.result, 'chemin', 1, exemple.essayer.reponse)
            selonLeContrat(r.result, exemple.essayer.reponse, 'essayer')
        end)
    end)
end)

test("contrat avec le serveur : le refus d'une photo agrandie passe tel quel ; rien d'écrit ni de rendu", function()
    local refus = lireContrat().refus.agrandie
    local photo = photoDuContrat()
    photo.reglages.CropLeft, photo.reglages.CropRight = -0.1997, 1.1997
    parLaLiaison(function(envoyer)
        local r = envoyer('apercu', refus.apercu.params)
        egal(r.result, nil)
        egal(r.error, refus.apercu.erreur, "refus d'apercu")
    end)
    egal(#photo.appliques, 0)
    egal(#S.rendus, 0)
end)

A.bilan()
