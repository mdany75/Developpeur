-- Simulation.lua : imitation minimale du SDK de Lightroom Classic, pour tester le module hors
-- de Lightroom avec LuaJIT (même Lua 5.1). Installe les globales `import` et `_PLUGIN`.
-- Les écritures (réglages, métadonnées, instantanés) exigent withWriteAccessDo, comme dans Lightroom.

local S = {}
S.enAttente = {}

local catalogue = {}

-- Lightroom bloque sans erreur sur une table qui porte une métatable (tableau relu par
-- Json.decode) : la simulation le refuse.
local RAW_REFUSEES = { title = true, caption = true, copyright = true, label = true, creator = true, copyName = true,
    folder = true, keywordTags = true, keywordTagsForExport = true }

-- Constaté dans Lightroom Classic 15.6 : une collection créée dans une écriture ne se lit pas dans
-- la même (« Can't get collection information after creating collection inside the same
-- withWriteAccessDo function »). Supposé pareil pour un ensemble et un mot-clé, et pour leur
-- emploi (parent, ajout de photos).
local function lisible(objet, quoi)
    if objet and S.ecritureEnCours and objet.nee ~= nil and objet.nee == S.numeroEcriture then
        error("Can't get " .. quoi .. " information after creating " .. quoi .. " inside the same withWriteAccessDo function", 0)
    end
end

local function naissance()
    return S.ecritureEnCours and S.numeroEcriture or nil
end

local function verifierSansMetatable(valeur, chemin)
    if type(valeur) ~= 'table' then
        return
    end
    assert(getmetatable(valeur) == nil, "table avec métatable passée à Lightroom : " .. chemin)
    for cle, element in pairs(valeur) do
        verifierSansMetatable(element, chemin .. '.' .. tostring(cle))
    end
end

-- Lightroom garde sa propre copie de ce qu'on lui donne.
local function copier(valeur)
    if type(valeur) ~= 'table' then
        return valeur
    end
    local copie = {}
    for cle, element in pairs(valeur) do
        copie[cle] = copier(element)
    end
    return copie
end

-- Profils adaptatifs d'Adobe (dossier Adaptive) : Lightroom les reconnaît à leur UUID.
S.LOOKS_ADAPTATIFS = { ['226E6263ED94405B973B41F5A6E67BE9'] = 'Adaptive Color', ['5763124DCEAF42459912C1BD2AAC8FE5'] = 'Adaptive B&W' }

-- Vrai si Lightroom doit encore calculer pour rendre la photo : un masque IA sans empreinte, ou la
-- carte de profondeur d'un flou d'objectif actif (un profil adaptatif : photo.lookAMettreAJour).
local function calculsIAEnAttente(reglages)
    for _, correction in ipairs(reglages.MaskGroupBasedCorrections or {}) do
        for _, m in ipairs(correction.CorrectionMasks or {}) do
            if m.What == 'Mask/Image' and m.MaskDigest == nil then
                return true
            end
        end
    end
    -- Une tache de l'outil Supprimer sans le résultat de son calcul (pm_patch, relevé).
    for _, cle in ipairs({ 'RemoveAreas', 'RetouchAreas' }) do
        for _, tache in ipairs(reglages[cle] or {}) do
            if tache.SpotType == 'heal_patchmatch' and tache.pm_patch == nil then
                return true
            end
        end
    end
    local flou = reglages.LensBlur
    return type(flou) == 'table' and flou.Active == true and reglages.DepthMapInfo == nil
end

