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
--      catalogue) et par Releve.reclasser (la fenêtre Suivi, après son premier dessin).
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
-- sortent. Les écritures, vues et analyses comprises, sont espacées de Releve.delaiEcriture :
-- DELAI_ECRITURE secondes au moins, plus pour un grand relevé (FACTEUR_ECRITURE fois la durée propre
-- de la dernière, SECONDES_PAR_MO par Mo du fichier), DELAI_ECRITURE_MAX au plus (ce qui n'est pas
-- écrit se perd si Lightroom quitte : Arret.lua ne s'exécute pas), sauf avant un dessin demandé de la
-- fenêtre Suivi (Releve.ecrire, avant --graphiques, qui attend une écriture en cours) ; à la fin de
-- la file, la tâche attend le tour de la dernière (en rangeant les vues qui arrivent). Un fichier
-- illisible (ou d'un autre format) est mis de côté avant la première écriture
-- (suivi-illisible-<date>.json, jamais écrasé).
-- Le connecteur le lit (--graphiques), jamais ne l'écrit ; Fichiers.ecrireParMorceaux l'écrit
-- (jamais à moitié écrit). Tout ce qui sort vers une vue est une copie neuve, sans métatable.
--
-- Toute la bibliothèque d'un coup (correctif 1.3.8, demandé par Dany le 26 octobre 2026 : son
-- catalogue a 88 071 photos, il veut les ouvrir toutes, Toutes les photographies, tout
-- sélectionner) : MAX_SELECTION et MAX_ORIGINAUX à 250 000. À cette taille (85 000 originaux font
-- environ 57 Mo de relevé, 250 000 environ 170 Mo), rien ne se fait plus d'un seul morceau : chaque
-- tâche rend la main à Lightroom (rendreLaMain, Photos.rendreLaMain : LrTasks.yield, seulement si
-- LrTasks.canYield, jamais à travers un pcall simple, que Lua 5.1 refuse) toutes les PAS entrées des
-- boucles, PAS_UNE_A_UNE lectures une à une du catalogue, LOT_LECTURE photos des lectures groupées,
-- PAS_ECRITURE entrées écrites et PAS_JSON valeurs relues. Mesuré sous luajit -joff (Lightroom : à
-- peu près autant, au plus 2,5 fois) le 26 octobre 2026, à 250 000 originaux, le plus long morceau
-- reste sous 0,3 s (0,03 à 0,08 s le plus souvent ; avant, 5,7 s pour la relecture et 6,5 s par
-- écriture, d'un seul morceau ; les plus longs, de 0,1 à 0,27 s, sont l'agrandissement d'un coup
-- d'une table de 131 072 à 262 144 places, jsonDe ou la table des chaînes de Lua). Pour cela :
--   - le relevé se relit par morceaux (Json.decode avec un rythme), une seule tâche à la fois (les
--     autres attendent : deux relectures rangeraient deux registres, et ce qui change dans le
--     premier se perdrait) ;
--   - il s'écrit par morceaux, entrée par entrée (Fichiers.ecrireParMorceaux, Json.ecrivain), une
--     écriture à la fois, `aEcrire` remis à faux dès le début (ce qui change pendant qu'il s'écrit
--     s'écrit à la suivante), abandonnée si le Suivi s'éteint ; le texte JSON de chaque entrée est
--     gardé (jsonDe) jusqu'à ce qu'elle change (changee) : une écriture pendant l'analyse ne refait
--     que les entrées changées (85 000 originaux : 0,11 s au lieu de 1,8 s ; 250 000 : 0,38 s au lieu
--     de 5,9 s), et Releve.reclasser ne change que les entrées dont le classement a changé ;
--   - la file d'analyse se garde d'une vue à l'autre : les originaux d'une vue passent devant
--     (mettreDevant), une analyse manquée aussi, à son heure (Releve.reessais) ; elle ne se refait
--     entière qu'épuisée, ou quand les règles du connecteur montent, par paquets de même heure de vue
--     triés en nombres (aucun tri de 125 000 textes, que Lua 5.1 compare par strcoll) ;
--   - les lectures du catalogue d'une grande vue et de Releve.reclasser se font par tranches, et les
--     photos des Essais se lisent d'un coup pour une grande vue (Carnet.photosDesEssais) ; une
--     sélection que la fenêtre Suivi pose (les photos d'une barre, Releve.poserSelection) ne se range
--     pas : ses photos sont déjà au relevé.
-- La mémoire (mesurée sous luajit -joff par la revue de la 1.3.8 ; pour Lua 5.1, celui de Lightroom,
-- d'après un modèle des tailles de ses objets) : le registre et jsonDe tiennent environ 175 Mo à
-- 85 000 originaux et 490 Mo à 250 000 sous luajit (Lua 5.1 : environ 0,2 et 0,6 Go), pendant toute
-- la séance ; la relecture et la première écriture en demandent à peu près deux fois plus un moment
-- (le texte, l'arbre décodé et le registre ensemble, jusqu'au ramasse-miettes suivant : environ
-- 0,45 Go à 85 000 et 1,2 à 1,5 Go à 250 000 dans Lightroom, d'après le modèle). À constater.

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
    -- Les analyses manquées à réessayer, dans l'ordre de leur heure : { cle, le (os.time où la
    -- réessayer) } (manquee, prochainLot).
    reessais = {},
    -- La fenêtre Suivi pose une sélection (Releve.poserSelection) : aucune vue ne compte pendant ce
    -- temps.
    selectionPosee = 0,
}

Releve.FORMAT = 1
-- 250 000 depuis le correctif 1.3.8 (20 000 avant ; demandé par Dany le 26 octobre 2026 : toute sa
-- bibliothèque, 88 071 photos, dont 3 323 vidéos qui n'entrent pas ; à 20 000, le relevé perdait déjà
-- des originaux analysés à chaque grande sélection).
Releve.MAX_ORIGINAUX = 250000
Releve.MAX_VUES = 20
-- 250 000 depuis le correctif 1.3.8 (demandé par Dany le 26 octobre 2026 : toute la bibliothèque
-- sélectionnée d'un coup ; 10 000 le matin même, 1 000 avant : un dossier de 3 500 photos se
-- sélectionnait par tranches). La file d'analyse est plus longue derrière.
Releve.MAX_SELECTION = 250000
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
-- Écart minimal entre deux écritures du fichier, vues et analyses comprises (secondes) : Dany qui
-- parcourt ses photos aux flèches en voit une toutes les 2 s, une écriture chacune figeait Lightroom
-- à chaque photo (à 20 000 originaux, 13,6 Mo écrits d'un coup, sans rendre la main). Depuis le
-- correctif 1.3.8, le fichier s'écrit par morceaux et l'écart (Releve.delaiEcriture) est aussi d'au
-- moins FACTEUR_ECRITURE fois la durée propre de la dernière écriture (ses morceaux seuls, sans le
-- temps des autres tâches quand elle rend la main ; la première après la relecture refait toutes les
-- entrées : à 250 000 originaux, 6,4 s sous luajit -joff ; les suivantes, 0,38 s), pour que
-- l'écriture ne prenne jamais plus d'un dixième du temps de la tâche, et de SECONDES_PAR_MO par Mo du
-- fichier (chaque écriture l'écrit en entier : 85 000 originaux, 57 Mo, toutes les 57 s environ, au
-- lieu de toutes les 20 s, plus de 9 Go par heure d'analyse) ; jamais plus de DELAI_ECRITURE_MAX :
-- ce qui n'est pas encore écrit se perd si Lightroom quitte (les analyses se refont, une vue d'une
-- photo nouvelle non).
Releve.DELAI_ECRITURE = 20
Releve.FACTEUR_ECRITURE = 10
Releve.SECONDES_PAR_MO = 1
Releve.DELAI_ECRITURE_MAX = 60
-- Analyses manquées gardées pour passer devant la file à leur heure (Releve.reessais) ; au-delà,
-- elles attendent que la file se refasse.
Releve.MAX_REESSAIS = 1000
-- Vues en attente au-delà desquelles elles se fondent en une seule (la tâche analyse un lot, ou ne
-- tourne pas encore) : aucune photo perdue (MAX_SELECTION au plus).
Releve.MAX_EN_ATTENTE = 20
-- Photos par lecture groupée du catalogue (la main rendue entre deux).
Releve.LOT_LECTURE = 500
-- La main rendue à Lightroom (correctif 1.3.8) : toutes les PAS entrées d'une boucle du module,
-- PAS_UNE_A_UNE lectures une à une du catalogue (getPhotoByLocalId, une photo que la lecture groupée
-- n'a pas rendue), PAS_ECRITURE entrées écrites, PAS_JSON valeurs relues (Json.decode).
Releve.PAS = 2000
Releve.PAS_UNE_A_UNE = 200
Releve.PAS_ECRITURE = 500
Releve.PAS_JSON = 10000
-- Une vue d'au moins tant de photos lit d'un coup les photos des Essais (Carnet.photosDesEssais) au
-- lieu de demander ses collections à chaque photo (Carnet.estPhotoDEssai).
Releve.SEUIL_ESSAIS = 200
-- Une sélection identique revue (Releve.revoir : la fenêtre rouverte) moins de REVOIR_APRES
-- secondes après sa dernière vue entière ne revoit que la photo active, au-delà de SEUIL_REVOIR
-- photos (une bibliothèque entière : toutes ses lectures du catalogue à chaque ouverture).
Releve.REVOIR_APRES = 600
Releve.SEUIL_REVOIR = 2000
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
-- Une relecture du fichier en cours (une tâche à la fois : les autres l'attendent).
local enChargement = false
-- Une écriture du fichier en cours (une à la fois : elles écriraient le même fichier provisoire).
local enEcriture = false
-- Le texte JSON de chaque entrée, gardé jusqu'à ce qu'elle change (changee) : une écriture ne refait
-- que les entrées changées depuis la précédente. Clés faibles : une entrée retirée l'emporte.
local jsonDe = setmetatable({}, { __mode = 'k' })
-- La durée propre (secondes) de la dernière écriture et la taille du fichier (octets, écrit ou relu),
-- pour espacer les suivantes (Releve.delaiEcriture).
local dureeEcriture = 0
local tailleFichier = 0
-- Défini avec la file d'analyse (plus bas) : les originaux d'une vue mis en tête de la file gardée.
local mettreDevant

local q = Texte.shell

-- Rend la main à Lightroom (correctif 1.3.8) : Photos.rendreLaMain, la seule copie (seulement dans
-- une tâche qui le peut, LrTasks.canYield ; sous LrTasks.pcall).
local rendreLaMain = Photos.rendreLaMain
Releve.rendreLaMain = rendreLaMain

-- Une entrée changée : son texte JSON se refera à la prochaine écriture.
local function changee(e)
    if e then
        jsonDe[e] = nil
    end
end

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
-- et ce que le module n'écrit pas sont oubliés). La main rendue toutes les PAS entrées ; chaque
-- entrée relue quitte la table décodée, que le ramasse-miettes reprend à son tour (Json.decode a
-- déjà bâti tout l'arbre : un moment, l'arbre décodé et le registre sont tous deux en mémoire). La
-- table décodée n'est qu'à cette lecture : la parcourir en rendant la main ne gêne aucune autre
-- tâche.
local function normaliser(r)
    local propre = vide()
    local k = 0
    for chemin, c in pairs(type(r.catalogues) == 'table' and r.catalogues or {}) do
        if texte(chemin) and type(c) == 'table' then
            local photos = {}
            local brutes = type(c.photos) == 'table' and c.photos or {}
            for cle, e in pairs(brutes) do
                local entree = normaliserEntree(e, cle)
                if entree then
                    photos[cleDe(entree.original)] = entree
                end
                -- Une clé existante mise à nil pendant le parcours : permis (Lua 5.1).
                brutes[cle] = nil
                k = k + 1
                if k % Releve.PAS == 0 then
                    rendreLaMain()
                end
            end
            propre.catalogues[chemin] = { photos = photos }
        end
    end
    return propre
end

-- Relit le fichier (une tâche à la fois), par morceaux.
local function relire()
    local fichier = Releve.fichier()
    local contenu = Fichiers.lire(fichier)
    tailleFichier = contenu and #contenu or 0
    -- Présent mais vide : rien à garder ; présent mais illisible (contenu nil compris) : à garder.
    local present = Fichiers.existe(fichier) and contenu ~= ''
    -- LrTasks.pcall : Json.decode rend la main (un pcall simple l'en empêcherait, Lua 5.1).
    local ok, r = LrTasks.pcall(function() return contenu and Json.decode(contenu, rendreLaMain, Releve.PAS_JSON) end)
    contenu = nil
    if ok and type(r) == 'table' and tonumber(r.format) == Releve.FORMAT then
        local okN, propre = LrTasks.pcall(normaliser, r)
        if okN then
            return propre
        end
        Journal.noter("Suivi : relevé non relu :", tostring(propre))
    end
    local nouveau = vide()
    -- Un fichier présent mais illisible, ou d'un autre format : mis de côté avant d'écrire (un
    -- fichier vide ne garde rien).
    nouveau.illisible = present
    return nouveau
end

local function charger()
    if registre then
        return registre
    end
    -- Une autre tâche le relit : l'attendre (deux relectures rangeraient deux registres). Sans
    -- pouvoir attendre (hors d'une tâche), relu ici d'un seul morceau ; le premier rangé l'emporte.
    if enChargement and LrTasks.canYield() then
        while enChargement and not registre do
            LrTasks.sleep(0.1)
        end
        if registre then
            return registre
        end
    end
    enChargement = true
    local ok, relu = LrTasks.pcall(relire)
    enChargement = false
    if registre then
        return registre
    end
    if not ok then
        error(relu, 0)
    end
    registre = relu
    return registre
end

-- Pour les essais : oublie le registre chargé, la file et les vues à ranger (relus du fichier à la
-- prochaine lecture).
function Releve.oublier()
    registre = nil
    enChargement, enEcriture, dureeEcriture, tailleFichier = false, false, 0, 0
    jsonDe = setmetatable({}, { __mode = 'k' })
    Releve.aVoir = {}
    Releve.cleVue, Releve.groupeVu, Releve.groupeVuLe, Releve.aRevoir, Releve.tete = nil, nil, nil, false, nil
    Releve.file, Releve.rangs, Releve.sansRefaire, Releve.reclassement, Releve.revues = nil, nil, nil, false, nil
    Releve.prochaineVerification, Releve.regles, Releve.connecteurAbsentDit, Releve.derniereErreur = 0, nil, nil, nil
    Releve.aEcrire, Releve.ecritLe, Releve.arrete = false, nil, false
    Releve.reessais, Releve.selectionPosee = {}, 0
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

-- Trie des clés d'entrées par heure de vue (`vuDe(cle)`, décroissante si `recents`), puis par un
-- nombre propre à chaque clé (`nombreDe(cle)`, croissant ; nil : à la fin), sans tri de textes (Lua
-- 5.1 les compare par strcoll) ni comparateur Lua sur toute la liste : des paquets de même heure,
-- chacun trié en nombres (en C). La main rendue toutes les PAS clés (par `rendre`, rendreLaMain par
-- défaut). Rend une liste neuve.
local function trierParVu(cles, vuDe, nombreDe, recents, rendre)
    rendre = rendre or rendreLaMain
    local paquets, heures, parNombre, autres = {}, {}, {}, {}
    for k, cle in ipairs(cles) do
        local n = nombreDe(cle)
        if n == nil or parNombre[n] ~= nil then
            autres[#autres + 1] = cle
        else
            local vu = math.floor(tonumber(vuDe(cle)) or 0)
            local h = recents and -vu or vu
            local p = paquets[h]
            if not p then
                p = {}
                paquets[h] = p
                heures[#heures + 1] = h
            end
            p[#p + 1] = n
            parNombre[n] = cle
        end
        if k % Releve.PAS == 0 then
            rendre()
        end
    end
    table.sort(heures)
    local liste = {}
    for _, h in ipairs(heures) do
        local p = paquets[h]
        table.sort(p)
        for _, n in ipairs(p) do
            liste[#liste + 1] = parNombre[n]
        end
        if #p >= Releve.PAS then
            rendre()
        end
    end
    for _, cle in ipairs(autres) do
        liste[#liste + 1] = cle
    end
    return liste
end

-- L'identifiant d'une clé en nombre entier (de 0 à 2^34), nil sinon (une clé est un identifiant).
local ID_MAX = 2 ^ 34
local function idDe(cle)
    local id = tonumber(cle)
    if id and id >= 0 and id < ID_MAX and id == math.floor(id) then
        return id
    end
    return nil
end

-- Au-delà de MAX_ORIGINAUX, les entrées vues le moins récemment (vu, puis l'id) sortent. Compter ne
-- coûte qu'un parcours ; trier n'a lieu qu'au-delà de la borne (trierParVu, la main rendue par
-- `rendre`). L'heure de vue de chaque entrée est lue d'abord, en nombre : une entrée revue (son `vu`
-- changé) ou remplacée pendant le tri (une vue rangée par une autre tâche) reste.
local function elaguer(c, rendre)
    local n = 0
    for _ in pairs(c.photos) do
        n = n + 1
    end
    if n <= Releve.MAX_ORIGINAUX then
        return 0
    end
    local cles, avant, vuLu = {}, {}, {}
    for cle, e in pairs(c.photos) do
        cles[#cles + 1] = cle
        avant[cle] = e
        vuLu[cle] = math.floor(tonumber(e.vu) or 0)
    end
    local ordre = trierParVu(cles, function(cle) return vuLu[cle] end, function(cle) return idDe(cle) or 0 end, false, rendre)
    local aSortir, sorties = n - Releve.MAX_ORIGINAUX, 0
    for _, cle in ipairs(ordre) do
        if sorties >= aSortir then
            break
        end
        local e = c.photos[cle]
        if e ~= nil and e == avant[cle] and math.floor(tonumber(e.vu) or 0) == vuLu[cle] then
            c.photos[cle] = nil
            sorties = sorties + 1
        end
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

-- Le texte JSON d'une entrée, gardé jusqu'à ce qu'elle change (changee).
local function jsonDeLEntree(e)
    local t = jsonDe[e]
    if not t then
        t = Json.encode(versJson(e))
        jsonDe[e] = t
    end
    return t
end

-- Écrit le registre entier (tous les catalogues), par morceaux (sous le verrou d'enregistrer) : le
-- même texte que Json.encode({ format, catalogues }) donnerait, à l'ordre des entrées près (un objet
-- JSON n'a pas d'ordre), par Json.ecrivain. `aEcrire` repasse à faux dès le début : une vue ou une
-- analyse rangée pendant l'écriture (une autre tâche, quand celle-ci rend la main) s'écrit à la
-- suivante. Le Suivi éteint pendant l'écriture : abandonnée, le fichier d'avant reste tel quel. Sa
-- durée propre (dureeEcriture) est la somme de ses morceaux : le temps que les autres tâches prennent
-- quand elle rend la main n'y compte pas (il espacerait les écritures de plusieurs minutes).
local function ecrireLeRegistre()
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
    Releve.aEcrire = false
    local propre, depuis = 0, LrDate.currentTime()
    local function rendre()
        propre = propre + math.max(0, LrDate.currentTime() - depuis)
        rendreLaMain()
        depuis = LrDate.currentTime()
    end
    -- Les catalogues d'abord (aucun parcours d'une table qu'une autre tâche agrandirait pendant que
    -- celle-ci rend la main), puis leurs entrées.
    local chemins = {}
    for chemin in pairs(r.catalogues) do
        chemins[#chemins + 1] = chemin
    end
    table.sort(chemins)
    for _, chemin in ipairs(chemins) do
        local sorties = elaguer(r.catalogues[chemin], rendre)
        if sorties > 0 then
            Journal.noter(string.format("Suivi : %d original(aux) vu(s) le moins récemment retiré(s) du relevé de %s (%d au plus)",
                sorties, chemin, Releve.MAX_ORIGINAUX))
        end
    end
    local octets = 0
    local ok, ecrit = LrTasks.pcall(Fichiers.ecrireParMorceaux, fichier, function(ecrireTexte)
        -- Entrée par entrée (le fichier les tient en mémoire tampon) : aucun grand texte assemblé.
        local w = Json.ecrivain(function(texte)
            octets = octets + #texte
            ecrireTexte(texte)
        end)
        w.ouvrir()
        w.cle('catalogues')
        w.ouvrir()
        for _, chemin in ipairs(chemins) do
            local c = r.catalogues[chemin]
            w.cle(chemin)
            w.ouvrir()
            w.cle('photos')
            w.ouvrir()
            local cles = {}
            for cle in pairs(c.photos) do
                cles[#cles + 1] = cle
            end
            for i, cle in ipairs(cles) do
                local e = c.photos[cle]
                if e then
                    w.cle(cle)
                    w.brut(jsonDeLEntree(e))
                end
                if i % Releve.PAS_ECRITURE == 0 then
                    rendre()
                    if Releve.arrete then
                        return false
                    end
                end
            end
            w.fermer()
            w.fermer()
        end
        w.fermer()
        w.cle('format')
        w.valeur(Releve.FORMAT)
        w.fermer()
        return not Releve.arrete
    end)
    propre = propre + math.max(0, LrDate.currentTime() - depuis)
    dureeEcriture = propre
    Releve.ecritLe = os.time()
    if not ok then
        Releve.aEcrire = true
        Journal.noter("Suivi non enregistré :", tostring(ecrit))
        return false, tostring(ecrit)
    end
    if ecrit ~= true then
        -- Éteint pendant l'écriture : le fichier est à la nouvelle instance (un rechargement).
        Releve.aEcrire = true
        return false, "Suivi éteint"
    end
    tailleFichier = octets
    Releve.version = Releve.version + 1
    return true
end

-- Écrit le registre (ecrireLeRegistre), une écriture à la fois : une autre en cours, elle s'attend
-- (hors d'une tâche, rien n'est écrit : à la suivante). Rend vrai, ou faux et la raison. Jamais après
-- Releve.eteindre : le fichier est alors à la nouvelle instance du module (un rechargement) ; ce qui
-- n'est pas écrit se refait (une analyse revient en file, la vue suivante se range).
local function enregistrer()
    if Releve.arrete then
        return false, "Suivi éteint"
    end
    while enEcriture do
        if not LrTasks.canYield() then
            Releve.aEcrire = true
            return false, "écriture en cours"
        end
        LrTasks.sleep(0.05)
        if Releve.arrete then
            return false, "Suivi éteint"
        end
    end
    enEcriture = true
    local ok, fait, raison = LrTasks.pcall(ecrireLeRegistre)
    enEcriture = false
    if not ok then
        Releve.aEcrire = true
        Journal.noter("Suivi non enregistré :", tostring(fait))
        return false, tostring(fait)
    end
    return fait, raison
end

-- L'écart entre deux écritures : DELAI_ECRITURE secondes au moins, FACTEUR_ECRITURE fois la durée
-- propre de la dernière et SECONDES_PAR_MO par Mo du fichier (un grand relevé s'écrit moins souvent),
-- DELAI_ECRITURE_MAX au plus (ce qui n'est pas écrit se perd si Lightroom quitte).
function Releve.delaiEcriture()
    local delai = math.max(Releve.DELAI_ECRITURE, math.floor(Releve.FACTEUR_ECRITURE * dureeEcriture),
        math.floor(Releve.SECONDES_PAR_MO * tailleFichier / 1000000))
    return math.min(delai, math.max(Releve.DELAI_ECRITURE, Releve.DELAI_ECRITURE_MAX))
end

-- Vrai quand une écriture attend et que la dernière a son écart (Releve.delaiEcriture).
local function ecritureDue()
    return Releve.aEcrire and os.time() - (Releve.ecritLe or 0) >= Releve.delaiEcriture()
end

-- Une vue ou une analyse rangée : le fichier s'écrit si le dernier écrit a son écart, sinon à la
-- prochaine écriture, à son tour pendant une pause ou à la fin de la file (Releve.vider).
local function ecrireBientot()
    Releve.aEcrire = true
    if ecritureDue() then
        enregistrer()
    end
end

-- Écrit tout de suite ce qui attend son tour : la fenêtre Suivi, avant un dessin demandé
-- (--graphiques lit le fichier). Une écriture en cours (une autre tâche, qui rend la main) s'attend
-- d'abord : le fichier n'est remplacé qu'à sa fin, et ce qui s'est rangé pendant s'écrit ensuite.
-- Rend vrai si le fichier est écrit (par cet appel ou par celle qu'il a attendue).
function Releve.ecrire()
    local attendue = false
    if enEcriture and LrTasks.canYield() then
        local version = Releve.version
        while enEcriture and not Releve.arrete do
            LrTasks.sleep(0.05)
        end
        attendue = Releve.version ~= version
    end
    if not Releve.aEcrire then
        return attendue
    end
    return (enregistrer()) == true
end

-- Lectures (copies neuves) --------------------------------------------------------------------

-- Les entrées du catalogue ouvert, triées par identifiant de l'original (une copie de tout le
-- relevé : pour les essais et le diagnostic ; la fenêtre Suivi lit Releve.uuidsDe).
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

-- L'uuid de l'entrée de chacun de ces originaux au relevé du catalogue ouvert ({ [id] = uuid } ; un
-- original absent du relevé manque), lu dans le registre sans le copier, la main rendue toutes les
-- PAS : la fenêtre Suivi, au clic sur une barre (jusqu'à toute la bibliothèque).
function Releve.uuidsDe(ids)
    local photos = tableDu(cheminCatalogue() or '', false).photos
    local r = {}
    for i, id in ipairs(type(ids) == 'table' and ids or {}) do
        local e = photos[cleDe(id)]
        if type(e) == 'table' and type(e.uuid) == 'string' then
            r[tonumber(id) or id] = e.uuid
        end
        if i % Releve.PAS == 0 then
            rendreLaMain()
        end
    end
    return r
end

-- Lectures groupées du catalogue -------------------------------------------------------------------

-- Les métadonnées de ces photos, par lots de LOT_LECTURE : batchGetRawMetadata,
-- batchGetFormattedMetadata et batchGetPropertyForPlugin (SDK 3.0), comme Photos.decrireTout ;
-- une photo qu'une lecture groupée ne rend pas se lit une à une (une clé refusée ne gêne pas les
-- autres). La main rendue après chaque lecture groupée et toutes les PAS_UNE_A_UNE photos lues une à
-- une (correctif 1.3.8 : une sélection de toute la bibliothèque). Rend, pour chaque photo dans
-- l'ordre, { brut = {}, formate = {}, champ = {} } ; un texte formaté vide vaut nil.
local function lireGroupe(photos, brutes, formatees, champs)
    local lus = {}
    local cat = Photos.catalogue()
    local uneAUne = 0
    local function uneDePlus()
        uneAUne = uneAUne + 1
        if uneAUne % Releve.PAS_UNE_A_UNE == 0 then
            rendreLaMain()
        end
    end
    for debut = 1, #photos, Releve.LOT_LECTURE do
        local morceau = {}
        for i = debut, math.min(#photos, debut + Releve.LOT_LECTURE - 1) do
            morceau[#morceau + 1] = photos[i]
        end
        local okB, b, okF, f, okM, m = false, nil, false, nil, false, nil
        if brutes then
            okB, b = LrTasks.pcall(cat.batchGetRawMetadata, cat, morceau, brutes)
            rendreLaMain()
        end
        if formatees then
            okF, f = LrTasks.pcall(cat.batchGetFormattedMetadata, cat, morceau, formatees)
            rendreLaMain()
        end
        if champs then
            okM, m = LrTasks.pcall(cat.batchGetPropertyForPlugin, cat, morceau, _PLUGIN, champs)
            rendreLaMain()
        end
        for j, photo in ipairs(morceau) do
            local l = { brut = {}, formate = {}, champ = {} }
            local bp = okB and type(b) == 'table' and b[photo]
            for _, cle in ipairs(brutes or {}) do
                if type(bp) == 'table' then
                    l.brut[cle] = bp[cle]
                else
                    l.brut[cle] = Photos.brut(photo, cle)
                    uneDePlus()
                end
            end
            local fp = okF and type(f) == 'table' and f[photo]
            for _, cle in ipairs(formatees or {}) do
                local valeur
                if type(fp) == 'table' then
                    valeur = fp[cle]
                else
                    valeur = Photos.meta(photo, cle)
                    uneDePlus()
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
                    uneDePlus()
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
-- et ses copies virtuelles hors de « Développeur › Essais » (`essais` : Carnet.photosDesEssais, lu
-- d'un coup pour une grande série ; nil : Carnet.estPhotoDEssai, copie par copie). Par lectures
-- groupées, la main rendue toutes les PAS familles.
local function lireClassements(originaux, lus, essais)
    local membres, familleDe = {}, {}
    for i, original in ipairs(originaux) do
        membres[#membres + 1] = original
        familleDe[#membres] = i
        local copies = lus[i].brut.virtualCopies
        for _, copieVirtuelle in ipairs(type(copies) == 'table' and copies or {}) do
            if type(copieVirtuelle) == 'table' and copieVirtuelle ~= original then
                local dEssai
                if essais then
                    dEssai = Carnet.estDansLesEssais(essais, copieVirtuelle, original)
                else
                    dEssai = Carnet.estPhotoDEssai(copieVirtuelle)
                end
                if not dEssai then
                    membres[#membres + 1] = copieVirtuelle
                    familleDe[#membres] = i
                end
            end
        end
        if i % (essais and Releve.PAS or Releve.PAS_UNE_A_UNE) == 0 then
            rendreLaMain()
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
        if j % Releve.PAS == 0 then
            rendreLaMain()
        end
    end
    for i, k in ipairs(classements) do
        classements[i] = { note = k.note, retouchee = k.retouchee,
            drapeau = k.retenue and 'retenue' or (k.membres > 0 and k.rejetees == k.membres and 'rejetee' or 'aucun') }
    end
    return classements
end

-- Les photos des Essais d'un coup pour une grande série (au moins SEUIL_ESSAIS photos), sinon nil
-- (Carnet.estPhotoDEssai, photo par photo, comme avant le correctif 1.3.8).
local function essaisPour(n)
    if n >= Releve.SEUIL_ESSAIS then
        return Carnet.photosDesEssais()
    end
    return nil
end

-- Le classement lu d'une famille (lireClassements) posé sur son entrée, seulement s'il change (ou
-- s'il n'a jamais été posé) : classement_le dit alors quand. Rend vrai s'il a changé. Une entrée
-- inchangée garde son texte JSON (jsonDe) : Releve.reclasser sur tout le relevé, sans rien de changé
-- dans le catalogue, ne réécrit rien (à 250 000 originaux, 150 Mo réencodés et écrits à chaque
-- ouverture de la fenêtre Suivi).
local function poserClassement(e, k, maintenant)
    if e.classement_le ~= nil and e.note == k.note and e.drapeau == k.drapeau and e.retouchee_par_claude == k.retouchee then
        return false
    end
    e.note, e.drapeau, e.retouchee_par_claude, e.classement_le = k.note, k.drapeau, k.retouchee, maintenant
    changee(e)
    return true
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
-- Les vues sont prises d'un coup (la main rendue toutes les PAS photos, une vue ajoutée entre-temps
-- par l'autre fenêtre, plus récente, reste après la vue fondue ; une vue que la tâche du Suivi prend
-- entre-temps n'y est plus).
local function fusionnerVues()
    local vues = Releve.aVoir
    Releve.aVoir = {}
    local photos, deja, auDela, k = {}, {}, 0, 0
    for i = #vues, 1, -1 do
        for _, photo in ipairs(vues[i].photos) do
            local id = photo.localIdentifier
            if not deja[id] then
                deja[id] = true
                if #photos < Releve.MAX_SELECTION then
                    photos[#photos + 1] = photo
                else
                    auDela = auDela + 1
                end
            end
            k = k + 1
            if k % Releve.PAS == 0 then
                rendreLaMain()
            end
        end
    end
    if auDela > 0 then
        Journal.noter(string.format("Suivi : %d vues en attente fondues en une ; %d photo(s) au-delà de %d ne sont pas rangées",
            #vues, auDela, Releve.MAX_SELECTION))
    end
    table.insert(Releve.aVoir, 1, { photos = photos, le = os.time() })
end

-- Une sélection vue par la fenêtre Claude ou la Demande rapide (`info` : Lightroom.photos()) : si
-- elle a changé (sa clé, info.cle) ou après Releve.revoir, la photo active et les photos de la
-- sélection (MAX_SELECTION au plus, la photo active d'abord) s'ajoutent aux vues à ranger ; dans le
-- même groupe (info.groupe), une autre photo active ne revoit qu'elle, comme le même grand groupe
-- revu (Releve.revoir) moins de REVOIR_APRES secondes après sa dernière vue entière. Ne lit que la
-- sélection : la tâche (Releve.relancer) range la vue. Rend vrai si une vue s'ajoute. À appeler
-- depuis une tâche.
function Releve.voirSelection(info)
    if not Releve.allume or type(info) ~= 'table' or not info.cle or Releve.selectionPosee > 0 then
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
    local memeGroupe = info.groupe ~= nil and info.groupe == Releve.groupeVu
    local entier = Releve.aRevoir or not memeGroupe
    if Releve.aRevoir and memeGroupe and (tonumber(info.selection) or 0) > Releve.SEUIL_REVOIR
        and os.time() - (Releve.groupeVuLe or 0) < Releve.REVOIR_APRES then
        entier = false
    end
    Releve.cleVue, Releve.groupeVu, Releve.aRevoir = info.cle, info.groupe, false
    local photos = { active }
    if entier then
        Releve.groupeVuLe = os.time()
        -- Pas Lightroom.MAX_GROUPE (2 000, la clé d'un groupe de conversation) : la sélection se lit
        -- ici entière, par getTargetPhotos.
        local max = Releve.MAX_SELECTION
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

-- La fenêtre Suivi pose une sélection (FenetreSuivi.montrerPhotos : les photos d'une barre, toutes
-- prises au relevé) par `poser()`, dans une tâche : pendant ce temps, aucune sélection vue ne compte
-- (Releve.voirSelection : une sélection à moitié posée), puis la sélection posée est notée vue sans
-- être rangée (Releve.cleVue, groupeVu, groupeVuLe) : ses photos sont déjà au relevé, et à toute la
-- bibliothèque une vue entière relirait des dizaines de milliers de photos à chaque clic. Une autre
-- photo active ensuite dans la même sélection ne revoit qu'elle ; une autre sélection compte. Rend ce
-- que `poser` rend ; son erreur remonte.
function Releve.poserSelection(poser)
    Releve.selectionPosee = Releve.selectionPosee + 1
    local resultats = { LrTasks.pcall(poser) }
    Releve.selectionPosee = math.max(0, Releve.selectionPosee - 1)
    local info = Lightroom.photos()
    if Releve.selectionPosee == 0 and type(info) == 'table' and info.cle then
        Releve.cleVue, Releve.groupeVu, Releve.groupeVuLe = info.cle, info.groupe, os.time()
    end
    if not resultats[1] then
        error(resultats[2], 0)
    end
    return unpack(resultats, 2, table.maxn(resultats))
end

-- Range une vue : ses originaux au relevé (créés à leur première vue), leur prise de vue et le
-- classement de leur famille relus, la vue ajoutée à `vues`. Des lectures du catalogue, rien d'écrit
-- au catalogue : elle se range même pendant que Claude travaille. Le fichier s'écrit à son tour
-- (ecrireBientot : au plus toutes les Releve.delaiEcriture secondes). Une vue de toute la
-- bibliothèque se lit et se range par tranches, la main rendue (lireGroupe, PAS) ; les photos des
-- Essais se lisent alors d'un coup (essaisPour).
local function rangerVue(vue)
    local chemin = cheminCatalogue()
    if not chemin then
        Journal.noter("Suivi : chemin du catalogue ouvert illisible, vue non rangée")
        return false
    end
    local maintenant = os.time()
    local essais = essaisPour(#vue.photos)
    local lus = lireGroupe(vue.photos, CLES_VUE_BRUTES, CLES_VUE_FORMATEES)
    local familles, ordre = {}, {}
    local tete
    for i, photo in ipairs(vue.photos) do
        local l = lus[i]
        if l.brut.fileFormat ~= 'VIDEO' and texte(l.brut.uuid) then
            local original = photo
            if l.brut.isVirtualCopy == true and type(l.brut.masterPhoto) == 'table' then
                original = l.brut.masterPhoto
            end
            local dEssai
            if essais then
                dEssai = Carnet.estDansLesEssais(essais, photo, original)
            else
                dEssai = Carnet.estPhotoDEssai(photo)
            end
            if not dEssai then
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
        if i % (essais and Releve.PAS or Releve.PAS_UNE_A_UNE) == 0 then
            rendreLaMain()
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
    local classements = lireClassements(originaux, lo, essais)
    -- Éteint pendant les lectures (Arret.lua) : rien ne change.
    if not Releve.allume then
        return false
    end
    -- Tout est lu : le registre change entrée par entrée, chacune d'un coup, la main rendue toutes
    -- les PAS (une écriture d'une autre tâche entre deux ne voit que des entrées entières ;
    -- ecrireBientot, à la fin, fait écrire les autres à la suivante).
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
            -- Vue (vu, vues, prise de vue) : son texte JSON se refera ; un reclassement en cours ne
            -- remet pas le classement qu'il a lu avant elle.
            changee(e)
            if Releve.revues then
                Releve.revues[cle] = true
            end
            Releve.rangs[cle] = i
        end
        if i % Releve.PAS == 0 then
            rendreLaMain()
            if not Releve.allume then
                return false
            end
        end
    end
    if tete then
        Releve.tete = tete
    end
    -- La file gardée : les originaux de la vue passent devant (ils viennent d'être vus), sans la
    -- refaire entière (Releve.file ; sans file gardée, elle se refera).
    mettreDevant(c, ordre, maintenant)
    ecrireBientot()
    return true
end

-- Relit la note, le drapeau et « retouchée par Claude » de chaque famille du relevé du catalogue
-- ouvert (la fenêtre Suivi, après son premier dessin, dans une tâche à part), par tranches : chaque
-- original retrouvé par getPhotoByLocalId (la main rendue toutes les PAS_UNE_A_UNE), puis par
-- lectures groupées ; une écriture du fichier, seulement si un classement a changé (poserClassement).
-- Un original qui n'est plus au catalogue, ou d'un autre uuid, garde ce qu'il avait ; une entrée
-- qu'une vue range pendant qu'il tourne (Releve.revues, que rangerVue remplit) garde le classement de
-- la vue, plus frais que celui lu ici avant elle. Un seul à la fois (un autre en cours : 0). Rend le
-- nombre d'entrées dont le classement a changé. À appeler depuis une tâche.
local function reclasserTout()
    local chemin = cheminCatalogue()
    if not chemin then
        return 0
    end
    local c = tableDu(chemin, false)
    local cat = Photos.catalogue()
    -- Les clés d'abord : la main se rend pendant les lectures, et une vue rangée entre-temps ajoute
    -- des entrées (une table qui grandit ne se parcourt pas).
    local toutes = {}
    for cle in pairs(c.photos) do
        toutes[#toutes + 1] = cle
    end
    local cles, originaux = {}, {}
    for k, cle in ipairs(toutes) do
        if c.photos[cle] then
            local ok, photo = LrTasks.pcall(cat.getPhotoByLocalId, cat, tonumber(cle))
            if ok and type(photo) == 'table' then
                cles[#cles + 1] = cle
                originaux[#originaux + 1] = photo
            end
        end
        if k % Releve.PAS_UNE_A_UNE == 0 then
            rendreLaMain()
        end
    end
    local lo = lireGroupe(originaux, { 'uuid', 'virtualCopies' })
    local classements = lireClassements(originaux, lo, essaisPour(#originaux))
    local maintenant, n = os.time(), 0
    for i, cle in ipairs(cles) do
        local e = c.photos[cle]
        if e and not Releve.revues[cle] and e.uuid == texte(lo[i].brut.uuid) and poserClassement(e, classements[i], maintenant) then
            n = n + 1
        end
        if i % Releve.PAS == 0 then
            rendreLaMain()
        end
    end
    if n > 0 then
        Releve.aEcrire = true
        enregistrer()
    end
    return n
end

function Releve.reclasser()
    if Releve.reclassement then
        return 0
    end
    Releve.reclassement, Releve.revues = true, {}
    local ok, n = LrTasks.pcall(reclasserTout)
    Releve.reclassement, Releve.revues = false, nil
    if not ok then
        error(n, 0)
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
-- analyser maintenant, et dans combien de secondes la suivante le sera (nil : aucune). Les clés
-- d'abord (sans rendre la main : une table qu'une autre tâche agrandirait ne se parcourt pas), puis,
-- la main rendue toutes les PAS, chacune jugée et rangée dans le paquet de son heure de vue ; chaque
-- paquet trié par rang dans sa sélection puis par identifiant, en nombres (trierParVu : à 250 000
-- originaux, 125 000 en file, aucun tri de textes ni comparateur Lua sur toute la liste).
local RANG_ABSENT = 2 ^ 19 - 1
local function construireFile(c, maintenant)
    local toutes = {}
    for cle in pairs(c.photos) do
        toutes[#toutes + 1] = cle
    end
    local cles, attente, avecTete = {}, nil, false
    local tete = Releve.tete
    for k, cle in ipairs(toutes) do
        local e = c.photos[cle]
        local dans = e and quand(cle, e, maintenant)
        if dans == 0 then
            if cle == tete then
                avecTete = true
            else
                cles[#cles + 1] = cle
            end
        elseif dans then
            attente = math.min(attente or dans, dans)
        end
        if k % Releve.PAS == 0 then
            rendreLaMain()
        end
    end
    local rangs = Releve.rangs or {}
    local liste = trierParVu(cles, function(cle) return c.photos[cle] and c.photos[cle].vu or 0 end, function(cle)
        local id = idDe(cle)
        local rang = math.min(math.floor(tonumber(rangs[cle]) or RANG_ABSENT), RANG_ABSENT)
        return id and (math.max(0, rang) * ID_MAX + id) or nil
    end, true)
    if avecTete then
        table.insert(liste, 1, tete)
    end
    return liste, attente
end

-- Met ces clés (dans leur ordre, sans doublon) en tête de la file gardée, celles à analyser
-- maintenant : les originaux d'une vue rangée (rangerVue : la photo active d'abord, comme la file
-- refaite les rangerait), un lot remis (analyserLe). La suite de la file garde son ordre, sans ces
-- clés. Sans file gardée, rien : elle se refera entière. Seule la tâche du Suivi touche la file.
mettreDevant = function(c, cles, maintenant)
    local f = Releve.file
    if not f then
        return
    end
    local liste, devant = {}, {}
    for k, cle in ipairs(cles) do
        local e = c.photos[cle]
        if not devant[cle] and e and quand(cle, e, maintenant) == 0 then
            devant[cle] = true
            liste[#liste + 1] = cle
        end
        if k % Releve.PAS == 0 then
            rendreLaMain()
        end
    end
    if #liste == 0 then
        return
    end
    for i = f.i, #f.liste do
        local cle = f.liste[i]
        if not devant[cle] then
            liste[#liste + 1] = cle
        end
        if (i - f.i + 1) % Releve.PAS == 0 then
            rendreLaMain()
        end
    end
    Releve.file = { liste = liste, i = 1, attente = f.attente }
end

-- Refait la file du catalogue ouvert, entière (pour les essais et les relevés de durée : la tâche
-- du Suivi la refait elle-même, épuisée) ; rend sa longueur. À appeler depuis une tâche.
function Releve.refaireFile()
    local chemin = cheminCatalogue()
    if not chemin then
        return 0
    end
    local liste, attente = construireFile(tableDu(chemin, false), os.time())
    Releve.file = { liste = liste, i = 1, attente = attente }
    return #liste
end

-- Les analyses manquées dont l'heure est venue (Releve.reessais, dans l'ordre de leur heure), en tête
-- du lot : sans elles, une analyse manquée attendrait que toute la file gardée soit épuisée (à toute
-- la bibliothèque, des heures).
local function reessaisDus(c, maintenant, lot, dedans)
    local r = Releve.reessais
    local pris = 0
    while #lot < Releve.LOT_ANALYSE and pris < #r and r[pris + 1].le <= maintenant do
        pris = pris + 1
        local cle = r[pris].cle
        local e = c.photos[cle]
        if e and not dedans[cle] and quand(cle, e, maintenant) == 0 then
            lot[#lot + 1] = cle
            dedans[cle] = true
        end
    end
    if pris > 0 then
        local reste = {}
        for i = pris + 1, #r do
            reste[#reste + 1] = r[i]
        end
        Releve.reessais = reste
    end
end

-- Le prochain lot (LOT_ANALYSE clés au plus) : les analyses manquées dont l'heure est venue
-- (reessaisDus), puis la file gardée (les originaux d'une vue y passent devant : mettreDevant) ; nil
-- et l'attente quand elle est vide. Une file gardée épuisée se refait une fois : les lots analysés
-- depuis ont pu changer l'attente (une analyse manquée à réessayer) ou les règles connues.
local function prochainLot(c, maintenant)
    for _ = 1, 2 do
        local neuve = Releve.file == nil
        if neuve then
            local liste, attente = construireFile(c, maintenant)
            Releve.file = { liste = liste, i = 1, attente = attente }
        end
        local f, lot, dedans = Releve.file, {}, {}
        reessaisDus(c, maintenant, lot, dedans)
        while #lot < Releve.LOT_ANALYSE and f.i <= #f.liste do
            local cle = f.liste[f.i]
            f.i = f.i + 1
            local e = c.photos[cle]
            if e and not dedans[cle] and quand(cle, e, maintenant) == 0 then
                lot[#lot + 1] = cle
                dedans[cle] = true
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
    changee(e)
    -- À réessayer dans DELAI_REESSAI : elle passera devant la file gardée à son heure.
    if not e.analyse.abandonnee and #Releve.reessais < Releve.MAX_REESSAIS then
        Releve.reessais[#Releve.reessais + 1] = { cle = cle, le = maintenant + Releve.DELAI_REESSAI }
    end
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
                -- Des règles plus récentes que celles connues (la première réponse de la séance
                -- comprise) : des analyses sont peut-être à refaire, la file gardée n'en a aucune ;
                -- elle se refera au prochain lot.
                if not Releve.regles or regles > Releve.regles then
                    Releve.file = nil
                end
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
                changee(e)
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
        -- Le lot remis (Claude s'est mis au travail, ou le Suivi éteint) : il revient en tête de la
        -- file gardée.
        mettreDevant(c, lot, os.time())
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
            -- L'analyse attend. Ce qui est rangé s'écrit à son tour (Releve.delaiEcriture), pendant
            -- la pause comme hors d'elle : plus au début de chaque pause (correctif 1.3.8 : une liaison
            -- qui sert par moments, Claude Desktop qui enchaîne ses commandes, faisait écrire tout le
            -- relevé toutes les 7 s, juste quand une commande commençait).
            if ecritureDue() then
                enregistrer()
            end
            LrTasks.sleep(Releve.PAUSE)
        else
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
