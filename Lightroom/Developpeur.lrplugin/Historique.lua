-- Historique.lua : ce que la fenêtre Claude dit d'une photo, sans Claude ni jetons (correctif 1.3.6,
-- « une photo, une conversation », décidé avec Dany le 25 octobre 2026) : l'historique d'une photo,
-- qui ouvre sa conversation neuve (l'élément « Historique de la photo ») ; ce qu'une conversation en
-- a vu (Historique.vu) et ce qui a changé depuis (l'élément « Depuis la dernière fois ») ; le
-- résumé court d'un groupe de photos (« N de ces M photos ont déjà des étapes de Claude : … »).
-- Lightroom ne laisse pas lire son panneau Historique : « l'historique », ce sont le journal de
-- Claude (champ journalClaude, lu par Photos.lireJson : les étapes faites dans la fenêtre, la
-- Demande rapide ou Claude Desktop, avec leur raison et leur date) et les reprises à la main depuis
-- la dernière étape de Claude (apresClaude et Ecriture.difference, par
-- Ecriture.correctionsUtilisateur, comme corrections_utilisateur des réponses du connecteur).
--
-- Les lectures (Historique.lire, Historique.lireGroupe) se font par appel direct aux fonctions du
-- module, dans une tâche (Fenetre.majPhoto, Moteur.tic) ; le reste est pur. Tout ce qui en sort
-- est fait de textes, de nombres et de tables neuves (jamais une table relue par Json.decode : la
-- conversation l'écrit sur le disque, la fenêtre en tire ses lignes). Chaque texte a deux formes :
-- celle du fil (des lignes : l'en-tête, puis des puces « •  ») et celle jointe à la demande suivante
-- de Dany, entre crochets sur une ligne (Conversation.historiquesAEnvoyer), une seule fois.
--
-- Une photo sans étape de Claude a dans son historique le résumé de ses réglages : ceux de
-- Lightroom qui s'écartent de leur valeur par défaut (Historique.ecarts ; demandé par Dany le
-- 25 octobre 2026).
--
-- Aussi le résumé que la fenêtre montre en haut du fil, sous l'historique de la photo ou le résumé
-- court du groupe (deuxième retour de Dany du 25 octobre 2026, section « Le résumé de la fenêtre »
-- en bas de ce fichier) : la prise de vue, la note et l'état d'une photo, ou les dates, les
-- appareils et les comptes d'un groupe. Lui n'a que la forme du fil : il n'est jamais gardé dans la
-- conversation, ni envoyé à Claude.

local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'

local Conversation = require 'Conversation'
local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Photos = require 'Photos'
local Reglages = require 'Reglages'
local Texte = require 'Texte'

local Historique = {}

-- Étapes de Claude montrées (les plus récentes ; l'en-tête dit combien il y en a en tout), réglages
-- repris à la main montrés, noms d'un groupe montrés, et photos d'un groupe lues une à une quand les
-- lectures groupées du catalogue échouent (elles, toute la sélection : Historique.lireGroupe).
Historique.ETAPES_MONTREES = 8
Historique.REPRISES_MONTREES = 8
Historique.NOMS_GROUPE = 5
Historique.MAX_GROUPE = 500

-- Le début des puces (celui des listes de Claude dans le fil, Fil.ligneMarkdown).
Historique.PUCE = '•  '

-- Les en-têtes des trois éléments, et le début de la puce des réglages d'une photo sans étape de
-- Claude (Historique.texteReglages).
Historique.TITRE = "Historique de la photo"
Historique.TITRE_DEPUIS = "Depuis la dernière fois"
Historique.REGLAGES = "Réglages hors des valeurs par défaut"

-- Les réglages suivis par apresClaude qui n'ont pas de libellé dans Conversation.libelles (les
-- listes y sont comptées : « #MaskGroupBasedCorrections », Ecriture.etatSimple).
Historique.LIBELLES = {
    ['#MaskGroupBasedCorrections'] = "Masques", ['#RetouchAreas'] = "Taches", ['#PointColors'] = "Couleurs ponctuelles",
    ['#RedEyeInfo'] = "Yeux rouges", ['#DepthBasedCorrections'] = "Corrections de profondeur", ['Look.Name'] = "Look du profil",
    CameraProfile = "Profil", WhiteBalance = "Balance des blancs",
}

local function texte(v)
    if type(v) == 'number' then
        return string.format('%d', v)
    end
    return type(v) == 'string' and Texte.nettoyer(v) or ''
end

local function nombre(v)
    return type(v) == 'number' and v or nil
end

-- Une valeur de réglage en mots : « 0,45 », « oui », « Adobe Standard », « — » sans valeur.
local function valeur(v)
    if v == nil or v == Json.null then
        return '—'
    elseif type(v) == 'number' then
        return Texte.nombre(v)
    elseif type(v) == 'boolean' then
        return v and 'oui' or 'non'
    end
    return Texte.raccourcir(Texte.nettoyer(tostring(v)), 40)
end

-- Une entrée du journal de Claude, en table neuve : date (« AAAA-MM-JJ HH:MM », à l'heure locale,
-- Ecriture.horodatage), étape (« Claude · passe 1 : lumière »), son identifiant, son genre
-- ('retouche', 'classement', 'annulation', 'retour') et sa raison.
local function entree(e)
    return { date = texte(e.date), etape = texte(e.etape), etape_id = texte(e.etape_id), type = texte(e.type), raison = texte(e.raison) }
end

local function memeEntree(a, b)
    return type(a) == 'table' and type(b) == 'table' and a.date == b.date and a.etape == b.etape
        and (a.etape_id or '') == (b.etape_id or '') and (a.type or '') == (b.type or '')
end

-- Le nom d'une photo : son nom de fichier, et celui de sa copie virtuelle (« DSCF4961.RAF
-- (Copie 2) »).
local function nomDe(photo)
    local function meta(cle)
        local ok, v = LrTasks.pcall(function() return photo:getFormattedMetadata(cle) end)
        return ok and type(v) == 'string' and Texte.nettoyer(v) or ''
    end
    local nom, copie = meta('fileName'), meta('copyName')
    return nom .. ((nom ~= '' and copie ~= '') and (" (" .. copie .. ")") or '')
end

-- Lectures (dans une tâche) --------------------------------------------------------------------

-- Les réglages d'une photo hors de leur valeur par défaut, en mots (Historique.ecarts) ; nil sans
-- écart, ou s'ils ne se lisent pas.
local function ecartsDe(photo)
    local ok, ecarts = LrTasks.pcall(function()
        local reglages = photo:getDevelopSettings()
        return type(reglages) == 'table' and Historique.ecarts(reglages, Reglages.estRaw(photo, reglages)) or nil
    end)
    return ok and type(ecarts) == 'table' and #ecarts > 0 and ecarts or nil
end

-- L'état d'une photo (un LrPhoto) : { id, nom, journal (ses entrées, des plus anciennes aux plus
-- récentes), editCount, lastEditTime (métadonnées brutes, des nombres), reprises (nil, ou
-- { etape, changements = { { cle, claude, maintenant } } } : ce que Dany a changé à la main depuis
-- la dernière commande de Claude, valeurs en mots), reglages (nil, ou pour une photo sans étape de
-- Claude, ses réglages hors de leur valeur par défaut, en mots : Historique.ecarts) }.
-- `sansReprises` : sans lire les réglages (ce qu'une conversation a vu n'en a pas besoin).
function Historique.etat(photo, sansReprises)
    local journal = {}
    for _, e in ipairs(Photos.lireJson(photo, 'journalClaude', {})) do
        if type(e) == 'table' then
            journal[#journal + 1] = entree(e)
        end
    end
    local etat = { id = photo.localIdentifier, nom = nomDe(photo), journal = journal,
        editCount = nombre(tonumber(Photos.brut(photo, 'editCount'))), lastEditTime = nombre(tonumber(Photos.brut(photo, 'lastEditTime'))) }
    if not sansReprises then
        local ok, r = LrTasks.pcall(Ecriture.correctionsUtilisateur, photo)
        if ok and type(r) == 'table' and type(r.changements) == 'table' and #r.changements > 0 then
            local reprises = { etape = texte(r.etape), changements = {} }
            for _, ch in ipairs(r.changements) do
                if type(ch) == 'table' and type(ch.cle) == 'string' then
                    reprises.changements[#reprises.changements + 1] = { cle = ch.cle, claude = valeur(ch.claude), maintenant = valeur(ch.maintenant) }
                end
            end
            etat.reprises = #reprises.changements > 0 and reprises or nil
        end
        if #journal == 0 then
            etat.reglages = ecartsDe(photo)
        end
    end
    return etat
end

-- L'état de la photo de cet identifiant (localIdentifier), nil si elle n'est plus au catalogue ou
-- ne se lit pas.
function Historique.lire(id, sansReprises)
    local etat
    LrTasks.pcall(function()
        local photo = LrApplication.activeCatalog():getPhotoByLocalId(tonumber(id))
        if photo then
            etat = Historique.etat(photo, sansReprises)
        end
    end)
    return etat
end

-- La photo a-t-elle des étapes de Claude ? Par les lectures groupées du catalogue (le journal, son
-- propriétaire et l'uuid, comme Photos.decrireTout) : sans journal, non ; un journal à elle, oui.
-- Une mémoire sans propriétaire (écrite avant ce champ, ou reçue par une copie virtuelle de son
-- original), et toute photo quand une lecture groupée échoue, par Photos.lireJson.
local function avecEtapes(photo, champs, brutes)
    if champs then
        local m = type(champs[photo]) == 'table' and champs[photo] or {}
        local journal = m.journalClaude
        if type(journal) ~= 'string' or journal == '' or journal == '[]' then
            return false
        end
        local proprietaire, b = m.proprietaireMemoire, brutes and brutes[photo]
        if type(proprietaire) == 'string' and proprietaire ~= '' and type(b) == 'table' then
            return proprietaire == b.uuid
        end
    end
    return #Photos.lireJson(photo, 'journalClaude', {}) > 0
end

-- Le groupe de la sélection de Lightroom : { m (photos sélectionnées), lues (celles qui ont été
-- regardées : toute la sélection par les lectures groupées du catalogue, qui en tiennent des
-- milliers ; les MAX_GROUPE premières, une à une, si elles échouent), n (celles qui ont des étapes de
-- Claude, parmi les lues), noms (les NOMS_GROUPE premiers de celles-là) } ; nil si la sélection ne se
-- lit pas.
function Historique.lireGroupe()
    local groupe
    LrTasks.pcall(function()
        local cat = LrApplication.activeCatalog()
        local selection = cat:getTargetPhotos()
        local okChamps, champs = LrTasks.pcall(function()
            return cat:batchGetPropertyForPlugin(selection, _PLUGIN, { 'journalClaude', 'proprietaireMemoire' })
        end)
        local okBrutes, brutes = LrTasks.pcall(function() return cat:batchGetRawMetadata(selection, { 'uuid' }) end)
        champs = okChamps and type(champs) == 'table' and champs or nil
        brutes = okBrutes and type(brutes) == 'table' and brutes or nil
        local photos = selection
        if not champs and #selection > Historique.MAX_GROUPE then
            photos = {}
            for i = 1, Historique.MAX_GROUPE do
                photos[i] = selection[i]
            end
        end
        groupe = { m = #selection, lues = #photos, n = 0, noms = {} }
        for _, photo in ipairs(photos) do
            local ok, oui = LrTasks.pcall(avecEtapes, photo, champs, brutes)
            if ok and oui then
                groupe.n = groupe.n + 1
                if #groupe.noms < Historique.NOMS_GROUPE then
                    groupe.noms[#groupe.noms + 1] = nomDe(photo)
                end
            end
        end
    end)
    return groupe
end

-- Ce qu'une conversation a vu d'une photo, en table neuve : le nombre d'entrées de son journal, la
-- dernière, et editCount et lastEditTime (Conversation : `vu`, gardé sur le disque).
function Historique.vu(etat)
    local derniere = etat.journal[#etat.journal]
    return { n = #etat.journal, derniere = derniere and entree(derniere) or nil, editCount = etat.editCount,
        lastEditTime = etat.lastEditTime }
end

-- Deux vues de la même photo.
function Historique.memeVu(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then
        return a == b
    end
    return a.n == b.n and a.editCount == b.editCount and a.lastEditTime == b.lastEditTime
        and ((a.derniere == nil and b.derniere == nil) or memeEntree(a.derniere, b.derniere))
end

-- Ce qui a changé (pur) -------------------------------------------------------------------------

-- Les entrées du journal plus récentes que celles qu'une conversation a vues (`vu`) : après la
-- dernière vue (même date, étape, identifiant et genre) ; si elle n'y est plus (le journal garde
-- ses 200 dernières entrées), celles d'une date plus récente que la sienne ; sans `vu` (une
-- conversation d'avant le correctif 1.3.6), celles d'une date plus récente que `depuisLe` (texte
-- « AAAA-MM-JJ HH:MM » : sa dernière modification), aucune sans lui.
function Historique.nouvelles(etat, vu, depuisLe)
    local journal, nouvelles = etat.journal, {}
    if type(vu) == 'table' then
        if type(vu.derniere) ~= 'table' then
            for _, e in ipairs(journal) do
                nouvelles[#nouvelles + 1] = e
            end
            return nouvelles
        end
        for i = #journal, 1, -1 do
            if memeEntree(journal[i], vu.derniere) then
                for k = i + 1, #journal do
                    nouvelles[#nouvelles + 1] = journal[k]
                end
                return nouvelles
            end
        end
        depuisLe = vu.derniere.date
    end
    if type(depuisLe) ~= 'string' or depuisLe == '' then
        return nouvelles
    end
    for _, e in ipairs(journal) do
        if (e.date or '') > depuisLe then
            nouvelles[#nouvelles + 1] = e
        end
    end
    return nouvelles
end

-- Vrai si la photo a été retouchée (Claude ou la main) depuis ce que la conversation a vu ; vrai
-- sans `vu` (on ne sait pas ce qu'elle a vu).
function Historique.retouchee(etat, vu)
    if type(vu) ~= 'table' then
        return true
    end
    return etat.editCount ~= vu.editCount or etat.lastEditTime ~= vu.lastEditTime
end

-- Les réglages hors de leur valeur par défaut (pur) ---------------------------------------------

-- Les réglages d'une photo sans étape de Claude, ceux de Lightroom qui s'écartent de leur valeur
-- par défaut, en mots et dans l'ordre des panneaux du module Développement : « Profil Camera
-- CLASSIC CHROME · Balance 5 600 K / +8 · Exposition +0,45 · Ombres +30 · Recadrée · 2 masques »
-- (demandé par Dany le 25 octobre 2026). Seulement des réglages dont la valeur par défaut est sûre,
-- celle d'Adobe : le profil Adobe Color d'un RAW (Embedded, le profil incorporé, pour un autre
-- fichier) à son intensité de 100 ; la balance Telle quelle ; la tonalité, la présence, la TSL,
-- l'étalonnage, le calibrage, la transformation, les corrections d'objectif et les effets à 0 ; les
-- courbes linéaires ; la netteté à 40 et le bruit de couleur à 25 pour un RAW, à 0 sinon
-- (Catalogue.swift) ; ni recadrage, ni masque, ni tache. Ce qui n'est pas sûr se tait plutôt que d'inventer : un
-- réglage absent de ceux que Lightroom rend ; la TSL d'une photo en noir et blanc (le mélange des
-- gris la remplace) ; un quart de tour (l'orientation de la photo, que l'appareil pose aussi) et
-- les traitements calculés (débruitage, détails bruts : un même filtre) ; un profil par défaut
-- choisi par Dany dans ses préférences se dit comme un autre. Rend une liste neuve de textes.

-- Les profils par défaut d'Adobe (Reglages.nomProfil, à la casse près).
Historique.PROFILS_PAR_DEFAUT = { ['adobe color'] = true, embedded = true }

-- La balance des blancs nommée par Lightroom (WhiteBalance), en français ; Telle quelle (As Shot)
-- est celle par défaut.
Historique.BALANCES = {
    Auto = "auto", Custom = "personnalisée", Daylight = "Lumière du jour", Cloudy = "Nuageux", Shade = "Ombre",
    Tungsten = "Tungstène", Fluorescent = "Fluorescent", Flash = "Flash",
}

-- Tonalité et présence (Réglages de base), à 0 par défaut, avec leur libellé de Conversation.libelles.
Historique.TONALITE = { 'Exposure2012', 'Contrast2012', 'Highlights2012', 'Shadows2012', 'Whites2012', 'Blacks2012',
    'Texture', 'Clarity2012', 'Dehaze', 'Vibrance', 'Saturation' }

local COULEURS_TSL = { 'Red', 'Orange', 'Yellow', 'Green', 'Aqua', 'Blue', 'Purple', 'Magenta' }
local ETALONNAGE = { 'SplitToningShadowSaturation', 'SplitToningHighlightSaturation', 'ColorGradeMidtoneSat', 'ColorGradeGlobalSat',
    'ColorGradeShadowLum', 'ColorGradeMidtoneLum', 'ColorGradeHighlightLum', 'ColorGradeGlobalLum' }
local CALIBRAGE = { 'ShadowTint', 'RedHue', 'RedSaturation', 'GreenHue', 'GreenSaturation', 'BlueHue', 'BlueSaturation' }
local COURBE_PARAMETRIQUE = { 'ParametricShadows', 'ParametricDarks', 'ParametricLights', 'ParametricHighlights' }
local OBJECTIF_MANUEL = { 'LensManualDistortionAmount', 'VignetteAmount', 'DefringePurpleAmount', 'DefringeGreenAmount' }
local TRANSFORMATION = { PerspectiveVertical = 0, PerspectiveHorizontal = 0, PerspectiveRotate = 0, PerspectiveAspect = 0,
    PerspectiveScale = 100, PerspectiveX = 0, PerspectiveY = 0 }

-- Le signe moins et l'espace fine insécable des milliers et des unités (U+2212, U+202F : mesurés
-- dans Metriques.lua).
local MOINS, FINE = '\226\136\146', '\226\128\175'

-- « 5 600 », « 0,45 », « 30 » : un nombre à la française, ses milliers séparés.
local function chiffres(n)
    local t = Texte.nombre(n)
    local entier, reste = t:match('^(%d+)(.*)$')
    if not entier then
        return t
    end
    local groupes = {}
    while #entier > 3 do
        table.insert(groupes, 1, entier:sub(-3))
        entier = entier:sub(1, -4)
    end
    table.insert(groupes, 1, entier)
    return table.concat(groupes, FINE) .. reste
end

-- « +0,45 », « −12 », « 0 ».
local function signe(n)
    if n == 0 then
        return '0'
    end
    return (n > 0 and '+' or MOINS) .. chiffres(math.abs(n))
end

-- La valeur d'un réglage arrondie comme Lightroom l'affiche (Reglages.arrondir), si elle s'écarte
-- de `defaut` ; nil si elle ne s'en écarte pas ou si Lightroom ne l'a pas rendue.
local function ecart(r, cle, defaut)
    local v = Reglages.valeurNumerique(r[cle])
    if v == nil then
        return nil
    end
    local a = Reglages.arrondir(cle, v)
    if math.abs(a - Reglages.arrondir(cle, defaut or 0)) < 1e-9 then
        return nil
    end
    return a
end

-- Vrai si l'un de ces réglages s'écarte de 0.
local function touche(r, cles)
    for _, cle in ipairs(cles) do
        if ecart(r, cle, 0) then
            return true
        end
    end
    return false
end

local function compter(liste)
    return type(liste) == 'table' and #liste or 0
end

-- Le profil, s'il n'est pas celui d'Adobe par défaut ou que son intensité a changé.
local function profil(r)
    local nom = Reglages.nomProfil(r)
    if type(nom) ~= 'string' or Texte.nettoyer(nom) == '' then
        return nil
    end
    local look = not Reglages.lookVide(r.Look) and r.Look or nil
    local intensite = look and tonumber(look.Amount) and math.floor(tonumber(look.Amount) * 100 + 0.5)
    local autreIntensite = intensite ~= nil and intensite ~= 100
    if Historique.PROFILS_PAR_DEFAUT[nom:lower()] and not autreIntensite then
        return nil
    end
    return "Profil " .. Texte.nettoyer(nom) .. (autreIntensite and (" (intensité " .. chiffres(intensite) .. ")") or '')
end

-- La balance des blancs, si elle n'est pas Telle quelle : « Balance 5 600 K / +8 » (RAW, en
-- kelvins), « Balance +10 / −3 » (un autre fichier, relative), « Balance auto : 5 600 K / +8 ».
local function balance(r, raw)
    local nom = r.WhiteBalance
    if type(nom) ~= 'string' or nom == '' or nom == 'As Shot' then
        return nil
    end
    local t, teinte
    if raw then
        t, teinte = Reglages.valeurNumerique(r.Temperature), Reglages.valeurNumerique(r.Tint)
    else
        t, teinte = Reglages.valeurNumerique(r.IncrementalTemperature), Reglages.valeurNumerique(r.IncrementalTint)
    end
    local valeurs
    if t and teinte then
        t, teinte = math.floor(t + 0.5), math.floor(teinte + 0.5)
        valeurs = (raw and (chiffres(t) .. FINE .. 'K') or signe(t)) .. ' / ' .. signe(teinte)
    end
    if nom == 'Custom' then
        return valeurs and ("Balance " .. valeurs) or ("Balance " .. Historique.BALANCES.Custom)
    end
    local mots = Historique.BALANCES[nom] or Texte.nettoyer(nom)
    return "Balance " .. mots .. (valeurs and (" : " .. valeurs) or '')
end

-- Une courbe des tonalités qui n'est pas linéaire (par points, d'un canal, ou paramétrique).
local function courbe(r)
    for _, cle in ipairs(Reglages.CLES_COURBES) do
        local c = r[cle]
        if type(c) == 'table' and #c > 0 and not Reglages.egal(c, Reglages.COURBE_LINEAIRE) then
            return true
        end
    end
    return touche(r, COURBE_PARAMETRIQUE)
end

-- Les corrections d'objectif posées : « Objectif : profil, aberrations chromatiques ».
local function objectif(r)
    local parties = {}
    if ecart(r, 'LensProfileEnable', 0) then
        parties[#parties + 1] = "profil"
    end
    if ecart(r, 'AutoLateralCA', 0) then
        parties[#parties + 1] = "aberrations chromatiques"
    end
    if touche(r, OBJECTIF_MANUEL) then
        parties[#parties + 1] = "réglages manuels"
    end
    return #parties > 0 and ("Objectif : " .. table.concat(parties, ", ")) or nil
end

-- La transformation : Upright, ou des réglages manuels.
local function transformation(r)
    local upright = ecart(r, 'PerspectiveUpright', 0) ~= nil
    local manuelle = false
    for cle, defaut in pairs(TRANSFORMATION) do
        if ecart(r, cle, defaut) then
            manuelle = true
        end
    end
    if upright then
        return manuelle and "Transformation (Upright et réglages manuels)" or "Transformation (Upright)"
    end
    return manuelle and "Transformation" or nil
end

-- Recadrée (un cadre plus petit que l'image), puis redressée (l'angle du cadre, au dixième).
local function recadrage(r, parties)
    local g, h, d, b = Reglages.valeurNumerique(r.CropLeft), Reglages.valeurNumerique(r.CropTop),
        Reglages.valeurNumerique(r.CropRight), Reglages.valeurNumerique(r.CropBottom)
    if (g and g > 0.0005) or (h and h > 0.0005) or (d and d < 0.9995) or (b and b < 0.9995) then
        parties[#parties + 1] = "Recadrée"
    end
    local angle = Reglages.valeurNumerique(r.CropAngle)
    angle = angle and math.floor(math.abs(angle) * 10 + 0.5) / 10
    if angle and angle > 0 then
        parties[#parties + 1] = "Redressée de " .. chiffres(angle) .. "°"
    end
end

function Historique.ecarts(r, raw)
    local parties = {}
    local function ajouter(texte)
        if texte then
            parties[#parties + 1] = texte
        end
    end
    if type(r) ~= 'table' then
        return parties
    end
    ajouter(profil(r))
    ajouter(balance(r, raw))
    local noirEtBlanc = r.ConvertToGrayscale == true
    ajouter(noirEtBlanc and "Noir et blanc" or nil)
    for _, cle in ipairs(Historique.TONALITE) do
        local v = ecart(r, cle, 0)
        ajouter(v and ((Conversation.libelles[cle] or cle) .. ' ' .. signe(v)) or nil)
    end
    ajouter(courbe(r) and "Courbe des tonalités" or nil)
    if not noirEtBlanc then
        for _, couleur in ipairs(COULEURS_TSL) do
            if touche(r, { 'HueAdjustment' .. couleur, 'SaturationAdjustment' .. couleur, 'LuminanceAdjustment' .. couleur }) then
                ajouter("TSL touchée")
                break
            end
        end
    end
    ajouter(touche(r, ETALONNAGE) and "Étalonnage touché" or nil)
    local nettete = ecart(r, 'Sharpness', raw and 40 or 0)
    ajouter(nettete and ("Netteté " .. chiffres(nettete)) or nil)
    local bruit = ecart(r, 'LuminanceSmoothing', 0)
    ajouter(bruit and ("Réduction du bruit " .. chiffres(bruit)) or nil)
    local couleur = ecart(r, 'ColorNoiseReduction', raw and 25 or 0)
    ajouter(couleur and ("Bruit de couleur " .. chiffres(couleur)) or nil)
    ajouter(objectif(r))
    ajouter(transformation(r))
    local vignetage = ecart(r, 'PostCropVignetteAmount', 0)
    ajouter(vignetage and ("Vignetage " .. signe(vignetage)) or nil)
    local grain = ecart(r, 'GrainAmount', 0)
    ajouter(grain and ("Grain " .. chiffres(grain)) or nil)
    ajouter(touche(r, CALIBRAGE) and "Calibrage touché" or nil)
    recadrage(r, parties)
    local masques = compter(r.MaskGroupBasedCorrections)
    ajouter(masques > 0 and Reglages.pluriel(masques, "masque", "masques") or nil)
    local taches = math.max(compter(r.RetouchAreas), compter(r.RetouchInfo))
    ajouter(taches > 0 and Reglages.pluriel(taches, "tache", "taches") or nil)
    local yeux = compter(r.RedEyeInfo)
    ajouter(yeux > 0 and Reglages.pluriel(yeux, "œil rouge corrigé", "yeux rouges corrigés") or nil)
    ajouter(type(r.LensBlur) == 'table' and r.LensBlur.Active == true and "Flou de l'objectif" or nil)
    return parties
end

-- La puce des réglages : « Réglages hors des valeurs par défaut : Profil … · Exposition +0,45 · … ».
function Historique.texteReglages(ecarts)
    return Historique.REGLAGES .. " : " .. table.concat(ecarts, " · ")
end

-- Textes ---------------------------------------------------------------------------------------

-- « 25 oct. 2026, 14 h 30 » pour « 2026-10-25 14:30 » (les mois par Carnet.MOIS_COURTS, leur seule
-- copie) ; le texte tel quel s'il est d'une autre forme.
function Historique.date(t)
    local a, m, j, h, mn = tostring(t or ''):match('^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)')
    local mois = a and require('Carnet').MOIS_COURTS[tonumber(m)]
    if not mois then
        return Texte.nettoyer(tostring(t or ''))
    end
    return string.format('%d %s %s, %d h %s', tonumber(j), mois, a, tonumber(h), mn)
end

-- « 3 étapes de Claude », « 1 étape de Claude ».
local function etapes(n)
    return n == 1 and "1 étape de Claude" or (n .. " étapes de Claude")
end

-- Une étape du journal en une puce : « 25 oct. 2026, 14 h 30 · passe 1 : lumière — sa raison ».
function Historique.texteEtape(e)
    local nom = Conversation.nomEtape(e.etape)
    local t = Historique.date(e.date) .. " · " .. (nom ~= '' and nom or "étape sans nom")
    if (e.raison or '') ~= '' then
        t = t .. " — " .. e.raison
    end
    return t
end

-- Les reprises à la main en une puce, pour le fil (libellés français) et pour Claude (clés de
-- Lightroom) : « Repris à la main depuis « passe 2 : finitions » : Exposition 0,45 → 0,6 ; … ».
function Historique.texteReprises(reprises)
    local montres, clefs = {}, {}
    for k, ch in ipairs(reprises.changements) do
        if k > Historique.REPRISES_MONTREES then
            montres[#montres + 1], clefs[#clefs + 1] = '…', '…'
            break
        end
        local libelle = Conversation.libelles[ch.cle] or Historique.LIBELLES[ch.cle] or ch.cle
        montres[#montres + 1] = libelle .. ' ' .. ch.claude .. ' → ' .. ch.maintenant
        clefs[#clefs + 1] = ch.cle .. ' ' .. ch.claude .. ' → ' .. ch.maintenant
    end
    local nom = Conversation.nomEtape(reprises.etape)
    local tete = "Repris à la main" .. (nom ~= '' and (" depuis « " .. nom .. " »") or " depuis la dernière étape de Claude") .. " : "
    return tete .. table.concat(montres, " ; "), tete .. table.concat(clefs, " ; ")
end

-- Un élément de la fenêtre en ses deux formes : `texte`, l'en-tête puis une puce par ligne (pour le
-- fil) ; `pourClaude`, la même chose entre crochets sur une ligne (« [en-tête ; puce ; puce] »).
local function element(tete, puces, pucesClaude)
    local lignes = { tete }
    for _, p in ipairs(puces) do
        lignes[#lignes + 1] = Historique.PUCE .. p
    end
    local pourClaude = { (tete:gsub('%.$', '')) }
    for _, p in ipairs(pucesClaude or puces) do
        pourClaude[#pourClaude + 1] = p
    end
    return { texte = table.concat(lignes, '\n'), pourClaude = '[' .. table.concat(pourClaude, ' ; ') .. ']' }
end

-- Les puces des étapes (les ETAPES_MONTREES dernières de la liste, dans l'ordre) et des reprises.
local function puces(liste, reprises)
    local montrees, claude = {}, {}
    for k = math.max(1, #liste - Historique.ETAPES_MONTREES + 1), #liste do
        montrees[#montrees + 1] = Historique.texteEtape(liste[k])
        claude[#claude + 1] = montrees[#montrees]
    end
    if reprises then
        local montree, pourClaude = Historique.texteReprises(reprises)
        montrees[#montrees + 1], claude[#claude + 1] = montree, pourClaude
    end
    return montrees, claude
end

local function combien(liste)
    local n = #liste
    local t = etapes(n)
    if n > Historique.ETAPES_MONTREES then
        t = t .. " (les " .. Historique.ETAPES_MONTREES .. " dernières ci-dessous)"
    end
    return t
end

-- L'élément « Historique de la photo » d'une conversation neuve : ses étapes de Claude (avec leur
-- raison et leur date) et ses reprises à la main depuis la dernière ; sans étape de Claude,
-- « retouchée à la main » (editCount au-dessus de 0 : pas constaté sur une photo jamais
-- développée) et la puce de ses réglages hors de leur valeur par défaut (Historique.ecarts : un
-- paramètre prédéfini posé à l'importation en fait aussi, sans retouche) ; nil sans rien à dire.
function Historique.historique(etat)
    local journal = etat.journal
    if #journal == 0 then
        local reglages = type(etat.reglages) == 'table' and #etat.reglages > 0 and { Historique.texteReglages(etat.reglages) } or {}
        if (etat.editCount or 0) > 0 then
            return element(Historique.TITRE .. " : retouchée à la main, sans étape de Claude.", reglages)
        elseif #reglages > 0 then
            return element(Historique.TITRE .. " : sans étape de Claude.", reglages)
        end
        return nil
    end
    local derniere = journal[#journal]
    local tete = Historique.TITRE .. " : " .. combien(journal) .. ", la dernière le " .. Historique.date(derniere.date)
        .. (etat.reprises and ", puis des reprises à la main." or ".")
    return element(tete, puces(journal, etat.reprises))
end

-- L'élément « Depuis la dernière fois » d'une conversation reprise : les étapes de Claude plus
-- récentes que celles qu'elle a vues (Historique.nouvelles), et les reprises à la main depuis la
-- dernière étape de Claude si la photo a été retouchée depuis (Historique.retouchee) ; nil sans rien
-- de changé.
function Historique.depuis(etat, vu, depuisLe)
    local nouvelles = Historique.nouvelles(etat, vu, depuisLe)
    local reprises = Historique.retouchee(etat, vu) and etat.reprises or nil
    if #nouvelles == 0 and not reprises then
        return nil
    end
    local parties = {}
    if #nouvelles > 0 then
        parties[#parties + 1] = combien(nouvelles)
    end
    if reprises then
        parties[#parties + 1] = "des reprises à la main"
    end
    return element(Historique.TITRE_DEPUIS .. " : " .. table.concat(parties, ", ") .. ".", puces(nouvelles, reprises))
end

-- Le résumé court d'un groupe (Historique.lireGroupe) : « 3 de ces 12 photos ont déjà des étapes de
-- Claude : DSCF4961.RAF, DSCF4962.RAF, … » (les premiers noms, puis « … »), « Aucune de ces 12
-- photos n'a encore d'étape de Claude. ». Quand seules les premières ont été lues (`lues`, lectures
-- groupées en échec), le texte le dit : « 3 des 500 premières de ces 600 photos… ».
function Historique.groupe(g)
    local de = string.format("de ces %d photos", g.m)
    if (g.lues or g.m) < g.m then
        de = string.format("des %d premières de ces %d photos", g.lues, g.m)
    end
    if g.n == 0 then
        return element(string.format("Aucune %s n'a encore d'étape de Claude.", de), {})
    end
    local noms = table.concat(g.noms, ", ") .. (g.n > #g.noms and ", …" or "")
    return element(string.format("%d %s %s déjà des étapes de Claude : %s.", g.n, de, g.n == 1 and "a" or "ont", noms), {})
end

-- Le résumé de la fenêtre (deuxième retour de Dany du 25 octobre 2026) -------------------------
-- À l'ouverture de la fenêtre Claude, et chaque fois qu'une autre photo ou un autre groupe change la
-- conversation montrée, la fenêtre fait un résumé, sans Claude ni jetons, montré en haut du fil :
-- sous l'historique de la photo ou le résumé court du groupe qui ouvre la conversation, au-dessus de
-- la première demande de Dany, sinon en tête du fil (Fenetre.resume, Fil.lignesResume,
-- Fil.avecResume ; demandé par Dany le 25 octobre 2026, d'abord en bas, sous la conversation) : pour
-- une photo, sa prise de vue (appareil, objectif, focale, ouverture, vitesse, ISO, date), sa note et
-- son drapeau, et son état (ses étapes de Claude, ses reprises à la main, ses réglages hors de leur
-- valeur par défaut : ce que l'historique sait déjà) ; pour plusieurs photos, leur nombre, leurs
-- dates (de … à …), leurs appareils, et combien sont retouchées par Claude, notées, rejetées. Il
-- n'est pas gardé dans la conversation (ni sur le disque, ni envoyé à Claude) : il n'a que la forme
-- du fil, l'en-tête puis des puces, refaite à chaque fois.
-- Les lectures se font par les lectures groupées du catalogue (batchGetFormattedMetadata,
-- batchGetRawMetadata, batchGetPropertyForPlugin, comme Photos.decrireTout), dans une tâche ; si
-- l'une échoue, les photos se lisent une à une, les MAX_GROUPE premières d'un groupe seulement. Les
-- textes de la prise de vue sont ceux de Lightroom (getFormattedMetadata, comme son panneau
-- Métadonnées), la date à l'heure locale (timeToUserFormat, comme Lightroom.legende).

Historique.TITRE_RESUME = "Résumé de la photo"
Historique.TITRE_RESUME_GROUPE = "Résumé de la sélection"
-- Appareils nommés dans le résumé d'un groupe (les plus fréquents ; les autres : « … »).
Historique.APPAREILS_MONTRES = 4

-- Ce que le résumé lit de chaque photo : la prise de vue en textes de Lightroom, la date, la note
-- et le drapeau bruts, et les champs du module qui disent « retouchée par Claude » (seulement si la
-- mémoire est celle de la photo : proprietaireMemoire, comme Photos.decrireTout).
Historique.CLES_PRISE = { 'cameraModel', 'lens', 'focalLength', 'aperture', 'shutterSpeed', 'isoSpeedRating' }
local NOMS_PRISE = { cameraModel = 'appareil', lens = 'objectif', focalLength = 'focale', aperture = 'ouverture',
    shutterSpeed = 'vitesse', isoSpeedRating = 'iso' }
local CLES_BRUTES = { 'dateTimeOriginal', 'rating', 'pickStatus', 'uuid' }
local CHAMPS_RETOUCHE = { 'retoucheeParClaude', 'proprietaireMemoire' }

-- Le drapeau (pickStatus : 1, 0 ou −1) comme Lightroom.photos le donne de la photo active.
local DRAPEAUX = { [1] = 'retenue', [0] = 'aucun', [-1] = 'rejetee' }

-- Un texte de Lightroom (une métadonnée formatée peut être un nombre), nil s'il est vide.
local function texteOuNil(v)
    if type(v) == 'number' then
        v = tostring(v)
    end
    v = type(v) == 'string' and Texte.nettoyer(v) or ''
    return v ~= '' and v or nil
end

-- « AAAA-MM-JJ HH:MM » d'une date de LrDate, à l'heure locale ; nil sans date.
local function aLHeureLocale(t)
    if type(t) ~= 'number' then
        return nil
    end
    local ok, texte = LrTasks.pcall(LrDate.timeToUserFormat, t, '%Y-%m-%d %H:%M')
    return ok and type(texte) == 'string' and texte or nil
end

-- La description d'une photo pour le résumé, en table neuve : appareil, objectif, focale,
-- ouverture, vitesse, iso (textes de Lightroom), prise (« AAAA-MM-JJ HH:MM »), note (0 à 5), drapeau
-- ('retenue', 'aucun', 'rejetee'), retouchee (par Claude). `f`, `b` et `m` lisent une métadonnée
-- formatée, brute, ou un champ du module ; `retouchee` dit si la mémoire est celle de la photo.
local function decrire(f, b, retouchee)
    local d = {}
    for _, cle in ipairs(Historique.CLES_PRISE) do
        d[NOMS_PRISE[cle]] = texteOuNil(f(cle))
    end
    d.prise = aLHeureLocale(b('dateTimeOriginal'))
    d.note = math.max(0, math.min(5, math.floor(tonumber(b('rating')) or 0)))
    d.drapeau = DRAPEAUX[tonumber(b('pickStatus')) or 0] or 'aucun'
    d.retouchee = retouchee()
    return d
end

-- Les descriptions de ces photos (Historique.lireResumePhoto, Historique.lireResumeGroupe), par les
-- trois lectures groupées du catalogue ; une photo qu'elles n'ont pas donnée se lit une à une, parmi
-- les `uneAUne` premières seulement. Une photo absente de la lecture groupée des champs du module,
-- quand elle a réussi, n'en a aucun (comme Historique.lireGroupe). Rend la liste (dans l'ordre des
-- photos lues) et le nombre de photos lues.
local function lireDescriptions(cat, photos, uneAUne)
    local okF, formatees = LrTasks.pcall(function() return cat:batchGetFormattedMetadata(photos, Historique.CLES_PRISE) end)
    local okB, brutes = LrTasks.pcall(function() return cat:batchGetRawMetadata(photos, CLES_BRUTES) end)
    local okC, champs = LrTasks.pcall(function() return cat:batchGetPropertyForPlugin(photos, _PLUGIN, CHAMPS_RETOUCHE) end)
    local champsLus = okC and type(champs) == 'table'
    formatees = okF and type(formatees) == 'table' and formatees or {}
    brutes = okB and type(brutes) == 'table' and brutes or {}
    champs = champsLus and champs or {}
    local liste = {}
    for i, photo in ipairs(photos) do
        local fp, bp, mp = formatees[photo], brutes[photo], champs[photo]
        if mp == nil and champsLus then
            mp = {}
        end
        if type(fp) == 'table' and type(bp) == 'table' and type(mp) == 'table' then
            liste[#liste + 1] = decrire(function(cle) return fp[cle] end, function(cle) return bp[cle] end, function()
                if mp.retoucheeParClaude ~= 'oui' then
                    return false
                end
                if type(mp.proprietaireMemoire) == 'string' and mp.proprietaireMemoire ~= '' then
                    return mp.proprietaireMemoire == bp.uuid
                end
                return Photos.lireChamp(photo, 'retoucheeParClaude') == 'oui'
            end)
        elseif i <= uneAUne then
            local ok, d = LrTasks.pcall(decrire, function(cle) return Photos.meta(photo, cle) end,
                function(cle) return Photos.brut(photo, cle) end,
                function() return Photos.lireChamp(photo, 'retoucheeParClaude') == 'oui' end)
            if ok and d then
                liste[#liste + 1] = d
            end
        end
    end
    return liste, #liste
end

-- Le résumé de la photo `id` (localIdentifier), en table neuve : sa description (lireDescriptions),
-- son nom et son état (Historique.etat : journal, reprises à la main, et ici ses réglages hors de
-- leur valeur par défaut même quand Claude y a fait des étapes) ; nil si elle ne se lit pas.
function Historique.lireResumePhoto(id)
    local r
    LrTasks.pcall(function()
        local cat = LrApplication.activeCatalog()
        local photo = cat:getPhotoByLocalId(tonumber(id))
        if not photo then
            return
        end
        local d = lireDescriptions(cat, { photo }, 1)[1] or {}
        local etat = Historique.etat(photo)
        if #etat.journal > 0 then
            etat.reglages = ecartsDe(photo)
        end
        d.id, d.nom, d.etat = photo.localIdentifier, etat.nom, etat
        r = d
    end)
    return r
end

-- « 25 oct. 2026 » pour « 2026-10-25 … ».
local function jour(t)
    local a, m, j = tostring(t or ''):match('^(%d%d%d%d)-(%d%d)-(%d%d)')
    local mois = a and require('Carnet').MOIS_COURTS[tonumber(m)]
    return mois and string.format('%d %s %s', tonumber(j), mois, a) or nil
end

-- Le résumé de la sélection de Lightroom, en table neuve : m (photos sélectionnées), lues (celles
-- décrites), debut et fin (« 3 oct. 2026 », la plus ancienne et la plus récente prise de vue, nil sans
-- date), sansDate, appareils (liste { nom, n }, des plus fréquents aux moins, puis par nom), sansAppareil,
-- retouchees (par Claude), notees (au moins 1 ★), rejetees ; nil si la sélection ne se lit pas.
function Historique.lireResumeGroupe()
    local g
    LrTasks.pcall(function()
        local cat = LrApplication.activeCatalog()
        local selection = cat:getTargetPhotos()
        local liste, lues = lireDescriptions(cat, selection, Historique.MAX_GROUPE)
        g = { m = #selection, lues = lues, sansDate = 0, appareils = {}, sansAppareil = 0, retouchees = 0, notees = 0, rejetees = 0 }
        local premiere, derniere
        local parNom = {}
        for _, d in ipairs(liste) do
            if d.prise then
                premiere = (not premiere or d.prise < premiere) and d.prise or premiere
                derniere = (not derniere or d.prise > derniere) and d.prise or derniere
            else
                g.sansDate = g.sansDate + 1
            end
            if d.appareil then
                if not parNom[d.appareil] then
                    parNom[d.appareil] = { nom = d.appareil, n = 0 }
                    g.appareils[#g.appareils + 1] = parNom[d.appareil]
                end
                parNom[d.appareil].n = parNom[d.appareil].n + 1
            else
                g.sansAppareil = g.sansAppareil + 1
            end
            g.retouchees = g.retouchees + (d.retouchee and 1 or 0)
            g.notees = g.notees + ((d.note or 0) > 0 and 1 or 0)
            g.rejetees = g.rejetees + (d.drapeau == 'rejetee' and 1 or 0)
        end
        table.sort(g.appareils, function(a, b)
            if a.n ~= b.n then
                return a.n > b.n
            end
            return a.nom < b.nom
        end)
        g.debut, g.fin = jour(premiere), jour(derniere)
    end)
    return g
end

-- Les textes du résumé (purs).

-- « 3 ★ · retenue », « pas encore notée · sans drapeau », « 2 ★ · rejetée ».
function Historique.texteNote(note, drapeau)
    local n = math.floor(tonumber(note) or 0)
    local etoiles = n > 0 and (n .. " ★") or "pas encore notée"
    local mots = ({ retenue = "retenue", rejetee = "rejetée" })[drapeau or ''] or "sans drapeau"
    return etoiles .. " · " .. mots
end

-- L'état d'une photo en une puce : ses étapes de Claude (combien, la dernière et sa date), sinon ce
-- que editCount dit d'une retouche à la main.
local function etatPhoto(etat)
    local journal = etat.journal or {}
    if #journal == 0 then
        if (etat.editCount or 0) > 0 then
            return "retouchée à la main, sans étape de Claude"
        end
        return "sans étape de Claude ni retouche"
    end
    local derniere = journal[#journal]
    local nom = Conversation.nomEtape(derniere.etape)
    return etapes(#journal) .. ", la dernière le " .. Historique.date(derniere.date)
        .. (nom ~= '' and (" (« " .. nom .. " »)") or '') .. (etat.reprises and ", puis des reprises à la main" or '')
end

-- Le résumé d'une photo (Historique.lireResumePhoto) : « Résumé de la photo : DSCF4961.RAF », puis
-- la prise de vue (les textes de Lightroom, dans l'ordre de son panneau Métadonnées, puis la date),
-- la note et le drapeau, l'état, les reprises à la main et les réglages hors de leur valeur par
-- défaut (les puces de l'historique, Historique.texteReprises et Historique.texteReglages).
function Historique.resumePhoto(d)
    local prise = {}
    for _, cle in ipairs(Historique.CLES_PRISE) do
        local v = d[NOMS_PRISE[cle]]
        if (v or '') ~= '' then
            prise[#prise + 1] = v
        end
    end
    if (d.prise or '') ~= '' then
        prise[#prise + 1] = Historique.date(d.prise)
    end
    local etat = type(d.etat) == 'table' and d.etat or { journal = {} }
    local puces = {
        "Prise de vue : " .. (#prise > 0 and table.concat(prise, " · ") or "rien de lu"),
        "Note et drapeau : " .. Historique.texteNote(d.note, d.drapeau),
        "État : " .. etatPhoto(etat),
    }
    if etat.reprises then
        puces[#puces + 1] = (Historique.texteReprises(etat.reprises))
    end
    if type(etat.reglages) == 'table' and #etat.reglages > 0 then
        puces[#puces + 1] = Historique.texteReglages(etat.reglages)
    end
    local nom = (d.nom or '') ~= '' and d.nom or ("photo " .. tostring(d.id or '?'))
    return element(Historique.TITRE_RESUME .. " : " .. nom, puces).texte
end

-- Le résumé d'un groupe (Historique.lireResumeGroupe) : « Résumé de la sélection : 12 photos », puis
-- les dates de prise de vue, les appareils (« X-H2S (10), X-T20 (2) ») et les comptes. Quand seules
-- les premières ont été lues (lectures groupées en échec), l'en-tête le dit.
function Historique.resumeGroupe(g)
    local tete = Historique.TITRE_RESUME_GROUPE .. " : " .. (g.m == 1 and "1 photo" or (g.m .. " photos"))
    if (g.lues or g.m) < g.m then
        tete = tete .. " (les " .. g.lues .. " premières lues)"
    end
    local puces = {}
    local dates
    if not g.debut then
        dates = "Dates de prise de vue inconnues"
    elseif g.debut == g.fin then
        dates = "Prises le " .. g.debut
    else
        dates = "Prises du " .. g.debut .. " au " .. g.fin
    end
    if g.debut and (g.sansDate or 0) > 0 then
        dates = dates .. " (" .. g.sansDate .. " sans date)"
    end
    puces[#puces + 1] = dates
    local appareils = {}
    for k, a in ipairs(g.appareils or {}) do
        if k > Historique.APPAREILS_MONTRES then
            appareils[#appareils + 1] = "…"
            break
        end
        appareils[#appareils + 1] = (#g.appareils == 1 and (g.sansAppareil or 0) == 0) and a.nom or (a.nom .. " (" .. a.n .. ")")
    end
    if (g.sansAppareil or 0) > 0 then
        appareils[#appareils + 1] = "inconnu (" .. g.sansAppareil .. ")"
    end
    if #appareils > 0 then
        puces[#puces + 1] = (#appareils == 1 and #(g.appareils or {}) <= 1 and "Appareil : " or "Appareils : ") .. table.concat(appareils, ", ")
    end
    puces[#puces + 1] = string.format("Retouchées par Claude : %d · notées : %d · rejetées : %d", g.retouchees or 0, g.notees or 0,
        g.rejetees or 0)
    return element(tete, puces).texte
end

return Historique
