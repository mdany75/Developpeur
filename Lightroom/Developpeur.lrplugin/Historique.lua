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

local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'

local Conversation = require 'Conversation'
local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Photos = require 'Photos'
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

-- Les en-têtes des trois éléments.
Historique.TITRE = "Historique de la photo"
Historique.TITRE_DEPUIS = "Depuis la dernière fois"

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

-- L'état d'une photo (un LrPhoto) : { id, nom, journal (ses entrées, des plus anciennes aux plus
-- récentes), editCount, lastEditTime (métadonnées brutes, des nombres), reprises (nil, ou
-- { etape, changements = { { cle, claude, maintenant } } } : ce que Dany a changé à la main depuis
-- la dernière commande de Claude, valeurs en mots) }. `sansReprises` : sans lire les réglages (ce
-- qu'une conversation a vu n'en a pas besoin).
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
-- raison et leur date) et ses reprises à la main depuis la dernière ; sans étape de Claude, au plus
-- « retouchée à la main » (editCount au-dessus de 0 : pas constaté sur une photo jamais
-- développée) ; nil sans rien à dire.
function Historique.historique(etat)
    local journal = etat.journal
    if #journal == 0 then
        if (etat.editCount or 0) > 0 then
            return element(Historique.TITRE .. " : retouchée à la main, sans étape de Claude.", {})
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

return Historique
