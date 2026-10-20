-- FenetreNotation.lua : la fenêtre « Claude · Séance de notation ». En haut, les photos à noter
-- (sélection ou collection), figées à l'ouverture de la séance (Notation.ouvrirSeance) ; à gauche
-- les quatre passes du standard de notation, une question chacune, lancées auprès de Claude dans
-- la conversation de la séance ; au centre la planche (12 vignettes par page, la note proposée et
-- son état) et le court fil de cette conversation ; à droite la fiche de la photo choisie (note
-- posée, proposition, critères, plafond, raison) ; en bas Tout accepter, le filtre et la demande.
--
-- Claude propose (propose_ratings, rangé par Notation.lua) ; seuls Accepter, Changer… et Tout
-- accepter écrivent dans le catalogue (Notation.poser), sans Claude ni quota, et jamais pendant
-- que Claude travaille : ses commandes passent par la liaison au même moment. À vérifier et
-- Écarter ne touchent que le registre.
--
-- Une fenêtre ouverte ne change pas de structure : la planche est une grille fixe de cases
-- parcourue par pages, chaque image et chaque état des variantes superposées. Les collections se
-- lisent à l'ouverture (↻ rouvre la fenêtre pour les relire).

local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

require 'Compat'
local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Images = require 'Images'
local Journal = require 'Journal'
local Metriques = require 'Metriques'
local Moteur = require 'Moteur'
local Notation = require 'Notation'
local Publication = require 'Publication'
local Texte = require 'Texte'
local Vignettes = require 'Vignettes'

local FenetreNotation = { ouverte = false, generation = 0, vignettes = {}, cacheFil = {}, defilement = 0, page = 1 }

