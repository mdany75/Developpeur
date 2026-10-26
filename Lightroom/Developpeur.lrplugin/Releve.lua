-- Releve.lua : le relevé du Suivi (correctif 1.3.7, décidé avec Dany le 25 octobre 2026 ; contrat
-- figé dans Tests/Contrats/suivi.json), rangé dans suivi.json (à côté de carnet.json), à part du
-- catalogue : rien n'y est écrit dans le catalogue, tout y est lu. (Suivi.lua est la fenêtre de la
-- liaison, d'où ce nom.) Deux choses :
--
--   1. Le relevé : toute photo que la fenêtre Claude voit (la photo active et la sélection, à chaque
--      changement et à chaque ouverture : Fenetre.suivreSelection, Fenetre.afficher) ou que la
--      Demande rapide voit (FenetreRapide.suivreSelection, FenetreRapide.afficher), seule ou en
--      groupe, entre par son original (une copie virtuelle compte pour lui, une seule fois : sa vue
--      s'ajoute à `vues`), sauf les vidéos et les photos de « Développeur › Essais »
--      (Carnet.estPhotoDEssai : elle ou son original). D'une sélection, les MAX_SELECTION premières
--      photos seulement (le reste est dit au journal). Une autre photo active dans le même groupe ne
--      revoit que la photo active. Pas de rattrapage : le Suivi part de zéro à l'installation. La
--      note, le drapeau et « retouchée par Claude » sont ceux de la famille (l'original et ses
--      copies virtuelles, sans celles des Essais), relus à chaque vue (lectures groupées du
--      catalogue) et par Releve.reclasser (la fenêtre Suivi, à son ouverture).
--   2. La file d'analyse : ce sont les entrées sans analyse (elle reprend d'elle-même après une
--      fermeture de Lightroom). Une seule tâche (Releve.vider, lancée par Releve.relancer depuis la
--      boucle de la fenêtre Claude et celle de la Demande rapide) range les vues, puis analyse par
--      lots de LOT_ANALYSE : la vignette de l'original du cache de Lightroom (Vignettes.demander, à
--      TAILLE_VIGNETTE), redressée (Images.redresser), mesurée par le connecteur
--      (`mcp-developpeur --analyser`, sous l'alarme de perl comme --focus : Images.lireFocus), sans
--      Claude ni jetons. La photo active nouvellement vue passe en tête. L'analyse attend pendant que
--      Claude travaille (Moteur.travaille) ou que la liaison sert (Lightroom.liaisonOccupee : Claude
--      Desktop, Claude Code en terminal, la recette) ; les vues, elles, se rangent quand même (des
--      lectures du catalogue : une photo que Dany parcourt pendant une Retouche pro compte), et
--      celles qui s'accumulent pendant un lot se fondent en une seule au-delà de MAX_EN_ATTENTE,
--      sans en perdre une photo. Une analyse n'est jamais refaite après une édition (les défauts
--      disent la prise de vue ; une retouche les cacherait) ; une erreur compte
--      un essai, réessayé DELAI_REESSAI secondes plus tard, puis l'entrée est abandonnée au
--      ESSAIS_ANALYSE-ième (elle ne revient plus). Une réponse dont `regles` dépasse celle d'une
--      analyse la fait refaire (versions à venir).
--
-- Le Suivi ne tourne que dans Lightroom : Init.lua l'allume (Releve.allumer), Arret.lua l'éteint
-- (Releve.eteindre : le module désactivé, rechargé ou déchargé ; après un rechargement, l'ancienne
-- instance continue de tourner, et sa tâche s'arrête après son attente sans plus jamais écrire le
-- relevé, que la nouvelle tient). Les suites de tests ne chargent pas Init.lua, sauf leurs essais
-- d'Init, qui l'éteignent ensuite : rien n'y tourne, sauf dans essais-releve.lua, qui l'allume.
--
-- Format 1 :
--   { format = 1, catalogues = { [chemin du catalogue] = { photos = { ['<id de l'original>'] =
--     entrée } } } }
--   entrée : { original (localIdentifier), uuid, fichier, ajout (os.time de la première vue),
--     ajout_le ('AAAA-MM-JJ HH:MM', heure locale), vu (os.time de la dernière vue), vues = { { id,
--     uuid, copie_virtuelle, fichier, le } } (dans l'ordre de leur première vue, MAX_VUES au plus),
--     prise_de_vue = { le ('AAAA-MM-JJ HH:MM'), appareil, objectif, focale (mm), ouverture, vitesse,
--     iso } (une valeur que Lightroom ne donne pas manque), note (0 à 5), drapeau ('retenue',
--     'aucun', 'rejetee'), retouchee_par_claude, classement_le, analyse }
--   analyse : absente (en file) ; réussie { le, regles, cherches = { codes }, defauts = { codes } } ;
--     manquée { le, erreur, essais, abandonnee? }
-- Les codes sont ceux de PriseDeVue.defauts (connecteur) : aucune liste de défauts dans ce module.
-- Au-delà de MAX_ORIGINAUX dans un catalogue, les entrées vues le moins récemment (vu, puis l'id)
-- sortent. Les écritures, vues et analyses comprises, sont espacées d'au moins DELAI_ECRITURE
-- secondes (à 20 000 originaux, chacune prend de l'ordre d'une seconde sans rendre la main), sauf
-- au début d'une pause (Claude se met au travail) et avant un dessin de la fenêtre Suivi
-- (Releve.ecrire, avant --graphiques) ; à la fin de la file, la tâche attend le tour de la dernière
-- (DELAI_ECRITURE secondes au plus, en rangeant les vues qui arrivent). Un fichier illisible (ou
-- d'un autre format) est mis de côté avant la première écriture (suivi-illisible-<date>.json,
-- jamais écrasé).
-- Le connecteur le lit (--graphiques), jamais ne l'écrit ; Fichiers.ecrire l'écrit d'un coup
-- (jamais à moitié écrit). Tout ce qui sort vers une vue est une copie neuve, sans métatable.

local LrDate = import 'LrDate'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

require 'Compat'
local Carnet = require 'Carnet'
local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Images = require 'Images'
local Journal = require 'Journal'
local Json = require 'Json'
local Lightroom = require 'Lightroom'
local Photos = require 'Photos'
local Texte = require 'Texte'
local Vignettes = require 'Vignettes'

local Releve = {
    -- Allumé par Init.lua (dans Lightroom seulement), éteint par Arret.lua.
    allume = false,
    -- Éteint par Arret.lua (Releve.eteindre) : cette instance n'écrit plus le relevé.
    arrete = false,
    -- +1 à chaque écriture du relevé : la fenêtre Suivi compare pour savoir s'il faut redessiner.
    version = 0,
    -- La tâche qui vide la file tourne (une seule à la fois).
    enCours = false,
    -- Les vues à ranger, dans leur ordre : { photos (de Lightroom, la photo active d'abord), le }.
    aVoir = {},
    -- Prochaine heure (os.time) où regarder la file sans vue nouvelle (0 : dès que possible ; une
    -- analyse à réessayer, ou un connecteur absent).
    prochaineVerification = 0,
    -- Les règles de l'analyse rendues par le connecteur (regles de --analyser), nil avant la première
    -- réponse de la séance.
    regles = nil,
    -- La dernière erreur de la tâche (une vue non rangée, un lot non analysé, la tâche arrêtée),
    -- aussi dite au journal ; nil sans erreur (diagnostic).
    derniereErreur = nil,
    -- Des analyses rangées en mémoire, pas encore écrites (DELAI_ECRITURE), et l'heure (os.time) de
    -- la dernière écriture.
    aEcrire = false,
    ecritLe = nil,
}

Releve.FORMAT = 1
Releve.MAX_ORIGINAUX = 20000
Releve.MAX_VUES = 20
Releve.MAX_SELECTION = 1000
Releve.LOT_ANALYSE = 10
Releve.ESSAIS_ANALYSE = 3
-- Vignette demandée à Lightroom pour l'analyse (Detail.side du connecteur, 1 024 px).
Releve.TAILLE_VIGNETTE = 1024
-- Alarme de perl pour --analyser (secondes) : dix vignettes mesurées, Vision deux à la fois.
Releve.ALARME = 60
-- Attente entre deux regards pendant que Claude travaille (secondes).
Releve.PAUSE = 2
-- Délai avant de réessayer une analyse manquée (une vignette de 256 px juste après une retouche :
-- Lightroom refait l'aperçu ensuite), et avant de regarder de nouveau un connecteur absent.
Releve.DELAI_REESSAI = 600
Releve.DELAI_VERIFICATION = 60
-- Écart minimal entre deux écritures du fichier, vues et analyses comprises (secondes) : à 20 000
-- originaux, il fait une dizaine de mégaoctets (13,6 Mo mesurés, 0,42 s pour la copie et
-- Json.encode sous luajit -joff ; plus dans Lightroom), écrits sans rendre la main à Lightroom.
-- Dany qui parcourt ses photos aux flèches en voit une toutes les 2 s : une écriture chacune figeait
-- Lightroom à chaque photo.
Releve.DELAI_ECRITURE = 20
-- Vues en attente au-delà desquelles elles se fondent en une seule (la tâche analyse un lot, ou ne
-- tourne pas encore) : aucune photo perdue (MAX_SELECTION au plus).
Releve.MAX_EN_ATTENTE = 20
-- Photos par lecture groupée du catalogue.
Releve.LOT_LECTURE = 500
-- Les codes rendus par le connecteur : des mots, au plus tant par analyse.
Releve.MAX_CODES = 20
Releve.LONGUEUR_CODE = 40
-- Ce que le module dit d'un connecteur muet (contrat : erreurs._note).
Releve.PAS_DE_REPONSE = "Le connecteur n'a pas répondu à temps"

-- Drapeau (pickStatus : 1, 0 ou −1), en mots, comme Lightroom.photos.
local DRAPEAUX = { [1] = 'retenue', [0] = 'aucun', [-1] = 'rejetee' }

-- Listes : des tableaux JSON, même vides, dans le fichier.
local LISTES = { vues = true, cherches = true, defauts = true }

local CHAMPS_MEMOIRE = { 'retoucheeParClaude', 'proprietaireMemoire' }

local registre

local q = Texte.shell

function Releve.fichier()
    return LrPathUtils.child(Chemins.racine(), 'suivi.json')
end

-- Copie neuve, sans métatable ni Json.null.
local function copie(valeur)
    if valeur == Json.null then
        return nil
    end
    if type(valeur) ~= 'table' then
        return valeur
    end
    local t = {}
    for cle, element in pairs(valeur) do
        t[cle] = copie(element)
    end
    return t
end

-- Copie pour Json.encode : les listes marquées tableaux, même vides.
local function versJson(valeur, cle)
    if type(valeur) ~= 'table' or valeur == Json.null then
        return valeur
    end
    local t = {}
    for k, element in pairs(valeur) do
        t[k] = versJson(element, k)
    end
    if LISTES[cle] then
        return Json.tableau(t)
    end
    return t
end

local function cleDe(id)
    return tostring(tonumber(id) or id)
end

local function texte(valeur)
    if type(valeur) == 'string' and valeur ~= '' then
        return valeur
    end
    return nil
end

local function nombre(valeur)
    local n = tonumber(valeur)
    if n and n == n and n ~= math.huge and n ~= -math.huge then
        return n
    end
    return nil
end

-- « AAAA-MM-JJ HH:MM » à l'heure locale. Une date de Lightroom (dateTimeOriginal, secondes depuis
-- 2001) passe par timeToUserFormat (timeToW3CDate donne l'UTC, constaté pour le jour de
-- Bibliotheque ; comme Carnet.datesPrise) ; une heure du module (os.time, secondes Unix : ajout,
-- vu), par os.date (Compat).
local FORMAT_DATE = '%Y-%m-%d %H:%M'

local function dateValide(ok, le)
    if ok and type(le) == 'string' and le:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$') then
        return le
    end
    return nil
end

local function datePrise(t)
    t = tonumber(t)
    return t and dateValide(pcall(LrDate.timeToUserFormat, t, FORMAT_DATE)) or nil
end

local function dateDuModule(t)
    t = tonumber(t)
    return t and dateValide(pcall(os.date, FORMAT_DATE, t)) or nil
end

-- Les codes d'une liste relue (du fichier ou du connecteur) : des mots, dans leur ordre, sans
-- doublon.
local function codes(liste)
    local propre, vus = {}, {}
    for _, c in ipairs(type(liste) == 'table' and liste or {}) do
        if type(c) == 'string' and #c <= Releve.LONGUEUR_CODE and c:match('^[%a_]+$') and not vus[c] and #propre < Releve.MAX_CODES then
            propre[#propre + 1] = c
            vus[c] = true
        end
    end
    return propre
end

-- Relecture -----------------------------------------------------------------------------------

local function normaliserVues(v)
    local propre = {}
    for _, vue in ipairs(type(v) == 'table' and v or {}) do
        if type(vue) == 'table' and nombre(vue.id) and #propre < Releve.MAX_VUES then
            propre[#propre + 1] = { id = nombre(vue.id), uuid = texte(vue.uuid), copie_virtuelle = vue.copie_virtuelle == true,
                fichier = texte(vue.fichier), le = nombre(vue.le) or 0 }
        end
    end
    return propre
end

local function normaliserPrise(p)
    if type(p) ~= 'table' then
        return {}
    end
    return { le = texte(p.le), appareil = texte(p.appareil), objectif = texte(p.objectif), focale = nombre(p.focale),
        ouverture = texte(p.ouverture), vitesse = texte(p.vitesse), iso = nombre(p.iso) }
end

local function normaliserAnalyse(a)
    if type(a) ~= 'table' then
        return nil
    end
    if type(a.cherches) == 'table' then
        return { le = nombre(a.le) or 0, regles = nombre(a.regles), cherches = codes(a.cherches), defauts = codes(a.defauts) }
    end
    if texte(a.erreur) then
        return { le = nombre(a.le) or 0, erreur = a.erreur, essais = math.max(1, math.floor(nombre(a.essais) or 1)),
            abandonnee = a.abandonnee == true or nil }
    end
    return nil
end

local function normaliserEntree(e, cle)
    if type(e) ~= 'table' then
        return nil
    end
    local original = nombre(e.original) or nombre(cle)
    if not original or not texte(e.uuid) then
        return nil
    end
    local note = math.floor(nombre(e.note) or 0)
    return {
        original = original, uuid = e.uuid, fichier = texte(e.fichier), ajout = nombre(e.ajout) or 0, ajout_le = texte(e.ajout_le),
        vu = nombre(e.vu) or nombre(e.ajout) or 0, vues = normaliserVues(e.vues), prise_de_vue = normaliserPrise(e.prise_de_vue),
        note = math.max(0, math.min(5, note)), drapeau = (e.drapeau == 'retenue' or e.drapeau == 'rejetee') and e.drapeau or 'aucun',
        retouchee_par_claude = e.retouchee_par_claude == true, classement_le = nombre(e.classement_le),
        analyse = normaliserAnalyse(e.analyse),
    }
end

local function vide()
    return { catalogues = {} }
end

-- Registre relu du fichier : des tables neuves, des clés d'original en texte (les clés « _note »
-- et ce que le module n'écrit pas sont oubliés).
local function normaliser(r)
    local propre = vide()
    for chemin, c in pairs(type(r.catalogues) == 'table' and r.catalogues or {}) do
        if texte(chemin) and type(c) == 'table' then
            local photos = {}
            for cle, e in pairs(type(c.photos) == 'table' and c.photos or {}) do
                local entree = normaliserEntree(e, cle)
                if entree then
                    photos[cleDe(entree.original)] = entree
                end
            end
            propre.catalogues[chemin] = { photos = photos }
        end
    end
    return propre
end

local function charger()
    if registre then
        return registre
    end
    local fichier = Releve.fichier()
    local contenu = Fichiers.lire(fichier)
    local ok, r = pcall(function() return contenu and Json.decode(contenu) end)
    if ok and type(r) == 'table' and tonumber(r.format) == Releve.FORMAT then
        registre = normaliser(r)
    else
        registre = vide()
        -- Un fichier présent mais illisible, ou d'un autre format : mis de côté avant d'écrire (un
        -- fichier vide ne garde rien).
        registre.illisible = Fichiers.existe(fichier) and contenu ~= ''
    end
    return registre
end

-- Pour les essais : oublie le registre chargé, la file et les vues à ranger (relus du fichier à la
-- prochaine lecture).
function Releve.oublier()
    registre = nil
    Releve.aVoir = {}
    Releve.cleVue, Releve.groupeVu, Releve.aRevoir, Releve.tete = nil, nil, false, nil
    Releve.file, Releve.rangs, Releve.sansRefaire = nil, nil, nil
    Releve.prochaineVerification, Releve.regles, Releve.connecteurAbsentDit, Releve.derniereErreur = 0, nil, nil, nil
    Releve.aEcrire, Releve.ecritLe, Releve.arrete = false, nil, false
end

local function cheminCatalogue()
    local ok, chemin = LrTasks.pcall(function()
        local cat = Photos.catalogue()
        return cat and cat:getPath()
    end)
    return ok and texte(chemin) or nil
end

-- La table du catalogue de ce chemin (créée avec `creer`).
local function tableDu(chemin, creer)
    local r = charger()
    local c = r.catalogues[chemin]
    if not c then
        c = { photos = {} }
        if creer then
            r.catalogues[chemin] = c
        end
    end
    return c
end

-- Au-delà de MAX_ORIGINAUX, les entrées vues le moins récemment (vu, puis l'id) sortent.
local function elaguer(c)
    local entrees = {}
    for cle, e in pairs(c.photos) do
        entrees[#entrees + 1] = { cle = cle, vu = tonumber(e.vu) or 0, id = tonumber(cle) or 0 }
    end
    if #entrees <= Releve.MAX_ORIGINAUX then
        return 0
    end
    table.sort(entrees, function(a, b)
        if a.vu ~= b.vu then
            return a.vu < b.vu
        end
        return a.id < b.id
    end)
    local sorties = #entrees - Releve.MAX_ORIGINAUX
    for i = 1, sorties do
        c.photos[entrees[i].cle] = nil
    end
    return sorties
end

-- Le nom de la copie mise de côté, jamais celui d'un fichier qui existe déjà.
local function nomDeCote()
    local base = 'suivi-illisible-' .. tostring(os.time())
    local nom, n = base .. '.json', 1
    while Fichiers.existe(LrPathUtils.child(Chemins.racine(), nom)) do
        n = n + 1
        nom = base .. '-' .. n .. '.json'
    end
    return LrPathUtils.child(Chemins.racine(), nom)
end

-- Écrit le registre entier (tous les catalogues). Rend vrai, ou faux et la raison. Jamais après
-- Releve.eteindre : le fichier est alors à la nouvelle instance du module (un rechargement) ; ce qui
-- n'est pas écrit se refait (une analyse revient en file, la vue suivante se range).
local function enregistrer()
    if Releve.arrete then
        return false, "Suivi éteint"
    end
    local r = charger()
    local fichier = Releve.fichier()
    if r.illisible and Fichiers.existe(fichier) then
        local aCote = nomDeCote()
        LrTasks.pcall(LrFileUtils.move, fichier, aCote)
        if Fichiers.existe(fichier) or not Fichiers.existe(aCote) then
            Journal.noter("Suivi illisible non mis de côté : rien n'est écrit dans", fichier)
            return false, "suivi.json illisible, laissé tel quel"
        end
        Journal.noter("Suivi illisible mis de côté :", aCote)
    end
    r.illisible = nil
    for chemin, c in pairs(r.catalogues) do
        local sorties = elaguer(c)
        if sorties > 0 then
            Journal.noter(string.format("Suivi : %d original(aux) vu(s) le moins récemment retiré(s) du relevé de %s (%d au plus)",
                sorties, chemin, Releve.MAX_ORIGINAUX))
        end
    end
    local ok, erreur = pcall(Fichiers.ecrire, fichier, Json.encode({ format = Releve.FORMAT, catalogues = versJson(r.catalogues) }))
    Releve.version = Releve.version + 1
    Releve.aEcrire, Releve.ecritLe = false, os.time()
    if not ok then
        Journal.noter("Suivi non enregistré :", tostring(erreur))
        return false, tostring(erreur)
    end
    return true
end

-- Vrai quand une écriture attend et que la dernière a DELAI_ECRITURE secondes.
local function ecritureDue()
    return Releve.aEcrire and os.time() - (Releve.ecritLe or 0) >= Releve.DELAI_ECRITURE
end

-- Une vue ou une analyse rangée : le fichier s'écrit si le dernier écrit a DELAI_ECRITURE secondes,
-- sinon à la prochaine écriture, au début d'une pause ou à la fin de la file (Releve.vider).
local function ecrireBientot()
    Releve.aEcrire = true
    if ecritureDue() then
        enregistrer()
    end
end

-- Écrit tout de suite ce qui attend son tour (DELAI_ECRITURE) : la fenêtre Suivi, avant
-- --graphiques, qui lit le fichier. Rend vrai si le fichier est écrit.
function Releve.ecrire()
    if not Releve.aEcrire then
        return false
    end
    return (enregistrer()) == true
end

-- Lectures (copies neuves) --------------------------------------------------------------------

-- Les entrées du catalogue ouvert, triées par identifiant de l'original.
function Releve.entrees()
    local c = tableDu(cheminCatalogue() or '', false)
    local cles = {}
    for cle in pairs(c.photos) do
        cles[#cles + 1] = cle
    end
    table.sort(cles, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    local liste = {}
    for _, cle in ipairs(cles) do
        liste[#liste + 1] = copie(c.photos[cle])
    end
    return liste
end

-- L'entrée d'un original du catalogue ouvert ; nil s'il n'est pas au relevé.
function Releve.entree(idOriginal)
    if idOriginal == nil then
        return nil
    end
    return copie(tableDu(cheminCatalogue() or '', false).photos[cleDe(idOriginal)])
end

-- Nombre d'originaux au relevé du catalogue ouvert, et combien sont en file (diagnostic).
function Releve.nombre()
    local n, enFile = 0, 0
    for _, e in pairs(tableDu(cheminCatalogue() or '', false).photos) do
        n = n + 1
        if not e.analyse or (e.analyse.erreur and not e.analyse.abandonnee) then
            enFile = enFile + 1
        end
    end
    return n, enFile
end

-- Lectures groupées du catalogue -------------------------------------------------------------------

-- Les métadonnées de ces photos, par lots de LOT_LECTURE : batchGetRawMetadata,
-- batchGetFormattedMetadata et batchGetPropertyForPlugin (SDK 3.0), comme Photos.decrireTout ;
-- une photo qu'une lecture groupée ne rend pas se lit une à une (une clé refusée ne gêne pas les
-- autres). Rend, pour chaque photo dans l'ordre, { brut = {}, formate = {}, champ = {} } ; un texte
-- formaté vide vaut nil.
local function lireGroupe(photos, brutes, formatees, champs)
    local lus = {}
    local cat = Photos.catalogue()
    for debut = 1, #photos, Releve.LOT_LECTURE do
        local morceau = {}
        for i = debut, math.min(#photos, debut + Releve.LOT_LECTURE - 1) do
            morceau[#morceau + 1] = photos[i]
        end
        local okB, b, okF, f, okM, m = false, nil, false, nil, false, nil
        if brutes then
            okB, b = LrTasks.pcall(cat.batchGetRawMetadata, cat, morceau, brutes)
        end
        if formatees then
            okF, f = LrTasks.pcall(cat.batchGetFormattedMetadata, cat, morceau, formatees)
        end
        if champs then
            okM, m = LrTasks.pcall(cat.batchGetPropertyForPlugin, cat, morceau, _PLUGIN, champs)
        end
        for j, photo in ipairs(morceau) do
            local l = { brut = {}, formate = {}, champ = {} }
            local bp = okB and type(b) == 'table' and b[photo]
            for _, cle in ipairs(brutes or {}) do
                if type(bp) == 'table' then
                    l.brut[cle] = bp[cle]
                else
                    l.brut[cle] = Photos.brut(photo, cle)
                end
            end
            local fp = okF and type(f) == 'table' and f[photo]
            for _, cle in ipairs(formatees or {}) do
                local valeur
                if type(fp) == 'table' then
                    valeur = fp[cle]
                else
                    valeur = Photos.meta(photo, cle)
                end
                if valeur ~= nil and valeur ~= '' and valeur ~= Json.null then
                    l.formate[cle] = valeur
                end
            end
            local mp = okM and type(m) == 'table' and m[photo]
            for _, cle in ipairs(champs or {}) do
                if type(mp) == 'table' then
                    l.champ[cle] = mp[cle]
                else
                    local ok, valeur = LrTasks.pcall(photo.getPropertyForPlugin, photo, _PLUGIN, cle)
                    l.champ[cle] = ok and valeur or nil
                end
            end
            lus[debut + j - 1] = l
        end
    end
    return lus
end

-- Nom du fichier, avec sa copie virtuelle (« XH2S1208.RAF (Copie 1) »), comme Photos.nomFichier.
local function nomDe(photo, l)
    local nom = texte(l.formate.fileName) or ('photo ' .. tostring(photo.localIdentifier))
    local copieNom = texte(l.formate.copyName)
    if copieNom then
        nom = nom .. ' (' .. copieNom .. ')'
    end
    return nom
end

-- La photo porte-t-elle la mémoire de Claude, la sienne (retoucheeParClaude = 'oui' et
-- proprietaireMemoire = son uuid) ? Une mémoire sans propriétaire se vérifie par Photos.lireChamp,
-- comme Photos.decrireTout.
local function retoucheeParClaude(photo, l)
    if l.champ.retoucheeParClaude ~= 'oui' then
        return false
    end
    local proprietaire = l.champ.proprietaireMemoire
    if type(proprietaire) == 'string' and proprietaire ~= '' then
        return proprietaire == l.brut.uuid
    end
    local ok, valeur = LrTasks.pcall(Photos.lireChamp, photo, 'retoucheeParClaude')
    return ok and valeur == 'oui'
end

-- La focale réelle en millimètres (getRawMetadata focalLength ; un nombre, à constater dans
-- Lightroom : un texte « 23 mm » se lit aussi).
local function focale(valeur)
    if type(valeur) == 'number' then
        return nombre(valeur)
    end
    if type(valeur) == 'string' then
        local n = nombre((valeur:match('[%d]+[,.]?[%d]*') or ''):gsub(',', '.'))
        return n
    end
    return nil
end

-- L'ISO en nombre, comme Photos.sensibilite.
local function iso(valeur)
    local n = nombre(valeur)
    if n and n > 0 then
        return n
    end
    return nil
end

local CLES_VUE_BRUTES = { 'isVirtualCopy', 'masterPhoto', 'uuid', 'fileFormat' }
local CLES_VUE_FORMATEES = { 'fileName', 'copyName' }
local CLES_ORIGINAL_BRUTES = { 'uuid', 'dateTimeOriginal', 'focalLength', 'isoSpeedRating', 'virtualCopies' }
local CLES_ORIGINAL_FORMATEES = { 'fileName', 'copyName', 'cameraModel', 'lens', 'aperture', 'shutterSpeed' }
local CLES_CLASSEMENT = { 'rating', 'pickStatus', 'uuid' }

-- La prise de vue d'un original, lue (lireGroupe) : une valeur que Lightroom ne donne pas manque.
local function priseDeVue(l)
    return {
        le = datePrise(l.brut.dateTimeOriginal), appareil = texte(l.formate.cameraModel), objectif = texte(l.formate.lens),
        focale = focale(l.brut.focalLength), ouverture = texte(l.formate.aperture), vitesse = texte(l.formate.shutterSpeed),
        iso = iso(l.brut.isoSpeedRating),
    }
end

-- Le classement de chaque famille : pour chaque original (et ce que lireGroupe en a lu, avec
-- virtualCopies), { note (la plus haute), drapeau (« retenue » si l'une l'est, « rejetee » si
-- toutes le sont, sinon « aucun »), retouchee (l'une porte la mémoire de Claude) }, sur l'original
-- et ses copies virtuelles hors de « Développeur › Essais ». Par lectures groupées.
local function lireClassements(originaux, lus)
    local membres, familleDe = {}, {}
    for i, original in ipairs(originaux) do
        membres[#membres + 1] = original
        familleDe[#membres] = i
        local copies = lus[i].brut.virtualCopies
        for _, copieVirtuelle in ipairs(type(copies) == 'table' and copies or {}) do
            if type(copieVirtuelle) == 'table' and copieVirtuelle ~= original and not Carnet.estPhotoDEssai(copieVirtuelle) then
                membres[#membres + 1] = copieVirtuelle
                familleDe[#membres] = i
            end
        end
    end
    local lm = lireGroupe(membres, CLES_CLASSEMENT, nil, CHAMPS_MEMOIRE)
    local classements = {}
    for i = 1, #originaux do
        classements[i] = { note = 0, retenue = false, rejetees = 0, membres = 0, retouchee = false }
    end
    for j, membre in ipairs(membres) do
        local k = classements[familleDe[j]]
        local l = lm[j]
        local note = math.floor(nombre(l.brut.rating) or 0)
        k.note = math.max(k.note, math.max(0, math.min(5, note)))
        local drapeau = DRAPEAUX[nombre(l.brut.pickStatus) or 0] or 'aucun'
        k.retenue = k.retenue or drapeau == 'retenue'
        k.rejetees = k.rejetees + (drapeau == 'rejetee' and 1 or 0)
        k.membres = k.membres + 1
        k.retouchee = k.retouchee or retoucheeParClaude(membre, l)
    end
    for i, k in ipairs(classements) do
        classements[i] = { note = k.note, retouchee = k.retouchee,
            drapeau = k.retenue and 'retenue' or (k.membres > 0 and k.rejetees == k.membres and 'rejetee' or 'aucun') }
    end
    return classements
end

local function poserClassement(e, k, maintenant)
    e.note, e.drapeau, e.retouchee_par_claude, e.classement_le = k.note, k.drapeau, k.retouchee, maintenant
end

-- Les vues ------------------------------------------------------------------------------------

-- Le Suivi tourne (Init.lua, dans Lightroom seulement ; une réactivation dans le Gestionnaire de
-- modules externes le rallume).
function Releve.allumer()
    Releve.allume, Releve.arrete = true, false
end

-- Le Suivi s'arrête (Arret.lua : le module désactivé, rechargé ou déchargé). Aucune vue ne s'ajoute,
-- aucune tâche ne part ; celle qui tourne s'arrête après son attente (vignettes, --analyser, une
-- pause : Moteur.travaille peut rester vrai pour toujours dans l'ancienne instance), sans lancer le
-- connecteur ni écrire le relevé : après un rechargement, la nouvelle instance le relit et le tient
-- (deux tâches sur la même file s'effaceraient l'une l'autre). Ce qui n'était pas écrit se refait.
function Releve.eteindre()
    Releve.allume, Releve.arrete = false, true
end

-- La prochaine sélection vue compte, même inchangée, groupe entier (l'ouverture d'une fenêtre).
function Releve.revoir()
    Releve.aRevoir = true
end

-- Les vues en attente fondues en une seule (au-delà de MAX_EN_ATTENTE : la tâche analyse un lot, ou
-- ne tourne pas encore) : la photo active de la plus récente en tête, puis les photos des vues de la
-- plus récente à la plus ancienne, sans doublon, MAX_SELECTION au plus (le reste est dit au
-- journal). Aucune vue ne se perd : Releve.cleVue a déjà retenu chacune, qui ne serait jamais revue.
local function fusionnerVues()
    local photos, deja, auDela = {}, {}, 0
    for i = #Releve.aVoir, 1, -1 do
        for _, photo in ipairs(Releve.aVoir[i].photos) do
            local id = photo.localIdentifier
            if not deja[id] then
                deja[id] = true
                if #photos < Releve.MAX_SELECTION then
                    photos[#photos + 1] = photo
                else
                    auDela = auDela + 1
                end
            end
        end
    end
    if auDela > 0 then
        Journal.noter(string.format("Suivi : %d vues en attente fondues en une ; %d photo(s) au-delà de %d ne sont pas rangées",
            #Releve.aVoir, auDela, Releve.MAX_SELECTION))
    end
    Releve.aVoir = { { photos = photos, le = os.time() } }
end

-- Une sélection vue par la fenêtre Claude ou la Demande rapide (`info` : Lightroom.photos()) : si
-- elle a changé (sa clé, info.cle) ou après Releve.revoir, la photo active et les photos de la
-- sélection (MAX_SELECTION au plus, la photo active d'abord) s'ajoutent aux vues à ranger ; dans le
-- même groupe (info.groupe), une autre photo active ne revoit qu'elle. Ne lit que la sélection :
-- la tâche (Releve.relancer) range la vue. Rend vrai si une vue s'ajoute. À appeler depuis une
-- tâche.
function Releve.voirSelection(info)
    if not Releve.allume or type(info) ~= 'table' or not info.cle then
        return false
    end
    if info.cle == Releve.cleVue and not Releve.aRevoir then
        return false
    end
    local cat = Photos.catalogue()
    local active = cat:getTargetPhoto()
    if not active then
        return false
    end
    local entier = Releve.aRevoir or info.groupe == nil or info.groupe ~= Releve.groupeVu
    Releve.cleVue, Releve.groupeVu, Releve.aRevoir = info.cle, info.groupe, false
    local photos = { active }
    if entier then
        local max = math.min(Releve.MAX_SELECTION, Lightroom.MAX_GROUPE)
        local deja, auDela = { [active.localIdentifier] = true }, 0
        for _, photo in ipairs(cat:getTargetPhotos() or {}) do
            if not deja[photo.localIdentifier] then
                if #photos < max then
                    photos[#photos + 1] = photo
                    deja[photo.localIdentifier] = true
                else
                    auDela = auDela + 1
                end
            end
        end
        if auDela > 0 then
            Journal.noter(string.format("Suivi : sélection de %d photos, seules les %d premières comptent (%d au plus)",
                #photos + auDela, #photos, max))
        end
    end
    Releve.aVoir[#Releve.aVoir + 1] = { photos = photos, le = os.time() }
    if #Releve.aVoir > Releve.MAX_EN_ATTENTE then
        fusionnerVues()
    end
    return true
end

-- Range une vue : ses originaux au relevé (créés à leur première vue), leur prise de vue et le
-- classement de leur famille relus, la vue ajoutée à `vues`. Des lectures du catalogue, rien d'écrit
-- au catalogue : elle se range même pendant que Claude travaille. Le fichier s'écrit à son tour
-- (ecrireBientot : au plus toutes les DELAI_ECRITURE secondes).
local function rangerVue(vue)
    local chemin = cheminCatalogue()
    if not chemin then
        Journal.noter("Suivi : chemin du catalogue ouvert illisible, vue non rangée")
        return false
    end
    local maintenant = os.time()
    local lus = lireGroupe(vue.photos, CLES_VUE_BRUTES, CLES_VUE_FORMATEES)
    local familles, ordre = {}, {}
    local tete
    for i, photo in ipairs(vue.photos) do
        local l = lus[i]
        if l.brut.fileFormat ~= 'VIDEO' and texte(l.brut.uuid) and not Carnet.estPhotoDEssai(photo) then
            local original = photo
            if l.brut.isVirtualCopy == true and type(l.brut.masterPhoto) == 'table' then
                original = l.brut.masterPhoto
            end
            local cle = cleDe(original.localIdentifier)
            local f = familles[cle]
            if not f then
                f = { original = original, vues = {} }
                familles[cle] = f
                ordre[#ordre + 1] = cle
            end
            f.vues[#f.vues + 1] = { id = photo.localIdentifier, uuid = l.brut.uuid, copie_virtuelle = l.brut.isVirtualCopy == true,
                fichier = nomDe(photo, l) }
            if i == 1 then
                tete = cle
            end
        end
    end
    if #ordre == 0 then
        return false
    end
    local originaux = {}
    for i, cle in ipairs(ordre) do
        originaux[i] = familles[cle].original
    end
    local lo = lireGroupe(originaux, CLES_ORIGINAL_BRUTES, CLES_ORIGINAL_FORMATEES)
    local classements = lireClassements(originaux, lo)
    -- Éteint pendant les lectures (Arret.lua) : rien ne change.
    if not Releve.allume then
        return false
    end
    -- Tout est lu : le registre change d'un coup, sans rendre la main.
    local c = tableDu(chemin, true)
    Releve.rangs = Releve.rangs or {}
    for i, cle in ipairs(ordre) do
        local l, original = lo[i], originaux[i]
        local uuid = texte(l.brut.uuid)
        if uuid then
            local e = c.photos[cle]
            -- Une autre photo sous ce numéro (un autre uuid) remplace l'entrée, comme au carnet.
            if not e or e.uuid ~= uuid then
                e = { original = original.localIdentifier, uuid = uuid, ajout = maintenant, ajout_le = dateDuModule(maintenant), vues = {} }
                c.photos[cle] = e
            end
            e.fichier = nomDe(original, l)
            e.vu = maintenant
            for _, v in ipairs(familles[cle].vues) do
                local dejaVue = false
                for _, avant in ipairs(e.vues) do
                    if avant.id == v.id and avant.uuid == v.uuid then
                        dejaVue = true
                        break
                    end
                end
                if not dejaVue and #e.vues < Releve.MAX_VUES then
                    e.vues[#e.vues + 1] = { id = v.id, uuid = v.uuid, copie_virtuelle = v.copie_virtuelle, fichier = v.fichier, le = maintenant }
                end
            end
            e.prise_de_vue = priseDeVue(l)
            poserClassement(e, classements[i], maintenant)
            Releve.rangs[cle] = i
        end
    end
    if tete then
        Releve.tete = tete
    end
    -- La file se refait : de nouvelles entrées, une autre photo en tête.
    Releve.file = nil
    ecrireBientot()
    return true
end

-- Relit la note, le drapeau et « retouchée par Claude » de chaque famille du relevé du catalogue
-- ouvert (la fenêtre Suivi, à son ouverture, avant --graphiques), par lectures groupées ; une
-- écriture du fichier. Un original qui n'est plus au catalogue, ou d'un autre uuid, garde ce qu'il
-- avait. Rend le nombre d'entrées relues. À appeler depuis une tâche.
function Releve.reclasser()
    local chemin = cheminCatalogue()
    if not chemin then
        return 0
    end
    local c = tableDu(chemin, false)
    local cat = Photos.catalogue()
    local cles, originaux = {}, {}
    for cle, e in pairs(c.photos) do
        local ok, photo = LrTasks.pcall(cat.getPhotoByLocalId, cat, tonumber(cle))
        if ok and type(photo) == 'table' then
            cles[#cles + 1] = cle
            originaux[#originaux + 1] = photo
        end
    end
    local lo = lireGroupe(originaux, { 'uuid', 'virtualCopies' })
    local classements = lireClassements(originaux, lo)
    local maintenant, n = os.time(), 0
    for i, cle in ipairs(cles) do
        local e = c.photos[cle]
        if e and e.uuid == texte(lo[i].brut.uuid) then
            poserClassement(e, classements[i], maintenant)
            n = n + 1
        end
    end
    if n > 0 then
        enregistrer()
    end
    return n
end

-- La file d'analyse ---------------------------------------------------------------------------

-- Quand analyser cette entrée : 0 (maintenant), un nombre de secondes (une analyse manquée à
-- réessayer), ou nil (jamais : analysée selon les règles connues, ou abandonnée).
local function quand(cle, e, maintenant)
    local a = e.analyse
    if not a then
        return 0
    end
    if a.cherches then
        if Releve.regles and (a.regles or 0) < Releve.regles and not (Releve.sansRefaire and Releve.sansRefaire[cle]) then
            return 0
        end
        return nil
    end
    if a.abandonnee then
        return nil
    end
    return math.max(0, (a.le or 0) + Releve.DELAI_REESSAI - maintenant)
end

-- La file du catalogue ouvert, triée : la photo active de la dernière vue d'abord, puis les plus
-- récemment vues, dans l'ordre de leur sélection, puis par identifiant. Rend la liste des clés à
-- analyser maintenant, et dans combien de secondes la suivante le sera (nil : aucune).
local function construireFile(c, maintenant)
    local liste, attente = {}, nil
    for cle, e in pairs(c.photos) do
        local dans = quand(cle, e, maintenant)
        if dans == 0 then
            liste[#liste + 1] = cle
        elseif dans then
            attente = math.min(attente or dans, dans)
        end
    end
    local rangs, tete = Releve.rangs or {}, Releve.tete
    table.sort(liste, function(a, b)
        if (a == tete) ~= (b == tete) then
            return a == tete
        end
        local va, vb = c.photos[a].vu or 0, c.photos[b].vu or 0
        if va ~= vb then
            return va > vb
        end
        local ra, rb = rangs[a] or math.huge, rangs[b] or math.huge
        if ra ~= rb then
            return ra < rb
        end
        return (tonumber(a) or 0) < (tonumber(b) or 0)
    end)
    return liste, attente
end

-- Le prochain lot (LOT_ANALYSE clés au plus), pris dans la file gardée (refaite après chaque vue) ;
-- nil et l'attente quand elle est vide. Une file gardée épuisée se refait une fois : les lots
-- analysés depuis ont pu changer l'attente (une analyse manquée à réessayer) ou les règles connues.
local function prochainLot(c, maintenant)
    for _ = 1, 2 do
        local neuve = Releve.file == nil
        if neuve then
            local liste, attente = construireFile(c, maintenant)
            Releve.file = { liste = liste, i = 1, attente = attente }
        end
        local f, lot = Releve.file, {}
        while #lot < Releve.LOT_ANALYSE and f.i <= #f.liste do
            local cle = f.liste[f.i]
            f.i = f.i + 1
            local e = c.photos[cle]
            if e and quand(cle, e, maintenant) == 0 then
                lot[#lot + 1] = cle
            end
        end
        if #lot > 0 then
            return lot
        end
        Releve.file = nil
        if neuve then
            return nil, f.attente
        end
    end
end

-- Une analyse manquée : un essai de plus, abandonnée au ESSAIS_ANALYSE-ième. Une analyse réussie
-- qu'on refaisait (d'autres règles) reste telle quelle, et n'est plus refaite de la séance.
local function manquee(cle, e, raison, maintenant)
    local avant = e.analyse
    if avant and avant.cherches then
        Releve.sansRefaire = Releve.sansRefaire or {}
        Releve.sansRefaire[cle] = true
        return
    end
    local essais = (avant and avant.erreur and avant.essais or 0) + 1
    e.analyse = { le = maintenant, erreur = raison, essais = essais, abandonnee = essais >= Releve.ESSAIS_ANALYSE or nil }
end

-- Le dossier d'un lot (Temporaire/Suivi/Analyse-<n>), neuf : effacé après la réponse.
local numeroLot = 0
local function dossierDuLot()
    numeroLot = numeroLot + 1
    return LrPathUtils.child(LrPathUtils.child(Chemins.temporaire(), 'Suivi'), string.format('Analyse-%d-%d', os.time(), numeroLot))
end

-- Lance `mcp-developpeur --analyser` sur la liste des photos du lot ; rend la réponse décodée (à
-- lire seulement : elle porte des métatables), ou nil sans réponse lisible.
local function demanderAnalyse(connecteur, liste, dossier)
    local reponse = LrPathUtils.child(dossier, 'reponse.json')
    LrTasks.execute(string.format("/usr/bin/perl -e 'alarm %d; exec @ARGV' %s --analyser %s > %s 2>/dev/null", Releve.ALARME,
        q(connecteur), q(Json.encode({ photos = liste })), q(reponse)))
    local contenu = Fichiers.lire(reponse) or ''
    local ok, json = pcall(Json.decode, contenu)
    if ok and type(json) == 'table' then
        return json
    end
    return nil
end

-- Analyse un lot : les vignettes des originaux (du cache de Lightroom, redressées), puis le
-- connecteur, puis le relevé changé d'un coup. Rend vrai, ou faux si le lot est remis (Claude s'est
-- mis au travail pendant les vignettes, ou le Suivi s'est éteint pendant une attente : rien ne
-- change, le connecteur n'est pas lancé après l'arrêt).
local function analyserLot(c, cles, connecteur)
    local cat = Photos.catalogue()
    local photos, entrees, uuids, introuvables = {}, {}, {}, {}
    for _, cle in ipairs(cles) do
        local e = c.photos[cle]
        local ok, photo = LrTasks.pcall(cat.getPhotoByLocalId, cat, tonumber(cle))
        local uuid = ok and type(photo) == 'table' and Photos.brut(photo, 'uuid') or nil
        if uuid ~= nil and uuid == e.uuid then
            photos[#photos + 1] = photo
            entrees[#photos] = cle
            uuids[cle] = e.uuid
        else
            introuvables[#introuvables + 1] = cle
            uuids[cle] = e.uuid
        end
    end
    local lus = lireGroupe(photos, { 'uuid' }, nil, CHAMPS_MEMOIRE)
    local dossier = dossierDuLot()
    Fichiers.supprimer(dossier)
    Fichiers.creerDossier(dossier)
    local chemins = #photos > 0 and Vignettes.demander(photos, Releve.TAILLE_VIGNETTE, dossier) or {}
    local liste = Json.tableau()
    for i, photo in ipairs(photos) do
        local id = photo.localIdentifier
        if chemins[id] then
            local ok, d = LrTasks.pcall(Vignettes.decrireVignette, photo, {})
            if ok and type(d) == 'table' then
                LrTasks.pcall(Images.redresser, chemins[id], d.geometrie)
            end
        end
        local e = c.photos[entrees[i]]
        liste[#liste + 1] = { id = id, vignette = LrPathUtils.child(dossier, string.format('%d.jpg', id)),
            iso = e and e.prise_de_vue and e.prise_de_vue.iso or nil, cache = true, retouchee = retoucheeParClaude(photo, lus[i]) or nil }
    end
    if not Releve.allume or Releve.occupe() then
        Fichiers.supprimer(dossier)
        return false
    end
    local json = #photos > 0 and demanderAnalyse(connecteur, liste, dossier) or nil
    Fichiers.supprimer(dossier)
    if not Releve.allume then
        return false
    end
    local maintenant = os.time()
    local resultats, raisonDuLot = {}, nil
    if #photos > 0 then
        if not json then
            raisonDuLot = 'pas_de_reponse'
            Journal.noter("Suivi :", Releve.PAS_DE_REPONSE, string.format("(--analyser, %d photo(s))", #photos))
        elseif json.ok ~= true then
            raisonDuLot = texte(json.raison) or 'pas_de_reponse'
            Journal.noter("Suivi : --analyser refusé :", tostring(texte(json.texte) or raisonDuLot))
        else
            local regles = nombre(json.regles)
            if regles then
                Releve.regles = math.max(Releve.regles or 0, regles)
            end
            for _, r in ipairs(type(json.photos) == 'table' and json.photos or {}) do
                if type(r) == 'table' and nombre(r.id) then
                    resultats[cleDe(nombre(r.id))] = r
                end
            end
            json.regles = regles
        end
    end
    -- Le registre change d'un coup : une entrée remplacée entre-temps (un autre uuid) n'est pas
    -- touchée.
    for _, cle in ipairs(introuvables) do
        local e = c.photos[cle]
        if e and e.uuid == uuids[cle] then
            manquee(cle, e, 'photo_introuvable', maintenant)
        end
    end
    for i = 1, #photos do
        local cle = entrees[i]
        local e = c.photos[cle]
        if e and e.uuid == uuids[cle] then
            local r = resultats[cle]
            if raisonDuLot then
                manquee(cle, e, raisonDuLot, maintenant)
            elseif type(r) == 'table' and type(r.cherches) == 'table' then
                local cherches = codes(r.cherches)
                local dedans = {}
                for _, code in ipairs(cherches) do
                    dedans[code] = true
                end
                local defauts = {}
                for _, code in ipairs(codes(r.defauts)) do
                    if dedans[code] then
                        defauts[#defauts + 1] = code
                    end
                end
                e.analyse = { le = maintenant, regles = json.regles, cherches = cherches, defauts = defauts }
            else
                manquee(cle, e, type(r) == 'table' and texte(r.raison) or 'pas_de_reponse', maintenant)
            end
        end
    end
    ecrireBientot()
    return true
end

-- Claude travaille (fenêtre Claude, Demande rapide) ou la liaison sert (Claude Desktop, Claude Code
-- en terminal, la recette) : le Suivi attend.
function Releve.occupe()
    return require('Moteur').travaille == true or Lightroom.liaisonOccupee() == true
end

-- Analyse un lot de la file (analyserLot), à l'abri de ses erreurs.
local function analyserLe(c, lot, connecteur)
    local ok, fait = LrTasks.pcall(analyserLot, c, lot, connecteur)
    if ok and fait == false then
        -- Le lot remis (Claude s'est mis au travail, ou le Suivi éteint) : la file se refait, il
        -- revient en tête.
        Releve.file = nil
    elseif not ok then
        local erreur = fait
        -- Une erreur du module compte un essai à chaque photo du lot : jamais sans fin.
        Releve.derniereErreur = tostring(erreur)
        Journal.noter("Suivi : lot non analysé :", tostring(erreur))
        local maintenant = os.time()
        for _, cle in ipairs(lot) do
            if c.photos[cle] then
                manquee(cle, c.photos[cle], 'module', maintenant)
            end
        end
        ecrireBientot()
    end
end

-- Plus rien à analyser maintenant : vrai si la tâche peut s'arrêter (rien n'attend d'être écrit, ou
-- son tour est venu : Releve.vider l'écrit) ; sinon elle attend une pause, et range les vues qui
-- arrivent d'ici là (au plus DELAI_ECRITURE secondes).
local function finir()
    if not Releve.aEcrire or ecritureDue() then
        return true
    end
    LrTasks.sleep(Releve.PAUSE)
    return false
end

local function viderFile()
    local enPause = false
    while Releve.allume do
        if #Releve.aVoir > 0 then
            -- Une vue se range même pendant que Claude travaille ou que la liaison sert : des
            -- lectures du catalogue, et l'écriture du fichier à son tour.
            local vue = table.remove(Releve.aVoir, 1)
            local ok, erreur = LrTasks.pcall(rangerVue, vue)
            if not ok then
                Releve.derniereErreur = tostring(erreur)
                Journal.noter("Suivi : vue non rangée :", tostring(erreur))
            end
        elseif Releve.occupe() then
            -- L'analyse attend. Ce qui est rangé s'écrit au début de la pause (Claude peut
            -- travailler longtemps), puis à son tour (des vues rangées pendant la pause).
            if Releve.aEcrire and (not enPause or ecritureDue()) then
                enregistrer()
            end
            enPause = true
            LrTasks.sleep(Releve.PAUSE)
        else
            enPause = false
            local chemin = cheminCatalogue()
            local connecteur = Chemins.prefs().cheminConnecteur
            if not chemin or not Fichiers.existe(connecteur) then
                if not Releve.connecteurAbsentDit and chemin then
                    Releve.connecteurAbsentDit = true
                    Journal.noter("Suivi : connecteur introuvable, analyse remise à plus tard :", tostring(connecteur))
                end
                Releve.prochaineVerification = os.time() + Releve.DELAI_VERIFICATION
                if finir() then
                    return
                end
            else
                local c = tableDu(chemin, false)
                local lot, attente = prochainLot(c, os.time())
                if not lot then
                    Releve.prochaineVerification = attente and (os.time() + attente) or math.huge
                    if finir() then
                        return
                    end
                else
                    analyserLe(c, lot, connecteur)
                end
            end
        end
    end
end

-- Vide la file : les vues à ranger d'abord (même pendant que Claude travaille), puis les lots à
-- analyser ; l'analyse attend pendant que Claude travaille. S'arrête quand il n'y a plus rien à
-- faire maintenant (Releve.prochaineVerification dit quand regarder de nouveau) et que l'écriture a
-- eu son tour, ou quand le Suivi s'éteint ; puis écrit ce qui ne l'est pas encore (jamais après
-- Releve.eteindre). Une tâche à la fois (Releve.relancer).
function Releve.vider()
    local ok, erreur = LrTasks.pcall(viderFile)
    -- Ce qui n'est pas encore écrit (DELAI_ECRITURE), même après une erreur.
    if Releve.aEcrire then
        enregistrer()
    end
    if not ok then
        error(erreur, 0)
    end
end

-- Lance la tâche qui vide la file, si le Suivi tourne, qu'aucune ne tourne déjà et qu'il y a
-- quelque chose à faire (une vue à ranger, ou l'heure de regarder la file). Appelé par la boucle de
-- la fenêtre Claude et celle de la Demande rapide. Rend vrai si une tâche part.
function Releve.relancer()
    if not Releve.allume or Releve.enCours then
        return false
    end
    if #Releve.aVoir == 0 and os.time() < Releve.prochaineVerification then
        return false
    end
    Releve.enCours = true
    LrTasks.startAsyncTask(function()
        local ok, erreur = LrTasks.pcall(Releve.vider)
        Releve.enCours = false
        if not ok then
            Releve.derniereErreur = tostring(erreur)
            Journal.noter("Suivi :", tostring(erreur))
            Releve.prochaineVerification = os.time() + Releve.DELAI_VERIFICATION
        end
    end)
    return true
end

return Releve