-- Dossier personnel simulé : ses fichiers restent en mémoire (S.fichiers), jamais sur le disque ;
-- de même les fichiers temporaires du module (vignettes, sous /tmp/Developpeur).
S.home = '/simulation/home'
local ouvrir = io.open
io.open = function(chemin, mode)
    if type(chemin) ~= 'string' or (chemin:sub(1, #S.home + 1) ~= S.home .. '/' and chemin:sub(1, 16) ~= '/tmp/Developpeur') then
        return ouvrir(chemin, mode)
    end
    if mode and (mode:find('w', 1, true) or mode:find('a', 1, true)) then
        local morceaux = { mode:find('a', 1, true) and S.fichiers[chemin] or nil }
        return {
            write = function(fichier, ...)
                for _, morceau in ipairs({ ... }) do
                    morceaux[#morceaux + 1] = tostring(morceau)
                end
                return fichier
            end,
            close = function()
                S.fichiers[chemin] = table.concat(morceaux)
                return true
            end,
        }
    end
    local contenu = S.fichiers[chemin]
    if not contenu then
        return nil, chemin .. ': No such file or directory'
    end
    return { read = function() return contenu end, close = function() return true end }
end

-- Empreinte (CameraProfileDigest) d'Adobe Standard pour le X-H2S, relevée dans le catalogue.
S.EMPREINTE_ADOBE_STANDARD = 'E94692538493408AA1DC693245344733'

-- Clés que Lightroom range mais que getDevelopSettings ne rend pas (constaté dans Lightroom
-- Classic 15.6 : présentes dans le catalogue, absentes de la relecture).
local CLES_CACHEES = { CameraProfileDigest = true, MissingCameraProfile = true, MissingCameraProfileDigest = true }

-- Profil d'appareil posé par applyDevelopSettings, résolu un peu plus tard (à la première attente
-- du module, LrTasks.sleep) : Lightroom le cherche parmi les profils de l'appareil de la photo
-- (photo.profils, des noms ; sans liste, tout nom est pris). Constaté dans Lightroom Classic 15.6
-- sur un RAW de X-H2S : juste après l'écriture, la relecture montre « Camera PRO Neg. Hi » ;
-- moins d'une demi-seconde plus tard, Adobe Standard, et le nom introuvable est rangé sous
-- MissingCameraProfile. Tant qu'il y reste, tout profil d'appareil posé ensuite retombe à Adobe
-- Standard, même un nom valide (« Camera ASTIA/Soft », le profil de base « Camera
-- PROVIA/Standard » de CLASSIC Neg) ; MissingCameraProfile = '' le libère. Le nom se cherche
-- sans la casse, et Lightroom range le sien (« Camera MONOCHROME » devient « Camera Monochrome ») ;
-- la ponctuation compte (« Camera PRO Neg. Hi » introuvable, « Camera Pro Neg Hi » trouvé).
local function profilConnu(photo, nom)
    if type(nom) ~= 'string' then
        return nil
    end
    for _, connu in ipairs(photo.profils) do
        if connu:lower() == nom:lower() then
            return connu
        end
    end
    if nom:lower() == 'adobe standard' then
        return 'Adobe Standard'
    end
    return nil
end

local function resoudreProfil(photo)
    if not photo.profilAResoudre then
        return
    end
    photo.profilAResoudre = false
    local r = photo.reglages
    local manquant = type(r.MissingCameraProfile) == 'string' and r.MissingCameraProfile ~= ''
    local connu = profilConnu(photo, r.CameraProfile)
    if not manquant and connu then
        r.CameraProfile = connu
        return
    end
    if not manquant then
        r.MissingCameraProfile = r.CameraProfile
        r.MissingCameraProfileDigest = r.CameraProfileDigest or ''
    end
    r.CameraProfile = 'Adobe Standard'
    r.CameraProfileDigest = S.EMPREINTE_ADOBE_STANDARD
end

-- Géométrie du rendu. Constaté dans Lightroom Classic 15.6 (16 octobre 2026, copie d'essai RAW de
-- X-H2S, XF16-55) : le cadre (Crop*) se pose sur l'image transformée, et Upright posé par
-- applyDevelopSettings ne le touche pas ; Upright complet (2) laisse des coins vides, blancs dans
-- l'aperçu (7,8 % de blanc pur sans recadrage, 0,4 % avec un cadre au ratio d'origine réduit à
-- 85 %). La simulation déforme donc l'image quand Upright, la perspective ou la distorsion
-- manuelle sont actifs : photo.deformation (sinon S.trapeze), du point (u, v) de l'image affichée
-- entière au point de l'image d'origine (de 0 à 1). Chaque rendu note coinsVides, la part de son
-- cadre qui tombe hors de l'image d'origine. Lightroom calcule aussi les matrices
-- UprightTransform_* (constaté) ; la simulation les pose au rendu suivant (le moment est supposé).
local function transformee(r)
    for _, cle in ipairs({ 'PerspectiveUpright', 'PerspectiveVertical', 'PerspectiveHorizontal', 'PerspectiveRotate',
        'PerspectiveAspect', 'PerspectiveX', 'PerspectiveY', 'LensManualDistortionAmount' }) do
        if (tonumber(r[cle]) or 0) ~= 0 then
            return true
        end
    end
    return (tonumber(r.PerspectiveScale) or 100) ~= 100
end

-- Verticales redressées : l'image d'origine se resserre vers le haut, les coins du bas restent vides.
function S.trapeze(force)
    return function(u, v)
        return 0.5 + (u - 0.5) * (1 - force * (1 - v)) * 1.1, 0.03 + v * 0.98
    end
end

local VERS_AFFICHAGE = {
    AB = function(s, t) return s, t end,
    BC = function(s, t) return 1 - t, s end,
    CD = function(s, t) return 1 - s, 1 - t end,
    DA = function(s, t) return t, 1 - s end,
}

function S.deformation(photo)
    if not transformee(photo.reglages) then
        return nil
    end
    return photo.deformation or S.trapeze(0.12)
end

-- Part du cadre de la photo qui montre un coin vide, échantillonnée sur 41 × 41 points.
function S.coinsVides(photo)
    local deformation = S.deformation(photo)
    if not deformation then
        return 0
    end
    local r = photo.reglages
    local d = photo.brut.dimensions or {}
    local orientation = photo.brut.orientation or 'AB'
    local lf, hf = tonumber(d.width) or 6000, tonumber(d.height) or 4000
    if orientation == 'BC' or orientation == 'DA' then
        lf, hf = hf, lf
    end
    local angle = math.rad(tonumber(r.CropAngle) or 0)
    local gauche, haut = tonumber(r.CropLeft) or 0, tonumber(r.CropTop) or 0
    local dx, dy = ((tonumber(r.CropRight) or 1) - gauche) * lf, ((tonumber(r.CropBottom) or 1) - haut) * hf
    local w = dx * math.cos(angle) + dy * math.sin(angle)
    local h = -dx * math.sin(angle) + dy * math.cos(angle)
    local dehors, total = 0, 0
    for i = 0, 40 do
        for j = 0, 40 do
            local a, b = i / 40, j / 40
            local x = gauche * lf + a * w * math.cos(angle) - b * h * math.sin(angle)
            local y = haut * hf + a * w * math.sin(angle) + b * h * math.cos(angle)
            local u, v = VERS_AFFICHAGE[orientation](x / lf, y / hf)
            local ox, oy = deformation(u, v)
            total = total + 1
            if ox < 0 or ox > 1 or oy < 0 or oy > 1 then
                dehors = dehors + 1
            end
        end
    end
    return dehors / total
end

-- « Contraindre le recadrage » (CropConstrainToWarp). Constaté dans Lightroom Classic 15.6
-- (16 octobre 2026, même copie, Upright complet) : posé à 1 par applyDevelopSettings, avec Upright
-- ou après, Lightroom resserre aussitôt le cadre pour qu'il ne montre aucun coin vide (0 % de blanc
-- pur ensuite), même ratio et même angle, et de nouveau à chaque écriture du cadre ou du mode
-- Upright tant que la case reste cochée. Un cadre qui ne montre que la photo reste tel quel, même
-- plus petit que le plus grand possible ; un cadre qui déborde un peu se réduit autour de son
-- centre ; un cadre qui touche deux bords (l'image entière, un 4:5 pleine hauteur) devient le plus
-- grand cadre possible, quitte à se déplacer (centre 0,43 pour le 3:2, 0,25 pour le 4:5). La
-- simulation réduit autour du centre dans tous les cas. Ce changement ne figure pas dans ce que le
-- module a écrit, et le retour à l'origine ne le défait que si le cadre d'avant est mémorisé.
local function contraindre(photo)
    local r = photo.reglages
    if (tonumber(r.CropConstrainToWarp) or 0) ~= 1 or S.coinsVides(photo) == 0 then
        return
    end
    local gauche, haut = tonumber(r.CropLeft) or 0, tonumber(r.CropTop) or 0
    local droite, bas = tonumber(r.CropRight) or 1, tonumber(r.CropBottom) or 1
    local cx, cy = (gauche + droite) / 2, (haut + bas) / 2
    local function poser(f)
        r.CropLeft, r.CropRight = cx - f * (cx - gauche), cx + f * (droite - cx)
        r.CropTop, r.CropBottom = cy - f * (cy - haut), cy + f * (bas - cy)
    end
    local bon, mauvais = 0, 1
    for _ = 1, 30 do
        local f = (bon + mauvais) / 2
        poser(f)
        if S.coinsVides(photo) == 0 then
            bon = f
        else
            mauvais = f
        end
    end
    poser(bon)
end

-- Profil adaptatif posé (constaté dans Lightroom Classic 15.6, Adaptive Color sur un RAW de
-- X-H2S) : Lightroom range la Look en y ajoutant isAdobeAdaptive, et un AILook actif avec ses
-- versions. Il ne le calcule (AILookData) que s'il l'a marqué « à mettre à jour », ce que fait
-- seulement un paramètre prédéfini dont la Look porte déjà isAdobeAdaptive et qui porte AILook
-- actif ; posé par applyDevelopSettings (jusqu'à la 1.6.1), ou par un paramètre prédéfini sans l'un
-- des deux, il reste rangé et inerte, même après un rendu. Marqué, il n'est calculé ni de
-- lui-même, ni par l'exportation seule : par la fenêtre « Mises à jour IA recommandées » (clic de
-- l'utilisateur) ou « Mettre à jour » dans Développement (mettreAJourLook).
local function rangerLookAdaptatif(photo, reglages, parPreset)
    if reglages.Look ~= nil or reglages.AILook ~= nil then
        photo.lookAMettreAJour = false
    end
    local look = reglages.Look
    if type(look) ~= 'table' or not S.LOOKS_ADAPTATIFS[look.UUID] then
        return
    end
    photo.reglages.Look = copier(photo.reglages.Look)
    photo.reglages.Look.isAdobeAdaptive = true
    local calcul = photo.reglages.AILook
    if type(calcul) == 'table' and calcul.Active == true and calcul.AILookData == nil then
        photo.reglages.AILook = copier(calcul)
        photo.reglages.AILook.ModelVersion, photo.reglages.AILook.Version = 285409280, 285212672
        photo.lookAMettreAJour = parPreset and look.isAdobeAdaptive == true
    end
end

-- Taches de l'outil Supprimer. Relevé dans le code de Lightroom Classic 15.6 (AgCameraRawController,
-- getRetouchKey et le rappel de flushSettingsChanges) : une photo qui porte RemoveAreas est lue par
-- là, et Lightroom en dérive RetouchAreas (sans les taches Mask/Image, à détection d'objet). Supposé :
-- une écriture de RetouchAreas seul y est donc perdue, remplacée par ce que dérive RemoveAreas.
local function deriverTaches(photo)
    local supprimer = photo.reglages.RemoveAreas
    if type(supprimer) ~= 'table' or next(supprimer) == nil then
        return
    end
    local liste = {}
    for _, tache in ipairs(supprimer) do
        local objet = false
        for _, m in ipairs(tache.Masks or {}) do
            objet = objet or m.What == 'Mask/Image'
        end
        if not objet then
            liste[#liste + 1] = copier(tache)
        end
    end
    photo.reglages.RetouchAreas = liste
end

-- Profil adaptatif déjà calculé dont l'image change : à recalculer, ce que fait updateAISettings.
-- Constaté dans Lightroom Classic 15.6 (17 octobre 2026) : après une tache ou un flou d'objectif,
-- updateAISettings le recalcule (InputDigest changé) ; une rotation ne le change pas (il est calculé
-- sur la photo entière, avant le recadrage).
local function perimerLook(photo, reglages)
    local look, calcul = photo.reglages.Look, photo.reglages.AILook
    if type(look) == 'table' and look.isAdobeAdaptive == true and type(calcul) == 'table' and calcul.AILookData ~= nil
        and (reglages.RetouchAreas ~= nil or reglages.RemoveAreas ~= nil or reglages.LensBlur ~= nil) then
        photo.lookPerime = true
    end
end

-- Masques posés par le module, comme Lightroom Classic 15.6 les lit (constaté le 17 octobre 2026) :
-- - un objet désigné par un rectangle (Gesture = Mask/Polygon) n'est calculé que si ses Points sont
--   des tables {X, Y} ; sinon Lightroom retire le geste et range ErrorReason = 1 ;
-- - LocalPointColors : un texte de 19 nombres « %f, %f, … » par couleur (DevelopPointColorUtils) ;
-- - plage de couleurs : PointModels, des textes de six nombres « c1 c2 c3 x y 0 » ;
-- - plage de profondeur : DepthRange, quatre valeurs de 0 à 1 ; DepthMin, DepthMax ou DepthFeather
--   (forme « M2 ») font prendre l'image entière : la simulation les refuse.
local function verifierMasques(reglages)
    for _, correction in ipairs(type(reglages.MaskGroupBasedCorrections) == 'table' and reglages.MaskGroupBasedCorrections or {}) do
        for _, texte in ipairs(correction.LocalPointColors or {}) do
            local n = 0
            for _ in tostring(texte):gmatch('[^,]+') do n = n + 1 end
            assert(type(texte) == 'string' and n == 19 and texte:find(', ', 1, true), "LocalPointColors : un texte de 19 nombres « %f, %f, … »")
        end
        for _, m in ipairs(correction.CorrectionMasks or {}) do
            local geste = type(m.Gesture) == 'table' and m.Gesture[1]
            if m.What == 'Mask/Image' and type(geste) == 'table' and geste.What == 'Mask/Polygon' then
                local valides = type(geste.Points) == 'table' and #geste.Points >= 3
                for _, p in ipairs(type(geste.Points) == 'table' and geste.Points or {}) do
                    valides = valides and type(p) == 'table' and type(p.X) == 'number' and type(p.Y) == 'number'
                end
                if not valides then
                    m.Gesture, m.ErrorReason, m.ReferencePoint = nil, 1, '0.500000 0.500000'
                end
            end
            local r = m.CorrectionRangeMask
            if type(r) == 'table' and r.Type == 1 then
                for _, modele in ipairs(r.PointModels or {}) do
                    local n = 0
                    for _ in tostring(modele):gmatch('%S+') do n = n + 1 end
                    assert(n == 6, "PointModels : « c1 c2 c3 x y 0 »")
                end
            elseif type(r) == 'table' and r.Type == 3 then
                assert(r.DepthMin == nil and r.DepthMax == nil and r.DepthFeather == nil, "plage de profondeur : DepthRange, pas DepthMin/DepthMax (l'image entière serait prise)")
                local n = 0
                for v in tostring(r.DepthRange):gmatch('%S+') do
                    n = n + 1
                    assert(tonumber(v) and tonumber(v) >= 0 and tonumber(v) <= 1, "DepthRange : quatre valeurs de 0 à 1")
                end
                assert(n == 4, "DepthRange : quatre valeurs de 0 à 1")
            end
        end
    end
end

-- meta : métadonnées formatées (getFormattedMetadata) ; brut : métadonnées brutes
-- (getRawMetadata), qui reprennent meta pour les clés absentes.
-- Champs IPTC qu'écrit setRawMetadata (outre le titre, la légende et les droits d'auteur).
S.CHAMPS_IPTC = {}
for _, champ in ipairs({ 'headline', 'rightsUsageTerms', 'copyrightInfoUrl', 'creator', 'creatorJobTitle', 'creatorAddress',
    'creatorCity', 'creatorStateProvince', 'creatorPostalCode', 'creatorCountry', 'creatorPhone', 'creatorEmail', 'creatorUrl',
    'descriptionWriter', 'jobIdentifier', 'instructions', 'provider', 'source', 'location', 'city', 'stateProvince', 'country',
    'isoCountryCode', 'intellectualGenre', 'scene', 'iptcSubjectCode', 'event', 'personShown',
    'altTextAccessibility', 'extDescrAccessibility' }) do
    S.CHAMPS_IPTC[champ] = true
end

function S.Photo(id, reglages, meta, brut)
    local photo = {
        localIdentifier = id,
        reglages = reglages or {},
        meta = meta or {},
        brut = brut or {},
        proprietes = {},
        appliques = {},
        instantanes = {},
        snapshots = {},
        motsCles = {},
        metadonneesEcrites = {},
    }
    function photo:getDevelopSettings()
        lisible(self, 'photo')
        local copie = {}
        for cle, valeur in pairs(self.reglages) do
            if not CLES_CACHEES[cle] then
                copie[cle] = valeur
            end
        end
        return copie
    end
    function photo:applyDevelopSettings(reglages, nom)
        assert(S.ecritureEnCours, "applyDevelopSettings hors de withWriteAccessDo")
        verifierSansMetatable(reglages, 'reglages')
        self:modifiee()
        -- La mémoire du module garde l'état du débruitage sous Amelioration : ce n'est pas un réglage.
        assert(reglages.Amelioration == nil, "clé Amelioration passée à applyDevelopSettings")
        -- Ni l'état de la suppression des reflets, gardé sous Suppression.
        assert(reglages.Suppression == nil, "clé Suppression passée à applyDevelopSettings")
        -- Ni le classement dans la Bibliothèque (note, mots-clés…), gardé sous Bibliotheque.
        assert(reglages.Bibliotheque == nil, "clé Bibliotheque passée à applyDevelopSettings")
        -- Constaté le 18 octobre 2026 : un filtre (FilterList) sans ses cadres est refusé.
        local filtres = type(reglages.FilterList) == 'table' and reglages.FilterList.Filters
        for _, filtre in ipairs(type(filtres) == 'table' and filtres or {}) do
            if filtre.Name == 'Dust Removal' and (tonumber(filtre.SrcBoundsRight) == nil or tonumber(filtre.DstBoundsBottom) == nil) then
                error("Invalid parameters for constructing an AgRect.", 2)
            end
        end
        -- Constaté le 18 octobre 2026 : LensProfileSetup = 'LensDefaults' ne remplace pas 'Custom'.
        local objectifPerso = self.reglages.LensProfileSetup == 'Custom'
        for cle, valeur in pairs(reglages) do
            self.reglages[cle] = valeur
        end
        if objectifPerso and reglages.LensProfileSetup == 'LensDefaults' then
            self.reglages.LensProfileSetup = 'Custom'
        end
        verifierMasques(self.reglages)
        deriverTaches(self)
        perimerLook(self, reglages)
        rangerLookAdaptatif(self, reglages, false)
        if reglages.CameraProfile ~= nil and self.profils then
            self.profilAResoudre = true
        end
        if reglages.PerspectiveUpright ~= nil then
            self.uprightACalculer = true
        end
        contraindre(self)
        self.appliques[#self.appliques + 1] = { reglages = reglages, nom = nom }
    end
    -- Constaté dans Lightroom Classic 15.6 : editCount et lastEditTime (métadonnées brutes, des
    -- nombres) disent combien de fois et quand les réglages de la photo ont changé. La simulation
    -- les fait suivre chaque écriture de réglages (supposé : pas les champs du module).
    function photo:modifiee()
        self.editions = (self.editions or 0) + 1
        self.derniereEdition = S.horloge + self.editions / 1000
    end
    -- Constaté par ses effets dans Lightroom Classic 15.6 (20 octobre 2026) : dans une écriture,
    -- un champ du module se relit avec sa valeur d'avant l'écriture ; ce qu'elle y écrit n'est vu
    -- qu'après (S.ecrireEnAttente). La première retouche d'une copie virtuelle qui avait reçu la
    -- mémoire de son original n'en gardait qu'un champ : chaque champ gardé relisait l'ancien
    -- propriétaire et effaçait les précédents.
    function photo:getPropertyForPlugin(plugin, cle)
        return self.proprietes[cle]
    end
    -- Les champs du module s'écrivent dans une écriture, ordinaire ou privée
    -- (withPrivateWriteAccessDo, réservée à ces champs).
    function photo:setPropertyForPlugin(plugin, cle, valeur)
        assert(S.ecritureEnCours or S.ecriturePriveeEnCours, "setPropertyForPlugin hors de withWriteAccessDo")
        local enAttente = S.enAttente[self] or {}
        S.enAttente[self] = enAttente
        enAttente[#enAttente + 1] = { cle = cle, valeur = valeur }
    end
    function photo:getFormattedMetadata(cle)
        return self.meta[cle]
    end
    -- Constaté dans Lightroom Classic 15.6 (diagnostic) : getRawMetadata refuse le titre, la
    -- légende, les droits d'auteur, le libellé, le nom de copie et quelques autres, que
    -- getFormattedMetadata donne ; colorNameForLabel est la couleur du libellé dans le jeu de
    -- libellés actif (S.jeuLibelles ; « none » sans libellé, « custom » hors du jeu : supposé).
    function photo:getRawMetadata(cle)
        if RAW_REFUSEES[cle] then
            error("getRawMetadata : clé inconnue " .. cle, 2)
        end
        if cle == 'keywords' then
            local liste = {}
            for _, motCle in ipairs(self.motsCles) do
                liste[#liste + 1] = motCle
            end
            return liste
        elseif cle == 'colorNameForLabel' then
            -- Dans une écriture, la couleur reste celle du libellé d'avant (constaté indirectement
            -- dans Lightroom Classic 15.6 : « Rouge » posé n'y était pas encore rouge).
            local texte = self.meta.label
            if S.ecritureEnCours and self.libelleFige then
                texte = self.libelleFige.valeur
            end
            if texte == nil or texte == '' then
                return 'none'
            end
            return S.jeuLibelles[texte] or 'custom'
        elseif cle == 'virtualCopies' then
            return self.copies
        elseif cle == 'editCount' then
            return self.editions or 0
        elseif cle == 'lastEditTime' then
            return self.derniereEdition or 0
        end
        if self.brut[cle] ~= nil then
            return self.brut[cle]
        end
        return self.meta[cle]
    end
    function photo:setRawMetadata(cle, valeur)
        assert(S.ecritureEnCours, "setRawMetadata hors de withWriteAccessDo")
        verifierSansMetatable(valeur, cle)
        if cle == 'rating' or cle == 'pickStatus' then
            self.brut[cle] = valeur
        elseif cle == 'gps' then
            -- D'après la référence du SDK : { latitude, longitude }, nil pour l'effacer.
            assert(valeur == nil or (type(valeur.latitude) == 'number' and type(valeur.longitude) == 'number'), "gps : { latitude, longitude }")
            self.brut.gps = valeur
        elseif cle == 'gpsAltitude' or cle == 'gpsImgDirection' then
            assert(valeur == nil or type(valeur) == 'number', cle .. " : un nombre")
            self.brut[cle] = valeur
        elseif cle == 'altTextAccessibility' or cle == 'extDescrAccessibility' then
            -- Lus par getRawMetadata (SDK 13.2, constaté dans Lightroom Classic 15.6 : accepté).
            if valeur == nil then
                error('entity:__newindex(): Field "' .. cle .. '" cannot be set to nil.', 2)
            end
            self.brut[cle] = valeur
        elseif cle == 'label' or cle == 'title' or cle == 'caption' or cle == 'copyright' or S.CHAMPS_IPTC[cle] then
            -- Constaté pour le libellé dans Lightroom Classic 15.6 (supposé pour les autres textes).
            if valeur == nil then
                error('entity:__newindex(): Field "' .. (cle == 'label' and 'colorLabels' or cle) .. '" cannot be set to nil.', 2)
            end
            self.meta[cle] = valeur
        else
            error("setRawMetadata : clé non simulée " .. tostring(cle), 2)
        end
        self.metadonneesEcrites[#self.metadonneesEcrites + 1] = cle
    end
    function photo:addKeyword(motCle)
        assert(S.ecritureEnCours, "addKeyword hors de withWriteAccessDo")
        for _, deja in ipairs(self.motsCles) do
            if deja == motCle then
                return
            end
        end
        self.motsCles[#self.motsCles + 1] = motCle
    end
    function photo:removeKeyword(motCle)
        assert(S.ecritureEnCours, "removeKeyword hors de withWriteAccessDo")
        for i = #self.motsCles, 1, -1 do
            if self.motsCles[i] == motCle then
                table.remove(self.motsCles, i)
            end
        end
    end
    -- Original sur le disque (SDK 2.0) : faux pour une photo marquée absente.
    function photo:checkPhotoAvailability()
        return not self.absente
    end
    -- Aperçu dynamique (SDK 5.0) : smartPreviewInfo est une table vide sans lui (constaté en 2.4).
    function photo:buildSmartPreview()
        if type(self.brut.smartPreviewInfo) == 'table' and self.brut.smartPreviewInfo.smartPreviewPath then
            return 'existed'
        end
        if self.absente then
            return 'failed'
        end
        self.brut.smartPreviewInfo = { smartPreviewPath = '/Apercus/' .. tostring(self.localIdentifier) .. '.dng', smartPreviewSize = 2097152 }
        return 'created'
    end
    function photo:deleteSmartPreview()
        assert(not S.ecritureEnCours, "deleteSmartPreview dans withWriteAccessDo")
        self.brut.smartPreviewInfo = {}
        return 'deleted'
    end
    -- Nom que donnerait un modèle de noms (SDK 3.0) : S.nomsModeles[id] avec le texte et le numéro.
    -- Constaté en 2.5 : le même nom que l'exportation avec ce modèle.
    function photo:getNameViaPreset(id, texte, numero)
        local forme = S.nomsModeles[id]
        assert(forme, "modèle de noms inconnu : " .. tostring(id))
        local base = tostring(self.meta.fileName or 'photo'):gsub('%.[^.]*$', '')
        return (forme:gsub('{texte}', texte or ''):gsub('{numero}', tostring(numero)):gsub('{nom}', base))
    end
    function photo:getContainedCollections()
        local liste = {}
        for _, c in ipairs(S.collections) do
            if not c.dynamique and c.membres[self] then
                liste[#liste + 1] = c
            end
        end
        return liste
    end
    -- Un paramètre prédéfini remplace les réglages qu'il porte, masques compris : ceux de la
    -- photo disparaissent (constaté dans Lightroom Classic 15.6 : un masque IA ajouté à cinq
    -- autres n'en laissait qu'un). Lightroom calcule alors les masques IA sans empreinte
    -- (MaskDigest), ce qu'il ne fait pas pour ceux que pose applyDevelopSettings. Un paramètre
    -- prédéfini du module sans balance des blancs fait tomber une balance personnalisée aux
    -- butées (constaté sur un RAW ; ceux d'Adobe la gardent).
    -- quantite : la Quantité prédéfinie, en % (relevé dans SdkApplyDevelopPreset de Lightroom
    -- Classic 15.6 : arrondie, divisée par 100, ignorée hors de 0 à 2). Supposé : un réglage
    -- numérique va de sa valeur actuelle à celle du paramètre prédéfini en proportion.
    function photo:applyDevelopPreset(preset, plugin, quantite)
        assert(S.ecritureEnCours, "applyDevelopPreset hors de withWriteAccessDo")
        verifierSansMetatable(preset.reglages, 'preset')
        self:modifiee()
        local part = 1
        if type(quantite) == 'number' then
            local q = math.floor(quantite + 0.5) / 100
            if q >= 0 and q <= 2 then
                part = q
            end
            S.quantitesPresets[#S.quantitesPresets + 1] = quantite
        end
        if preset.duModule and preset.reglages.WhiteBalance == nil and self.reglages.WhiteBalance == 'Custom'
            and self.reglages.Temperature ~= nil then
            self.reglages.Temperature, self.reglages.Tint = 2000, -150
        end
        for cle, valeur in pairs(preset.reglages) do
            local actuel = tonumber(self.reglages[cle]) or 0
            if part ~= 1 and type(valeur) == 'number' then
                self.reglages[cle] = actuel + (valeur - actuel) * part
            else
                self.reglages[cle] = copier(valeur)
            end
        end
        -- Profil d'objectif (constaté le 18 octobre 2026) : sans LensProfileEnable, un paramètre
        -- prédéfini qui porte LensProfileSetup le met à 0 ; 'LensDefaults' y tient, et Lightroom
        -- reprend le profil par défaut de la photo (photo.objectifParDefaut).
        if preset.reglages.LensProfileSetup ~= nil and preset.reglages.LensProfileEnable == nil then
            self.reglages.LensProfileEnable = 0
        end
        if preset.reglages.LensProfileSetup == 'LensDefaults' and type(self.objectifParDefaut) == 'table' then
            for cle, valeur in pairs(self.objectifParDefaut) do
                self.reglages[cle] = valeur
            end
        end
        -- Mélange noir et blanc automatique (supposé calculé comme la tonalité automatique, par un
        -- paramètre prédéfini) : Lightroom fixe les curseurs GrayMixer* d'après la photo.
        if preset.reglages.AutoGrayscaleMix == true and self.reglages.ConvertToGrayscale == true then
            for i, couleur in ipairs({ 'Red', 'Orange', 'Yellow', 'Green', 'Aqua', 'Blue', 'Purple', 'Magenta' }) do
                self.reglages['GrayMixer' .. couleur] = (i * 7) % 30 - 12
            end
        end
        verifierMasques(self.reglages)
        perimerLook(self, preset.reglages)
        rangerLookAdaptatif(self, preset.reglages, true)
        -- Dans Lightroom, le calcul vient peu après, à l'affichage de la photo : S.calculDiffere le
        -- repousse à la première attente du module (LrTasks.sleep), ou jamais avec S.jamaisCalcule.
        if not S.calculDiffere then
            self:calculerMasquesIA()
        end
        self.appliques[#self.appliques + 1] = { preset = preset.nom }
    end
    -- Calculs IA de Lightroom : masques (MaskDigest) et carte de profondeur d'un flou d'objectif
    -- actif (DepthMapInfo, relevé dans le catalogue).
    function photo:calculerMasquesIA()
        for _, correction in ipairs(self.reglages.MaskGroupBasedCorrections or {}) do
            for _, m in ipairs(correction.CorrectionMasks or {}) do
                if m.What == 'Mask/Image' and m.MaskDigest == nil and (tonumber(m.ErrorReason) or 0) == 0 then
                    m.MaskDigest = 'calculé pour ' .. tostring(self.localIdentifier)
                    -- Masque d'une personne précise (constaté le 18 octobre 2026) : Lightroom ne la
                    -- reconnaît que si le masque porte les cadres de toutes les personnes qu'il trouve
                    -- (photo.personnes), à peu près (le centre de chacun dans le sien) ; il range alors
                    -- ReferencePoint au centre de la personne. Sinon, il retire InstanceIDs et calcule
                    -- un masque de sous-type 3.
                    if m.InstanceIDs then
                        local trouvees, bornes = self.personnes or {}, m.InstanceBounds
                        local reconnue = type(bornes) == 'table' and #bornes == #trouvees and #trouvees > 0
                        for j, b in ipairs(reconnue and bornes or {}) do
                            local t = trouvees[j]
                            local cx, cy = (b.Left + b.Right) / 2, (b.Top + b.Bottom) / 2
                            if not (cx >= t.Left and cx <= t.Right and cy >= t.Top and cy <= t.Bottom) then
                                reconnue = false
                            end
                        end
                        local id = tonumber(m.InstanceIDs[1] and m.InstanceIDs[1].InstanceID) or 0
                        local t = trouvees[id + 1]
                        if reconnue and t then
                            m.ReferencePoint = string.format('%f %f', (t.Left + t.Right) / 2, (t.Top + t.Bottom) / 2)
                        else
                            m.InstanceIDs, m.MaskSubType, m.MaskSubCategoryID = nil, 3, 13
                        end
                    end
                end
            end
        end
        -- Poussière (constaté le 18 octobre 2026) : un filtre Dust Removal sans résultat (Images) est
        -- vidé ; un filtre copié d'une autre photo est gardé tel quel (pas de nouvelle recherche).
        local liste = type(self.reglages.FilterList) == 'table' and self.reglages.FilterList.Filters
        if type(liste) == 'table' then
            local filtres, change = {}, false
            for _, filtre in ipairs(liste) do
                if filtre.Name == 'Dust Removal' and (type(filtre.Images) ~= 'table' or #filtre.Images == 0) then
                    change = true
                else
                    filtres[#filtres + 1] = filtre
                end
            end
            if change then
                self.reglages.FilterList = #filtres > 0 and { Filters = filtres } or {}
            end
        end
        local flou = self.reglages.LensBlur
        if type(flou) == 'table' and flou.Active == true and self.reglages.DepthMapInfo == nil then
            self.reglages.DepthMapInfo = { BaseRawDepthInputDigest = 'profondeur de ' .. tostring(self.localIdentifier), DepthSource = 2 }
        end
        -- Constaté le 17 octobre 2026 : une zone nette manuelle (FocalRangeSource = 0, FocalRange et
        -- SubjectRange donnés) est gardée, et Lightroom range alors FocalRangeSource = 3.
        if type(flou) == 'table' and flou.Active == true and tonumber(flou.FocalRangeSource) == 0 then
            flou.FocalRangeSource = 3
        end
        -- Taches de l'outil Supprimer, calculées comme les masques (constaté le 17 octobre 2026 par la
        -- recette : pm_patch, pm_version… rangés, et fill_method retiré d'une tache sans IA générative).
        for _, cle in ipairs({ 'RemoveAreas', 'RetouchAreas' }) do
            for _, tache in ipairs(self.reglages[cle] or {}) do
                if tache.SpotType == 'heal_patchmatch' and tache.pm_patch == nil then
                    tache.pm_patch, tache.pm_version = 'remplissage pour ' .. tostring(self.localIdentifier), 327680
                    if tache.fill_method == 'patchmatch' then
                        tache.fill_method = nil
                    end
                end
            end
        end
    end
    -- Profil adaptatif marqué « à mettre à jour » : calculé pour cette photo (relevé dans le
    -- catalogue : AILookData, InputDigest, InputDigestVersion, ModelVersion, Version, Active).
    function photo:mettreAJourLook()
        if not self.lookAMettreAJour then
            return
        end
        self.lookAMettreAJour = false
        local calcul = copier(self.reglages.AILook)
        S.recalculsLook = S.recalculsLook + 1
        calcul.AILookData = 'look de ' .. tostring(self.localIdentifier)
        calcul.InputDigest, calcul.InputDigestVersion = 'image de ' .. tostring(self.localIdentifier) .. ' (' .. S.recalculsLook .. ')', 5
        self.reglages.AILook = calcul
    end
    -- Réglages IA mis à jour par le SDK (Lightroom Classic 13.3 et suivants ; S.miseAJourIA, à poser
    -- avant de créer la photo). Relevé dans le code de Lightroom Classic 15.6 (LrPhoto,
    -- AgCameraRawBatchPixelMaskUpdate) : updateAISettings fait la mise à jour de la case « Mettre à
    -- jour les photos concernées » de la fenêtre « Mises à jour IA recommandées », sans fenêtre, et
    -- rend la main à la fin ; sans les modèles IA téléchargés (S.modelesIAAbsents), rien, sans
    -- erreur ; elle écrit par une commande de Lightroom (supposé : à appeler hors de
    -- withWriteAccessDo, que la simulation refuse). needsUpdateAISettings dit s'il reste à calculer.
    -- Un profil adaptatif déjà calculé est recalculé après une tache ou un flou d'objectif
    -- (photo.lookPerime, constaté ; S.lookFige pour un Lightroom qui ne le ferait pas).
    if S.miseAJourIA then
        function photo:needsUpdateAISettings()
            return calculsIAEnAttente(self.reglages) or self.lookAMettreAJour == true
        end
        function photo:updateAISettings()
            assert(not S.ecritureEnCours, "updateAISettings dans withWriteAccessDo")
            S.misesAJourIA[#S.misesAJourIA + 1] = self.localIdentifier
            S.horloge = S.horloge + S.dureeCalculIA
            if S.pendantMiseAJourIA then
                S.pendantMiseAJourIA(self)
            end
            if S.modelesIAAbsents then
                return
            end
            self:calculerMasquesIA()
            self:mettreAJourLook()
            local calcul = self.reglages.AILook
            if self.lookPerime and not S.lookFige and type(calcul) == 'table' and calcul.AILookData ~= nil then
                calcul = copier(calcul)
                S.recalculsLook = S.recalculsLook + 1
                calcul.InputDigest = 'image de ' .. tostring(self.localIdentifier) .. ' (' .. S.recalculsLook .. ')'
                self.reglages.AILook = calcul
            end
            self.lookPerime = false
        end
    end
    -- Vignette du cache d'aperçus (SDK 5.0) : le rappel reçoit le JPEG (un texte), ou nil et la
    -- raison (photo.vignetteImpossible) ; avec S.vignettesDifferees, au prochain LrTasks.sleep ;
    -- photo.vignetteJamais : jamais de rappel. La taille demandée est un minimum.
    function photo:requestJpegThumbnail(largeur, hauteur, rappel)
        S.vignettesDemandees[#S.vignettesDemandees + 1] = { photo = self.localIdentifier, largeur = largeur, hauteur = hauteur }
        local requete = { photo = self }
        local function rendre()
            if self.vignetteImpossible then
                rappel(nil, self.vignetteImpossible)
            else
                rappel('JPEG ' .. tostring(self.localIdentifier) .. ' ' .. tostring(largeur))
            end
        end
        if self.vignetteJamais then
            return requete
        end
        if S.vignettesDifferees then
            S.vignettesEnAttente[#S.vignettesEnAttente + 1] = rendre
        else
            rendre()
        end
        return requete
    end
    -- Instantanés (panneau Instantanés) : leur nom (instantanes) et les réglages de chacun
    -- (snapshots, avec snapshotID et id_global comme getDevelopSnapshots).
    function photo:createDevelopSnapshot(nom, majSiExiste)
        assert(S.ecritureEnCours, "createDevelopSnapshot hors de withWriteAccessDo")
        for _, snap in ipairs(self.snapshots) do
            if snap.name == nom then
                if not majSiExiste then return false end
                snap.reglages = copier(self.reglages)
                return true
            end
        end
        self.instantanes[#self.instantanes + 1] = nom
        S.prochainInstantane = S.prochainInstantane + 1
        self.snapshots[#self.snapshots + 1] = { snapshotID = S.prochainInstantane, id_global = 'snap-' .. S.prochainInstantane,
            name = nom, reglages = copier(self.reglages) }
        return true
    end
    function photo:getDevelopSnapshots()
        local liste = {}
        for _, snap in ipairs(self.snapshots) do
            liste[#liste + 1] = { snapshotID = snap.snapshotID, id_global = snap.id_global, name = snap.name }
        end
        return liste
    end
    -- Relevé dans le code de Lightroom Classic 15.6 : applyDevelopSnapshot(snapshotID) et
    -- deleteDevelopSnapshot(id_global) sont des commandes du module Développement. Constaté le
    -- 17 octobre 2026 : dans une écriture, applyDevelopSnapshot ne change rien, sans erreur ;
    -- deleteDevelopSnapshot efface par l'id_global, photo affichée dans le module Développement.
    -- Constaté le 17 octobre 2026 : hors écriture aussi, rien ne change tant que la photo n'est pas
    -- affichée dans le module Développement.
    function photo:applyDevelopSnapshot(id)
        if S.ecritureEnCours or S.instantaneBloque or not (S.module == 'develop' and S.active == self) then
            S.instantanesIgnores[#S.instantanesIgnores + 1] = id
            return
        end
        for _, snap in ipairs(self.snapshots) do
            if snap.snapshotID == id then
                self.reglages = copier(snap.reglages)
                S.instantanesPoses[#S.instantanesPoses + 1] = snap.name
                return
            end
        end
        S.instantanesIgnores[#S.instantanesIgnores + 1] = id
    end
    function photo:deleteDevelopSnapshot(uuid)
        if S.ecritureEnCours or not (S.module == 'develop' and S.active == self) then
            S.instantanesIgnores[#S.instantanesIgnores + 1] = uuid
            return
        end
        for i, snap in ipairs(self.snapshots) do
            if snap.id_global == uuid then
                table.remove(self.snapshots, i)
                for j, nom in ipairs(self.instantanes) do
                    if nom == snap.name then table.remove(self.instantanes, j) break end
                end
                return
            end
        end
    end
    -- Paramètre prédéfini de métadonnées (S.presetsMeta[id] : champs IPTC et mots-clés). Constaté
    -- en 2.3 (Lightroom Classic 15.6) : ses valeurs ne se voient qu'après l'écriture qui l'applique.
    function photo:applyMetadataPreset(id)
        assert(S.ecritureEnCours, "applyMetadataPreset hors de withWriteAccessDo")
        local preset = S.presetsMeta[id]
        assert(preset, "applyMetadataPreset : paramètre prédéfini inconnu " .. tostring(id))
        S.apresEcriture[#S.apresEcriture + 1] = function()
            for cle, valeur in pairs(preset.champs or {}) do
                self.meta[cle] = valeur
            end
            for _, motCle in ipairs(preset.motsCles or {}) do
                self.motsCles[#self.motsCles + 1] = motCle
            end
        end
        S.presetsMetaAppliques[#S.presetsMetaAppliques + 1] = { photo = self.localIdentifier, id = id }
    end
    function photo:openExportDialog()
        S.fenetreExport = self
    end
    -- Rotation d'un quart de tour (SDK 7.4). Relevé dans le code de Lightroom Classic 15.6 (LrPhoto) :
    -- la commande ag.library.rotate, qui change l'orientation de la photo, pas ses réglages ; ses
    -- dimensions affichées s'échangent. Supposé : hors d'une écriture, comme les autres commandes.
    local SUIVANTE = { AB = 'BC', BC = 'CD', CD = 'DA', DA = 'AB' }
    function photo:tourner(quarts)
        assert(not S.ecritureEnCours, "rotation dans withWriteAccessDo")
        for _ = 1, quarts do
            self.brut.orientation = SUIVANTE[self.brut.orientation or 'AB']
            local d = self.brut.dimensions
            if type(d) == 'table' then
                d.width, d.height = d.height, d.width
            end
        end
        S.rotations[#S.rotations + 1] = { photo = self.localIdentifier, quarts = quarts }
    end
    function photo:rotateRight() self:tourner(1) end
    function photo:rotateLeft() self:tourner(3) end
    if photo.brut.uuid == nil then
        photo.brut.uuid = 'uuid-' .. tostring(id)
    end
    S.photos[id] = photo
    return photo
end

-- Photo › Créer une copie virtuelle : mêmes réglages et métadonnées, une autre uuid, l'original
-- en masterPhoto. Constaté dans Lightroom Classic 15.6 : Lightroom y copie aussi les champs du
-- module (une copie d'une photo retouchée par Claude, réinitialisée ensuite, était « Retouchée par
-- Claude » avant toute retouche, et sa comparaison montrait l'état d'avant Claude de l'original).
-- Le propriétaire de la mémoire, ajouté depuis, est copié comme les autres (constaté en 2.3 :
-- proprietaireMemoire de la copie = uuid de sa source).
function S.copieVirtuelle(original, id, nom)
    local meta = copier(original.meta)
    meta.copyName = nom or 'Copie 1'
    local brut = {}
    for cle, valeur in pairs(original.brut) do
        if cle ~= 'uuid' and cle ~= 'masterPhoto' then
            brut[cle] = copier(valeur)
        end
    end
    brut.isVirtualCopy = true
    brut.masterPhoto = original.brut.masterPhoto or original
    local copie = S.Photo(id, copier(original.reglages), meta, brut)
    copie.proprietes = copier(original.proprietes)
    local maitre = brut.masterPhoto
    maitre.copies = maitre.copies or {}
    maitre.copies[#maitre.copies + 1] = copie
    return copie
end

function catalogue:getTargetPhoto()
    return S.active
end

function catalogue:getTargetPhotos()
    return S.selection
end

function catalogue:getPhotoByLocalId(id)
    return S.photos[id]
end

-- Sélection : la photo devient la photo active, sauf si elle n'est pas visible dans le film
-- fixe (S.invisibles), où Lightroom ne la sélectionne pas.
-- Constaté en 2.3 (Lightroom Classic 15.6) : aussitôt après setActiveSources, une photo du dossier
-- affiché ne se sélectionne pas encore (S.visiblesDes).
local function selectionnable(photo)
    return not S.invisibles[photo.localIdentifier] and (S.visiblesDes[photo.localIdentifier] or 0) <= S.horloge
end

function catalogue:setSelectedPhotos(active, autres)
    if not selectionnable(active) then
        return
    end
    S.active = active
    local selection = { active }
    for _, photo in ipairs(autres or {}) do
        if selectionnable(photo) then
            selection[#selection + 1] = photo
        end
    end
    S.selection = selection
    S.chargementJusqua = S.horloge + S.delaiChargement
    S.qualiteJusqua = S.chargementJusqua + S.delaiQualite
end

function catalogue:getPath()
    return '/Users/test/Images/Catalogue.lrcat'
end

-- Écriture privée (SDK 9.0) : seulement les champs du module, sans opération dans Édition ›
-- Annuler (supposé, d'après la référence du SDK) ; la simulation refuse tout autre changement.
function catalogue:withPrivateWriteAccessDo(fonction, delai)
    assert(not S.ecritureEnCours, "withPrivateWriteAccessDo dans withWriteAccessDo")
    S.ecriturePriveeEnCours = true
    S.ecrituresPrivees = S.ecrituresPrivees + 1
    local ok, erreur = pcall(fonction)
    S.ecriturePriveeEnCours = false
    S.ecrireEnAttente(ok)
    if not ok then
        error(erreur, 0)
    end
    return 'executed'
end

-- Masques vides (SDK 14.0). Relevé dans le code de Lightroom Classic 15.6 (LrCatalog) : la commande
-- ag.develop.deleteEmptyMasks pour les photos données. Un masque est vide quand ses composants IA
-- n'ont rien trouvé sur la photo (photo.vides, par sous-type ou catégorie). Supposé : hors d'une
-- écriture, comme les autres commandes.
function catalogue:deleteAllEmptyMasks(photos)
    assert(not S.ecritureEnCours, "deleteAllEmptyMasks dans withWriteAccessDo")
    for _, photo in ipairs(photos or S.selection) do
        local gardes = {}
        for _, correction in ipairs(photo.reglages.MaskGroupBasedCorrections or {}) do
            local vide = #(correction.CorrectionMasks or {}) > 0
            for _, m in ipairs(correction.CorrectionMasks or {}) do
                local cle = m.MaskSubCategoryID or m.MaskSubType
                if not (m.What == 'Mask/Image' and photo.vides and photo.vides[cle]) then
                    vide = false
                end
            end
            if not vide then
                gardes[#gardes + 1] = correction
            end
        end
        if #gardes ~= #(photo.reglages.MaskGroupBasedCorrections or {}) then
            photo.reglages.MaskGroupBasedCorrections = gardes
            photo:modifiee()
        end
    end
    S.masquesVidesRetires = S.masquesVidesRetires + 1
end

-- Champs du module écrits pendant une écriture : vus seulement après elle, dans l'ordre où ils
-- ont été écrits ; oubliés si l'écriture échoue (supposé, comme le reste de l'écriture).
function S.ecrireEnAttente(reussie)
    local enAttente = S.enAttente
    S.enAttente = {}
    if not reussie then
        return
    end
    for photo, champs in pairs(enAttente) do
        for _, champ in ipairs(champs) do
            photo.proprietes[champ.cle] = champ.valeur
        end
    end
end

function catalogue:withWriteAccessDo(nom, fonction, delai)
    S.numeroEcriture = S.numeroEcriture + 1
    for _, photo in pairs(S.photos) do
        photo.libelleFige = { valeur = photo.meta.label }
    end
    S.ecritureEnCours = true
    S.ecritures[#S.ecritures + 1] = nom
    S.apresEcriture = {}
    local ok, erreur = pcall(fonction)
    S.ecritureEnCours = false
    S.ecrireEnAttente(ok)
    if not ok then
        error(erreur, 0)
    end
    for _, effet in ipairs(S.apresEcriture) do
        effet()
    end
    S.apresEcriture = {}
    return 'executed'
end

-- Bibliothèque -------------------------------------------------------------------------
--
-- Mots-clés, collections et ensembles, recherche et copies virtuelles, avec les fonctions que la
-- commande diagnostic a trouvées dans Lightroom Classic 15.6. Toute écriture exige
-- withWriteAccessDo (createVirtualCopies aussi : constaté en 2.3, la copie se crée dans une écriture).

local function nouvelId()
    S.prochainId = S.prochainId + 1
    return S.prochainId
end


function S.MotCle(nom, parent, synonymes)
    local motCle = { nom = nom, parent = parent, enfants = {}, nee = naissance(), synonymes = synonymes or {} }
    function motCle:getName() lisible(self, 'keyword') return self.nom end
    function motCle:getParent() lisible(self, 'keyword') return self.parent end
    function motCle:getChildren()
        lisible(self, 'keyword')
        local liste = {}
        for _, enfant in ipairs(self.enfants) do liste[#liste + 1] = enfant end
        return liste
    end
    function motCle:getSynonyms()
        local liste = {}
        for _, s in ipairs(self.synonymes) do liste[#liste + 1] = s end
        return liste
    end
    -- setAttributes { keywordName, synonyms, … } (SDK 3.0), dans une écriture.
    function motCle:setAttributes(attributs)
        assert(S.ecritureEnCours, "setAttributes hors de withWriteAccessDo")
        lisible(self, 'keyword')
        verifierSansMetatable(attributs, 'attributs')
        if attributs.keywordName then self.nom = attributs.keywordName end
        if attributs.synonyms then self.synonymes = attributs.synonyms end
    end
    function motCle:getPhotos()
        local liste = {}
        for _, photo in pairs(S.photos) do
            for _, m in ipairs(photo.motsCles) do
                if m == self then liste[#liste + 1] = photo end
            end
        end
        return liste
    end
    if parent then
        parent.enfants[#parent.enfants + 1] = motCle
    else
        S.motsClesRacine[#S.motsClesRacine + 1] = motCle
    end
    return motCle
end

function catalogue:getKeywords()
    local liste = {}
    for _, m in ipairs(S.motsClesRacine) do liste[#liste + 1] = m end
    return liste
end

-- createKeyword(nom, synonymes, inclureALExport, parent, rendreExistant)
-- Constaté en 2.3 (Lightroom Classic 15.6) : un mot-clé créé dans l'écriture sert de parent au
-- suivant et se pose sur une photo (addKeyword) dans la même écriture ; seule sa lecture (getName…)
-- y échoue.
function catalogue:createKeyword(nom, synonymes, inclure, parent, rendreExistant)
    assert(S.ecritureEnCours, "createKeyword hors de withWriteAccessDo")
    if rendreExistant then
        for _, m in ipairs(parent and parent.enfants or S.motsClesRacine) do
            if m.nom == nom then return m end
        end
    end
    S.motsClesCrees[#S.motsClesCrees + 1] = nom
    verifierSansMetatable(synonymes, 'synonymes')
    return S.MotCle(nom, parent, synonymes)
end

function S.Ensemble(nom, parent)
    local ensemble = { nom = nom, parent = parent, localIdentifier = nouvelId(), nee = naissance() }
    function ensemble:getName() lisible(self, 'collection set') return self.nom end
    function ensemble:getParent() lisible(self, 'collection set') return self.parent end
    function ensemble:getChildCollections()
        lisible(self, 'collection set')
        local liste = {}
        for _, c in ipairs(S.collections) do
            if c.parent == self then liste[#liste + 1] = c end
        end
        return liste
    end
    function ensemble:getChildCollectionSets()
        lisible(self, 'collection set')
        local liste = {}
        for _, e in ipairs(S.ensembles) do
            if e.parent == self then liste[#liste + 1] = e end
        end
        return liste
    end
    S.ensembles[#S.ensembles + 1] = ensemble
    return ensemble
end

function S.Collection(nom, parent, recherche)
    local c = { nom = nom, parent = parent, id = nouvelId(), membres = {}, dynamique = recherche ~= nil, recherche = recherche,
        nee = naissance() }
    setmetatable(c, { __index = function(t, cle)
        if cle == 'localIdentifier' then
            lisible(t, 'collection')
            return rawget(t, 'id')
        end
    end })
    function c:getName() lisible(self, 'collection') return self.nom end
    function c:getParent() lisible(self, 'collection') return self.parent end
    function c:isSmartCollection() return self.dynamique end
    function c:getSearchDescription() return self.recherche end
    function c:setName(nouveau)
        assert(S.ecritureEnCours, "setName hors de withWriteAccessDo")
        lisible(self, 'collection')
        self.nom = nouveau
    end
    function c:setParent(ensemble)
        assert(S.ecritureEnCours, "setParent hors de withWriteAccessDo")
        lisible(self, 'collection')
        if ensemble then lisible(ensemble, 'collection set') end
        self.parent = ensemble
    end
    function c:setSearchDescription(recherche)
        assert(S.ecritureEnCours, "setSearchDescription hors de withWriteAccessDo")
        assert(self.dynamique, "setSearchDescription sur une collection ordinaire")
        verifierSansMetatable(recherche, 'recherche')
        self.recherche = recherche
    end
    function c:getPhotos()
        if self.dynamique then
            return catalogue:findPhotos({ searchDesc = self.recherche })
        end
        local liste = {}
        for photo in pairs(self.membres) do liste[#liste + 1] = photo end
        table.sort(liste, function(a, b) return a.localIdentifier < b.localIdentifier end)
        return liste
    end
    function c:addPhotos(photos)
        assert(S.ecritureEnCours, "addPhotos hors de withWriteAccessDo")
        lisible(self, 'collection')
        assert(not self.dynamique, "addPhotos sur une collection dynamique")
        for _, photo in ipairs(photos) do self.membres[photo] = true end
    end
    function c:removePhotos(photos)
        assert(S.ecritureEnCours, "removePhotos hors de withWriteAccessDo")
        lisible(self, 'collection')
        for _, photo in ipairs(photos) do self.membres[photo] = nil end
    end
    S.collections[#S.collections + 1] = c
    return c
end

-- Services de publication (lecture seulement dans une tâche : pas simulé). Constaté en 2.3 :
-- getPublishSettings rend une table observable que pairs ne parcourt pas (ses clés se lisent une
-- à une).
function S.Service(nom, module, reglages)
    local service = { nom = nom, module = module, localIdentifier = nouvelId(), reglages = reglages or {} }
    function service:getName() return self.nom end
    function service:getPluginId() return self.module end
    function service:getPublishSettings()
        local lus = self.reglages
        return setmetatable({}, { __index = function(_, cle) return lus[cle] end })
    end
    S.services[#S.services + 1] = service
    return service
end

function catalogue:getPublishServices() return S.services end

-- Photo par son chemin (brut.path) : celles que l'exportation réimporte y sont ajoutées.
function catalogue:findPhotoByPath(chemin)
    for _, photo in pairs(S.photos) do
        if photo.brut.path == chemin and not photo.retireeDuCatalogue then return photo end
    end
    return nil
end

-- Aperçus dynamiques (référence du SDK 5.0) : created, existed, failed ; rien pour une photo dont
-- l'original manque.
function catalogue:buildSmartPreviews(photos)
    local bilan = { created = {}, existed = {}, failed = {} }
    for _, photo in ipairs(photos) do
        local liste = bilan[photo:buildSmartPreview()]
        liste[#liste + 1] = photo
    end
    return bilan
end

local function enfantsRacine(liste)
    local resultat = {}
    for _, element in ipairs(liste) do
        if element.parent == nil then resultat[#resultat + 1] = element end
    end
    return resultat
end

function catalogue:getChildCollections() return enfantsRacine(S.collections) end
function catalogue:getChildCollectionSets() return enfantsRacine(S.ensembles) end

function catalogue:getCollectionByLocalIdentifier(id)
    for _, c in ipairs(S.collections) do
        if rawget(c, 'id') == id then return c end
    end
    return nil
end

local function existante(liste, nom, parent)
    for _, element in ipairs(liste) do
        if element.nom == nom and element.parent == parent then return element end
    end
    return nil
end

function catalogue:createCollectionSet(nom, parent, rendreExistant)
    assert(S.ecritureEnCours, "createCollectionSet hors de withWriteAccessDo")
    lisible(parent, 'collection set')
    return (rendreExistant and existante(S.ensembles, nom, parent)) or S.Ensemble(nom, parent)
end

function catalogue:createCollection(nom, parent, rendreExistant)
    assert(S.ecritureEnCours, "createCollection hors de withWriteAccessDo")
    lisible(parent, 'collection set')
    return (rendreExistant and existante(S.collections, nom, parent)) or S.Collection(nom, parent)
end

function catalogue:createSmartCollection(nom, recherche, parent, rendreExistant)
    assert(S.ecritureEnCours, "createSmartCollection hors de withWriteAccessDo")
    lisible(parent, 'collection set')
    return (rendreExistant and existante(S.collections, nom, parent)) or S.Collection(nom, parent, recherche)
end

-- findPhotos : les critères que le module emploie, comme les collections dynamiques d'Adobe ;
-- un critère ou une opération inconnus échouent, comme une faute de frappe le ferait.
local COULEUR_NUMERO = { red = 1, yellow = 2, green = 3, blue = 4, purple = 5 }
local SECONDES_JOUR = 86400

local function texteContient(texte, valeur)
    return texte ~= nil and tostring(texte):lower():find(tostring(valeur):lower(), 1, true) ~= nil
end

local function compare(a, operation, b)
    if a == nil then return false end
    if operation == '==' then return a == b
    elseif operation == '!=' then return a ~= b
    elseif operation == '>=' then return a >= b
    elseif operation == '<=' then return a <= b end
    error("opération inconnue : " .. tostring(operation), 0)
end

local function repond(photo, c)
    local op = c.operation
    if c.criteria == 'rating' then
        return compare(tonumber(photo.brut.rating) or 0, op, c.value)
    elseif c.criteria == 'pick' then
        return compare(tonumber(photo.brut.pickStatus) or 0, op, c.value)
    elseif c.criteria == 'labelColor' then
        return compare(COULEUR_NUMERO[photo:getRawMetadata('colorNameForLabel')], op, c.value)
    elseif c.criteria == 'isoSpeedRating' then
        return compare(tonumber(photo.brut.isoSpeedRating or photo.meta.isoSpeedRating), op, c.value)
    elseif c.criteria == 'fileFormat' then
        return compare(photo.brut.fileFormat or photo.meta.fileFormat, op, c.value)
    elseif c.criteria == 'camera' or c.criteria == 'lens' then
        assert(op == '==', "opération non simulée pour " .. c.criteria)
        local valeur = c.criteria == 'camera' and photo.meta.cameraModel or photo.meta.lens
        return valeur ~= nil and tostring(valeur):lower() == tostring(c.value):lower()
    elseif c.criteria == 'keywords' then
        if op == 'empty' then return #photo.motsCles == 0 end
        assert(op == 'words', "opération non simulée pour keywords : " .. tostring(op))
        for _, m in ipairs(photo.motsCles) do
            if m.nom:lower() == tostring(c.value):lower() then return true end
        end
        return false
    elseif c.criteria == 'all' then
        assert(op == 'all', "opération non simulée pour all : " .. tostring(op))
        for mot in tostring(c.value):gmatch('%S+') do
            local trouve = texteContient(photo.meta.fileName, mot) or texteContient(photo.meta.title, mot)
                or texteContient(photo.meta.caption, mot)
            for _, m in ipairs(photo.motsCles) do
                trouve = trouve or texteContient(m.nom, mot)
            end
            if not trouve then return false end
        end
        return true
    elseif c.criteria == 'captureTime' then
        assert(op == 'inLast' and c.value_units == 'days', "opération non simulée pour captureTime")
        local t = tonumber(photo.brut.dateTimeOriginal)
        return t ~= nil and t >= S.maintenant - c.value * SECONDES_JOUR
    elseif c.criteria == 'sdktext:' .. _PLUGIN.id .. '.retoucheeParClaude' then
        local valeur = photo.proprietes.retoucheeParClaude
        if op == 'notEmpty' then return valeur ~= nil and valeur ~= '' end
        if op == 'empty' then return valeur == nil or valeur == '' end
        error("opération non simulée pour le champ du module", 0)
    end
    error("critère inconnu : " .. tostring(c.criteria), 0)
end

function catalogue:findPhotos(args)
    local desc = args.searchDesc
    assert(desc.combine == 'intersect', "combine non simulé")
    S.recherches[#S.recherches + 1] = desc
    local liste = {}
    for _, photo in pairs(S.photos) do
        local garde = true
        for _, c in ipairs(desc) do
            garde = garde and repond(photo, c)
        end
        if garde then liste[#liste + 1] = photo end
    end
    table.sort(liste, function(a, b) return a.localIdentifier < b.localIdentifier end)
    return liste
end

function catalogue:batchGetFormattedMetadata(photos, cles)
    S.lecturesGroupees = (S.lecturesGroupees or 0) + 1
    local resultat = {}
    for _, photo in ipairs(photos) do
        local valeurs = {}
        for _, cle in ipairs(cles) do valeurs[cle] = photo:getFormattedMetadata(cle) end
        resultat[photo] = valeurs
    end
    return resultat
end

function catalogue:batchGetPropertyForPlugin(photos, plugin, champs)
    local resultat = {}
    for _, photo in ipairs(photos) do
        local valeurs = {}
        for _, champ in ipairs(champs) do valeurs[champ] = photo:getPropertyForPlugin(plugin, champ) end
        resultat[photo] = valeurs
    end
    return resultat
end

-- Jeu de libellés actif (SDK 3.0, dans une tâche) : supposé texte → couleur, comme son nom le dit ;
-- le module lit les deux sens.
function catalogue:getLabelMapToColorName()
    if S.jeuLibellesIllisible then
        error("getLabelMapToColorName : non offert", 0)
    end
    local table_ = {}
    for texte, couleur in pairs(S.jeuLibelles) do table_[texte] = couleur end
    return table_
end

-- Filtre de la Bibliothèque (SDK 3.0) : la simulation garde la table posée.
function catalogue:getCurrentViewFilter()
    return copier(S.filtre), S.filtrePreset
end

function catalogue:setViewFilter(filtre)
    if type(filtre) == 'string' then
        for nom, id in pairs(S.presetsFiltre) do
            if id == filtre then
                local change = S.filtrePreset ~= nom
                S.filtre, S.filtrePreset = { preset = nom }, nom
                S.filtresPoses[#S.filtresPoses + 1] = nom
                return change
            end
        end
        return nil
    end
    verifierSansMetatable(filtre, 'filtre')
    S.filtre, S.filtrePreset = copier(filtre), nil
    -- Constaté en 2.4 : un filtre posé sans columnBrowserDesc remet les colonnes par défaut.
    if S.filtre.columnBrowserDesc == nil then
        S.filtre.columnBrowserDesc = { { criteria = 'dateHierarchy' }, { criteria = 'camera' }, { criteria = 'lens' }, { criteria = 'label' } }
    end
    S.filtresPoses[#S.filtresPoses + 1] = copier(filtre)
    return true
end

function catalogue:batchGetRawMetadata(photos, cles)
    local resultat = {}
    for _, photo in ipairs(photos) do
        local valeurs = {}
        for _, cle in ipairs(cles) do valeurs[cle] = photo:getRawMetadata(cle) end
        resultat[photo] = valeurs
    end
    return resultat
end

-- Dossiers : d'après le chemin des photos (brut.path).
local function dossierDe(chemin)
    return (chemin or ''):match('^(.*)/[^/]*$')
end

function catalogue:getFolderByPath(chemin)
    local existe = false
    for _, photo in pairs(S.photos) do
        local d = dossierDe(photo.brut.path)
        if d and (d == chemin or d:sub(1, #chemin + 1) == chemin .. '/') then existe = true end
    end
    if not existe then return nil end
    return {
        chemin = chemin,
        getPath = function() return chemin end,
        getPhotos = function(_, sousDossiers)
            local liste = {}
            for _, photo in pairs(S.photos) do
                local d = dossierDe(photo.brut.path)
                if d == chemin or (sousDossiers and d and d:sub(1, #chemin + 1) == chemin .. '/') then
                    liste[#liste + 1] = photo
                end
            end
            table.sort(liste, function(a, b) return a.localIdentifier < b.localIdentifier end)
            return liste
        end,
    }
end

function catalogue:getActiveSources()
    return S.sources
end

-- Afficher un dossier rend visibles dans le film fixe les photos qu'il contient, après un moment.
function catalogue:setActiveSources(sources)
    S.sources = sources
    S.sourcesChangees[#S.sourcesChangees + 1] = sources
    for _, source in ipairs(sources or {}) do
        if source.chemin then
            for _, photo in ipairs(source:getPhotos(false)) do
                if S.invisibles[photo.localIdentifier] then
                    S.invisibles[photo.localIdentifier] = nil
                    S.visiblesDes[photo.localIdentifier] = S.horloge + S.delaiSource
                end
            end
        end
    end
end

-- Photo › Créer une copie virtuelle, pour les photos sélectionnées.
function catalogue:createVirtualCopies(nom)
    assert(S.ecritureEnCours, "createVirtualCopies hors de withWriteAccessDo")
    local copies = {}
    for _, photo in ipairs(S.selection) do
        copies[#copies + 1] = S.copieVirtuelle(photo, nouvelId(), nom)
    end
    return copies
end

-- Panneau Amélioration (débruitage, détails bruts, super résolution), comme le code de Lightroom
-- Classic 15.6 le montre : LrDevelopController n'agit que sur la photo affichée dans le module
-- Développement (assert ailleurs, getEnhancePanelState nil) ; setEnhance refuse un traitement que
-- Lightroom ne permet pas pour la photo, avec sa raison ; la case change tout de suite, mais le
-- résultat n'arrive dans FilterList qu'à la fin du calcul (S.dureeAmelioration attentes du
-- module, jamais avec S.ameliorationBloquee). Constaté dans Lightroom Classic 15.6 : le débruitage
-- et la super résolution cochent aussi les détails bruts (le débruitage les retire avec lui ; la
-- super résolution aussi : constaté en 2.3, retour à l'origine sans amélioration), et Lightroom refuse de toucher aux détails bruts tant que
-- l'un des deux est actif (rawDetailsEnabled faux, raison DETAILS_IMPOSES) ; FilterList.Filters
-- porte un filtre Name = 'Enhance', FilterID = 1, Title = '$$$/CRaw/Filter/Title/Denoise=Denoise',
-- et pour les traitements seuls « Raw Details » ou « Super Resolution » après le « = » (début du
-- titre supposé). Le module les appelle hors de withWriteAccessDo : la simulation le refuse.
local function etatAmelioration(photo)
    photo.amelioration = photo.amelioration or { denoise = false, rawDetails = false, superRes = false, denoiseAmount = 50 }
    return photo.amelioration
end

local DETAILS_IMPOSES = "Appliqué automatiquement lors de l’utilisation de la super-résolution ou de la réduction de bruit."

local function detailsImposes(photo, nom)
    local e = etatAmelioration(photo)
    return nom == 'rawDetails' and (e.denoise or e.superRes)
end

-- Relevé dans DevelopEnhance (Lightroom Classic 15.6) : <nom>Enabled = negative:isFinalQuality()
-- and … ; tant que la photo affichée n'est pas chargée en pleine qualité (S.delaiQualite secondes
-- après son chargement), les trois sont faux, et <nom>InfoText n'est que la description du
-- traitement. Constaté : premier passage au module Développement après la relance de Lightroom,
-- sur une photo en super résolution.
local DESCRIPTIONS = {
    denoise = "Réduit le bruit.",
    rawDetails = "Améliore le dématriçage.",
    superRes = "Double la résolution de l'image. Idéal pour les écrans et tirages de grande taille.",
}

local function pleineQualite()
    return S.horloge >= S.qualiteJusqua
end

local function permis(photo, nom)
    if not pleineQualite() or detailsImposes(photo, nom) then
        return false
    end
    return not (photo.ameliorationsRefusees and photo.ameliorationsRefusees[nom])
end

local function raisonRefus(photo, nom)
    if not pleineQualite() then
        return DESCRIPTIONS[nom]
    end
    return detailsImposes(photo, nom) and DETAILS_IMPOSES or (photo.raisonAmelioration or '')
end

local function lancerCalcul(photo)
    assert(not S.ecritureEnCours, "LrDevelopController dans withWriteAccessDo")
    photo.calculAmelioration = S.dureeAmelioration
end

function S.avancerAmeliorations()
    if S.ameliorationBloquee then
        return
    end
    for _, photo in pairs(S.photos) do
        local reflets = photo.calculReflets
        if reflets then
            reflets.duree = reflets.duree - 1
            if reflets.duree <= 0 then
                photo.calculReflets = nil
                local filtres = {}
                for _, filtre in ipairs((photo.reglages.FilterList or {}).Filters or {}) do
                    if filtre.Name ~= 'Reflections' then
                        filtres[#filtres + 1] = filtre
                    end
                end
                if reflets.actif then
                    local melange = string.format('%d/1073741824', math.floor(reflets.intensite / 100 * 1073741824))
                    filtres[#filtres + 1] = { Name = 'Reflections', FilterID = 3, Quality = reflets.qualite,
                        Title = '$$$/CRaw/Filter/ReflectionRemoval/FilterPanelTitle=Reflection Removal',
                        Images = { { BlendParams = { melange, melange, melange, melange } } },
                        CompressedSettings = 'reflets ' .. tostring(reflets.intensite) }
                    photo.reglages.EnableDistractionRemoval = true
                end
                photo.reglages.FilterList = { Filters = filtres }
                if reflets.rappel then
                    reflets.rappel(reflets.argument)
                end
            end
        end
    end
    for _, photo in pairs(S.photos) do
        if photo.calculAmelioration then
            photo.calculAmelioration = photo.calculAmelioration - 1
            if photo.calculAmelioration <= 0 then
                photo.calculAmelioration = nil
                local e = etatAmelioration(photo)
                local filtres = {}
                local titre = e.denoise and 'Denoise' or (e.superRes and 'Super Resolution') or (e.rawDetails and 'Raw Details')
                if titre then
                    filtres[1] = { Name = 'Enhance', FilterID = 1, Title = '$$$/CRaw/Filter/Title/' .. titre:gsub(' ', '') .. '=' .. titre,
                        CompressedSettings = tostring(e.denoiseAmount) .. tostring(e.rawDetails) .. tostring(e.superRes) }
                end
                photo.reglages.FilterList = { Filters = filtres }
            end
        end
    end
end

-- Photo que montre le module Développement : la photo active, une fois chargée (S.delaiChargement
-- secondes après un changement de photo ou de module ; avant, encore la précédente).
local function affichee()
    if S.module ~= 'develop' then
        return nil
    end
    if S.horloge >= S.chargementJusqua then
        S.affichee = S.active
    end
    return S.affichee
end

local function dansDeveloppement()
    local photo = affichee()
    if not photo then
        error("this operation can be executed only when the Develop module is opened.", 0)
    end
    return photo
end

-- Synchronisation automatique (S.synchroAuto) : supposée suivie par LrDevelopController, comme les
-- curseurs que MIDI2LR règle ; le traitement s'appliquerait à toutes les photos sélectionnées.
local function photosTraitees(photo)
    local liste = { photo }
    if S.synchroAuto then
        for _, autre in ipairs(S.selection) do
            if autre ~= photo then
                liste[#liste + 1] = autre
            end
        end
    end
    return liste
end

-- Suppression des reflets, comme le code de Lightroom Classic 15.6 le montre (LrDevelopController) :
-- toggleReflectionRemoval pose le filtre dereflect (ou le retire s'il est là) à la fin d'un calcul
-- en arrière-plan (S.dureeAmelioration attentes), puis appelle le rappel ; sans rien faire, sans
-- erreur, si la photo n'est pas chargée en pleine qualité ou pas prise en charge
-- (photo.refletsNonPris). Filtre relevé le 17 octobre 2026 : Name = 'Reflections', FilterID = 3,
-- intensité dans BlendParams (« n/d ») ; EnableDistractionRemoval = true. changeReflectionRemovalAmount
-- ne change pas le filtre rangé (constaté). getReflectionRemovalPanelState exige l'outil Supprimer
-- ouvert (goToRemove).
local function filtreReflets(photo)
    for _, filtre in ipairs((photo.reglages.FilterList or {}).Filters or {}) do
        if filtre.Name == 'Reflections' then
            return filtre
        end
    end
    return nil
end

local QUALITES_REFLETS = { preview = true, standard = true, best = true }

local controleur = {
    hasFilterWithName = function(nom)
        local photo = dansDeveloppement()
        if nom == 'dereflect' then
            return filtreReflets(photo) ~= nil
        end
        for _, filtre in ipairs((photo.reglages.FilterList or {}).Filters or {}) do
            if filtre.Name == nom then
                return true
            end
        end
        return false
    end,
    resetFilterWithName = function(nom)
        local photo = dansDeveloppement()
        assert(not S.ecritureEnCours, "LrDevelopController dans withWriteAccessDo")
        if nom == 'dereflect' and filtreReflets(photo) then
            photo.calculReflets = { duree = 1, actif = false }
        end
    end,
    toggleReflectionRemoval = function(intensite, qualite, rappel, argument)
        local photo = dansDeveloppement()
        assert(not S.ecritureEnCours, "LrDevelopController dans withWriteAccessDo")
        if filtreReflets(photo) then
            photo.calculReflets = { duree = S.dureeAmelioration, actif = false, rappel = rappel, argument = argument }
            S.appelsReflets[#S.appelsReflets + 1] = { fonction = 'toggleReflectionRemoval', actif = false }
            return
        end
        if intensite ~= nil and (type(intensite) ~= 'number' or intensite < -100 or intensite > 100) then
            error("invalid reflection removal amount", 0)
        end
        if qualite ~= nil and not QUALITES_REFLETS[qualite] then
            error(string.format("Invalid Reflection removal quality: %s. Allowed values: 'preview', 'standard', 'best'", tostring(qualite)), 0)
        end
        if not pleineQualite() or photo.refletsNonPris then
            return
        end
        photo.calculReflets = { duree = S.dureeAmelioration, actif = true, intensite = intensite or 100, qualite = qualite or 'standard',
            rappel = rappel, argument = argument }
        S.appelsReflets[#S.appelsReflets + 1] = { fonction = 'toggleReflectionRemoval', actif = true, intensite = intensite, qualite = qualite }
    end,
    changeReflectionRemovalAmount = function(intensite)
        dansDeveloppement()
        S.appelsReflets[#S.appelsReflets + 1] = { fonction = 'changeReflectionRemovalAmount', actif = true, intensite = intensite }
    end,
    goToRemove = function()
        dansDeveloppement()
        S.outil = 'dust'
    end,
    getSelectedTool = function() return S.outil end,
    selectTool = function(outil) S.outil = outil end,
    getReflectionRemovalPanelState = function()
        local photo = dansDeveloppement()
        if S.outil ~= 'dust' then
            error("this operation can be executed only when Remove-tool is opened in Develop module", 0)
        end
        local filtre = filtreReflets(photo)
        return { checkboxState = filtre ~= nil, amount = 100, quality = 'standard',
            enabled = pleineQualite(), isSupported = not photo.refletsNonPris }
    end,
    getEnhancePanelState = function()
        local photo = affichee()
        if not photo then
            return nil
        end
        local e = etatAmelioration(photo)
        return {
            denoiseState = e.denoise, rawDetailsState = e.rawDetails, superResState = e.superRes,
            denoiseAmount = e.denoiseAmount,
            denoiseEnabled = permis(photo, 'denoise'), rawDetailsEnabled = permis(photo, 'rawDetails'),
            superResEnabled = permis(photo, 'superRes'),
            denoiseInfoText = raisonRefus(photo, 'denoise'), rawDetailsInfoText = raisonRefus(photo, 'rawDetails'),
            superResInfoText = raisonRefus(photo, 'superRes'),
            enhanceNeedsUpdate = false,
        }
    end,
    setEnhance = function(nom, actif, intensite)
        if nom ~= 'denoise' and nom ~= 'rawDetails' and nom ~= 'superRes' then
            error("invalid paramName name passed to LrDevelopController.toggleEnhance", 0)
        end
        if intensite ~= nil and (type(intensite) ~= 'number' or intensite < 1 or intensite > 100) then
            error("invalid denoise amount", 0)
        end
        local photo = dansDeveloppement()
        if not permis(photo, nom) then
            error("toggleEnhance: " .. nom .. " - " .. raisonRefus(photo, nom), 0)
        end
        if photo.erreurAmelioration then
            error(photo.erreurAmelioration, 0)
        end
        for _, traitee in ipairs(photosTraitees(photo)) do
            lancerCalcul(traitee)
            local e = etatAmelioration(traitee)
            e[nom] = actif == true
            if nom == 'denoise' or nom == 'superRes' then
                e.rawDetails = (e.denoise or e.superRes) and true or false
            end
            if nom == 'denoise' and actif and intensite then
                e.denoiseAmount = intensite
            end
        end
        S.appelsAmelioration[#S.appelsAmelioration + 1] = { fonction = 'setEnhance', photo = photo.localIdentifier, nom = nom,
            actif = actif == true, intensite = intensite }
    end,
    -- Version de processus (module Développement). Constaté dans Lightroom Classic 15.6 :
    -- setProcessVersion('Version 6') ne fait rien (il compare le nom aux noms à traduire, ZSTR, de
    -- kProcessVersionHistoryNames, jamais égaux) ; refus par assert d'un autre nom.
    setProcessVersion = function(nom)
        dansDeveloppement()
        assert(not S.ecritureEnCours, "LrDevelopController dans withWriteAccessDo")
        local valeurs = { ['Version 1'] = true, ['Version 2'] = true, ['Version 3'] = true, ['Version 4'] = true,
            ['Version 5'] = true, ['Version 6'] = true }
        assert(valeurs[nom], "setProcessVersion: process version must be one of: Version 1, Version 2, Version 3, Version 4, Version 5, Version 6")
    end,
    changeDenoiseAmount = function(intensite)
        local photo = dansDeveloppement()
        local e = etatAmelioration(photo)
        if e.denoise then
            lancerCalcul(photo)
            e.denoiseAmount = intensite
            S.appelsAmelioration[#S.appelsAmelioration + 1] = { fonction = 'changeDenoiseAmount', photo = photo.localIdentifier,
                nom = 'denoise', actif = true, intensite = intensite }
        end
    end,
}

local modules = {
    LrApplicationView = {
        getCurrentModuleName = function() return S.module end,
        showView = function(nom) S.vue = nom end,
        switchToModule = function(nom)
            S.module = nom
            S.modulesOuverts[#S.modulesOuverts + 1] = nom
            S.chargementJusqua = S.horloge + S.delaiChargement
            S.qualiteJusqua = S.chargementJusqua + S.delaiQualite
        end,
    },
    LrDevelopController = controleur,
    -- Constaté en 2.5 : removeFromCatalog retire la photo sélectionnée, sans fenêtre.
    LrSelection = {
        removeFromCatalog = function()
            local photo = S.active
            assert(photo and #S.selection == 1, "removeFromCatalog : une seule photo sélectionnée")
            photo.retireeDuCatalogue = true
            S.photos[photo.localIdentifier] = nil
            S.retireesDuCatalogue[#S.retireesDuCatalogue + 1] = photo
        end,
    },
    -- Barre de progression (SDK 1.3) : la simulation garde chaque barre et ce qu'elle a montré.
    LrProgressScope = setmetatable({}, { __call = function(_, args)
        local barre = { titre = args.title, fait = 0, total = 0, legendes = {}, annulee = false, finie = false }
        function barre:setCancelable(oui) self.annulable = oui end
        function barre:setPortionComplete(fait, total) self.fait, self.total = fait, total end
        function barre:setCaption(texte) self.legendes[#self.legendes + 1] = texte end
        function barre:isCanceled() return self.annulee end
        function barre:done() self.finie = true end
        S.barres[#S.barres + 1] = barre
        return barre
    end }),
    LrApplication = {
        activeCatalog = function() return catalogue end,
        backupAtNextShutdown = function(id)
            assert(id == _PLUGIN.id, "backupAtNextShutdown : l'identifiant du module")
            S.sauvegardeDemandee = true
        end,
        viewFilterPresets = function()
            local presets = {}
            for nom, id in pairs(S.presetsFiltre) do presets[nom] = id end
            return presets, S.filtrePreset
        end,
        versionString = function() return '15.0' end,
        developPresetFolders = function()
            local dossiers = {}
            for _, d in ipairs(S.presets) do
                dossiers[#dossiers + 1] = {
                    getName = function() return d.nom end,
                    getDevelopPresets = function()
                        local liste = {}
                        for _, p in ipairs(d.presets) do
                            liste[#liste + 1] = {
                                nom = p.nom, reglages = p.reglages,
                                getName = function() return p.nom end,
                                getUuid = function() return p.uuid end,
                                getSetting = function() return p.reglages end,
                            }
                        end
                        return liste
                    end,
                }
            end
            return dossiers
        end,
        filenamePresets = function() return S.modelesNoms end,
        metadataPresets = function()
            local noms = {}
            for id, preset in pairs(S.presetsMeta) do noms[preset.nom] = id end
            return noms
        end,
        addDevelopPresetForPlugin = function(plugin, nom, reglages)
            local preset = { nom = nom, reglages = reglages, duModule = true, getUuid = function() return 'uuid-' .. nom end }
            S.presetsCrees[#S.presetsCrees + 1] = preset
            return preset
        end,
    },
    LrDate = {
        -- Horloge de la simulation : elle avance pendant les attentes du module (LrTasks.sleep).
        currentTime = function() return S.horloge end,
        -- L'heure locale de la simulation est l'UTC décalé de S.fuseau secondes (−4 h : l'heure
        -- avancée de l'Est) ; timeToW3CDate, elle, donne l'UTC (constaté en 2.4).
        timeToUserFormat = function(t, format)
            if format == '%Y-%m-%d' then return os.date('!%Y-%m-%d', 978307200 + t + S.fuseau) end
            return format == '%Y-%m-%d %H:%M:%S' and '2026-07-21 12:00:00' or '12:00:00'
        end,
        -- Secondes depuis le 1er janvier 2001, comme dans Lightroom.
        timeToW3CDate = function(t) return os.date('!%Y-%m-%dT%H:%M:%S', 978307200 + t) end,
    },
    LrTasks = {
        pcall = pcall,
        -- Une tâche qui attend l'utilisateur (fenêtre de choix) : S.differerTaches la garde jusqu'à
        -- l'heure S.reprendreTachesA de la simulation.
        startAsyncTask = function(fonction)
            if S.differerTaches then
                S.tachesDifferees[#S.tachesDifferees + 1] = fonction
            else
                fonction()
            end
        end,
        sleep = function(secondes)
            S.attentes = S.attentes + 1
            if #S.tachesDifferees > 0 and S.horloge >= S.reprendreTachesA then
                local taches = S.tachesDifferees
                S.tachesDifferees = {}
                for _, tache in ipairs(taches) do tache() end
            end
            local differees = S.vignettesEnAttente
            S.vignettesEnAttente = {}
            for _, rendre in ipairs(differees) do
                rendre()
            end
            S.horloge = S.horloge + (tonumber(secondes) or 0)
            S.avancerAmeliorations()
            for _, photo in pairs(S.photos) do
                resoudreProfil(photo)
            end
            if S.pendantAttente then
                S.pendantAttente()
            end
            if S.calculDiffere and not S.jamaisCalcule then
                for _, photo in pairs(S.photos) do
                    photo:calculerMasquesIA()
                end
            end
        end,
    },
    LrPrefs = {
        prefsForPlugin = function() return S.prefs end,
    },
    LrPathUtils = {
        child = function(dossier, nom) return dossier .. '/' .. nom end,
        getStandardFilePath = function(nom) return nom == 'home' and S.home or '/tmp' end,
        leafName = function(chemin) return chemin:match('[^/]+$') end,
        parent = function(chemin) return chemin:match('^(.*)/[^/]*$') end,
    },
    LrFileUtils = {
        -- Un dossier est rangé dans S.fichiers avec la valeur 'dossier'.
        createAllDirectories = function(chemin)
            if chemin and S.fichiers[chemin] == nil then S.fichiers[chemin] = 'dossier' end
            return true
        end,
        exists = function(chemin)
            local valeur = S.fichiers[chemin]
            if valeur == nil then return false end
            return valeur == 'dossier' and 'directory' or 'file'
        end,
        delete = function(chemin)
            S.fichiers[chemin] = nil
            return true
        end,
        fileAttributes = function(chemin)
            return S.fichiers[chemin] and { fileSize = #S.fichiers[chemin] } or nil
        end,
        move = function(de, vers)
            S.fichiers[vers], S.fichiers[de] = S.fichiers[de], nil
            return true
        end,
        files = function(dossier)
            local liste = {}
            for chemin in pairs(S.fichiers) do
                if chemin:sub(1, #dossier + 1) == dossier .. '/' and not chemin:sub(#dossier + 2):find('/', 1, true) then
                    liste[#liste + 1] = chemin
                end
            end
            table.sort(liste)
            local i = 0
            return function()
                i = i + 1
                return liste[i]
            end
        end,
    },
    -- Les rendus ne déforment pas l'image : ils comptent seulement les coins vides du cadre
    -- (coinsVides, voir S.deformation). Constaté dans Lightroom Classic 15.6 : les positions des
    -- taches, des yeux rouges et des dégradés sont rangées avant la correction d'objectif ; les
    -- tests du recalage vérifient donc les réglages de chaque rendu (reglagesRendus : sans
    -- recadrage, puis sans corrections géométriques) et la grille appliquée aux positions.
    -- Exporter la photo active dont un calcul IA manque ouvre la fenêtre « Mises à jour IA
    -- recommandées », qui attend un clic : la réponse du module ne vient jamais (constaté dans
    -- Lightroom Classic 15.6). L'utilisateur (S.clicUtilisateur) y clique Exporter, case « Mettre à
    -- jour » cochée : Lightroom calcule, puis rend.
    LrExportSession = function(args)
        S.dernierExport = args
        S.rendus[#S.rendus + 1] = args
        -- Réglages de la photo au moment du rendu (pour les tests des propositions).
        args.reglagesRendus = copier(args.photosToExport[1].reglages)
        args.coinsVides = S.coinsVides(args.photosToExport[1])
        local reglages = args.exportSettings
        -- Livraison (LR_collisionHandling = 'rename') : un fichier par photo, nommé d'après les
        -- jetons, « -2 », « -3 »… si le nom existe déjà (comme Lightroom) ; jamais d'écrasement.
        -- Relevé dans Lightroom Classic 15.6 (AgExportSettings) : pas de HDR Rec. 2020 en JPEG ;
        -- 32 bits seulement en HDR ; JPEG 8 bits, AVIF 10 bits.
        assert(not (reglages.LR_format == 'JPEG' and reglages.LR_export_colorSpace == 'Rec2020_hdr'), "HDR Rec. 2020 en JPEG : Lightroom ne l'offre pas")
        assert(not (reglages.LR_export_bitDepth == 32 and not reglages.LR_enableHDRDisplay), "32 bits sans sortie HDR")
        assert(reglages.LR_format ~= 'AVIF' or reglages.LR_export_bitDepth == nil or reglages.LR_export_bitDepth == 10, "AVIF : 10 bits")
        local function cheminLivre(photo, index)
            local dossier = reglages.LR_export_destinationPathPrefix
            -- « Même dossier que la photo originale » : celui de l'original.
            if reglages.LR_export_destinationType == 'sourceFolder' then
                dossier = tostring(photo.brut.path or '/Photos/x'):match('^(.*)/[^/]*$')
            end
            if reglages.LR_export_useSubfolder then
                dossier = dossier .. '/' .. tostring(reglages.LR_export_destinationPathSuffix)
            end
            local base = tostring(photo.meta.fileName or 'photo'):gsub('%.[^.]*$', '')
            if reglages.LR_renamingTokensOn then
                local sequence = (tonumber(reglages.LR_initialSequenceNumber) or 1) + index - 1
                base = tostring(reglages.LR_tokens):gsub('{{([%w_]+)}}', function(jeton)
                    if jeton == 'image_name' then return base end
                    if jeton == 'custom_token' then return reglages.LR_tokenCustomString or '' end
                    if jeton == 'date_YYYYMMDD' then return '20260721' end
                    local chiffres = jeton:match('^naming_sequenceNumber_(%d)Digit')
                    if chiffres then return string.format('%0' .. chiffres .. 'd', sequence) end
                    return '{{' .. jeton .. '}}'
                end)
            end
            local extensions = { JPEG = 'jpg', TIFF = 'tif', PNG = 'png', DNG = 'dng', JXL = 'jxl', AVIF = 'avif', PSD = 'psd' }
            local extension = extensions[reglages.LR_format] or tostring(photo.meta.fileName or 'x.raf'):match('%.([^.]*)$'):lower()
            local chemin = dossier .. '/' .. base .. '.' .. extension
            local n = 1
            while S.fichiers[chemin] do
                n = n + 1
                chemin = dossier .. '/' .. base .. '-' .. n .. '.' .. extension
            end
            S.fichiers[chemin] = 'fichier livré de ' .. tostring(photo.meta.fileName)
            S.exportsLivres[#S.exportsLivres + 1] = chemin
            -- Réimporté : Lightroom l'ajoute au catalogue après le rendu ; empilé avec l'original
            -- seulement dans son dossier (ExportLocationSection : canStackWithOriginal).
            if reglages.LR_reimportExportedPhoto then
                local nouvelle = S.Photo(nouvelId(), {}, { fileName = chemin:match('[^/]+$') }, { path = chemin })
                if reglages.LR_reimport_stackWithOriginal and reglages.LR_export_destinationType == 'sourceFolder' then
                    nouvelle.empileeAvec = photo.brut.masterPhoto or photo
                end
            end
            return chemin
        end
        return {
            renditions = function()
                local i = 0
                return function()
                    i = i + 1
                    local photo = args.photosToExport[i]
                    if not photo then return nil end
                    local index = i
                    return i, {
                        photo = photo,
                        waitForRender = function()
                            if photo.uprightACalculer then
                                photo.uprightACalculer = false
                                local mode = tonumber(photo.reglages.PerspectiveUpright) or 0
                                -- Le mode avec repères (5) ne se calcule pas au rendu (constaté le
                                -- 18 octobre 2026) : seulement par le bouton « Mettre à jour ».
                                if mode ~= 0 and mode ~= 5 then
                                    photo.reglages.UprightTransform_0 = 'matrices calculées pour le mode ' .. mode
                                end
                            end
                            -- Un profil adaptatif à mettre à jour ouvre la fenêtre même pour une photo
                            -- qui n'est pas affichée (constaté le 16 octobre 2026).
                            if (photo == S.active and calculsIAEnAttente(photo.reglages)) or photo.lookAMettreAJour then
                                S.fenetresIA[#S.fenetresIA + 1] = { photo = photo.meta.fileName }
                                if not S.clicUtilisateur then
                                    error("la fenêtre « Mises à jour IA recommandées » attend un clic : la réponse ne vient jamais", 0)
                                end
                                photo:calculerMasquesIA()
                                photo:mettreAJourLook()
                            end
                            if S.renduImpossible then
                                return false, S.renduImpossible
                            end
                            if photo.exportImpossible then
                                return false, photo.exportImpossible
                            end
                            -- Original absent : Lightroom rend l'aperçu dynamique (constaté en 2.5),
                            -- 2560 px de grand côté au plus ; sans lui, rien.
                            if photo.absente then
                                local info = photo.brut.smartPreviewInfo
                                if not (type(info) == 'table' and info.smartPreviewPath) then
                                    return false, "fichier original introuvable"
                                end
                                args.depuisApercu = true
                            end
                            args.filigrane = reglages.LR_useWatermark and reglages.LR_watermarking_id or nil
                            -- Constaté en 2.4 : tout rendu par LrExportSession, un aperçu de Claude
                            -- compris, fait passer isExported à vrai.
                            photo.brut.isExported = true
                            if reglages.LR_collisionHandling == 'rename' then
                                return true, cheminLivre(photo, index)
                            end
                            return true, reglages.LR_export_destinationPathPrefix .. '/photo.jpg'
                        end,
                    }
                end
            end,
        }
    end,
    LrFunctionContext = {
        postAsyncTaskWithContext = function() end,
    },
    LrSocket = {
        bind = function() error("pas de réseau dans les tests", 0) end,
    },
    LrDialogs = {
        -- La fenêtre de choix rend une liste de chemins, nil si l'utilisateur annule (référence du
        -- SDK ; constaté en 2.5 : le chemin choisi, dossier de départ respecté).
        runOpenPanel = function(args)
            S.panneaux[#S.panneaux + 1] = args
            return S.dossierChoisi
        end,
        message = function() end,
        showBezel = function(texte) S.bezels[#S.bezels + 1] = texte end,
    },
    LrShell = {
        revealInShell = function(chemin) S.revele = chemin end,
    },
    -- Interface : seulement chargées, jamais affichées dans les tests.
    LrBinding = {},
    LrView = {},
}

function import(nom)
    return modules[nom] or error("module non simulé : " .. nom, 2)
end

_PLUGIN = { id = 'com.danymenard.developpeur' }

function S.reinitialiser()
    S.photos = {}
    S.active = nil
    S.selection = {}
    S.prefs = {}
    S.ecritures = {}
    S.envois = {}
    S.ecritureEnCours = false
    S.enAttente = {}
    S.apresEcriture = {}
    S.dernierExport = nil
    S.rendus = {}
    S.presets = {}
    S.presetsCrees = {}
    S.attentes = 0
    S.calculDiffere = false
    S.jamaisCalcule = false
    S.module = 'library'
    S.modulesOuverts = {}
    S.invisibles = {}
    -- Photos d'un dossier qu'on vient d'afficher : sélectionnables seulement à partir de cette heure.
    S.visiblesDes = {}
    S.delaiSource = 0.5
    S.appelsAmelioration = {}
    S.appelsReflets = {}
    S.bezels = {}
    S.revele = nil
    S.outil = 'loupe'
    S.vignettesDemandees = {}
    S.vignettesDifferees = false
    S.vignettesEnAttente = {}
    S.dureeAmelioration = 3
    S.ameliorationBloquee = false
    S.horloge = 0
    S.delaiChargement = 1
    S.chargementJusqua = 0
    S.delaiQualite = 0
    S.qualiteJusqua = 0
    S.affichee = nil
    S.synchroAuto = false
    S.pendantAttente = nil
    S.fichiers = {}
    S.clicUtilisateur = true
    S.fenetresIA = {}
    S.renduImpossible = nil
    S.motsClesRacine = {}
    S.motsClesCrees = {}
    S.collections = {}
    S.ensembles = {}
    S.recherches = {}
    S.sources = nil
    S.sourcesChangees = {}
    S.vue = nil
    S.miseAJourIA = true
    S.modelesIAAbsents = false
    S.misesAJourIA = {}
    S.pendantMiseAJourIA = nil
    S.dureeCalculIA = 0
    S.lookFige = false
    S.recalculsLook = 0
    S.prochainId = 90000
    S.numeroEcriture = 0
    -- 21 juillet 2026 à midi (UTC), en secondes depuis 2001 : la « date du jour » des recherches.
    S.maintenant = 806328000
    S.jeuLibelles = { Rouge = 'red', Jaune = 'yellow', Vert = 'green', Bleu = 'blue', Violet = 'purple' }
    S.prochainInstantane = 0
    S.instantanesPoses = {}
    S.instantanesIgnores = {}
    S.instantaneBloque = false
    S.presetsMeta = {}
    S.presetsMetaAppliques = {}
    S.modelesNoms = {}
    S.services = {}
    S.nomsModeles = {}
    S.dossierChoisi = nil
    S.panneaux = {}
    S.panneauDiffere = false
    S.retireesDuCatalogue = {}
    S.differerTaches = false
    S.tachesDifferees = {}
    S.reprendreTachesA = 0
    S.fenetreExport = nil
    S.exportsLivres = {}
    S.ecriturePriveeEnCours = false
    S.ecrituresPrivees = 0
    S.quantitesPresets = {}
    S.rotations = {}
    S.masquesVidesRetires = 0
    S.barres = {}
    S.sauvegardeDemandee = false
    S.filtre = { filtersActive = false }
    S.filtrePreset = nil
    S.filtresPoses = {}
    S.presetsFiltre = {}
    S.lecturesGroupees = 0
    S.jeuLibellesIllisible = false
    S.fuseau = 0
end

S.reinitialiser()

return S