FenetreNotation.GAUCHE = 230
-- Côté d'une case de la planche, et de la vignette de la fiche (images carrées sur fond).
FenetreNotation.CASE = 120
FenetreNotation.FICHE = 300
FenetreNotation.COLONNES = 4
FenetreNotation.RANGEES = 3
FenetreNotation.CASES = 12
FenetreNotation.ESPACE_CASES = 8
FenetreNotation.CENTRE = FenetreNotation.COLONNES * FenetreNotation.CASE + (FenetreNotation.COLONNES - 1) * FenetreNotation.ESPACE_CASES
FenetreNotation.LIGNES_FIL = 8
-- Côté demandé à Lightroom (un minimum : l'aperçu rendu peut être plus grand) pour la case et la
-- fiche.
FenetreNotation.TAILLE_DEMANDEE = 320
FenetreNotation.DELAI_RETOUR = 0.3
FenetreNotation.PASSES = 4

-- Le filtre de la planche : clé, titre.
FenetreNotation.FILTRES = {
    { 'toutes', "Toutes" }, { 'proposees', "Proposées" }, { 'a_verifier', "À vérifier" }, { 'acceptees', "Acceptées" },
}

-- Couleur de l'état d'une proposition (case et fiche).
local COULEUR_ETAT = { proposee = 'orange', a_verifier = 'rouge', acceptee = 'vert', changee = 'vert', ecartee = 'gris' }
local COULEURS_ETAT = { 'orange', 'rouge', 'vert', 'gris' }
local MOTS_ETAT = { proposee = "proposée", a_verifier = "à vérifier", acceptee = "acceptée", changee = "changée", ecartee = "écartée" }
local MOIS = { 'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.' }

FenetreNotation.RAPPEL = table.concat({
    "0 ☆   pas encore jugée",
    "⚑   Rejeter : défaut majeur, involontaire",
    "1 ★   gardée, sous le niveau 2",
    "2 ★   correcte, sans défaut visible",
    "3 ★   tient seule devant un inconnu",
    "4 ★   une 3 ★ qui a de l'impact",
    "5 ★   parmi vos meilleures : vous seul",
    "Plafonds : défaut visible à la taille d'usage, 2 ★ ; visible seulement à 100 %, 3 ★.",
}, '\n')

-- Les couleurs se créent à la construction : ce fichier se charge aussi sans LrColor (liens.lua
-- charge les modules requis sous la simulation de la liaison).
local COULEURS
local function couleurs()
    if not COULEURS then
        local LrColor = import 'LrColor'
        COULEURS = {
            texte = LrColor(0.11, 0.11, 0.12),
            dany = LrColor(0.04, 0.32, 0.72),
            gris = LrColor(0.45, 0.45, 0.48),
            mono = LrColor(0.24, 0.24, 0.27),
            vert = LrColor(0.18, 0.62, 0.28),
            orange = LrColor(0.88, 0.50, 0.05),
            rouge = LrColor(0.82, 0.18, 0.18),
            bleu = LrColor(0.10, 0.42, 0.85),
        }
    end
    return COULEURS
end

-- Les polices du fil sont celles que Fil.lua mesure (Metriques).
local function police(cle, taille)
    local m = Metriques[cle]
    return { name = m.nom, size = taille or m.taille }
end

local POLICES = {
    texte = police('texte'),
    gras = police('gras'),
    mono = police('mono'),
    titre = police('gras', 15),
    petit = police('texte', 11),
    petitGras = police('gras', 11),
}

-- Le fil : icônes et variantes de texte d'une ligne selon son genre (comme la fenêtre Claude).
local ICONES = {
    { cle = 'dany', glyphe = '›', couleur = 'dany' },
    { cle = 'ok', glyphe = '✓', couleur = 'vert' },
    { cle = 'cours', glyphe = '●', couleur = 'orange' },
    { cle = 'erreur', glyphe = '✕', couleur = 'rouge' },
    { cle = 'apercu', glyphe = '▣', couleur = 'bleu' },
    { cle = 'proposition', glyphe = '●', couleur = 'orange' },
    { cle = 'note', glyphe = 'ⓘ', couleur = 'gris' },
}
local STYLES = {
    { genres = { claude = true, vide = true }, police = 'texte', couleur = 'texte' },
    { genres = { titre = true }, police = 'gras', couleur = 'texte' },
    { genres = { dany = true }, police = 'texte', couleur = 'dany' },
    { genres = { outil = true }, police = 'mono', couleur = 'mono' },
    { genres = { apercu = true }, police = 'texte', couleur = 'bleu' },
    { genres = { proposition = true }, police = 'gras', couleur = 'orange' },
    { genres = { note = true }, police = 'texte', couleur = 'gris' },
}

local bind = LrView.bind

local function egal(cle, valeur)
    return bind { key = cle, transform = function(v) return v == valeur end }
end

local function nonLie(cle)
    return bind { key = cle, transform = function(v) return not v end }
end

-- Change une propriété seulement si sa valeur change.
local function poser(p, cle, valeur)
    if p[cle] ~= valeur then
        p[cle] = valeur
    end
end

-- Les fenêtres modales, les confirmations et les écritures s'ouvrent dans une tâche, jamais depuis
-- l'action d'un bouton.
local function enTache(fn, ...)
    local arguments = { ... }
    LrTasks.startAsyncTask(function()
        local ok, erreur = LrTasks.pcall(fn, unpack(arguments))
        if not ok then
            Journal.noter("Séance de notation :", tostring(erreur))
            FenetreNotation.dire(tostring(erreur), 'erreur')
        end
    end)
end

-- Textes ----------------------------------------------------------------------------------------

-- « ★★★☆☆ » : une note de 0 à 5.
function FenetreNotation.etoiles(note)
    local n = math.max(0, math.min(5, math.floor(tonumber(note) or 0)))
    return string.rep('★', n) .. string.rep('☆', 5 - n)
end

-- Une note proposée ou choisie : « ★★★★☆ », ou « ⚑ Rejeter ».
function FenetreNotation.texteNote(note, drapeau)
    if drapeau == 'rejetee' then
        return "⚑ Rejeter"
    end
    return FenetreNotation.etoiles(note)
end

-- « DSCF4961 » pour DSCF4961.RAF.
local function nomCourt(nom)
    return (tostring(nom or ''):gsub('%.[^.]*$', ''))
end

local function compte(n, singulier, pluriel)
    return n .. ' ' .. (n == 1 and singulier or pluriel)
end

-- « 20 oct. à 9:41 ».
local function date(t)
    local d = os.date('*t', t)
    return string.format("%d %s à %d:%02d", d.day, MOIS[d.month], d.hour, d.min)
end

-- « 5 proposées · 2 acceptées · 1 à vérifier » d'après des comptes de Notation.compter.
function FenetreNotation.texteComptes(c, vide)
    c = c or {}
    local morceaux = {}
    if (c.proposees or 0) > 0 then
        morceaux[#morceaux + 1] = compte(c.proposees, "proposée", "proposées")
    end
    if (c.acceptees or 0) > 0 then
        morceaux[#morceaux + 1] = compte(c.acceptees, "acceptée", "acceptées")
    end
    if (c.a_verifier or 0) > 0 then
        morceaux[#morceaux + 1] = c.a_verifier .. " à vérifier"
    end
    if (c.ecartees or 0) > 0 then
        morceaux[#morceaux + 1] = compte(c.ecartees, "écartée", "écartées")
    end
    return #morceaux > 0 and table.concat(morceaux, " · ") or (vide or '')
end

-- Une proposition « à vérifier » : Claude en doute, ou l'utilisateur l'y a mise.
local function aVerifier(prop)
    return prop ~= nil and (prop.etat == 'a_verifier' or (prop.etat == 'proposee' and prop.a_verifier == true))
end

-- La photo correspond-elle au filtre ?
function FenetreNotation.correspond(prop, filtre)
    if filtre == 'proposees' then
        return prop ~= nil and prop.etat == 'proposee' and not aVerifier(prop)
    elseif filtre == 'a_verifier' then
        return aVerifier(prop)
    elseif filtre == 'acceptees' then
        return prop ~= nil and (prop.etat == 'acceptee' or prop.etat == 'changee')
    end
    return true
end

-- Ce que montre une case ou la fiche : couleur, étoiles, état en mots. Sans proposition, la note
-- posée dans Lightroom.
function FenetreNotation.etatPhoto(prop, info)
    info = info or {}
    if not prop then
        if (info.drapeau or 0) == -1 then
            return 'gris', "⚑ Rejetée", "posée dans Lightroom"
        end
        local note = info.note or 0
        return 'gris', FenetreNotation.etoiles(note), note > 0 and "posée dans Lightroom" or "pas encore jugée"
    end
    local etat = aVerifier(prop) and 'a_verifier' or prop.etat
    local etoiles = FenetreNotation.texteNote(prop.note, prop.drapeau)
    if etat == 'changee' then
        etoiles = FenetreNotation.texteNote(prop.note_choisie, prop.drapeau_choisi)
    end
    local mots = MOTS_ETAT[etat] or tostring(etat)
    if tonumber(prop.passe) then
        mots = mots .. " · passe " .. tostring(prop.passe)
    end
    return COULEUR_ETAT[etat] or 'gris', etoiles, mots
end

-- Message du bas de la fenêtre : genre 'erreur' (orange) ou 'info' (gris).
function FenetreNotation.dire(texte, genre)
    local p = FenetreNotation.p
    if not p then
        return
    end
    p.genreMessage = genre or 'info'
    p.message = texte or ''
    FenetreNotation.majBandeau()
end

function FenetreNotation.majBandeau()
    local p = FenetreNotation.p
    if not p then
        return
    end
    local etat = 'vide'
    if Moteur.travaille then
        etat = 'activite'
    elseif (p.message or '') ~= '' then
        etat = p.genreMessage == 'erreur' and 'erreur' or 'info'
    end
    poser(p, 'bandeau', etat)
end

-- Lightroom ---------------------------------------------------------------------------------------

-- Nom, note et drapeau posés, nombre de modifications d'une photo du catalogue (nil si
-- introuvable). À lire depuis une tâche.
function FenetreNotation.lirePhoto(id)
    local ok, info = LrTasks.pcall(function()
        local photo = LrApplication.activeCatalog():getPhotoByLocalId(tonumber(id))
        if not photo then
            return nil
        end
        return {
            nom = photo:getFormattedMetadata('fileName') or '',
            -- Entre parenthèses : une seule valeur, même si aucune n'est rendue.
            note = tonumber((photo:getRawMetadata('rating'))) or 0,
            drapeau = tonumber((photo:getRawMetadata('pickStatus'))) or 0,
            edition = tonumber((photo:getRawMetadata('editCount'))) or 0,
        }
    end)
    return ok and info or nil
end

-- Les identifiants des photos, dans l'ordre de la prise de vue (une rafale reste ensemble), sinon
-- dans l'ordre donné.
function FenetreNotation.ordonner(photos)
    local ok, dates = LrTasks.pcall(function()
        return LrApplication.activeCatalog():batchGetRawMetadata(photos, { 'dateTimeOriginal' })
    end)
    local liste = {}
    for i, photo in ipairs(photos) do
        local d = ok and type(dates) == 'table' and dates[photo] and tonumber(dates[photo].dateTimeOriginal) or nil
        liste[i] = { id = photo.localIdentifier, date = d, rang = i }
    end
    table.sort(liste, function(a, b)
        if a.date and b.date and a.date ~= b.date then
            return a.date < b.date
        elseif (a.date ~= nil) ~= (b.date ~= nil) then
            return a.date ~= nil
        end
        return a.rang < b.rang
    end)
    local ids = {}
    for i, x in ipairs(liste) do
        ids[i] = x.id
    end
    return ids
end

function FenetreNotation.dossier()
    return LrPathUtils.child(Chemins.temporaire(), 'Notation')
end

-- Source -----------------------------------------------------------------------------------------

-- Nombre de photos de la source choisie (sélection ou collection), dans une tâche.
function FenetreNotation.recalculerSource()
    local p = FenetreNotation.p
    if not p then
        return
    end
    local photos = Publication.photos(p.portee, p.collection)
    local n = #photos
    FenetreNotation.nombreSource = n
    if p.portee == 'collection' then
        p.textePhotos = (p.collection and p.collection ~= 0) and (n == 1 and "1 photo dans la collection." or (n .. " photos dans la collection."))
            or "Choisissez une collection."
    elseif n == 0 then
        p.textePhotos = "Aucune photo sélectionnée dans Lightroom."
    else
        p.textePhotos = n == 1 and "1 photo sélectionnée." or (n .. " photos sélectionnées.")
    end
    FenetreNotation.majBoutons()
end

local function titreCollection(id)
    for _, item in ipairs(FenetreNotation.p and FenetreNotation.p.collections or {}) do
        if item.value == id then
            return item.title
        end
    end
    return "collection " .. tostring(id)
end

-- Ouvre une séance sur les photos de la source : la liste est figée (Notation.ouvrirSeance).
function FenetreNotation.ouvrirSeance()
    local p = FenetreNotation.p
    if not p then
        return
    end
    if Moteur.travaille then
        FenetreNotation.dire("Claude travaille : ouvrez la séance quand il a fini.", 'erreur')
        return
    end
    local photos = Publication.photos(p.portee, p.collection)
    if #photos == 0 then
        FenetreNotation.dire("Aucune photo : sélectionnez des photos dans Lightroom, ou choisissez une collection.", 'erreur')
        return
    end
    local active = Notation.seanceActive()
    local ancienne = active and Notation.seance(active)
    if ancienne then
        local reponse = LrDialogs.confirm(string.format("Ouvrir une séance de %d photos ?", #photos),
            "La séance « " .. tostring(ancienne.titre) .. " » se ferme ; les notes posées ne changent pas.", "Ouvrir", "Annuler")
        if reponse ~= 'ok' then
            return
        end
    end
    local ids = FenetreNotation.ordonner(photos)
    local titre
    if p.portee == 'collection' then
        titre = titreCollection(p.collection)
    else
        local d = os.date('*t')
        titre = string.format("Sélection du %d %s", d.day, MOIS[d.month])
    end
    local ok, id = LrTasks.pcall(Notation.ouvrirSeance, {
        titre = titre,
        source = { portee = p.portee, collection = p.portee == 'collection' and p.collection or nil },
        photos = ids,
    })
    if not ok then
        FenetreNotation.dire(tostring(id), 'erreur')
        return
    end
    FenetreNotation.idSeance = nil
    FenetreNotation.choisie = ids[1]
    FenetreNotation.page = 1
    FenetreNotation.dire(string.format("Séance ouverte : %d photos, figées jusqu'à la fin de la séance.", #ids), 'info')
    FenetreNotation.aRafraichir = true
end

-- Registre ----------------------------------------------------------------------------------------

-- La conversation de la séance (Moteur.nouvelleSeance la reprend si elle existe). Sans `creer`,
-- seulement celle qui existe déjà.
function FenetreNotation.conversation(seance, creer)
    if not seance then
        return nil
    end
    for _, c in ipairs(Moteur.conversations or {}) do
        if c.genre == 'notation' and tostring(c.seance) == tostring(seance.id) then
            return c
        end
    end
    if not creer then
        return nil
    end
    return Moteur.nouvelleSeance { titre = "Séance · " .. tostring(seance.titre), seance = seance.id }
end

-- Les propositions de la séance par photo (clé texte).
local function parPhoto(liste)
    local t = {}
    for _, prop in pairs(liste or {}) do
        if type(prop) == 'table' and prop.photo ~= nil then
            t[tostring(prop.photo)] = prop
        end
    end
    return t
end

-- Les propositions encore « proposées » de la passe (Tout accepter) : ni à vérifier, ni décidées.
function FenetreNotation.aAccepter()
    local s, props, passe = FenetreNotation.seance, FenetreNotation.props or {}, tonumber(FenetreNotation.p and FenetreNotation.p.passe) or 1
    local liste = {}
    for _, id in ipairs(s and s.photos or {}) do
        local prop = props[tostring(id)]
        if prop and prop.etat == 'proposee' and not aVerifier(prop) and (tonumber(prop.passe) or passe) == passe then
            liste[#liste + 1] = prop
        end
    end
    return liste
end

-- Les photos montrées par la planche : celles de la séance qui passent le filtre.
function FenetreNotation.visibles()
    local s, props = FenetreNotation.seance, FenetreNotation.props or {}
    local filtre = FenetreNotation.p and FenetreNotation.p.filtre or 'toutes'
    local liste = {}
    for _, id in ipairs(s and s.photos or {}) do
        if FenetreNotation.correspond(props[tostring(id)], filtre) then
            liste[#liste + 1] = id
        end
    end
    return liste
end

-- Rafraîchissement --------------------------------------------------------------------------------

-- Tout ce qui dépend du registre et du catalogue : séance, passes, planche, fiche. `recale` : le
-- registre vient d'être recalé sur les notes relues par la planche (tout se relit une fois).
function FenetreNotation.rafraichir(recale)
    local p = FenetreNotation.p
    if not p then
        return
    end
    FenetreNotation.versionVue = Notation.version
    local id = Notation.seanceActive()
    local s = id and Notation.seance(id) or nil
    FenetreNotation.seance = s
    if id ~= FenetreNotation.idSeance then
        -- Une autre séance : sa passe, la première page, sa première photo.
        FenetreNotation.idSeance = id
        FenetreNotation.page = 1
        FenetreNotation.defilement = 0
        FenetreNotation.cacheFil = {}
        if s then
            p.passe = tonumber(s.passe) or 1
            local dedans = false
            for _, x in ipairs(s.photos) do
                dedans = dedans or x == FenetreNotation.choisie
            end
            if not dedans then
                FenetreNotation.choisie = s.photos[1]
            end
        else
            FenetreNotation.choisie = nil
        end
    end
    FenetreNotation.props = parPhoto(s and Notation.propositions(id) or {})
    FenetreNotation.rangs = {}
    for i, x in ipairs(s and s.photos or {}) do
        FenetreNotation.rangs[tostring(x)] = i
    end

    local c = s and Notation.compter(id) or nil
    if s then
        poser(p, 'titreSeance', "Séance « " .. tostring(s.titre) .. " »")
        local morceaux = { compte(#s.photos, "photo", "photos") }
        local texte = FenetreNotation.texteComptes(c)
        if texte ~= '' then
            morceaux[#morceaux + 1] = texte
        end
        if tonumber(s.cree) then
            morceaux[#morceaux + 1] = "ouverte le " .. date(tonumber(s.cree))
        end
        poser(p, 'resumeSeance', table.concat(morceaux, " · "))
    else
        poser(p, 'titreSeance', "Aucune séance ouverte")
        poser(p, 'resumeSeance', "Choisissez les photos, puis « Ouvrir la séance » : la liste est figée, Claude propose passe par passe, vous décidez ici.")
    end
    for n = 1, FenetreNotation.PASSES do
        local parPasse = c and c.par_passe[n]
        local vide = Consignes.passes[n].seul or (s and "Pas encore de proposition." or '')
        poser(p, 'comptes' .. n, FenetreNotation.texteComptes(parPasse, vide))
    end
    local passe = tonumber(p.passe) or 1
    poser(p, 'titreLancer', "Lancer la passe " .. passe)
    FenetreNotation.aPoser = FenetreNotation.aAccepter()
    local n = #FenetreNotation.aPoser
    poser(p, 'titreToutAccepter', n > 0 and string.format("Tout accepter · passe %d (%d)", passe, n) or "Tout accepter")

    local manquantes = {}
    if FenetreNotation.rafraichirPlanche(manquantes, recale) then
        return FenetreNotation.rafraichir(true)
    end
    FenetreNotation.rafraichirFiche(manquantes)
    FenetreNotation.preparerVignettes(manquantes)
    FenetreNotation.majBoutons()
end

-- La vignette d'une photo est-elle prête (et à jour) ? Sinon, l'ajoute aux demandes.
local function vignette(id, info, cle, manquantes)
    local v = FenetreNotation.vignettes[id]
    local edition = info and info.edition or 0
    if v and v.edition == edition then
        if v[cle] then
            return v[cle]
        elseif v.erreur then
            return nil, v.erreur
        end
    end
    manquantes[#manquantes + 1] = { id = id, edition = edition, cle = cle }
    return nil
end

-- La planche relit la note et le drapeau posés de ses photos et de la fiche, et recale le
-- registre (Notation.recaler, une écriture pour la page) : une note retirée dans Lightroom
-- (undo_last, ⌘Z) remet sa proposition à décider. Rend vrai si le registre a changé (sans
-- `recale`) : la fenêtre se relit alors une fois, sans rien poser ici.
function FenetreNotation.rafraichirPlanche(manquantes, recale)
    local p = FenetreNotation.p
    local visibles = FenetreNotation.visibles()
    FenetreNotation.liste = visibles
    local pages = math.max(1, math.ceil(#visibles / FenetreNotation.CASES))
    FenetreNotation.page = math.max(1, math.min(FenetreNotation.page or 1, pages))
    local debut = (FenetreNotation.page - 1) * FenetreNotation.CASES
    -- La version du registre avant de lire les photos : une note posée entre-temps n'est pas défaite.
    local version = Notation.version
    local infos, releves = {}, {}
    local function lire(id)
        if id and infos[id] == nil then
            infos[id] = FenetreNotation.lirePhoto(id) or false
            if infos[id] then
                releves[#releves + 1] = { photo = id, note = infos[id].note, drapeau = infos[id].drapeau }
            end
        end
    end
    for k = 1, FenetreNotation.CASES do
        lire(visibles[debut + k])
    end
    lire(FenetreNotation.choisie)
    if not recale and #releves > 0 then
        local ok, n = LrTasks.pcall(Notation.recaler, releves, version)
        if ok and n > 0 then
            return true
        end
    end
    local total = FenetreNotation.seance and #FenetreNotation.seance.photos or 0
    if total == 0 then
        poser(p, 'pageTexte', '')
    elseif #visibles == 0 then
        poser(p, 'pageTexte', "Aucune photo pour ce filtre.")
    else
        poser(p, 'pageTexte', string.format("Page %d sur %d · %s", FenetreNotation.page, pages,
            #visibles == total and compte(total, "photo", "photos") or string.format("%d sur %d photos", #visibles, total)))
    end
    FenetreNotation.pages = pages
    FenetreNotation.cases = {}
    for k = 1, FenetreNotation.CASES do
        local id = visibles[debut + k]
        FenetreNotation.cases[k] = id
        local info = id and infos[id] or nil
        if id then
            local prop = FenetreNotation.props[tostring(id)]
            local nom = nomCourt(info and info.nom or (prop and prop.fichier) or tostring(id))
            poser(p, 'nom' .. k, (id == FenetreNotation.choisie and "▸ " or "") .. tostring(FenetreNotation.rangs[tostring(id)] or '') .. " · " .. nom)
            local couleur, etoiles, mots = FenetreNotation.etatPhoto(prop, info)
            poser(p, 'couleur' .. k, couleur)
            poser(p, 'etoiles' .. k, etoiles)
            poser(p, 'etatTexte' .. k, mots)
            local chemin, erreur = vignette(id, info, 'petite', manquantes)
            if chemin then
                poser(p, 'vignette' .. k, chemin)
            end
            poser(p, 'aVignette' .. k, chemin ~= nil)
            poser(p, 'attente' .. k, chemin and '' or (erreur and "Pas de vignette" or "Vignette…"))
        else
            poser(p, 'nom' .. k, '')
            poser(p, 'couleur' .. k, 'gris')
            poser(p, 'etoiles' .. k, '')
            poser(p, 'etatTexte' .. k, '')
            poser(p, 'aVignette' .. k, false)
            poser(p, 'attente' .. k, '')
        end
    end
end

function FenetreNotation.rafraichirFiche(manquantes)
    local p = FenetreNotation.p
    local id = FenetreNotation.choisie
    local s = FenetreNotation.seance
    local prop = id and FenetreNotation.props[tostring(id)]
    FenetreNotation.propositionChoisie = prop
    local info = id and FenetreNotation.lirePhoto(id)
    FenetreNotation.infoChoisie = info
    if not s or not id then
        poser(p, 'ficheNom', '')
        poser(p, 'ficheRang', '')
        poser(p, 'aFicheImage', false)
        poser(p, 'ficheAttente', s and "Cliquez le nom d'une photo de la planche." or "La fiche de la photo choisie s'affiche ici.")
        poser(p, 'fichePosee', '')
        poser(p, 'ficheCouleur', 'gris')
        poser(p, 'ficheProposee', '')
        poser(p, 'ficheDecision', '')
        poser(p, 'ficheCriteres', '')
        poser(p, 'fichePlafond', '')
        poser(p, 'ficheRaison', '')
        poser(p, 'titreAccepter', "Accepter")
        return
    end
    local rang = FenetreNotation.rangs[tostring(id)]
    poser(p, 'ficheNom', (rang and (rang .. " · ") or '') .. tostring(info and info.nom or (prop and prop.fichier) or id))
    local position
    for i, x in ipairs(FenetreNotation.liste or {}) do
        if x == id then
            position = i
        end
    end
    poser(p, 'ficheRang', position and string.format("%d sur %d", position, #FenetreNotation.liste) or "hors filtre")
    local chemin, erreur = vignette(id, info, 'grande', manquantes)
    if chemin then
        poser(p, 'ficheImage', chemin)
    end
    poser(p, 'aFicheImage', chemin ~= nil)
    poser(p, 'ficheAttente', chemin and '' or (erreur and ("Pas de vignette : " .. tostring(erreur)) or "Vignette…"))
    if info then
        poser(p, 'fichePosee', "Posée dans Lightroom : " .. ((info.drapeau == -1) and "⚑ rejetée" or FenetreNotation.etoiles(info.note))
            .. (info.drapeau == -1 and info.note > 0 and (" · " .. FenetreNotation.etoiles(info.note)) or ''))
    else
        poser(p, 'fichePosee', "Photo introuvable dans le catalogue.")
    end
    if prop then
        local couleur, _, mots = FenetreNotation.etatPhoto(prop, info)
        local proposee = FenetreNotation.texteNote(prop.note, prop.drapeau)
        poser(p, 'ficheCouleur', couleur)
        poser(p, 'ficheProposee', "Claude propose : " .. proposee .. (prop.drapeau ~= 'rejetee' and (" (" .. (tonumber(prop.note) or 0) .. " ★)") or ''))
        local decision = mots
        if prop.etat == 'changee' then
            decision = decision .. " : " .. FenetreNotation.texteNote(prop.note_choisie, prop.drapeau_choisi)
        end
        poser(p, 'ficheDecision', decision)
        local criteres = prop.criteres or {}
        local lignes = {}
        for _, x in ipairs({ { 'impact', "Impact" }, { 'qualites', "Qualités" }, { 'plancher', "Plancher technique" }, { 'finition', "Finition" } }) do
            local t = type(criteres[x[1]]) == 'string' and Texte.nettoyer(criteres[x[1]]) or ''
            if t ~= '' then
                lignes[#lignes + 1] = x[2] .. " : " .. t
            end
        end
        poser(p, 'ficheCriteres', table.concat(lignes, '\n'))
        local plafond = tonumber(prop.plafond)
        poser(p, 'fichePlafond', plafond == nil and "Plafond : aucun mesuré."
            or (plafond == 0 and "Plafond mesuré : 0 ★, défaut majeur" or ("Plafond mesuré : " .. plafond .. " ★")))
        poser(p, 'ficheRaison', type(prop.raison) == 'string' and prop.raison or '')
        poser(p, 'titreAccepter', "Accepter " .. proposee)
    else
        poser(p, 'ficheCouleur', 'gris')
        poser(p, 'ficheProposee', "Aucune proposition de Claude pour cette photo.")
        poser(p, 'ficheDecision', "Changer… pose une note sans attendre Claude.")
        poser(p, 'ficheCriteres', '')
        poser(p, 'fichePlafond', '')
        poser(p, 'ficheRaison', '')
        poser(p, 'titreAccepter', "Accepter")
    end
end

-- Ce qui dépend du travail de Claude : boutons, activité, bandeau.
function FenetreNotation.majBoutons()
    local p = FenetreNotation.p
    if not p then
        return
    end
    -- Une demande partie (le moteur ne travaille pas encore) compte comme un travail.
    local travaille = Moteur.travaille == true or FenetreNotation.envoiEnCours == true
    local libre = not travaille and not FenetreNotation.enEcriture
    local s = FenetreNotation.seance
    local prop = FenetreNotation.propositionChoisie
    local c = FenetreNotation.conversation(s, false)
    poser(p, 'travaille', travaille)
    poser(p, 'libre', libre)
    poser(p, 'aSeance', s ~= nil)
    poser(p, 'peutOuvrir', libre and (FenetreNotation.nombreSource or 0) > 0)
    poser(p, 'peutChoisirPasse', libre and s ~= nil)
    -- La passe 4 (5 ★, l'utilisateur seul) ne se lance pas : Claude n'y a rien à faire.
    local passe = Consignes.passes[tonumber(p.passe) or 1]
    poser(p, 'peutLancer', libre and s ~= nil and passe ~= nil and passe.message ~= nil)
    poser(p, 'peutAccepter', libre and prop ~= nil and prop.etat ~= 'acceptee')
    poser(p, 'peutChanger', libre and s ~= nil and FenetreNotation.choisie ~= nil and FenetreNotation.infoChoisie ~= nil)
    poser(p, 'peutVerifier', prop ~= nil and (prop.etat == 'proposee' and not aVerifier(prop) or prop.etat == 'ecartee'))
    poser(p, 'peutEcarter', prop ~= nil and (prop.etat == 'proposee' or prop.etat == 'a_verifier'))
    poser(p, 'peutToutAccepter', libre and #(FenetreNotation.aPoser or {}) > 0)
    poser(p, 'peutPagePrecedente', (FenetreNotation.page or 1) > 1)
    poser(p, 'peutPageSuivante', (FenetreNotation.page or 1) < (FenetreNotation.pages or 1))
    local liste = FenetreNotation.liste or {}
    poser(p, 'peutPhotoPrecedente', #liste > 0 and FenetreNotation.choisie ~= liste[1])
    poser(p, 'peutPhotoSuivante', #liste > 0 and FenetreNotation.choisie ~= liste[#liste])
    poser(p, 'peutEnvoyer', not travaille and s ~= nil)
    -- Arrêter : seulement la demande de cette séance (celle de la fenêtre Claude s'arrête là-bas).
    poser(p, 'peutArreter', travaille and c ~= nil and Moteur.enCours == c)
    FenetreNotation.majBandeau()
end

-- Le fil de la conversation de la séance (ses dernières lignes, ▲▼ pour remonter).
function FenetreNotation.rafraichirFil()
    local p = FenetreNotation.p
    if not p then
        return
    end
    local n = FenetreNotation.LIGNES_FIL
    local c = FenetreNotation.conversation(FenetreNotation.seance, false)
    if FenetreNotation.conversationAffichee ~= c then
        FenetreNotation.conversationAffichee = c
        FenetreNotation.cacheFil = {}
        FenetreNotation.defilement = 0
        FenetreNotation.total = nil
    end
    local lignes = c and Fil.lignes(c, FenetreNotation.CENTRE - 20, FenetreNotation.cacheFil) or {}
    if FenetreNotation.defilement > 0 and FenetreNotation.total and #lignes > FenetreNotation.total then
        FenetreNotation.defilement = FenetreNotation.defilement + (#lignes - FenetreNotation.total)
    end
    FenetreNotation.total = #lignes
    local premiere, defilement = Fil.fenetre(#lignes, n, FenetreNotation.defilement)
    FenetreNotation.defilement = defilement
    for i = 1, n do
        local l = lignes[premiere + i - 1]
        poser(p, 't' .. i, l and l.texte or '')
        poser(p, 'g' .. i, l and l.genre or 'vide')
        poser(p, 'i' .. i, l and l.icone or '')
    end
    if #lignes == 0 then
        poser(p, 't1', FenetreNotation.seance and "Lancez une passe : Claude propose, vous décidez sur la planche." or "Ouvrez une séance pour parler avec Claude.")
        poser(p, 'g1', 'titre')
        poser(p, 't2', "Une note ne s'écrit dans Lightroom que par Accepter, Changer… ou Tout accepter.")
        poser(p, 'g2', 'note')
    end
    poser(p, 'peutMonter', premiere > 1)
    poser(p, 'peutDescendre', defilement > 0)
end

function FenetreNotation.defiler(pas)
    FenetreNotation.defilement = math.max(0, (FenetreNotation.defilement or 0) + pas)
    FenetreNotation.rafraichirFil()
end

-- Vignettes -------------------------------------------------------------------------------------

-- Demande à Lightroom les vignettes qui manquent (une tâche à la fois ; ce qui manque encore se
-- redemande au rafraîchissement suivant). La tâche écrit dans le cache de la fenêtre qui l'a
-- lancée : fenêtre fermée puis rouverte (sans ↻), ses résultats vont dans une table orpheline,
-- sans toucher aux vignettes ni à l'état de la nouvelle fenêtre.
function FenetreNotation.preparerVignettes(manquantes)
    if #manquantes == 0 or FenetreNotation.vignettesEnCours then
        return
    end
    FenetreNotation.vignettesEnCours = true
    local seance = FenetreNotation.idSeance
    local cache, generation = FenetreNotation.vignettes, FenetreNotation.generation
    LrTasks.startAsyncTask(function()
        local ok, erreur = LrTasks.pcall(FenetreNotation.chargerVignettes, manquantes, seance, cache)
        if not ok then
            Journal.noter("Séance de notation, vignettes :", tostring(erreur))
            for _, m in ipairs(manquantes) do
                cache[m.id] = { edition = m.edition, erreur = tostring(erreur) }
            end
        end
        if FenetreNotation.generation == generation then
            FenetreNotation.vignettesEnCours = false
            FenetreNotation.aRafraichir = true
        end
    end)
end

-- Les JPEG de Lightroom (Vignettes.demander), puis les carrés de la case et de la fiche
-- (Images.vignette), rangés dans `cache` (par défaut, celui de la fenêtre). Chaque lot a son
-- dossier : un nom de fichier déjà réduit ne resservira pas après une retouche (le nombre de
-- modifications change).
function FenetreNotation.chargerVignettes(manquantes, seance, cache)
    cache = cache or FenetreNotation.vignettes
    local aDemander, vues = {}, {}
    for _, m in ipairs(manquantes) do
        local v = cache[m.id]
        if not (v and v.edition == m.edition and v.source) and not vues[m.id] then
            vues[m.id] = true
            aDemander[#aDemander + 1] = m.id
        end
    end
    if #aDemander > 0 then
        FenetreNotation.lot = (FenetreNotation.lot or 0) + 1
        local dossier = LrPathUtils.child(LrPathUtils.child(FenetreNotation.dossier(), tostring(seance or 'sans-seance')), tostring(FenetreNotation.lot))
        Fichiers.creerDossier(dossier)
        local chemins, erreurs = Vignettes.demander(aDemander, FenetreNotation.TAILLE_DEMANDEE, dossier)
        local editions = {}
        for _, m in ipairs(manquantes) do
            editions[m.id] = m.edition
        end
        for _, id in ipairs(aDemander) do
            if chemins[id] then
                cache[id] = { edition = editions[id], source = chemins[id] }
            else
                cache[id] = { edition = editions[id], erreur = erreurs[id] or "Lightroom n'a pas rendu de vignette" }
            end
        end
    end
    for _, m in ipairs(manquantes) do
        local v = cache[m.id]
        if v and v.source and not v[m.cle] then
            local cote = m.cle == 'grande' and FenetreNotation.FICHE or FenetreNotation.CASE
            v[m.cle] = Images.vignette(LrPathUtils.parent(v.source), LrPathUtils.leafName(v.source), cote)
            if not v[m.cle] then
                v.erreur = "réduction impossible"
            end
        end
    end
end

-- Actions -----------------------------------------------------------------------------------------

function FenetreNotation.choisir(id)
    FenetreNotation.choisie = id
    -- La page suit la photo choisie.
    for i, x in ipairs(FenetreNotation.liste or {}) do
        if x == id then
            FenetreNotation.page = math.ceil(i / FenetreNotation.CASES)
        end
    end
    FenetreNotation.aRafraichir = true
end

-- Clic sur le nom d'une case : sa photo dans la fiche.
function FenetreNotation.cliquerCase(k)
    FenetreNotation.annulerEnvoiAuto()
    local id = FenetreNotation.cases and FenetreNotation.cases[k]
    if id then
        FenetreNotation.choisir(id)
    end
end

function FenetreNotation.changerPage(pas)
    FenetreNotation.page = math.max(1, math.min((FenetreNotation.page or 1) + pas, FenetreNotation.pages or 1))
    FenetreNotation.aRafraichir = true
end

-- La photo précédente ou suivante de la planche (filtre compris).
function FenetreNotation.photoVoisine(pas)
    local liste = FenetreNotation.liste or {}
    local position = 0
    for i, x in ipairs(liste) do
        if x == FenetreNotation.choisie then
            position = i
        end
    end
    local suivante = liste[math.max(1, math.min(position + pas, #liste))]
    if suivante then
        FenetreNotation.choisir(suivante)
    end
end

-- Écrit des notes (dans une tâche) : une écriture pour toute la liste, une étape par photo dans
-- l'Historique (Notation.poser). Refusé pendant que Claude travaille.
function FenetreNotation.poser(liste)
    if Moteur.travaille then
        FenetreNotation.dire("Claude travaille : les notes se posent quand il a fini (ses commandes passent par Lightroom au même moment).", 'erreur')
        return false
    end
    if FenetreNotation.enEcriture then
        return false
    end
    FenetreNotation.enEcriture = true
    FenetreNotation.majBoutons()
    local ok, r = LrTasks.pcall(Notation.poser, liste)
    FenetreNotation.enEcriture = false
    local reussi = false
    if not ok then
        FenetreNotation.dire(tostring(r), 'erreur')
    elseif type(r) ~= 'table' or not r.ok then
        FenetreNotation.dire(type(r) == 'table' and tostring(r.erreur or "Aucune note posée.") or "Aucune note posée.", 'erreur')
    else
        local posees, premiere, erreurs = 0, nil, 0
        for _, res in ipairs(r.resultats or {}) do
            if res.erreur then
                erreurs = erreurs + 1
                premiere = premiere or res.erreur
            else
                posees = posees + 1
            end
        end
        local texte = posees == 1 and "1 note posée dans Lightroom." or (posees .. " notes posées dans Lightroom.")
        if erreurs > 0 then
            texte = texte .. string.format(" %d refusée%s : %s", erreurs, erreurs > 1 and "s" or "", tostring(premiere))
        end
        FenetreNotation.dire(texte, erreurs > 0 and 'erreur' or 'info')
        reussi = true
    end
    FenetreNotation.aRafraichir = true
    FenetreNotation.majBoutons()
    return reussi
end

-- Accepter : la proposition de Claude telle quelle (Notation.poser sans note ni drapeau).
function FenetreNotation.accepter()
    local prop = FenetreNotation.propositionChoisie
    if not prop then
        return false
    end
    return FenetreNotation.poser({ { photo = prop.photo } })
end

-- Tout accepter : les propositions encore « proposées » de la passe, en une écriture.
function FenetreNotation.toutAccepter()
    if Moteur.travaille then
        FenetreNotation.dire("Claude travaille : les notes se posent quand il a fini.", 'erreur')
        return false
    end
    -- Le registre relu : ce qui est proposé maintenant.
    LrTasks.pcall(FenetreNotation.rafraichir)
    local liste = FenetreNotation.aAccepter()
    local passe = tonumber(FenetreNotation.p and FenetreNotation.p.passe) or 1
    if #liste == 0 then
        FenetreNotation.dire(string.format("Aucune proposition à accepter pour la passe %d.", passe), 'info')
        return false
    end
    -- Notation.poser écrit par lots (Bibliotheque.noter : 500 photos au plus par écriture).
    local lots = math.ceil(#liste / Notation.LOT)
    local ecritures = lots == 1 and "Une écriture" or string.format("%d écritures (une par lot de %d photos)", lots, Notation.LOT)
    local reponse = LrDialogs.confirm(string.format("Poser les %d notes proposées de la passe %d ?", #liste, passe),
        ecritures .. ", une étape par photo dans l'Historique. Les photos à vérifier ne sont pas posées.", "Tout accepter", "Annuler")
    if reponse ~= 'ok' then
        return false
    end
    local items = {}
    for i, prop in ipairs(liste) do
        items[i] = { photo = prop.photo }
    end
    return FenetreNotation.poser(items)
end

-- Changer… : une autre note (de 0 à 5 ★ : l'utilisateur peut mettre 5 ★, Claude non) ou le
-- drapeau Rejeter, avec ou sans proposition de Claude.
function FenetreNotation.changer()
    local id = FenetreNotation.choisie
    if not id then
        return false
    end
    if Moteur.travaille then
        FenetreNotation.dire("Claude travaille : les notes se posent quand il a fini.", 'erreur')
        return false
    end
    local prop = FenetreNotation.propositionChoisie
    local info = FenetreNotation.infoChoisie or {}
    local choix
    LrFunctionContext.callWithContext('Claude · changer la note', function(context)
        local f = LrView.osFactory()
        local q = LrBinding.makePropertyTable(context)
        q.note = tonumber(prop and prop.note) or info.note or 0
        q.rejeter = (prop and prop.drapeau == 'rejetee') or info.drapeau == -1
        local notes = {}
        for n, titre in ipairs({ "pas encore jugée", "gardée", "correcte", "tient seule", "de l'impact", "parmi vos meilleures" }) do
            notes[n] = { title = string.format("%d ★ · %s", n - 1, titre), value = n - 1 }
        end
        local reponse = LrDialogs.presentModalDialog {
            title = "Changer la note · " .. tostring(info.nom or id),
            contents = f:column {
                bind_to_object = q,
                spacing = f:control_spacing(),
                f:static_text { title = prop and ("Claude propose : " .. FenetreNotation.texteNote(prop.note, prop.drapeau)) or "Aucune proposition de Claude." },
                f:row {
                    f:static_text { title = "Note :" },
                    f:popup_menu { value = bind 'note', items = notes, width = 220 },
                },
                f:checkbox { title = "Drapeau Rejeter", value = bind 'rejeter' },
            },
            actionVerb = "Poser",
        }
        if reponse == 'ok' then
            -- Sans Rejeter, seul un rejet déjà posé se retire : un drapeau Retenue reste.
            local drapeau
            if q.rejeter then
                drapeau = 'rejetee'
            elseif info.drapeau == -1 then
                drapeau = 'aucun'
            end
            choix = { photo = id, note = tonumber(q.note), drapeau = drapeau, raison = "Note choisie dans la séance de notation" }
        end
    end)
    if not choix then
        return false
    end
    return FenetreNotation.poser({ choix })
end

-- À vérifier, Écarter : dans le registre seulement (rien dans le catalogue).
function FenetreNotation.decider(etat)
    local prop = FenetreNotation.propositionChoisie
    if not prop then
        return false
    end
    local ok, fait, raison = LrTasks.pcall(Notation.decider, prop.photo, etat, { raison = "Décidé dans la séance de notation" })
    if not ok or not fait then
        FenetreNotation.dire(tostring(ok and raison or fait), 'erreur')
        return false
    end
    FenetreNotation.dire(etat == 'ecartee' and "Proposition écartée : rien n'est posé dans Lightroom." or "Mise à vérifier : rien n'est posé dans Lightroom.", 'info')
    FenetreNotation.aRafraichir = true
    return true
end

-- Demandes à Claude -------------------------------------------------------------------------------

-- La ligne qui remplace « [Lightroom : photo active…] » dans la demande.
function FenetreNotation.contexte(seance, passe, photo)
    local texte = string.format("[Lightroom : séance de notation « %s », %s ; passe %d", tostring(seance.titre),
        compte(#(seance.photos or {}), "photo", "photos"), passe)
    if photo then
        texte = texte .. string.format(" ; photo choisie %s (%s)", tostring(photo.id), tostring(photo.nom))
    end
    return texte .. "]"
end

-- Envoie une demande dans la conversation de la séance (sans changer celle de la fenêtre Claude).
-- `passe` : la passe lancée ; sans elle, une question, avec la photo choisie dans le contexte.
function FenetreNotation.envoyer(texte, passe)
    local p = FenetreNotation.p
    if Moteur.travaille then
        FenetreNotation.dire("Claude travaille : attendez la fin, ou cliquez Arrêter.", 'erreur')
        return false
    end
    local s = FenetreNotation.seance
    if not s then
        FenetreNotation.dire("Ouvrez d'abord une séance.", 'erreur')
        return false
    end
    local photo
    if not passe and FenetreNotation.choisie and FenetreNotation.infoChoisie then
        photo = { id = FenetreNotation.choisie, nom = FenetreNotation.infoChoisie.nom }
    end
    local contexte = FenetreNotation.contexte(s, passe or tonumber(p.passe) or 1, photo)
    FenetreNotation.dire('', 'info')
    FenetreNotation.envoiEnCours = true
    FenetreNotation.majBoutons()
    FenetreNotation.defilement = 0
    LrTasks.startAsyncTask(function()
        -- La conversation de la séance se prend ici, dans la tâche (Moteur lit ses conversations).
        local appel, ok, raison = LrTasks.pcall(function()
            return Moteur.envoyer(texte, { conversation = FenetreNotation.conversation(s, true), contexte = contexte })
        end)
        FenetreNotation.envoiEnCours = false
        if not appel then
            ok, raison = false, tostring(ok)
        end
        if not ok and FenetreNotation.p then
            FenetreNotation.dire(raison or "Demande non envoyée.", 'erreur')
            -- La demande tapée revient dans le champ.
            if not passe and Texte.nettoyer(FenetreNotation.p.saisie) == '' then
                FenetreNotation.ignorerSaisie = true
                FenetreNotation.p.saisie = texte
                FenetreNotation.ignorerSaisie = false
            end
        end
        FenetreNotation.aRafraichirFil = true
        FenetreNotation.majBoutons()
    end)
    return true
end

-- Lancer la passe choisie : son message tout fait (Consignes.passes), avec les photos de la
-- séance et la passe. La passe 4, sans message (l'utilisateur seul), ne part pas.
function FenetreNotation.lancerPasse()
    local p = FenetreNotation.p
    if Moteur.travaille then
        FenetreNotation.dire("Claude travaille : lancez la passe quand il a fini.", 'erreur')
        return false
    end
    local s = FenetreNotation.seance
    if not s then
        FenetreNotation.dire("Ouvrez d'abord une séance.", 'erreur')
        return false
    end
    local n = tonumber(p.passe) or 1
    local passe = Consignes.passes[n]
    if not passe then
        return false
    end
    if not passe.message then
        FenetreNotation.dire(passe.seul, 'info')
        return false
    end
    if tonumber(s.passe) ~= n then
        LrTasks.pcall(Notation.choisirPasse, s.id, n)
        s.passe = n
    end
    return FenetreNotation.envoyer(passe.message(s), n)
end

-- Champ de demande (immediate = false) : Retour le valide, et un clic de bouton aussi, juste
-- avant l'action du bouton (constaté dans la fenêtre Claude). Un texte reçu part après un court
-- délai, sauf si un clic le suit : le bouton décide.
function FenetreNotation.saisieValidee(valeur)
    if FenetreNotation.ignorerSaisie or type(valeur) ~= 'string' or Texte.nettoyer(valeur) == '' then
        return
    end
    local jeton = {}
    FenetreNotation.envoiAuto = jeton
    LrTasks.startAsyncTask(function()
        LrTasks.sleep(FenetreNotation.DELAI_RETOUR)
        if FenetreNotation.envoiAuto ~= jeton or not FenetreNotation.ouverte or not FenetreNotation.p then
            return
        end
        FenetreNotation.envoiAuto = nil
        FenetreNotation.envoyerSaisie()
    end)
end

function FenetreNotation.annulerEnvoiAuto()
    FenetreNotation.envoiAuto = nil
end

function FenetreNotation.envoyerSaisie()
    local p = FenetreNotation.p
    if Moteur.travaille then
        FenetreNotation.dire("Claude travaille : attendez la fin, ou cliquez Arrêter.", 'erreur')
        return
    end
    local texte = p.saisie
    if Texte.nettoyer(texte) == '' then
        FenetreNotation.dire("Écrivez une demande avant d'envoyer.", 'erreur')
        return
    end
    FenetreNotation.ignorerSaisie = true
    p.saisie = ''
    FenetreNotation.ignorerSaisie = false
    FenetreNotation.envoyer(texte)
end

function FenetreNotation.arreter()
    if Moteur.travaille then
        Moteur.interrompre()
    end
end

-- Rouvre la fenêtre (collections relues), le texte du champ gardé.
function FenetreNotation.rouvrir()
    local p = FenetreNotation.p
    FenetreNotation.aRouvrir = true
    FenetreNotation.brouillon = p and p.saisie or nil
    FenetreNotation.sourceGardee = p and { portee = p.portee, collection = p.collection } or nil
    if FenetreNotation.controle and FenetreNotation.controle.close then
        FenetreNotation.controle.close()
    end
end

-- Construction ------------------------------------------------------------------------------------

-- Le clic d'un bouton valide aussi le champ de demande : il ne doit pas l'envoyer.
local function bouton(f, args)
    local action = args.action
    args.action = function(...)
        FenetreNotation.annulerEnvoiAuto()
        return action(...)
    end
    return f:push_button(args)
end

local function ligneFil(f, C, i, largeur)
    local icones = { place = 'overlapping', width = 16 }
    for _, ic in ipairs(ICONES) do
        icones[#icones + 1] = f:static_text { title = ic.glyphe, font = POLICES.texte, text_color = C[ic.couleur], visible = egal('i' .. i, ic.cle) }
    end
    local textes = { place = 'overlapping' }
    for _, st in ipairs(STYLES) do
        local genres = st.genres
        textes[#textes + 1] = f:static_text {
            title = bind('t' .. i), width = largeur, font = POLICES[st.police], text_color = C[st.couleur], truncation = 'tail',
            visible = bind { key = 'g' .. i, transform = function(v) return genres[v] == true end },
        }
    end
    return f:row { spacing = 4, f:column(icones), f:column(textes) }
end

-- Un texte en couleurs superposées (une variante par couleur d'état).
local function enCouleurs(f, C, cleTexte, cleCouleur, args)
    local variantes = { place = 'overlapping' }
    for _, couleur in ipairs(COULEURS_ETAT) do
        local v = {}
        for cle, valeur in pairs(args) do
            v[cle] = valeur
        end
        v.title = bind(cleTexte)
        v.text_color = C[couleur]
        v.visible = egal(cleCouleur, couleur)
        variantes[#variantes + 1] = f:static_text(v)
    end
    return f:column(variantes)
end

-- Une case de la planche : la vignette (ou son attente), le nom (clic : la fiche), la note et son
-- état.
local function case(f, C, k)
    local cote = FenetreNotation.CASE
    return f:column {
        spacing = 2,
        width = cote,
        f:column {
            place = 'overlapping',
            f:picture { value = bind('vignette' .. k), width = cote, height = cote, visible = bind('aVignette' .. k) },
            f:static_text { title = bind('attente' .. k), width = cote, height = cote, alignment = 'center', font = POLICES.petit,
                text_color = C.gris, visible = nonLie('aVignette' .. k) },
        },
        f:static_text { title = bind('nom' .. k), width = cote, truncation = 'middle', font = POLICES.petitGras,
            tooltip = "Cliquer pour voir sa fiche", mouse_down = function() FenetreNotation.cliquerCase(k) end },
        enCouleurs(f, C, 'etoiles' .. k, 'couleur' .. k, { font = POLICES.texte, width = cote, truncation = 'tail' }),
        f:static_text { title = bind('etatTexte' .. k), width = cote, truncation = 'tail', font = POLICES.petit, text_color = C.gris },
    }
end

-- Le bas de la fenêtre : activité de Claude, message d'erreur ou d'information.
local function bandeau(f, C, largeur)
    return f:column {
        place = 'overlapping',
        f:static_text { title = bind 'activite', font = POLICES.petit, text_color = C.gris, width = largeur, truncation = 'tail', visible = egal('bandeau', 'activite') },
        f:static_text { title = bind 'message', font = POLICES.petit, text_color = C.orange, width = largeur, truncation = 'tail', visible = egal('bandeau', 'erreur') },
        f:static_text { title = bind 'message', font = POLICES.petit, text_color = C.gris, width = largeur, truncation = 'tail', visible = egal('bandeau', 'info') },
    }
end

function FenetreNotation.largeur()
    return FenetreNotation.GAUCHE + FenetreNotation.CENTRE + FenetreNotation.FICHE + 4 * 14 + 2
end

function FenetreNotation.construire(f, p)
    local C = couleurs()
    local G, M, D = FenetreNotation.GAUCHE, FenetreNotation.CENTRE, FenetreNotation.FICHE
    local L = FenetreNotation.largeur()

    local entete = f:column {
        spacing = 6,
        f:row {
            spacing = 8,
            f:static_text { title = "Photos à noter", font = POLICES.gras },
            f:radio_button { title = "Sélection", value = bind 'portee', checked_value = 'selection' },
            f:radio_button { title = "Collection", value = bind 'portee', checked_value = 'collection' },
            f:popup_menu { value = bind 'collection', items = bind 'collections', width = 240, enabled = egal('portee', 'collection') },
            bouton(f, { title = "↻", tooltip = "Relire les collections du catalogue", action = FenetreNotation.rouvrir }),
            f:static_text { title = bind 'textePhotos', text_color = C.gris, width = 220, truncation = 'tail' },
            f:spacer { fill_horizontal = 1 },
            bouton(f, { title = "Ouvrir la séance", enabled = bind 'peutOuvrir', action = function() enTache(FenetreNotation.ouvrirSeance) end }),
        },
        f:row {
            spacing = 12,
            f:static_text { title = bind 'titreSeance', font = POLICES.titre, width = 420, truncation = 'tail' },
            f:static_text { title = bind 'resumeSeance', text_color = C.gris, width = L - 460, truncation = 'tail' },
        },
    }

    local passes = { spacing = 10 }
    for n = 1, FenetreNotation.PASSES do
        local passe = Consignes.passes[n]
        passes[#passes + 1] = f:column {
            spacing = 1,
            f:radio_button { title = passe.titre, value = bind 'passe', checked_value = n, enabled = bind 'peutChoisirPasse' },
            f:row {
                f:spacer { width = 18 },
                f:static_text { title = passe.question, font = POLICES.petit, text_color = C.gris, width = G - 22, height_in_lines = 2 },
            },
            -- La passe 4 (l'utilisateur seul) montre `seul` à la place des comptes : deux lignes.
            f:row {
                f:spacer { width = 18 },
                passe.seul and f:static_text { title = bind('comptes' .. n), font = POLICES.petit, width = G - 22, height_in_lines = 2 }
                    or f:static_text { title = bind('comptes' .. n), font = POLICES.petit, width = G - 22, truncation = 'tail' },
            },
        }
    end
    local gauche = f:column {
        spacing = 10,
        width = G,
        f:static_text { title = "Passes, une question chacune", font = POLICES.gras },
        f:column(passes),
        bouton(f, { title = bind 'titreLancer', enabled = bind 'peutLancer', width = G, action = function() enTache(FenetreNotation.lancerPasse) end }),
        f:spacer { height = 4 },
        f:group_box {
            title = "Rappel du standard",
            width = G,
            f:static_text { title = FenetreNotation.RAPPEL, font = POLICES.petit, text_color = C.gris, width = G - 24, height_in_lines = 10 },
        },
    }

    local rangees = { spacing = 10 }
    for r = 1, FenetreNotation.RANGEES do
        local rangee = { spacing = FenetreNotation.ESPACE_CASES }
        for k = 1, FenetreNotation.COLONNES do
            rangee[#rangee + 1] = case(f, C, (r - 1) * FenetreNotation.COLONNES + k)
        end
        rangees[#rangees + 1] = f:row(rangee)
    end
    local grille = { spacing = 0 }
    for i = 1, FenetreNotation.LIGNES_FIL do
        grille[#grille + 1] = ligneFil(f, C, i, M - 20)
    end
    local centre = f:column {
        spacing = 8,
        width = M,
        f:row {
            f:static_text { title = "Planche", font = POLICES.gras },
            f:spacer { fill_horizontal = 1 },
            bouton(f, { title = '◀', enabled = bind 'peutPagePrecedente', action = function() FenetreNotation.changerPage(-1) end }),
            f:static_text { title = bind 'pageTexte', font = POLICES.petit, alignment = 'center', width = 230, truncation = 'tail' },
            bouton(f, { title = '▶', enabled = bind 'peutPageSuivante', action = function() FenetreNotation.changerPage(1) end }),
        },
        f:column(rangees),
        f:separator { fill_horizontal = 1 },
        f:row {
            f:static_text { title = "Échange avec Claude", font = POLICES.gras },
            f:spacer { fill_horizontal = 1 },
            bouton(f, { title = '▲', enabled = bind 'peutMonter', action = function() FenetreNotation.defiler(FenetreNotation.LIGNES_FIL - 2) end }),
            bouton(f, { title = '▼', enabled = bind 'peutDescendre', action = function() FenetreNotation.defiler(-(FenetreNotation.LIGNES_FIL - 2)) end }),
        },
        f:column(grille),
    }

    local droite = f:column {
        spacing = 6,
        width = D,
        f:row {
            spacing = 4,
            f:static_text { title = bind 'ficheNom', font = POLICES.gras, width = D - 120, truncation = 'middle' },
            f:spacer { fill_horizontal = 1 },
            bouton(f, { title = '◀', enabled = bind 'peutPhotoPrecedente', action = function() FenetreNotation.photoVoisine(-1) end }),
            f:static_text { title = bind 'ficheRang', font = POLICES.petit, text_color = C.gris, alignment = 'center', width = 56 },
            bouton(f, { title = '▶', enabled = bind 'peutPhotoSuivante', action = function() FenetreNotation.photoVoisine(1) end }),
        },
        f:column {
            place = 'overlapping',
            f:picture { value = bind 'ficheImage', width = D, height = D, visible = bind 'aFicheImage' },
            f:static_text { title = bind 'ficheAttente', width = D, height = D, alignment = 'center', text_color = C.gris, visible = nonLie 'aFicheImage' },
        },
        f:static_text { title = bind 'fichePosee', width = D, truncation = 'tail' },
        enCouleurs(f, C, 'ficheProposee', 'ficheCouleur', { font = POLICES.gras, width = D, truncation = 'tail' }),
        f:static_text { title = bind 'ficheDecision', font = POLICES.petit, text_color = C.gris, width = D, truncation = 'tail' },
        f:row {
            bouton(f, { title = bind 'titreAccepter', enabled = bind 'peutAccepter', width = 170, action = function() enTache(FenetreNotation.accepter) end }),
            bouton(f, { title = "Changer…", enabled = bind 'peutChanger', action = function() enTache(FenetreNotation.changer) end }),
        },
        f:row {
            bouton(f, { title = "À vérifier", enabled = bind 'peutVerifier', action = function() enTache(FenetreNotation.decider, 'a_verifier') end }),
            bouton(f, { title = "Écarter", enabled = bind 'peutEcarter', action = function() enTache(FenetreNotation.decider, 'ecartee') end }),
        },
        f:separator { fill_horizontal = 1 },
        f:static_text { title = "Critères, du plus lourd au plus léger", font = POLICES.petitGras },
        f:static_text { title = bind 'ficheCriteres', font = POLICES.petit, width = D, height_in_lines = 7 },
        f:static_text { title = bind 'fichePlafond', font = POLICES.petit, width = D, truncation = 'tail' },
        f:static_text { title = bind 'ficheRaison', font = POLICES.petit, text_color = C.gris, width = D, height_in_lines = 3 },
    }

    local filtres = { spacing = 6, f:static_text { title = "Afficher :" } }
    for _, filtre in ipairs(FenetreNotation.FILTRES) do
        filtres[#filtres + 1] = f:radio_button { title = filtre[2], value = bind 'filtre', checked_value = filtre[1] }
    end
    local bas = f:column {
        spacing = 6,
        f:row {
            spacing = 14,
            bouton(f, { title = bind 'titreToutAccepter', enabled = bind 'peutToutAccepter', width = 230, action = function() enTache(FenetreNotation.toutAccepter) end }),
            f:row(filtres),
            f:spacer { fill_horizontal = 1 },
            bandeau(f, C, 360),
        },
        f:row {
            spacing = 8,
            f:edit_field { value = bind 'saisie', immediate = false, width = L - 120, height_in_lines = 2, enabled = bind 'aSeance',
                placeholder_string = "Demander à Claude… (par exemple : « Pourquoi pas 4 ★ pour la 7 ? »)" },
            f:column {
                spacing = 4,
                bouton(f, { title = "Envoyer", enabled = bind 'peutEnvoyer', width = 100, action = FenetreNotation.envoyerSaisie }),
                bouton(f, { title = "Arrêter", enabled = bind 'peutArreter', width = 100, action = FenetreNotation.arreter }),
            },
        },
    }

    return f:column {
        bind_to_object = p,
        margin = 14,
        spacing = 10,
        entete,
        f:separator { fill_horizontal = 1 },
        f:row {
            spacing = 14,
            gauche,
            f:separator { fill_vertical = 1 },
            centre,
            f:separator { fill_vertical = 1 },
            droite,
        },
        f:separator { fill_horizontal = 1 },
        bas,
    }
end

-- Boucle -----------------------------------------------------------------------------------------

-- Un tour de la boucle (toutes les 0,25 s) : ce que le registre, le moteur ou Lightroom ont changé ;
-- toutes les 2 s, la planche relue (notes posées à la main dans Lightroom).
function FenetreNotation.tour(tic)
    local p = FenetreNotation.p
    if not p then
        return
    end
    if FenetreNotation.aRecalculer then
        FenetreNotation.aRecalculer = false
        local ok, erreur = LrTasks.pcall(FenetreNotation.recalculerSource)
        if not ok then
            Journal.noter("Séance de notation :", tostring(erreur))
        end
    end
    if FenetreNotation.aRafraichir or Notation.version ~= FenetreNotation.versionVue or (tic or 0) % 8 == 0 then
        FenetreNotation.aRafraichir = false
        local ok, erreur = LrTasks.pcall(FenetreNotation.rafraichir)
        if not ok then
            Journal.noter("Séance de notation :", tostring(erreur))
        end
        FenetreNotation.aRafraichirFil = true
    end
    if FenetreNotation.aRafraichirFil then
        FenetreNotation.aRafraichirFil = false
        LrTasks.pcall(FenetreNotation.rafraichirFil)
    end
    -- Sans conversation de séance (false, pas nil) : un travail en cours est dans la fenêtre Claude.
    local c = FenetreNotation.conversation(FenetreNotation.seance, false)
    poser(p, 'activite', Moteur.texteTravail(math.floor((tic or 0) / 2), c or false))
    if p.travaille ~= (Moteur.travaille == true) then
        FenetreNotation.aRafraichirFil = true
    end
    FenetreNotation.majBoutons()
end

-- Une seule boucle par ouverture (la génération change à chaque ouverture).
function FenetreNotation.boucle()
    local generation = FenetreNotation.generation
    local tic = 0
    while FenetreNotation.ouverte and FenetreNotation.generation == generation do
        tic = tic + 1
        FenetreNotation.tour(tic)
        LrTasks.sleep(0.25)
    end
end

-- Ouverture -------------------------------------------------------------------------------------

-- options : portee ('selection' ou 'collection'), collection (identifiant). La fenêtre déjà
-- ouverte passe devant, la source changée.
function FenetreNotation.afficher(options)
    options = type(options) == 'table' and options or {}
    if FenetreNotation.ouverte then
        local p = FenetreNotation.p
        if p and (options.portee == 'selection' or options.portee == 'collection') then
            p.portee = options.portee
            for _, item in ipairs(p.collections or {}) do
                if options.collection ~= nil and item.value == options.collection then
                    p.collection = item.value
                end
            end
        end
        if FenetreNotation.controle and FenetreNotation.controle.toFront then
            FenetreNotation.controle.toFront()
        end
        return
    end
    FenetreNotation.ouverte = true
    local reouverture = FenetreNotation.aRouvrir
    FenetreNotation.aRouvrir = false
    if reouverture and options.portee == nil and FenetreNotation.sourceGardee then
        options = FenetreNotation.sourceGardee
    end
    FenetreNotation.sourceGardee = nil
    FenetreNotation.generation = FenetreNotation.generation + 1
    LrFunctionContext.postAsyncTaskWithContext('Claude · séance de notation', function(context)
        context:addFailureHandler(function(_, erreur)
            FenetreNotation.ouverte = false
            FenetreNotation.p = nil
            Moteur.desabonner('seance')
            Notation.desabonner('seance')
            Journal.noter("Fenêtre Séance de notation :", tostring(erreur))
            LrDialogs.message("La fenêtre Séance de notation n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)
        Moteur.charger()
        if not reouverture then
            -- Les vignettes d'une ouverture précédente : redemandées (Lightroom les garde en cache).
            Fichiers.supprimer(FenetreNotation.dossier())
            FenetreNotation.vignettes = {}
        end
        FenetreNotation.idSeance = nil
        FenetreNotation.seance = nil
        FenetreNotation.props = {}
        FenetreNotation.propositionChoisie = nil
        FenetreNotation.infoChoisie = nil
        FenetreNotation.conversationAffichee = nil
        FenetreNotation.cacheFil = {}
        FenetreNotation.defilement = 0
        FenetreNotation.enEcriture = false
        FenetreNotation.envoiEnCours = false
        FenetreNotation.vignettesEnCours = false
        FenetreNotation.envoiAuto = nil

        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
        p.portee = (options.portee == 'collection' or options.portee == 'selection') and options.portee or 'selection'
        p.collections = Publication.collections()
        if #p.collections == 0 then
            p.collections = { { title = "Aucune collection", value = 0 } }
        end
        p.collection = p.collections[1].value
        for _, item in ipairs(p.collections) do
            if options.collection ~= nil and item.value == options.collection then
                p.collection = item.value
            end
        end
        p.textePhotos, p.titreSeance, p.resumeSeance = '', '', ''
        p.passe = 1
        p.titreLancer = "Lancer la passe 1"
        for n = 1, FenetreNotation.PASSES do
            p['comptes' .. n] = ''
        end
        p.pageTexte = ''
        -- Une image « aucun aperçu » du côté de la case, cachée tant que la vignette manque.
        local vide = Chemins.ressource('vide-' .. FenetreNotation.CASE .. '.png')
        for k = 1, FenetreNotation.CASES do
            p['vignette' .. k] = vide
            p['aVignette' .. k] = false
            p['attente' .. k] = ''
            p['nom' .. k] = ''
            p['couleur' .. k] = 'gris'
            p['etoiles' .. k] = ''
            p['etatTexte' .. k] = ''
        end
        for i = 1, FenetreNotation.LIGNES_FIL do
            p['t' .. i] = ''
            p['g' .. i] = 'vide'
            p['i' .. i] = ''
        end
        p.ficheNom, p.ficheRang, p.ficheAttente, p.fichePosee, p.ficheProposee, p.ficheDecision = '', '', '', '', '', ''
        p.ficheImage = Chemins.ressource('vide-' .. FenetreNotation.FICHE .. '.png')
        p.aFicheImage = false
        p.ficheCouleur = 'gris'
        p.ficheCriteres, p.fichePlafond, p.ficheRaison = '', '', ''
        p.titreAccepter = "Accepter"
        p.titreToutAccepter = "Tout accepter"
        p.filtre = 'toutes'
        p.saisie = ''
        p.message, p.genreMessage, p.bandeau, p.activite = '', 'info', 'vide', ''
        for _, cle in ipairs({ 'travaille', 'libre', 'aSeance', 'peutOuvrir', 'peutChoisirPasse', 'peutLancer', 'peutAccepter', 'peutChanger',
            'peutVerifier', 'peutEcarter', 'peutToutAccepter', 'peutPagePrecedente', 'peutPageSuivante', 'peutPhotoPrecedente',
            'peutPhotoSuivante', 'peutEnvoyer', 'peutArreter', 'peutMonter', 'peutDescendre' }) do
            p[cle] = false
        end
        FenetreNotation.p = p

        -- Un clic de bouton radio ou un choix de menu n'envoie pas la demande tapée.
        for _, cle in ipairs({ 'portee', 'collection' }) do
            p:addObserver(cle, function()
                FenetreNotation.annulerEnvoiAuto()
                FenetreNotation.aRecalculer = true
            end)
        end
        p:addObserver('filtre', function()
            FenetreNotation.annulerEnvoiAuto()
            FenetreNotation.page = 1
            FenetreNotation.aRafraichir = true
        end)
        p:addObserver('passe', function(_, _, n)
            FenetreNotation.annulerEnvoiAuto()
            local s = FenetreNotation.seance
            if s and tonumber(s.passe) ~= tonumber(n) then
                enTache(Notation.choisirPasse, s.id, n)
            end
            FenetreNotation.aRafraichir = true
        end)
        p:addObserver('saisie', function(_, _, valeur) FenetreNotation.saisieValidee(valeur) end)
        if reouverture and type(FenetreNotation.brouillon) == 'string' then
            FenetreNotation.ignorerSaisie = true
            p.saisie = FenetreNotation.brouillon
            FenetreNotation.ignorerSaisie = false
        end
        FenetreNotation.brouillon = nil

        local contenu = FenetreNotation.construire(f, p)
        FenetreNotation.recalculerSource()
        FenetreNotation.rafraichir()
        FenetreNotation.rafraichirFil()
        Notation.abonner('seance', function() FenetreNotation.aRafraichir = true end)
        Moteur.abonner('seance', function() FenetreNotation.aRafraichirFil = true end)
        LrTasks.startAsyncTask(FenetreNotation.boucle)
        LrDialogs.presentFloatingDialog(_PLUGIN, {
            title = "Claude · Séance de notation",
            contents = contenu,
            save_frame = 'DeveloppeurNotation',
            blockTask = true,
            onShow = function(controle) FenetreNotation.controle = controle end,
            selectionChangeObserver = function() FenetreNotation.aRecalculer = true end,
            windowWillClose = function()
                FenetreNotation.ouverte = false
                FenetreNotation.annulerEnvoiAuto()
                FenetreNotation.controle = nil
                Moteur.desabonner('seance')
                Notation.desabonner('seance')
            end,
        })
        -- Au cas où blockTask ne bloquerait pas : garder le contexte (et la table) en vie.
        while FenetreNotation.ouverte do
            LrTasks.sleep(0.5)
        end
        FenetreNotation.p = nil
        if FenetreNotation.aRouvrir then
            LrTasks.startAsyncTask(FenetreNotation.afficher)
        else
            Fichiers.supprimer(FenetreNotation.dossier())
            FenetreNotation.vignettes = {}
        end
    end)
end

return FenetreNotation
