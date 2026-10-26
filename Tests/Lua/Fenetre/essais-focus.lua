-- essais-focus.lua : l'onglet Focus de la fenêtre Claude (demandé par Dany le 22 octobre 2026), hors
-- de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : son segment, le premier (correctif
-- 1.3.6), sa carte (Image, Prise de vue, Mise au point : Fil.texteFocus, en 12 avec les titres
-- en gras 12, page par page), les valeurs de Lightroom lues clé par clé (Lightroom.infosFocus), le
-- connecteur imité comme pour --marquer-af (un faux `mcp-developpeur --focus`, qui recopie la
-- vignette et répond la ligne JSON de DSCF2402 telle que le vrai la rend), la lecture dans une tâche
-- par perl et son alarme de 5 s, le résultat gardé pour la photo (relu seulement si sa géométrie
-- change), une autre marque (sans connecteur, « non lue (seulement les fichiers Fujifilm pour
-- l'instant) »), un connecteur muet ou absent, la fenêtre ouverte sur Focus et ramenée à Focus quand
-- une autre photo choisie montre sa conversation (correctif 1.3.6, décision de Dany du 25 octobre
-- 2026), une image de Claude qui arrive montrée dans l'onglet Aperçu, l'aperçu des autres onglets
-- inchangé, et l'apparence sombre. Ni Claude, ni quota ; les fichiers vont dans un
-- dossier personnel temporaire.
-- Lancé par scripts/tester-module.sh dans Tests/Lua/Fenetre, avec PLUGIN_DIR.

local S = require 'Simulation'

local reussis, echecs = 0, 0
local function essai(nom, fn)
    local ok, erreur = xpcall(fn, debug.traceback)
    if ok then
        reussis = reussis + 1
        print('ok     ' .. nom)
    else
        echecs = echecs + 1
        print('ÉCHEC  ' .. nom .. '\n' .. tostring(erreur))
    end
end

local function egal(attendu, obtenu, quoi)
    if attendu ~= obtenu then
        error(string.format('%s : attendu %q, obtenu %q', quoi or 'valeur', tostring(attendu), tostring(obtenu)), 2)
    end
end

local function vrai(condition, quoi)
    if not condition then
        error(quoi or 'condition fausse', 2)
    end
end

local function contient(texte, morceau, quoi)
    if type(texte) ~= 'string' or not texte:find(morceau, 1, true) then
        error(string.format('%s : %q introuvable dans %q', quoi or 'texte', morceau, tostring(texte)), 2)
    end
end

local function absent(texte, morceau, quoi)
    if type(texte) == 'string' and texte:find(morceau, 1, true) then
        error(string.format('%s : %q présent dans %q', quoi or 'texte', morceau, tostring(texte)), 2)
    end
end

-- Lance les tâches parties depuis `depuis` (et celles qu'elles lancent), dans l'ordre.
local function lancerTaches(depuis)
    local i = (depuis or 0) + 1
    while i <= #S.taches do
        vrai(i - (depuis or 0) <= 100, 'des tâches sans fin')
        local t = S.taches[i]
        S.taches[i] = function() end
        t()
        i = i + 1
    end
end

local Chemins = require 'Chemins'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Images = require 'Images'
local Journal = require 'Journal'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Lightroom = require 'Lightroom'
local Notation = require 'Notation'
local Vignettes = require 'Vignettes'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'
local Conversation = require 'Conversation'
local Stockage = require 'Stockage'
-- La boucle de la fenêtre (toutes les 0,25 s tant qu'elle est ouverte) ne tourne pas ici : les
-- essais lancent eux-mêmes les tâches (lancerTaches), et Fenetre.majPhoto quand la photo change.
Fenetre.boucle = function() end
-- Les voyants (Claude Code, écran), lus à l'ouverture dans une tâche, ne sont pas de cet essai : le
-- faux Claude Code écrirait ses arguments dans le dossier courant.
Fenetre.verifier = function() end
local prefs = Chemins.prefs()
prefs.nouvelleParPhoto = false
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'

local D = Dispositions.dimensions()

-- Les erreurs que la fenêtre note dans son journal font échouer l'essai.
local journal = {}
local noterVraiment = Journal.noter
Journal.noter = function(...)
    journal[#journal + 1] = table.concat({ ... }, ' ')
    return noterVraiment(...)
end
local function sansErreur()
    vrai(#journal == 0, 'journal : ' .. table.concat(journal, ' | '))
end

-- Catalogue simulé ------------------------------------------------------------------------------

-- Une vraie image JPEG, que Lightroom rendrait comme vignette (paysage 3:2).
local JPEG
do
    local chemin = S.home .. '/source.jpg'
    S.executer('/usr/bin/sips -s format jpeg -z 200 300 ' .. S.q(S.plugin .. '/' .. Dispositions.imageVide('claire')) .. ' --out ' .. S.q(chemin)
        .. ' >/dev/null 2>&1')
    local f = assert(io.open(chemin, 'rb'), 'JPEG source')
    JPEG = f:read('*a')
    f:close()
end

-- La même, debout (200 × 300) : la vignette d'une photo verticale, que Lightroom rend tournée.
local JPEG_DEBOUT
do
    local chemin = S.home .. '/source-debout.jpg'
    S.executer('/usr/bin/sips -s format jpeg -z 300 200 ' .. S.q(S.plugin .. '/' .. Dispositions.imageVide('claire')) .. ' --out '
        .. S.q(chemin) .. ' >/dev/null 2>&1')
    local f = assert(io.open(chemin, 'rb'), 'JPEG debout')
    JPEG_DEBOUT = f:read('*a')
    f:close()
end

-- Ce que Lightroom Classic 15.6 donnerait de DSCF2402 (la copie d'essai 53709912, d'après la
-- capture de Focus-Points de Dany), en textes formatés ; et un HEIC d'iPhone.
local PRISE_2402 = os.time { year = 2026, month = 1, day = 13, hour = 9, min = 13, sec = 4 }
local PHOTOS = {}
local function photo(id, valeurs, description)
    local ph = { localIdentifier = id, valeurs = valeurs, description = description, uuid = 'uuid-' .. id }
    function ph:getFormattedMetadata(cle)
        if self.refusees and self.refusees[cle] then
            error('clé refusée : ' .. cle)
        end
        return self.valeurs[cle]
    end
    function ph:getRawMetadata(cle)
        if cle == 'dateTimeOriginal' then
            return self.prise
        elseif cle == 'editCount' then
            return self.editCount or 0
        elseif cle == 'uuid' then
            return self.uuid
        end
        return nil
    end
    function ph:getPropertyForPlugin()
        return nil
    end
    function ph:requestJpegThumbnail(largeur, _, rappel)
        self.demandesVignette = (self.demandesVignette or 0) + 1
        self.tailles = self.tailles or {}
        self.tailles[#self.tailles + 1] = largeur
        -- Après une retouche, Lightroom répond « error loading thumb » à 512 px et plus tant que son
        -- aperçu n'est pas refait, mais rend encore la vignette de 256 (constaté).
        if self.grandeRefusee and largeur >= 512 then
            rappel(nil, 'error loading thumb')
            return {}
        end
        if (self.echecsVignette or 0) > 0 then
            self.echecsVignette = self.echecsVignette - 1
            rappel(nil, 'error loading thumb')
            return {}
        end
        rappel(self.vignette and self:vignette(largeur) or JPEG)
        return {}
    end
    PHOTOS[id] = ph
    return ph
end
photo(2402, {
    fileName = 'DSCF2402.RAF', copyName = 'Essai', dimensions = '6240 x 4160', croppedDimensions = '6240 x 4160',
    cameraMake = 'FUJIFILM', cameraModel = 'X-H2S', lens = 'XF16-55mmF2.8 R LM WR', focalLength = '44,1 mm',
    shutterSpeed = '1/125 s', aperture = 'f / 2,8', isoSpeedRating = 'ISO 160', exposureBias = '0 EV',
    exposureProgram = 'Manuel', meteringMode = 'Multizone',
}, { marque = 'FUJIFILM', chemin_original = '/Volumes/Photos/Eloise/DSCF2402.RAF',
    geometrie = { largeur = 6240, hauteur = 4160, orientation = 'AB' } }).prise = PRISE_2402
photo(2403, { fileName = 'DSCF2403.RAF', cameraMake = 'FUJIFILM' },
    { marque = 'FUJIFILM', chemin_original = '/Volumes/Photos/Eloise/DSCF2403.RAF', geometrie = { largeur = 6240, hauteur = 4160, orientation = 'AB' } })
photo(3001, { fileName = 'IMG_3001.HEIC', cameraMake = 'Apple', cameraModel = 'iPhone 15 Pro', isoSpeedRating = 'ISO 80' },
    { marque = 'Apple', chemin_original = '/Volumes/Photos/iPhone/IMG_3001.HEIC', geometrie = { largeur = 4032, hauteur = 3024, orientation = 'AB' } })
-- XH2S0407.RAF (Copie 1), 4160 × 6240, l'appareil tenu en hauteur (retour de Dany du 25 octobre
-- 2026) : Lightroom rend sa vignette debout, sauf celle de 256 juste après une retouche, couchée
-- (le fichier avant son quart de tour : 320 × 213, l'image de Focus et d'Agrandir couchées) ;
-- `couchee` : toutes couchées.
photo(407, { fileName = 'XH2S0407.RAF', copyName = 'Copie 1', cameraMake = 'FUJIFILM', dimensions = '4160 x 6240',
    croppedDimensions = '4160 x 6240' },
    { marque = 'FUJIFILM', chemin_original = '/Volumes/Photos/XH2S0407.RAF', geometrie = { largeur = 4160, hauteur = 6240, orientation = 'DA' } })
PHOTOS[407].vignette = function(self, largeur)
    return (self.couchee or largeur < 512) and JPEG or JPEG_DEBOUT
end
S.catalogue.getPhotoByLocalId = function(_, id) return PHOTOS[tonumber(id)] end

-- La description de Vignettes (marque, original, géométrie), celle de la photo simulée : une copie
-- virtuelle y a déjà le chemin de son original (brut 'path').
Vignettes.decrireVignette = function(ph)
    local d = ph.description
    return { marque = d.marque, chemin_original = d.chemin_original, geometrie = d.geometrie }
end

local function activer(id)
    S.photoActive, S.selection = PHOTOS[id], { PHOTOS[id] }
end

-- Le faux connecteur ------------------------------------------------------------------------------

-- La ligne JSON que le vrai `mcp-developpeur --focus` a rendue pour DSCF2402.RAF le 22 octobre 2026
-- (hors de Lightroom, sur une vignette tirée de l'original), avec `dessinee`.
local REPONSE_2402 = '{"cadres":{"point_af":1,"sujets":4},"dessinee":true,"image":[],"lue":true,"mise_au_point":[["Points de mise au point","lus"],'
    .. '["Mode de mise au point","AF-S (ponctuel)"],["Priorité AF-S","Déclenchement"],["Mode AF","Point unique"],["Taille du point AF","6"],'
    .. '["Avertissement de mise au point","Bonne"],["Visages détectés","1"],["Éléments du sujet détectés","tête, visage, œil gauche, œil droit"]],'
    .. '"point_af":{"dans_le_cadre":true,"x":0.377,"y":0.287},"prise_de_vue":[["Stabilisation","Capteur, active (mode 1, en continu)"],'
    .. '["Mode d\'entraînement","Vue par vue"]]}'

-- Le faux `mcp-developpeur` : à --focus, il note l'original et la géométrie reçus, recopie la
-- vignette (les cadres « dessinés ») et répond `reponse-focus.json` ; sans ce fichier, code 1 (rien
-- de lu). À --marquer-af (aperçu des autres onglets), il recopie la vignette.
local FAUX = S.home .. '/faux-connecteur.sh'
local REPONSE = S.home .. '/reponse-focus.json'
local RECUS = S.home .. '/focus-recus.txt'
do
    local f = assert(io.open(FAUX, 'w'))
    f:write('#!/bin/sh\n'
        .. 'if [ "$1" = "--marquer-af" ]; then cp "$4" "$5"; exit 0; fi\n'
        .. '[ "$1" = "--focus" ] || exit 2\n'
        .. 'printf "%s\\t%s\\n" "$2" "$3" >> ' .. S.q(RECUS) .. '\n'
        .. '[ -f ' .. S.q(REPONSE) .. ' ] || exit 1\n'
        .. '[ -f "$4" ] && cp "$4" "$5"\n'
        .. 'cat ' .. S.q(REPONSE) .. '\n')
    f:close()
    S.executer('/bin/chmod +x ' .. S.q(FAUX))
end
prefs.cheminConnecteur = FAUX

local function repondre(texte)
    if texte then
        Fichiers.ecrire(REPONSE, texte .. '\n')
    else
        Fichiers.supprimer(REPONSE)
    end
end

-- Les --focus reçus : { original, geometrie }.
local function recus()
    local liste = {}
    for ligne in (Fichiers.lire(RECUS) or ''):gmatch('[^\n]+') do
        local original, geometrie = ligne:match('^(.-)\t(.*)$')
        liste[#liste + 1] = { original = original, geometrie = geometrie }
    end
    return liste
end

local function commandesFocus()
    local n = 0
    for _, c in ipairs(S.dernieresCommandes or {}) do
        if c:find(' --focus ', 1, true) then
            n = n + 1
        end
    end
    return n
end

-- Fenêtre ----------------------------------------------------------------------------------------

-- Ouvre la fenêtre Claude et appelle fn(p, contenu) pendant qu'elle est ouverte ; une erreur de fn
-- remonte une fois la fenêtre fermée.
local function ouvrirFenetre(fn)
    local erreur
    S.taches = {}
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function() fn(Fenetre.p, args.contents) end, debug.traceback)
        erreur = not ok and e or nil
    end
    Fenetre.afficher()
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    if erreur then
        error(erreur, 0)
    end
end

local vues = S.vues

-- Le calque d'un segment (son infobulle est le titre de l'onglet).
local function segment(contenu, titre)
    for _, v in ipairs(vues(contenu)) do
        if v.genre == 'static_text' and v.args.tooltip == titre and type(v.args.mouse_down) == 'function' then
            return v
        end
    end
    error('segment introuvable : ' .. titre)
end

-- La vue simple liée à `cle` (titre ou valeur).
local function liee(contenu, genre, cle)
    for _, v in ipairs(vues(contenu)) do
        local t = v.args.title or v.args.value
        if v.genre == genre and type(t) == 'table' and t.key == cle then
            return v
        end
    end
    return nil
end

-- Les essais ---------------------------------------------------------------------------------------

essai("Segment Focus : le premier (Focus, Note, Aperçu, Proposition), une variante à lui, sa carte en 12 (titres en gras 12), ▲ ▼ ; l'onglet de l'ouverture", function()
    local ordre = {}
    for _, o in ipairs(D.onglets) do
        ordre[#ordre + 1] = o.valeur
    end
    egal('focus notation apercu proposition', table.concat(ordre, ' '), 'quatre onglets dans cet ordre (correctif 1.3.6), plus de Suivi')
    egal('focus', D.ongletFocus)
    egal('Focus', D.onglets[1].titre)
    egal('seg-focus', D.onglets[1].image)
    egal('focus', D.ongletParDefaut, "Focus à l'ouverture (décision de Dany du 25 octobre 2026)")
    egal(nil, D.ongletSuivi, "plus d'onglet Suivi : la fenêtre Suivi")
    vrai(D.segments <= D.panneau, string.format('les quatre segments (%d) dans le panneau (%d)', D.segments, D.panneau))
    -- La fenêtre ne bascule d'elle-même vers Focus que par Fenetre.revenirAFocus (une autre photo
    -- choisie qui montre sa conversation), jamais en posant l'onglet à la main.
    local source = assert(Fichiers.lire(S.plugin .. '/Fenetre.lua'))
    local _, bascules = source:gsub('choisirOnglet%(T%.ongletFocus%)', '')
    egal(1, bascules, 'une seule bascule vers Focus (Fenetre.revenirAFocus)')
    for _, nom in ipairs({ 'Fenetre.lua', 'Vues.lua', 'Dispositions.lua', 'Moteur.lua', 'Conversation.lua' }) do
        local texte = assert(Fichiers.lire(S.plugin .. '/' .. nom), nom)
        absent(texte, 'choisirOnglet(Fenetre.T.ongletFocus', nom)
        absent(texte, "choisirOnglet('focus'", nom)
        absent(texte, 'p.onglet = T.ongletFocus', nom)
        absent(texte, "p.onglet = 'focus'", nom)
    end
    activer(2402)
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local carte = liee(contenu, 'static_text', 'focusTexte')
        vrai(carte, 'la carte Focus')
        egal(Fenetre.POLICES.texte12, carte.args.font)
        egal(Fenetre.POLICES.gras12, carte.args.emphasis_font)
        egal(D.carte, carte.args.width)
        egal(D.focusLignes, carte.args.height_in_lines)
        egal(Fenetre.POLICES.gras12, liee(contenu, 'static_text', 'focusTitre').args.font)
        local fleches = 0
        for _, v in ipairs(vues(contenu)) do
            if S.BOUTONS[v.genre] and type(v.args.enabled) == 'table' and (v.args.enabled.key == 'focusMonte' or v.args.enabled.key == 'focusDescend') then
                fleches = fleches + 1
            end
        end
        egal(2, fleches, '▲ ▼ de la carte Focus')
        egal('focus', p.onglet, "Focus à l'ouverture")
        egal(true, S.montreeDansFenetre(carte), 'sa carte montrée')
        S.cliquer(segment(contenu, 'Note'))
        egal(false, S.montreeDansFenetre(carte), 'carte cachée hors de son onglet')
    end)
    sansErreur()
end)

essai("Fujifilm : à l'ouverture, Focus montré lit dans une tâche (perl, alarme de 5 s) ; la carte Image, Prise de vue, Mise au point ; l'aperçu avec ses cadres", function()
    activer(2402)
    repondre(REPONSE_2402)
    Fichiers.supprimer(RECUS)
    Moteur.nouvelle()
    local avant = commandesFocus()
    ouvrirFenetre(function(p, contenu)
        -- Focus à l'ouverture (correctif 1.3.6) : la lecture part dans une tâche, la carte dit
        -- qu'elle lit, l'aperçu attend.
        egal('focus', p.onglet)
        egal(avant, commandesFocus(), 'rien de lu hors de la tâche')
        egal('Focus · DSCF2402.RAF (Essai)', p.focusTitre, 'le nom et la copie, avant la lecture')
        contient((p.focusTexte:gsub('\n', ' ')), "<EM>Mise au point :</EM> " .. Fil.FOCUS_EN_COURS)
        egal(Fenetre.imageVide(), p.imageApercu, 'image vide pendant la lecture')
        egal(false, p.peutPrecedente)
        egal(false, p.peutSuivante)
        lancerTaches()
        egal(avant + 1, commandesFocus(), 'une seule lecture')
        local commande
        for _, c in ipairs(S.dernieresCommandes) do
            if c:find(' --focus ', 1, true) then
                commande = c
            end
        end
        contient(commande, "/usr/bin/perl -e 'alarm 5; exec @ARGV' " .. S.q(FAUX) .. ' --focus ', 'cinq secondes au plus')
        local r = recus()
        egal('/Volumes/Photos/Eloise/DSCF2402.RAF', r[1].original, "l'original (celui de la copie virtuelle)")
        local geometrie = Json.decode(r[1].geometrie)
        egal(6240, geometrie.largeur, 'la géométrie de Vignettes.decrireVignette')
        egal('AB', geometrie.orientation)
        -- La carte : Image et Prise de vue de Lightroom, puis le boîtier, comme Focus-Points.
        egal('Focus · DSCF2402.RAF (Essai)', p.focusTitre)
        local texte = p.focusTexte
        for _, morceau in ipairs({
            '<EM>Image</EM>', 'Fichier : DSCF2402.RAF (Essai)', 'Prise de vue : 13 janv. 2026 à 09:13:04',
            "Taille d'origine : 6240 x 4160", 'Taille actuelle : 6240 x 4160',
            '<EM>Prise de vue</EM>', 'Marque : FUJIFILM', 'Modèle : X-H2S', 'Objectif : XF16-55mmF2.8 R LM WR', 'Focale : 44,1 mm',
            'Exposition : 1/125 s à f / 2,8', 'ISO : ISO 160', "Correction d'exposition : 0 EV", "Programme d'exposition : Manuel",
            'Mesure : Multizone', 'Stabilisation : Capteur, active (mode 1, en continu)', "Mode d'entraînement : Vue par vue",
            '<EM>Mise au point</EM>', 'Points de mise au point : lus', 'Mode de mise au point : AF-S (ponctuel)',
            'Priorité AF-S : Déclenchement', 'Mode AF : Point unique', 'Taille du point AF : 6',
            'Avertissement de mise au point : Bonne', 'Visages détectés : 1',
            'Éléments du sujet détectés : tête, visage, œil gauche, œil droit',
        }) do
            contient(texte, morceau, 'carte Focus')
        end
        vrai(texte:find('<EM>Image</EM>', 1, true) < texte:find('<EM>Prise de vue</EM>', 1, true)
            and texte:find('<EM>Prise de vue</EM>', 1, true) < texte:find('<EM>Mise au point</EM>', 1, true), 'les trois blocs dans l\'ordre')
        vrai(texte:find('Mesure : Multizone', 1, true) < texte:find('Stabilisation', 1, true), 'le boîtier au bout de Prise de vue')
        egal(false, p.focusMonte)
        egal(false, p.focusDescend, 'une seule page')
        -- L'aperçu : la vignette marquée par le connecteur, au cadre de l'aperçu, en 2x.
        local r0 = Fenetre.focus
        vrai(r0.fichier:find('%-focus%.jpg$'), 'la vignette marquée : ' .. tostring(r0.fichier))
        egal(r0.chemin, p.imageApercu)
        egal(true, p.aImage, 'Agrandir actif')
        local l, h = Images.dimensions(p.imageApercu)
        egal(D.pixelsApercu, l, "au cadre de l'aperçu")
        egal(D.pixelsApercuHauteur, h)
        contient(p.legendeApercu, '<EM>DSCF2402.RAF (Essai)</EM>')
        -- Agrandir : la photo redemandée en grand (Fenetre.agrandirActive), marquée de même : un
        -- --focus de plus, sur la grande vignette ; elle remplit 2 000 × 1 250.
        local dialogues = #S.dialogues
        Fenetre.agrandir()
        lancerTaches()
        egal(dialogues + 1, #S.dialogues, 'Agrandir')
        contient(S.dialogues[#S.dialogues].title, 'DSCF2402.RAF')
        egal(avant + 2, commandesFocus(), 'la grande vignette marquée')
        local grande = S.dialogues[#S.dialogues].contents.args
        egal('1875x1250', grande.width .. 'x' .. grande.height, 'dans 2 000 × 1 250')
        contient(grande.value, '/Grande-')
        -- Un autre onglet : l'aperçu de la photo active (avec le carré de --marquer-af), pas la
        -- vignette de Focus.
        S.cliquer(segment(contenu, 'Note'))
        lancerTaches()
        vrai(p.imageApercu ~= r0.chemin, "l'aperçu de Note n'est pas celui de Focus")
        egal(Fenetre.apercuActif.chemin, p.imageApercu, "l'aperçu de la photo active")
        -- Le résultat est gardé : un vrai clic de nouveau, même géométrie, rien n'est relu.
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        egal(avant + 2, commandesFocus(), 'même photo, même géométrie : rien de relu')
        egal(r0, Fenetre.focus, 'le résultat gardé')
        egal(r0.chemin, p.imageApercu)
        -- La photo recadrée dans Lightroom : un vrai clic relit, avec la nouvelle géométrie.
        S.cliquer(segment(contenu, 'Note'))
        PHOTOS[2402].description.geometrie = { largeur = 6240, hauteur = 4160, orientation = 'AB',
            cadre = { CropLeft = 0.1, CropTop = 0, CropRight = 0.9, CropBottom = 1, CropAngle = 0 } }
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        egal(avant + 3, commandesFocus(), 'géométrie changée : relue')
        egal(0.1, Json.decode(recus()[3].geometrie).cadre.CropLeft)
        vrai(Fenetre.focus ~= r0, 'un nouveau résultat')
        vrai(not Fichiers.existe(r0.dossier), "la vignette d'avant s'efface")
        PHOTOS[2402].description.geometrie = { largeur = 6240, hauteur = 4160, orientation = 'AB' }
    end)
    sansErreur()
end)

essai("L'onglet suit la photo active ; caché, il ne lit rien ; case Autre photo décochée, pas de bascule ; cochée, une autre photo qui montre sa conversation ramène Focus", function()
    activer(2402)
    repondre(REPONSE_2402)
    Fichiers.supprimer(RECUS)
    Moteur.nouvelle()
    local choisis = {}
    local choisir = Fenetre.choisirOnglet
    Fenetre.choisirOnglet = function(valeur)
        choisis[#choisis + 1] = tostring(valeur)
        return choisir(valeur)
    end
    local surFocus, crochets = Fenetre.surOnglet.focus, 0
    local ok, erreur = pcall(ouvrirFenetre, function(p, contenu)
        lancerTaches()
        egal('focus', p.onglet)
        local n = commandesFocus()
        -- Une autre photo Fujifilm devient active, l'onglet montré : sa lecture, dans une tâche.
        activer(2403)
        Fenetre.majPhoto()
        egal('Focus · DSCF2403.RAF', p.focusTitre)
        contient(p.focusTexte, Fil.FOCUS_EN_COURS)
        lancerTaches()
        egal(n + 1, commandesFocus(), 'la nouvelle photo lue')
        egal('/Volumes/Photos/Eloise/DSCF2403.RAF', recus()[#recus()].original)
        egal('focus', p.onglet)
        -- Sur Note, une autre photo, la case Autre photo décochée (la conversation montrée reste) :
        -- rien n'est lu, aucune bascule.
        S.cliquer(segment(contenu, 'Note'))
        activer(2402)
        Fenetre.majPhoto()
        lancerTaches()
        egal(n + 1, commandesFocus(), 'onglet caché : rien de lu')
        egal('notation', p.onglet, 'la conversation reste : pas de bascule vers Focus')
        -- Une lecture qui finit pendant que Note est montré ne bascule pas non plus.
        Fenetre.lireFocus(Fenetre.info.active)
        lancerTaches()
        egal(n + 2, commandesFocus())
        egal('notation', p.onglet, 'la lecture finie ne bascule pas')
        -- De retour sur Focus : le résultat de cette photo, sans relire.
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        egal(n + 2, commandesFocus(), 'gardé')
        egal('Focus · DSCF2402.RAF (Essai)', p.focusTitre)
        -- Sans photo active : l'aide.
        S.photoActive, S.selection = nil, {}
        Fenetre.majPhoto()
        egal('Focus', p.focusTitre)
        egal(Fenetre.FOCUS_AUCUNE_PHOTO, (p.focusTexte:gsub('\n', ' ')))
        egal('Aucune photo active', p.legendeApercu)
        egal(false, p.aImage)
        for _, v in ipairs(choisis) do
            vrai(v ~= 'focus', 'une bascule vers Focus sans conversation changée : ' .. table.concat(choisis, ', '))
        end
        -- La case cochée : Dany choisit une autre photo, sa conversation se montre, et Focus revient
        -- d'elle-même (une bascule : sans le crochet d'un vrai clic), qui lit la photo.
        prefs.nouvelleParPhoto = true
        Fenetre.surOnglet.focus = function(...) crochets = crochets + 1; return surFocus(...) end
        activer(2403)
        Fenetre.majPhoto()
        S.cliquer(segment(contenu, 'Note'))
        crochets = 0
        local lues = commandesFocus()
        activer(2402)
        Fenetre.majPhoto()
        egal('focus', p.onglet, 'une autre photo : Focus revient')
        egal('focus', choisis[#choisis], 'par une bascule de la fenêtre')
        egal(0, crochets, 'sans le crochet d\'un vrai clic')
        vrai(Conversation.dePhoto(Moteur.courante, 2402), 'la conversation de la photo montrée')
        lancerTaches()
        vrai(Fenetre.focusActif() and Fenetre.focusActif().id == 2402, 'la photo active, dans Focus')
        vrai(commandesFocus() <= lues + 1, 'une lecture au plus (le résultat gardé de la photo)')
        -- La même photo (sa conversation déjà montrée) : rien ne bascule.
        S.cliquer(segment(contenu, 'Note'))
        Fenetre.majPhoto()
        egal('notation', p.onglet, 'la même conversation : pas de bascule')
    end)
    Fenetre.choisirOnglet = choisir
    Fenetre.surOnglet.focus = surFocus
    prefs.nouvelleParPhoto = false
    assert(ok, erreur)
    sansErreur()
end)

essai('Autre marque : la photo sans cadre, Image et Prise de vue, « Mise au point : non lue (seulement les fichiers Fujifilm pour l\'instant) » ; l\'original n\'est pas ouvert', function()
    activer(3001)
    repondre(REPONSE_2402)
    Fichiers.supprimer(RECUS)
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        lancerTaches()
        local n = commandesFocus()
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        egal(n, commandesFocus(), 'pas de connecteur pour une autre marque')
        egal('Focus · IMG_3001.HEIC', p.focusTitre)
        contient(p.focusTexte, '<EM>Image</EM>\nFichier : IMG_3001.HEIC')
        contient(p.focusTexte, '<EM>Prise de vue</EM>\nMarque : Apple\nModèle : iPhone 15 Pro\nISO : ISO 80')
        contient((p.focusTexte:gsub('\n', ' ')), "<EM>Mise au point :</EM> non lue (seulement les fichiers Fujifilm pour l'instant)")
        absent(p.focusTexte, 'Stabilisation')
        absent(p.focusTexte, 'Objectif', 'une valeur absente n\'a pas de ligne')
        -- L'aperçu : la vignette de Lightroom telle quelle.
        vrai(not Fenetre.focus.fichier:find('focus', 1, true), Fenetre.focus.fichier)
        egal(true, p.aImage)
        egal(Fenetre.focus.chemin, p.imageApercu)
    end)
    sansErreur()
end)

essai('Connecteur muet (rien de lu, code 1) ou absent : la carte le dit, l\'aperçu montre la vignette sans cadre', function()
    activer(2402)
    repondre(nil)
    Moteur.nouvelle()
    local n = commandesFocus()
    ouvrirFenetre(function(p)
        -- Focus à l'ouverture : la lecture de la photo active.
        lancerTaches()
        egal(n + 1, commandesFocus(), 'le connecteur lancé')
        contient((p.focusTexte:gsub('\n', ' ')), '<EM>Mise au point :</EM> ' .. Fil.FOCUS_NON_LUE)
        contient(p.focusTexte, 'Marque : FUJIFILM', 'Lightroom quand même')
        absent(p.focusTexte, 'Stabilisation', 'rien du boîtier')
        vrai(not Fenetre.focus.fichier:find('-focus', 1, true), 'la vignette sans cadre')
        egal(true, p.aImage)
    end)
    -- Connecteur absent (pas installé) : réinstaller.
    local connecteur = prefs.cheminConnecteur
    prefs.cheminConnecteur = S.home .. '/introuvable/mcp-developpeur'
    local ok, erreur = pcall(ouvrirFenetre, function(p)
        lancerTaches()
        contient((p.focusTexte:gsub('\n', ' ')), '<EM>Mise au point :</EM> ' .. Fil.FOCUS_SANS_CONNECTEUR)
    end)
    prefs.cheminConnecteur = connecteur
    assert(ok, erreur)
    sansErreur()
end)

essai("Focus montré, une image de Claude arrive : l'onglet Aperçu la montre, Agrandir aussi ; de retour sur Focus, sa vignette ; un clic sur la ligne de l'image, l'onglet Aperçu", function()
    activer(2402)
    repondre(REPONSE_2402)
    Moteur.nouvelle()
    local c = Moteur.courante
    ouvrirFenetre(function(p, contenu)
        lancerTaches()
        egal('focus', p.onglet)
        local r0 = Fenetre.focus
        egal(r0.chemin, p.imageApercu)
        -- Claude regarde la photo : une image dans le fil (une vraie petite image JPEG).
        Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'v1', nom = 'mcp__developpeur__view_photo',
            entree = { photo_id = 2402 } } } })
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'v1', textes = { '{}' },
            images = { { donnees = 'x', type = 'image/jpeg' } }, erreur = false } } }, nil, function()
            Fichiers.creerDossier(Stockage.dossier(c.id))
            Fichiers.ecrire(Stockage.image(c.id, 'v1.jpg'), JPEG)
            return 'v1.jpg'
        end)
        Fenetre.rafraichir()
        lancerTaches()
        -- L'image de Claude montre l'onglet Aperçu (correctif 1.3.6), elle dans l'aperçu.
        egal('apercu', p.onglet, "l'image de Claude dans l'onglet Aperçu")
        egal('1 sur 1 · view_photo', p.legendeApercu, "l'image arrivée")
        vrai(p.imageApercu ~= r0.chemin, "plus la vignette Focus")
        -- Agrandir : l'image, pas la vignette Focus.
        local dialogues = #S.dialogues
        Fenetre.agrandir()
        lancerTaches()
        egal(dialogues + 1, #S.dialogues, 'Agrandir')
        local grande = S.dialogues[#S.dialogues].contents.args.value
        contient(grande, Stockage.dossier(c.id), "l'image en grand")
        absent(grande, r0.dossier, 'pas la vignette Focus')
        -- Focus de nouveau : l'aperçu et Agrandir reviennent à la vignette Focus.
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        egal(r0.chemin, p.imageApercu)
        Fenetre.agrandir()
        lancerTaches()
        contient(S.dialogues[#S.dialogues].contents.args.value, '/PhotoActive/Grande-', 'la photo active en grand, comme Focus')
        -- Un clic sur la ligne de l'image, Focus montré : l'onglet Aperçu, l'image.
        local ligne
        for i = 1, Fenetre.T.lignes do
            local l = Fenetre.lignes[Fenetre.premiere + i - 1]
            if l and l.image == 'v1.jpg' then
                ligne = ligne or i
            end
        end
        vrai(ligne, "la ligne de l'image dans le fil")
        Fenetre.cliquerLigne(ligne)
        lancerTaches()
        egal('apercu', p.onglet, "un clic sur l'image : l'onglet Aperçu")
        egal('1 sur 1 · view_photo', p.legendeApercu, "l'image cliquée")
        p.onglet = 'notation'
    end)
    sansErreur()
end)

essai("Deux lectures croisées : celle d'une photo quittée finit après celle de la photo active ; le résultat de la photo active reste, rien n'est relu", function()
    activer(2402)
    repondre(REPONSE_2402)
    Fichiers.supprimer(RECUS)
    Moteur.nouvelle()
    -- La tâche de chaque lecture, par photo, pour les finir dans l'ordre voulu.
    local lire, taches = Fenetre.lireFocus, {}
    Fenetre.lireFocus = function(active, verifier)
        local avant = #S.taches
        lire(active, verifier)
        if #S.taches > avant then
            taches[active.id] = #S.taches
        end
    end
    local n = commandesFocus()
    local ok, erreur = pcall(ouvrirFenetre, function(p)
        -- La lecture de A (DSCF2402), partie à l'ouverture (Focus montré), est lente ; Dany passe à
        -- B (DSCF2403), lu à son tour.
        local tacheA = taches[2402]
        vrai(tacheA, 'la lecture de A')
        activer(2403)
        Fenetre.majPhoto()
        local tacheB = taches[2403]
        vrai(tacheB and tacheB > tacheA, 'la lecture de B')
        -- B finit d'abord : son résultat se montre.
        local t = S.taches[tacheB]
        S.taches[tacheB] = function() end
        t()
        local rB = Fenetre.focus
        egal(2403, rB.id)
        egal(rB.chemin, p.imageApercu)
        egal('Focus · DSCF2403.RAF', p.focusTitre)
        -- Puis A : son résultat ne sert plus ; B reste montré, son dossier aussi.
        lancerTaches()
        egal(rB, Fenetre.focus, 'le résultat de la photo active reste')
        vrai(Fichiers.existe(rB.dossier), 'le dossier de la photo active reste')
        egal(rB.chemin, p.imageApercu, "l'aperçu de B")
        egal('Focus · DSCF2403.RAF', p.focusTitre)
        egal(n + 2, commandesFocus(), 'deux lectures, aucune de plus')
        local parOriginal = {}
        for _, x in ipairs(recus()) do
            parOriginal[x.original] = (parOriginal[x.original] or 0) + 1
        end
        egal(1, parOriginal['/Volumes/Photos/Eloise/DSCF2403.RAF'], 'B lu une seule fois')
        egal(1, parOriginal['/Volumes/Photos/Eloise/DSCF2402.RAF'], 'A lu une fois')
        Fenetre.rafraichirApercu()
        Fenetre.rafraichirApercu()
        lancerTaches()
        egal(n + 2, commandesFocus(), 'les rafraîchissements ne relisent pas')
    end)
    Fenetre.lireFocus = lire
    assert(ok, erreur)
    sansErreur()
end)

essai("Une lecture en erreur : la carte dit « non lue », les rafraîchissements ne la relancent pas ; un vrai clic sur Focus, si", function()
    activer(2402)
    repondre(REPONSE_2402)
    Moteur.nouvelle()
    local preparer, appels = Fenetre.preparerFocus, 0
    Fenetre.preparerFocus = function(...)
        appels = appels + 1
        return preparer(...)
    end
    local infos = Lightroom.infosFocus
    Lightroom.infosFocus = function() error('lecture cassée') end
    local ok, erreur = pcall(ouvrirFenetre, function(p, contenu)
        lancerTaches()
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        egal(1, appels, 'une lecture')
        egal(1, #journal, "l'erreur au journal")
        contient(journal[1], 'lecture cassée')
        journal = {}
        egal('Focus · DSCF2402.RAF (Essai)', p.focusTitre, 'le nom et la copie de la légende')
        contient((p.focusTexte:gsub('\n', ' ')), '<EM>Mise au point :</EM> ' .. Fil.FOCUS_NON_LUE, 'la carte dit « non lue »')
        absent(p.focusTexte, Fil.FOCUS_EN_COURS)
        egal(Fenetre.imageVide(), p.imageApercu)
        egal(false, p.aImage)
        -- Les rafraîchissements (fréquents pendant que Claude travaille) ne relancent rien.
        for _ = 1, 3 do
            Fenetre.rafraichir()
            Fenetre.rafraichirApercu()
            lancerTaches()
        end
        egal(1, appels, 'aucune lecture de plus')
        -- Un vrai clic sur le segment relit ; la lecture réussit.
        Lightroom.infosFocus = infos
        S.cliquer(segment(contenu, 'Note'))
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        egal(2, appels, 'le clic relit')
        contient(p.focusTexte, 'Modèle : X-H2S')
        egal(Fenetre.focus.chemin, p.imageApercu)
    end)
    Lightroom.infosFocus = infos
    Fenetre.preparerFocus = preparer
    assert(ok, erreur)
    sansErreur()
end)

essai("Rien de lu : la carte dit la raison du connecteur (introuvable, trop long à ouvrir, format pas lu comme un HEIF) ; sans raison, la phrase qui couvre les trois", function()
    egal("non lue (original illisible, introuvable ou trop long à ouvrir)", Fil.FOCUS_NON_LUE)
    contient(Fil.FOCUS_ILLISIBLE, 'HEIF')
    for _, cas in ipairs({ { 'introuvable', Fil.FOCUS_INTROUVABLE }, { 'delai', Fil.FOCUS_DELAI }, { 'illisible', Fil.FOCUS_ILLISIBLE },
        { 'autre', Fil.FOCUS_NON_LUE } }) do
        activer(2402)
        repondre('{"lue": false, "raison": "' .. cas[1] .. '"}')
        Moteur.nouvelle()
        ouvrirFenetre(function(p, contenu)
            lancerTaches()
            S.cliquer(segment(contenu, 'Focus'))
            lancerTaches()
            contient((p.focusTexte:gsub('\n', ' ')), '<EM>Mise au point :</EM> ' .. cas[2], cas[1])
            contient(p.focusTexte, 'Marque : FUJIFILM', 'Lightroom quand même')
            absent(p.focusTexte, 'Stabilisation', 'rien du boîtier')
            egal(true, p.aImage, 'la vignette sans cadre')
        end)
    end
    -- Images.lireFocus rend la raison en troisième, seulement une raison connue.
    local source = S.home .. '/raison.jpg'
    Fichiers.ecrire(source, JPEG)
    repondre('{"lue": false, "raison": "illisible"}')
    local json, marquee, raison = Images.lireFocus(FAUX, '/Volumes/Photos/DSCF0001.HIF', {}, source)
    egal(nil, json)
    egal(nil, marquee)
    egal('illisible', raison)
    repondre('{"lue": false, "raison": "autre"}')
    egal(nil, select(3, Images.lireFocus(FAUX, '/Volumes/Photos/DSCF0001.HIF', {}, source)), 'raison inconnue')
    sansErreur()
end)

essai('Images.lireFocus : la ligne JSON du connecteur, la vignette marquée à côté de la source ; rien de lu, nil', function()
    Fichiers.creerDossier(S.home .. '/lire-focus')
    local source = S.home .. '/lire-focus/2402.jpg'
    Fichiers.ecrire(source, JPEG)
    repondre(REPONSE_2402)
    local json, marquee = Images.lireFocus(FAUX, '/Volumes/Photos/DSCF2402.RAF', { largeur = 6240, hauteur = 4160 }, source)
    egal(true, json.lue)
    egal(S.home .. '/lire-focus/2402-focus.jpg', marquee)
    egal('Points de mise au point', json.mise_au_point[1][1])
    vrai(not Fichiers.existe(S.home .. '/lire-focus/2402-focus.json'), 'la réponse lue, puis effacée')
    -- Sans vignette : les valeurs seules.
    local seules, sans = Images.lireFocus(FAUX, '/Volumes/Photos/DSCF2402.RAF', { largeur = 6240, hauteur = 4160 }, nil)
    egal(true, seules.lue)
    egal(nil, sans)
    repondre(nil)
    egal(nil, (Images.lireFocus(FAUX, '/Volumes/Photos/DSCF2402.RAF', {}, source)), 'code 1 : nil')
    egal(nil, (Images.lireFocus(S.home .. '/absent', '/Volumes/Photos/DSCF2402.RAF', {}, source)), 'connecteur absent : nil')
    egal(nil, (Images.lireFocus(FAUX, nil, {}, source)), 'sans original : nil')
end)

essai('Lightroom.infosFocus : clé par clé (une clé refusée ne gêne pas les autres), date et heure à l\'heure locale ; Fil.texteFocus sans balise reçue', function()
    PHOTOS[2402].refusees = { lens = true }
    local infos = Lightroom.infosFocus(2402)
    PHOTOS[2402].refusees = nil
    egal(nil, infos.objectif, 'la clé refusée')
    egal('X-H2S', infos.modele, 'les autres lues')
    egal('13 janv. 2026 à 09:13:04', infos.date)
    egal('6240 x 4160', infos.actuelle)
    for cle, valeur in pairs(infos) do
        egal('string', type(valeur), cle)
    end
    -- Les textes reçus (Lightroom, connecteur) perdent leurs balises ; une paire sans titre est sautée.
    local texte = Fil.texteFocus({ nom = '<EM>x</EM>.RAF', marque = 'FUJIFILM' },
        { mise_au_point = { { 'Mode AF', '<EM>Zone</EM>' }, { '', 'rien' }, 'pas une paire' }, prise_de_vue = {}, image = { { 'Recadrage du boîtier', 'Viseur sport' } } }, 'lue')
    contient(texte, 'Fichier : x.RAF')
    contient(texte, 'Mode AF : Zone')
    contient(texte, 'Recadrage du boîtier : Viseur sport')
    absent(texte, 'rien')
    egal(3, select(2, texte:gsub('<EM>', '')), 'les titres des trois blocs seulement')
    -- Sans rien de Lightroom ni du boîtier : la mise au point seule.
    egal('<EM>Mise au point :</EM> ' .. Fil.FOCUS_NON_LUE, Fil.texteFocus(nil, nil, 'non_lue'))
    egal('Focus', Fil.titreFocus(nil))
end)

essai('Apparence sombre : le segment et la carte Focus du jeu sombre', function()
    activer(2402)
    prefs.apparence = 'sombre'
    Moteur.nouvelle()
    local ok, erreur = pcall(ouvrirFenetre, function(_, contenu)
        local trouvees = {}
        for _, v in ipairs(vues(contenu)) do
            if v.genre == 'picture' and type(v.args.value) == 'string' then
                for _, nom in ipairs({ 'seg-focus', 'seg-focus-actif', 'carte-focus' }) do
                    if v.args.value:sub(-#('/images/sombre/' .. nom .. '.png')) == '/images/sombre/' .. nom .. '.png' then
                        trouvees[nom] = true
                        vrai(Fichiers.existe(v.args.value), v.args.value)
                    end
                end
            end
        end
        for _, nom in ipairs({ 'seg-focus', 'seg-focus-actif', 'carte-focus' }) do
            vrai(trouvees[nom], nom .. ' du jeu sombre')
        end
    end)
    prefs.apparence = nil
    assert(ok, erreur)
    sansErreur()
end)

essai("Une retouche relit l'onglet : à un vrai clic, et à la fin d'un tour de Claude si l'onglet est montré ; caché, rien", function()
    activer(2402)
    repondre(REPONSE_2402)
    Fichiers.supprimer(RECUS)
    Moteur.nouvelle()
    PHOTOS[2402].editCount = 1
    ouvrirFenetre(function(p, contenu)
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        local n = commandesFocus()
        local r0 = Fenetre.focus
        vrai(r0 and r0.chemin, 'lu une première fois')
        -- Retouchée (une étape de Claude ou une main dans Lightroom) : un vrai clic relit.
        S.cliquer(segment(contenu, 'Note'))
        PHOTOS[2402].editCount = 2
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        egal(n + 1, commandesFocus(), 'retouchée : relue au clic')
        vrai(Fenetre.focus ~= r0, 'un nouveau résultat')
        -- Fin d'un tour de Claude, onglet montré, photo retouchée : relue d'elle-même.
        PHOTOS[2402].editCount = 3
        Moteur.finTravail = (Moteur.finTravail or 0) + 10
        Fenetre.suivreFocus()
        lancerTaches()
        egal(n + 2, commandesFocus(), 'fin du tour : relue')
        -- Fin d'un autre tour sans retouche : rien de relu.
        Moteur.finTravail = Moteur.finTravail + 10
        Fenetre.suivreFocus()
        lancerTaches()
        egal(n + 2, commandesFocus(), 'sans retouche : rien de relu')
        -- Onglet caché : la fin d'un tour ne lit rien.
        S.cliquer(segment(contenu, 'Note'))
        PHOTOS[2402].editCount = 4
        Moteur.finTravail = Moteur.finTravail + 10
        Fenetre.suivreFocus()
        lancerTaches()
        egal(n + 2, commandesFocus(), 'onglet caché : rien')
    end)
    PHOTOS[2402].editCount = nil
    sansErreur()
end)

essai("Après une retouche, Lightroom refait son aperçu : la vignette se redemande ; toujours sans, le prochain clic relit", function()
    activer(2402)
    repondre(REPONSE_2402)
    Fichiers.supprimer(RECUS)
    Moteur.nouvelle()
    PHOTOS[2402].editCount = 10
    ouvrirFenetre(function(p, contenu)
        -- Deux refus, puis la vignette : l'onglet a son image.
        PHOTOS[2402].demandesVignette, PHOTOS[2402].echecsVignette = 0, 2
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        egal(3, PHOTOS[2402].demandesVignette, 'deux refus, puis la vignette')
        local r = Fenetre.focus
        vrai(r and r.chemin, "l'image, après les refus")
        egal(r.chemin, p.imageApercu)
        -- La grande toujours refusée, la petite rendue : l'image de secours, sans signature.
        S.cliquer(segment(contenu, 'Note'))
        PHOTOS[2402].editCount = 11
        PHOTOS[2402].demandesVignette, PHOTOS[2402].grandeRefusee = 0, true
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        vrai(Fenetre.focus.chemin, 'la petite vignette, à jour')
        egal(nil, Fenetre.focus.signature, 'sans signature : la grande se relira')
        PHOTOS[2402].grandeRefusee = nil
        -- Toutes refusées : pas d'image ni de signature ; le prochain clic relit.
        S.cliquer(segment(contenu, 'Note'))
        PHOTOS[2402].editCount = 12
        PHOTOS[2402].demandesVignette, PHOTOS[2402].echecsVignette = 0, 100
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        -- L'onglet la redemande ESSAIS_VIGNETTE_FOCUS fois, puis une fois en petit ; l'aperçu commun
        -- des autres onglets peut l'avoir demandée une fois de plus.
        local demandes = PHOTOS[2402].demandesVignette
        vrai(demandes >= Fenetre.ESSAIS_VIGNETTE_FOCUS + 1 and demandes <= Fenetre.ESSAIS_VIGNETTE_FOCUS + 2,
            'redemandée, au plus ESSAIS_VIGNETTE_FOCUS fois, puis en petit : ' .. demandes)
        egal(nil, Fenetre.focus.chemin)
        egal(nil, Fenetre.focus.signature, 'sans signature')
        local n = commandesFocus()
        PHOTOS[2402].echecsVignette = 0
        S.cliquer(segment(contenu, 'Note'))
        S.cliquer(segment(contenu, 'Focus'))
        lancerTaches()
        vrai(Fenetre.focus.chemin, 'relue au clic, avec son image')
        vrai(commandesFocus() >= n, 'le connecteur relancé au besoin')
    end)
    PHOTOS[2402].editCount, PHOTOS[2402].echecsVignette, PHOTOS[2402].demandesVignette = nil, nil, nil
    PHOTOS[2402].grandeRefusee = nil
    -- Seul l'aperçu commun des autres onglets a pu noter les refus de Lightroom (il réessaie à son
    -- rafraîchissement suivant) ; aucune autre erreur.
    for i = #journal, 1, -1 do
        if journal[i]:find("Aperçu de la photo active : Lightroom n'a pas rendu de vignette", 1, true) then
            table.remove(journal, i)
        end
    end
    sansErreur()
end)

-- Une photo verticale, Agrandir (retour de Dany du 25 octobre 2026) ---------------------------------

-- Les commandes passées par LrTasks.execute qui contiennent `morceau`.
local function commandes(morceau)
    local n = 0
    for _, c in ipairs(S.dernieresCommandes or {}) do
        if c:find(morceau, 1, true) then
            n = n + 1
        end
    end
    return n
end

local function taille(chemin)
    local l, h = Images.dimensions(chemin)
    return tostring(l) .. 'x' .. tostring(h)
end

-- Le rendu de la liaison (Rendu.rendre, une exportation de Lightroom, qui ne se charge pas dans
-- cette simulation), imité : un JPEG debout de 400 × 600 dans un dossier à lui, comme le vrai ;
-- `rendus` note la photo et la taille demandées.
local rendus = {}
package.loaded.Rendu = {
    rendre = function(ph, cote)
        rendus[#rendus + 1] = { id = ph.localIdentifier, taille = cote }
        local dossier = S.home .. '/rendu-' .. #rendus
        S.executer('mkdir -p ' .. S.q(dossier) .. ' && /usr/bin/sips -s format jpeg -z 600 400 ' .. S.q(S.home .. '/source.jpg')
            .. ' --out ' .. S.q(dossier .. '/XH2S0407.jpg') .. ' >/dev/null 2>&1')
        return dossier .. '/XH2S0407.jpg', true
    end,
}

essai("Images.rotationManquante (pur) : le quart de tour qui manque à une vignette couchée, d'après la géométrie (orientation, cadre) ; rien pour une vignette à l'endroit, carrée, un demi-tour", function()
    local debout = { largeur = 4160, hauteur = 6240, orientation = 'DA' }
    egal(270, Images.rotationManquante(320, 213, debout), 'DA, couchée : 270° dans le sens des aiguilles (sips -r)')
    egal(90, Images.rotationManquante(320, 213, { largeur = 4160, hauteur = 6240, orientation = 'BC' }), 'BC, couchée')
    egal(nil, Images.rotationManquante(213, 320, debout), 'déjà debout')
    egal(nil, Images.rotationManquante(1146, 1720, debout), 'la vignette de 1 024, debout (relevée le 25 octobre 2026)')
    egal(nil, Images.rotationManquante(320, 213, { largeur = 6240, hauteur = 4160, orientation = 'AB' }), 'en paysage')
    egal(nil, Images.rotationManquante(213, 320, { largeur = 6240, hauteur = 4160, orientation = 'CD' }), 'un demi-tour ne se voit pas aux proportions')
    egal(nil, Images.rotationManquante(200, 200, debout), 'carrée')
    egal(nil, Images.rotationManquante(320, 213, nil), 'sans géométrie')
    egal(nil, Images.rotationManquante(320, 213, { orientation = 'DA' }), 'dimensions inconnues')
    egal(nil, Images.rotationManquante(nil, 213, debout), 'vignette illisible')
    -- Le cadre compte : recadrée à la moitié de sa hauteur dans le fichier, elle s'affiche en 1:3 debout.
    local recadree = { largeur = 4160, hauteur = 6240, orientation = 'DA',
        cadre = { CropLeft = 0, CropTop = 0, CropRight = 1, CropBottom = 0.5, CropAngle = 0 } }
    egal(nil, Images.rotationManquante(100, 300, recadree), 'recadrée, à l\'endroit')
    egal(270, Images.rotationManquante(300, 100, recadree), 'recadrée, couchée')
    -- Une vignette d'avant le cadre (l'aperçu pas encore refait après la retouche) : les proportions
    -- de la photo entière ; couchée, elle se tourne ; debout, elle reste.
    egal(270, Images.rotationManquante(320, 213, recadree), "d'avant le cadre, couchée : tournée")
    egal(nil, Images.rotationManquante(213, 320, recadree), "d'avant le cadre, debout : rien")
    egal(nil, Images.rotationManquante(400, 100, recadree), "ni l'une ni l'autre : rien")
    -- Recadrée en 4:5 (le cas du retour de Dany) : la vignette de secours de 320 × 213, couchée.
    local quatreCinq = { largeur = 4160, hauteur = 6240, orientation = 'DA',
        cadre = { CropLeft = 1 / 12, CropTop = 0, CropRight = 11 / 12, CropBottom = 1, CropAngle = 0 } }
    egal(270, Images.rotationManquante(320, 213, quatreCinq), '4:5, la vignette de secours couchée : tournée')
    egal(nil, Images.rotationManquante(213, 320, quatreCinq), "4:5, d'avant le cadre, debout : rien")
    egal(nil, Images.rotationManquante(400, 500, quatreCinq), '4:5, à l\'endroit')
    egal(270, Images.rotationManquante(500, 400, quatreCinq), '4:5, couchée au cadre')
    egal(90, Images.rotationManquante(320, 213, { largeur = 4160, hauteur = 6240, orientation = 'BC', cadre = quatreCinq.cadre }), 'BC, 4:5')
    -- Un portrait recadré en paysage 3:2 : la bonne vignette est aussi couchée à la photo entière ;
    -- debout au cadre, elle reste (le cadre d'abord).
    local paysage = { largeur = 4160, hauteur = 6240, orientation = 'DA',
        cadre = { CropLeft = 0, CropTop = 0, CropRight = 4 / 9, CropBottom = 1, CropAngle = 0 } }
    egal(nil, Images.rotationManquante(300, 200, paysage), 'recadré en paysage, à l\'endroit : rien')
    egal(270, Images.rotationManquante(200, 300, paysage), 'recadré en paysage, couchée au cadre')
end)

essai("Photo verticale juste après une retouche (XH2S0407.RAF (Copie 1)) : la vignette de secours, couchée, se redresse avant d'être marquée ; Focus la montre debout", function()
    activer(407)
    repondre(REPONSE_2402)
    Fichiers.supprimer(RECUS)
    Moteur.nouvelle()
    PHOTOS[407].grandeRefusee, PHOTOS[407].tailles = true, {}
    local tournees = commandes('/usr/bin/sips -r 270 ')
    ouvrirFenetre(function(p)
        egal('focus', p.onglet)
        lancerTaches()
        egal(Fenetre.TAILLE_SECOURS_FOCUS, PHOTOS[407].tailles[#PHOTOS[407].tailles], 'la vignette de secours')
        local r = Fenetre.focus
        vrai(r and r.fichier, "l'image de l'onglet")
        -- La vignette donnée au connecteur (le faux la recopie : l'image marquée) est debout : il
        -- dessine ses cadres dans l'image affichée.
        egal('200x300', taille(r.dossier .. '/' .. r.fichier), "redressée avant d'être marquée")
        egal(tournees + 1, commandes('/usr/bin/sips -r 270 '), 'le quart de tour de DA')
        egal(r.chemin, p.imageApercu)
    end)
    PHOTOS[407].grandeRefusee = nil
    sansErreur()
end)

essai("DA recadrée 4:5 par la retouche, vignette de secours 320 × 213 couchée (d'avant le cadre) : redressée avant --focus", function()
    activer(407)
    repondre(REPONSE_2402)
    Fichiers.supprimer(RECUS)
    Moteur.nouvelle()
    local description = PHOTOS[407].description
    local geometrie = description.geometrie
    description.geometrie = { largeur = 4160, hauteur = 6240, orientation = 'DA',
        cadre = { CropLeft = 1 / 12, CropTop = 0, CropRight = 11 / 12, CropBottom = 1, CropAngle = 0 } }
    PHOTOS[407].grandeRefusee, PHOTOS[407].tailles = true, {}
    local tournees = commandes('/usr/bin/sips -r 270 ')
    local ok, erreur = pcall(ouvrirFenetre, function(p)
        egal('focus', p.onglet)
        lancerTaches()
        egal(Fenetre.TAILLE_SECOURS_FOCUS, PHOTOS[407].tailles[#PHOTOS[407].tailles], 'la vignette de secours')
        local r = Fenetre.focus
        vrai(r and r.fichier, "l'image de l'onglet")
        -- Ni debout ni couchée au cadre de 4:5 : couchée à la photo entière, elle se tourne.
        egal('200x300', taille(r.dossier .. '/' .. r.fichier), "redressée avant d'être marquée")
        egal(tournees + 1, commandes('/usr/bin/sips -r 270 '), 'le quart de tour de DA')
        local recu = recus()[#recus()]
        vrai(recu, '--focus reçu')
        vrai(math.abs(Json.decode(recu.geometrie).cadre.CropLeft - 1 / 12) < 1e-6, 'le cadre passé au connecteur : ' .. recu.geometrie)
    end)
    description.geometrie = geometrie
    PHOTOS[407].grandeRefusee = nil
    vrai(ok, erreur)
    sansErreur()
end)

essai("Agrandir sur Focus : une grande vignette demandée au clic ; refusée, un rendu de la photo (pas pendant que Claude travaille : l'image de l'onglet) ; debout, marquée, dans 2 000 × 1 250", function()
    activer(407)
    repondre(REPONSE_2402)
    Fichiers.supprimer(RECUS)
    Moteur.nouvelle()
    PHOTOS[407].grandeRefusee = true
    ouvrirFenetre(function(p)
        lancerTaches()
        local r = Fenetre.focus
        vrai(r and r.fichier, "l'image de l'onglet")
        local function agrandir()
            local dialogues, n = #S.dialogues, commandesFocus()
            PHOTOS[407].tailles = {}
            Fenetre.agrandir()
            lancerTaches()
            egal(dialogues + 1, #S.dialogues, 'Agrandir')
            local d = S.dialogues[#S.dialogues]
            contient(d.title, 'XH2S0407.RAF')
            egal('picture', d.contents.genre)
            return d.contents.args, commandesFocus() - n
        end
        -- La grande refusée (juste après une retouche) : un rendu de la photo, par la liaison.
        local avant = #rendus
        local image, marquee = agrandir()
        egal(Fenetre.TAILLE_GRANDE, PHOTOS[407].tailles[1], 'la grande vignette, demandée au clic')
        egal(avant + 1, #rendus, 'refusée : un rendu')
        egal(407, rendus[#rendus].id)
        egal(Fenetre.TAILLE_GRANDE, rendus[#rendus].taille)
        egal('833x1250', image.width .. 'x' .. image.height, 'agrandie dans 2 000 × 1 250, debout')
        egal(1, marquee, 'ses cadres dessinés par le connecteur')
        vrai(not Fichiers.existe(image.value), 'effacée à la fermeture : ' .. image.value)
        -- Claude travaille : pas de rendu (il attendrait la liaison) ; l'image de l'onglet, agrandie.
        Moteur.travaille = true
        image, marquee = agrandir()
        Moteur.travaille = false
        egal(avant + 1, #rendus, 'pas de rendu pendant que Claude travaille')
        egal('833x1250', image.width .. 'x' .. image.height, "l'image de l'onglet, debout, agrandie")
        contient(image.value, r.dossier .. '/.vignettes/')
        egal(0, marquee, 'déjà marquée')
        -- Une commande de la liaison en cours (Claude Desktop, Claude Code en terminal : Moteur.travaille
        -- ne les voit pas), ou qui vient de finir : pas de rendu non plus, l'image de l'onglet.
        Liaison.enCours = 1
        image, marquee = agrandir()
        Liaison.enCours = 0
        egal(avant + 1, #rendus, 'pas de rendu pendant une commande de la liaison')
        egal('833x1250', image.width .. 'x' .. image.height, "l'image de l'onglet, agrandie")
        contient(image.value, r.dossier .. '/.vignettes/')
        Liaison.finCommande = os.time()
        image = agrandir()
        egal(avant + 1, #rendus, 'pas de rendu juste après une commande de la liaison')
        contient(image.value, r.dossier .. '/.vignettes/')
        Liaison.finCommande = os.time() - Lightroom.DELAI_LIAISON_LIBRE - 1
        image = agrandir()
        egal(avant + 2, #rendus, 'la liaison libre depuis DELAI_LIAISON_LIBRE : un rendu')
        Liaison.finCommande = nil
        -- La grande rendue : elle, marquée ; pas de rendu.
        PHOTOS[407].grandeRefusee = nil
        image, marquee = agrandir()
        egal(avant + 2, #rendus, 'la grande vignette : pas de rendu')
        egal('833x1250', image.width .. 'x' .. image.height)
        egal(1, marquee)
    end)
    PHOTOS[407].grandeRefusee = nil
    Liaison.enCours, Liaison.finCommande = 0, nil
    sansErreur()
end)

essai("Aperçu de la photo active juste après une retouche (onglet Note) : la vignette de secours, redressée et marquée, à la place de l'image vide ; Agrandir passe par la grande ; la grande se redemande ensuite", function()
    activer(407)
    repondre(REPONSE_2402)
    Moteur.nouvelle()
    PHOTOS[407].grandeRefusee, PHOTOS[407].tailles = true, {}
    ouvrirFenetre(function(p, contenu)
        S.cliquer(segment(contenu, 'Note'))
        lancerTaches()
        local a = Fenetre.apercuActif
        vrai(a and a.fichier, "l'aperçu de la photo active : la vignette de secours")
        egal(true, a.secours, 'notée de secours')
        local tailles = {}
        for _, t in ipairs(PHOTOS[407].tailles) do
            tailles[#tailles + 1] = tostring(t)
        end
        contient(table.concat(tailles, ' '), string.rep(Fenetre.TAILLE_PHOTO_ACTIVE .. ' ', Fenetre.ESSAIS_VIGNETTE_FOCUS)
            .. Fenetre.TAILLE_SECOURS_FOCUS, 'la grande redemandée, puis la petite')
        vrai(a.fichier:find('%-af%.jpg$'), 'marquée par --marquer-af : ' .. a.fichier)
        egal('200x300', taille(a.dossier .. '/' .. a.fichier), "redressée avant d'être marquée")
        egal(a.chemin, p.imageApercu)
        egal(true, p.aImage, 'Agrandir actif')
        -- Agrandir : la grande demandée au clic, refusée, un rendu de la photo (la liaison libre).
        local dialogues, avant = #S.dialogues, #rendus
        PHOTOS[407].tailles = {}
        Fenetre.agrandir()
        lancerTaches()
        egal(dialogues + 1, #S.dialogues, 'Agrandir')
        egal(Fenetre.TAILLE_GRANDE, PHOTOS[407].tailles[1], 'la grande vignette, demandée au clic')
        egal(avant + 1, #rendus, 'refusée : un rendu')
        egal('833x1250', S.dialogues[#S.dialogues].contents.args.width .. 'x' .. S.dialogues[#S.dialogues].contents.args.height)
        -- Lightroom a refait son aperçu. Un rafraîchissement dans le délai garde la petite (la fin de
        -- chaque demande rafraîchit l'aperçu : pas de demandes sans fin).
        PHOTOS[407].grandeRefusee, PHOTOS[407].tailles = nil, {}
        Fenetre.rafraichirApercu()
        lancerTaches()
        egal(0, #PHOTOS[407].tailles, 'dans le délai : rien de redemandé')
        egal(a, Fenetre.apercuActif)
        -- Le délai passé : la grande redemandée, montrée, sans secours.
        a.le = os.time() - Fenetre.DELAI_SECOURS_ACTIVE
        Fenetre.rafraichirApercu()
        egal(a.chemin, p.imageApercu, 'la petite reste montrée pendant la demande')
        lancerTaches()
        egal(Fenetre.TAILLE_PHOTO_ACTIVE, PHOTOS[407].tailles[1], 'la grande redemandée')
        local b = Fenetre.apercuActif
        vrai(b ~= a and b.fichier, 'la grande, à sa place')
        egal(nil, b.secours)
        egal(b.chemin, p.imageApercu)
        vrai(not Fichiers.existe(a.dossier), "le dossier de la petite effacé")
        -- Plus de secours : un rafraîchissement ne redemande rien.
        PHOTOS[407].tailles = {}
        b.le = os.time() - Fenetre.DELAI_SECOURS_ACTIVE
        Fenetre.rafraichirApercu()
        lancerTaches()
        egal(0, #PHOTOS[407].tailles, 'la grande gardée')
    end)
    PHOTOS[407].grandeRefusee = nil
    sansErreur()
end)

essai("Aperçu de la photo active (onglet Note) : une vignette couchée se redresse avant le carré de mise au point ; Agrandir la demande en grand, debout, avec son carré", function()
    activer(407)
    repondre(REPONSE_2402)
    Moteur.nouvelle()
    PHOTOS[407].couchee = true
    ouvrirFenetre(function(p, contenu)
        S.cliquer(segment(contenu, 'Note'))
        lancerTaches()
        local a = Fenetre.apercuActif
        vrai(a and a.fichier, "l'aperçu de la photo active")
        vrai(a.fichier:find('%-af%.jpg$'), 'marquée par --marquer-af : ' .. a.fichier)
        egal('200x300', taille(a.dossier .. '/' .. a.fichier), "redressée avant d'être marquée")
        local dialogues, marques, avant = #S.dialogues, commandes(' --marquer-af '), #rendus
        Fenetre.agrandir()
        lancerTaches()
        egal(dialogues + 1, #S.dialogues, 'Agrandir')
        local image = S.dialogues[#S.dialogues].contents.args
        egal('833x1250', image.width .. 'x' .. image.height, 'debout, dans 2 000 × 1 250')
        egal(marques + 1, commandes(' --marquer-af '), 'le carré sur la grande')
        egal(avant, #rendus, 'la grande vignette : pas de rendu')
    end)
    PHOTOS[407].couchee = nil
    sansErreur()
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if echecs > 0 then
    os.exit(1)
end
