-- FenetreSuivi.lua : la fenêtre « Claude · Suivi », en graphiques (correctif 1.3.7, décidé avec Dany
-- le 25 octobre 2026 ; fiche build/conception/1-3-7-a-faire.md, contrat figé dans
-- Tests/Contrats/suivi.json). Le bouton Suivi de l'en-tête de la fenêtre Claude l'ouvre
-- (Fenetre.ouvrirSuivi) ; ouverte, il la remet devant. Elle montre le relevé du Suivi (suivi.json,
-- tenu par Releve.lua : toute photo ouverte dans la fenêtre Claude ou la Demande rapide, analysée
-- d'office par le connecteur) et le carnet de progrès (carnet.json, ce que Claude a vu), sur une
-- période (menu Période : 3 derniers mois, 12 derniers mois par défaut, Tout) :
--
--   - quatre tuiles chiffrées : photos ouvertes, retouchées par Claude, notées 4 ★ ou plus, défaut
--     le plus fréquent ;
--   - « Mes prises de vue » : photos par mois (par date de prise de vue), focales, ISO, heure de la
--     prise de vue, objectifs ;
--   - « Mon carnet de progrès » : les défauts les plus fréquents (en % des photos où ils sont
--     cherchés) et l'évolution mois par mois d'un défaut (le plus fréquent par défaut, un menu pour
--     en choisir un autre) ; dessous, « Photos d'un défaut… » (les photos d'un défaut du carnet, et
--     « Retirer du carnet… »), comme dans la fenêtre de la 1.3.6.
--
-- Lightroom ne trace pas de graphique : les sept images sont dessinées par le connecteur
-- (`mcp-developpeur --graphiques '<json>' <dossier>`, sous l'alarme de perl comme --focus), en PNG
-- 2x, dans les couleurs de l'apparence du module (Dispositions.PALETTES, seule table des couleurs,
-- passées au connecteur : FenetreSuivi.couleursConnecteur) ; il rend aussi, en une ligne JSON, les
-- tuiles et, pour chaque graphique, ses barres et ses créneaux. Les images se refont dans une tâche
-- (la boucle de la fenêtre, FenetreSuivi.suivre) : à l'ouverture (après Releve.reclasser, qui relit
-- la note, le drapeau et « retouchée par Claude » de chaque famille), au changement de période ou
-- de défaut, et quand le relevé ou le carnet change pendant qu'elle est ouverte (Releve.version,
-- Carnet.version ; DELAI_REDESSIN entre deux) ; avant chacune, ce que le Suivi a rangé sans
-- l'écrire encore s'écrit (Releve.ecrire : ses écritures sont espacées). Chaque dessin a son
-- dossier neuf (Temporaire/Suivi/Graphiques-…, Lightroom garde une image par chemin) ;
-- l'avant-dernier s'efface quand le nouveau est montré, tous à la fermeture. Sans réponse lisible
-- du connecteur, rien ne change et la fenêtre le dit ; sans connecteur, elle le dit aussi.
--
-- Structure fixe à la création (règle de la fenêtre B) : sept f:picture liées (`image_<g>`), et sur
-- chacune un calque par créneau possible (photos par mois 12, focales 8, ISO 8, heures 12,
-- objectifs 8, défauts 8, évolution 12 : 68 calques). Les rectangles des créneaux ne dépendent que
-- de la taille du graphique (contrat : regles.geometrie, FenetreSuivi.creneaux) : chaque calque est
-- posé à sa place une fois pour toutes, dans une colonne poussée par ses marges (la colonne ne prend
-- pas les clics : constaté D6) ; seule la barre qui l'occupe change d'une réponse à l'autre, d'où sa
-- visibilité liée (`c_<g>_<i>` : une barre qui a des photos) et son infobulle liée (`i_<g>_<i>` : le
-- détail de la barre). Pas de menu « Voir les photos… » : les calques suffisent. Un clic montre les
-- photos de la barre dans la Bibliothèque (FenetreSuivi.montrerPhotos : les originaux retrouvés par
-- leur identifiant et vérifiés par l'uuid de leur entrée, sélectionnés en grille, Toutes les
-- photographies comme source quand la source affichée ne les a pas toutes ; seules comptent les
-- photos demandées que Lightroom cible, la photo active parmi elles), sans rien écrire au
-- catalogue. Fonds en aplats (f:picture sans image, comme la fenêtre Claude) dans les couleurs de
-- l'apparence, pour que les images s'y fondent ; les menus et les boutons restent ceux du système.
-- Toute table donnée à Lightroom est neuve : la réponse décodée du connecteur ne sert qu'à faire des
-- textes et des booléens.

local LrApplicationView = import 'LrApplicationView'
local LrBinding = import 'LrBinding'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

require 'Compat'
local Carnet = require 'Carnet'
local Chemins = require 'Chemins'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'
local Metriques = require 'Metriques'
local Photos = require 'Photos'
local Releve = require 'Releve'
local Texte = require 'Texte'

local FenetreSuivi = { ouverte = false }

-- Le titre de la fenêtre (les fenêtres du module gardent « Claude · … »), son cadre gardé (un nom
-- neuf pour la fenêtre en graphiques : celle de la 1.3.6, « DeveloppeurCarnet », n'avait pas cette
-- taille ; le nom change avec la taille du contenu) et le titre du carnet, que le registre donne
-- (seule copie).
FenetreSuivi.TITRE = "Claude · Suivi"
FenetreSuivi.CADRE = 'DeveloppeurSuiviGraphiques-1'
FenetreSuivi.TITRE_CARNET = Carnet.TITRES.carnet
FenetreSuivi.TITRE_DEFAUTS = "Photos d'un défaut"

-- Les textes de la fenêtre.
FenetreSuivi.ENTETE = "Suivi de vos photos"
FenetreSuivi.PRISES_DE_VUE = "Mes prises de vue"
FenetreSuivi.CARNET = "Mon carnet de progrès"
FenetreSuivi.LECTURE = "Lecture du suivi…"
FenetreSuivi.ATTENTE = "Dessin des graphiques…"
FenetreSuivi.ACCUEIL = "Le Suivi part de zéro : chaque photo que vous ouvrez dans la fenêtre Claude ou la Demande rapide y entre, "
    .. "seule ou dans une sélection, et le connecteur l'analyse d'office sur sa vignette, sans Claude ni forfait. Les graphiques se "
    .. "remplissent au fil de vos photos."
FenetreSuivi.SANS_PHOTO_PERIODE = "Aucune photo ouverte dans cette période."
FenetreSuivi.VOIR_TOUT = " Choisissez « Tout » pour voir les autres."
FenetreSuivi.CONNECTEUR_ABSENT = "Le connecteur mcp-developpeur est introuvable (son chemin : Gestionnaire de modules externes › "
    .. "Développeur) : les graphiques ne se dessinent pas."
FenetreSuivi.PAS_DE_REPONSE = "Le connecteur n'a pas répondu à temps : les graphiques ne sont pas refaits."
FenetreSuivi.REFUS = "Le connecteur n'a pas dessiné les graphiques : "
FenetreSuivi.SANS_CATALOGUE = "Le chemin du catalogue ouvert ne se lit pas : les graphiques ne se dessinent pas."
FenetreSuivi.SANS_GRAPHIQUE = "Pas de graphique."
FenetreSuivi.AIDE = "Un clic sur une barre montre ses photos dans la Bibliothèque, sans rien changer. Les défauts viennent de "
    .. "l'analyse d'office de chaque photo ouverte (sur sa vignette, sans Claude) ; l'horizon et la mise au point, de ce que Claude "
    .. "a vu en regardant la photo."
FenetreSuivi.INFOBULLE_BARRE = "Un clic : ces photos dans la Bibliothèque"

-- Les périodes du menu, dans leur ordre (contrat : graphiques.entree.periode), et celle de
-- l'ouverture.
FenetreSuivi.PERIODES = {
    { title = "3 derniers mois", value = '3_mois' },
    { title = "12 derniers mois", value = '12_mois' },
    { title = "Tout", value = 'tout' },
}
FenetreSuivi.PERIODE = '12_mois'

-- La valeur du menu du défaut suivi qui n'en choisit aucun : le plus fréquent (le connecteur le
-- cherche ; contrat : graphiques.defaut_suivi).
FenetreSuivi.LE_PLUS_FREQUENT = 'le_plus_frequent'
FenetreSuivi.TITRE_PLUS_FREQUENT = "Le plus fréquent"

-- Les quatre tuiles, dans l'ordre du contrat (graphiques.tuiles) : leur clé et leur titre avant la
-- première réponse (le connecteur rend le sien).
FenetreSuivi.TUILES = {
    { cle = 'photos_ouvertes', titre = "Photos ouvertes" },
    { cle = 'retouchees_par_claude', titre = "Retouchées par Claude" },
    { cle = 'notees_4_plus', titre = "Notées 4 ★ ou plus" },
    { cle = 'defaut_frequent', titre = "Défaut le plus fréquent" },
}

-- Les sept graphiques (contrat : graphiques.liste), dans l'ordre de la fenêtre : leur taille en
-- points (celle que la fenêtre demande au connecteur : graphiques.entree.tailles), leur nombre de
-- créneaux et leur sens, d'où les rectangles des créneaux ; le titre avant la première réponse.
FenetreSuivi.GRAPHIQUES = {
    { cle = 'photos_par_mois', titre = "Photos par mois", largeur = 620, hauteur = 150, max_barres = 12, orientation = 'verticale' },
    { cle = 'focales', titre = "Focales (mm)", largeur = 300, hauteur = 130, max_barres = 8, orientation = 'verticale' },
    { cle = 'iso', titre = "Sensibilité (ISO)", largeur = 300, hauteur = 130, max_barres = 8, orientation = 'verticale' },
    { cle = 'heures', titre = "Heure de la prise de vue", largeur = 620, hauteur = 120, max_barres = 12, orientation = 'verticale' },
    { cle = 'objectifs', titre = "Objectifs", largeur = 300, hauteur = 170, max_barres = 8, orientation = 'horizontale' },
    { cle = 'defauts_frequents', titre = "Défauts les plus fréquents", largeur = 620, hauteur = 180, max_barres = 8,
        orientation = 'horizontale', lignesNote = 2 },
    { cle = 'evolution_defaut', titre = "Évolution d'un défaut", largeur = 620, hauteur = 140, max_barres = 12, orientation = 'verticale' },
}

-- Les six couleurs passées au connecteur, tirées de Dispositions.PALETTES[apparence] (contrat :
-- couleurs.cles) : fond de l'image (celui de la fenêtre), libellés, valeurs et notes, ligne de base,
-- barres, défaut suivi.
FenetreSuivi.COULEURS_CONNECTEUR = { fond = 'fondDroite', texte = 'texte', gris = 'gris', filet = 'filetDroite', barre = 'bleu',
    accent = 'orange' }

-- Le connecteur : alarme de perl (contrat : graphiques.commande), secondes entre deux dessins
-- faits d'eux-mêmes (le relevé s'écrit au plus toutes les 20 s pendant les analyses), et le délai
-- pendant lequel la sélection se refait après un changement de source (comme Bibliotheque :
-- Lightroom met un moment à afficher la source, constaté en 2.3).
FenetreSuivi.ALARME = 20
FenetreSuivi.DELAI_REDESSIN = 10
FenetreSuivi.DELAI_SOURCE = 3

-- La disposition, en points : marges, colonnes de 620 (la largeur des grands graphiques ; les
-- petits, de 300, vont par deux à 20 d'écart), tuiles, hauteurs des textes. Le contenu en tire sa
-- taille (FenetreSuivi.dimensions), et la fenêtre la sienne (D7 : barre de titre de 33, 1 de
-- marge) : 1 310 × 1 028 points, qui tient sur l'écran de Dany (1 440 de haut) avec la barre des
-- menus et le Dock.
FenetreSuivi.TAILLES = {
    marge = 20, colonne = 620, ecartColonnes = 28, ecartPetits = 20, ecartBlocs = 12,
    entete = 28, etat = 30, ecartEtat = 6, ecartTuiles = 12, sousTuiles = 18,
    tuile = 305, hauteurTuile = 84, ecartTuile = 16,
    section = 18, sousSection = 8, titreGraphique = 16, sousTitre = 4, sousGraphique = 2, ligneNote = 14,
    enteteEvolution = 22, aide = 44, bas = 28,
    periode = 170, etiquettePeriode = 62, defaut = 290, defautsBouton = 170,
}

local function police(cle)
    local m = Metriques[cle]
    return { name = m.nom, size = m.taille }
end

-- Les polices mesurées (Metriques.lua) : le titre en gras 16, les sections en gras 13, les titres
-- des graphiques en gras 12, les étiquettes en 12, les notes en petit ; les chiffres des tuiles en
-- gras 24 (une seule ligne, coupée au besoin).
FenetreSuivi.POLICES = { titre = police('titre'), gras = police('gras'), gras12 = police('gras12'), texte12 = police('texte12'),
    petit = police('petit'), chiffre = { name = '<system/bold>', size = 24 } }

local bind = LrView.bind
local q = Texte.shell

local function poser(p, cle, valeur)
    if p[cle] ~= valeur then
        p[cle] = valeur
    end
end

local function texteOuNil(valeur)
    if type(valeur) == 'string' and Texte.nettoyer(valeur) ~= '' then
        return Texte.nettoyer(valeur)
    end
    return nil
end

-- Géométrie ----------------------------------------------------------------------------------

-- Les dimensions du contenu, tirées des tailles (une table neuve) : largeur intérieure (deux
-- colonnes), hauteur de chaque colonne, du contenu et de la fenêtre.
function FenetreSuivi.dimensions()
    local T = FenetreSuivi.TAILLES
    local D = {}
    for cle, valeur in pairs(T) do
        D[cle] = valeur
    end
    D.interieur = 2 * T.colonne + T.ecartColonnes
    D.largeurContenu = D.interieur + 2 * T.marge
    local function bloc(g)
        return T.titreGraphique + T.sousTitre + g.hauteur + T.sousGraphique + (g.lignesNote or 1) * T.ligneNote
    end
    local G = {}
    for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
        G[g.cle] = g
    end
    D.gauche = T.section + T.sousSection + bloc(G.photos_par_mois) + T.ecartBlocs + math.max(bloc(G.focales), bloc(G.iso))
        + T.ecartBlocs + bloc(G.heures) + T.ecartBlocs + bloc(G.objectifs)
    D.droite = T.section + T.sousSection + bloc(G.defauts_frequents) + T.ecartBlocs
        + (T.enteteEvolution - T.titreGraphique) + bloc(G.evolution_defaut) + T.ecartBlocs + T.aide + T.ecartBlocs + T.bas
    D.hauteurContenu = T.marge + T.entete + T.ecartEtat + T.etat + T.ecartTuiles + T.hauteurTuile + T.sousTuiles
        + math.max(D.gauche, D.droite) + T.marge
    D.largeurFenetre, D.hauteurFenetre = D.largeurContenu + 2, D.hauteurContenu + 34
    return D
end

-- Le graphique de cette clé (FenetreSuivi.GRAPHIQUES), nil s'il n'existe pas.
function FenetreSuivi.graphique(cle)
    for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
        if g.cle == cle then
            return g
        end
    end
    return nil
end

-- Les créneaux d'un graphique, dans le repère de son image (contrat : regles.geometrie) : pour un
-- graphique vertical de n créneaux, x_i = 8 + floor((i − 1) × (L − 16) / n), le dernier finissant à
-- L − 8, toute la hauteur ; pour un horizontal, y_i = 4 + floor((i − 1) × (H − 8) / n), le dernier
-- finissant à H − 4, toute la largeur. Ils ne dépendent que de la taille : les mêmes à chaque
-- réponse. Tables neuves.
function FenetreSuivi.creneaux(g)
    local L, H, n = g.largeur, g.hauteur, g.max_barres
    local liste = {}
    if g.orientation == 'horizontale' then
        local function y(i)
            if i > n then
                return H - 4
            end
            return 4 + math.floor((i - 1) * (H - 8) / n)
        end
        for i = 1, n do
            liste[i] = { x = 0, y = y(i), largeur = L, hauteur = y(i + 1) - y(i) }
        end
    else
        local function x(i)
            if i > n then
                return L - 8
            end
            return 8 + math.floor((i - 1) * (L - 16) / n)
        end
        for i = 1, n do
            liste[i] = { x = x(i), y = 0, largeur = x(i + 1) - x(i), hauteur = H }
        end
    end
    return liste
end

-- Les clés liées d'un calque : sa visibilité et son infobulle.
function FenetreSuivi.cleCalque(cle, i)
    return 'c_' .. cle .. '_' .. i, 'i_' .. cle .. '_' .. i
end

-- L'entrée de --graphiques -----------------------------------------------------------------------

-- La date du jour à l'heure locale (« AAAA-MM-JJ ») : les périodes ne dépendent pas de l'horloge du
-- connecteur (contrat : graphiques.entree.aujourd_hui).
function FenetreSuivi.aujourdhui()
    return os.date('%Y-%m-%d')
end

-- L'apparence du module (préférence `apparence`, Dispositions.apparence).
function FenetreSuivi.apparence()
    return Dispositions.apparence(Chemins.prefs().apparence)
end

-- Les six couleurs pour le connecteur, en six chiffres hexadécimaux (une table neuve).
function FenetreSuivi.couleursConnecteur(apparence)
    local palette = Dispositions.PALETTES[Dispositions.apparence(apparence)]
    local r = {}
    for cle, nom in pairs(FenetreSuivi.COULEURS_CONNECTEUR) do
        r[cle] = string.upper(palette[nom])
    end
    return r
end

-- Le chemin du catalogue ouvert, nil s'il ne se lit pas (depuis une tâche).
local function cheminCatalogue()
    local ok, chemin = LrTasks.pcall(function()
        local cat = Photos.catalogue()
        return cat and cat:getPath()
    end)
    return ok and texteOuNil(chemin) or nil
end

-- L'entrée de --graphiques (contrat : graphiques.entree), pour cette période et ce défaut (nil :
-- le plus fréquent). Rend nil et la raison sans catalogue lisible.
function FenetreSuivi.entree(periode, defaut)
    local catalogue = cheminCatalogue()
    if not catalogue then
        return nil, FenetreSuivi.SANS_CATALOGUE
    end
    local apparence = FenetreSuivi.apparence()
    local tailles = {}
    for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
        tailles[g.cle] = { largeur = g.largeur, hauteur = g.hauteur }
    end
    local entree = {
        suivi = Releve.fichier(),
        carnet = Carnet.fichier(),
        catalogue = catalogue,
        aujourd_hui = FenetreSuivi.aujourdhui(),
        periode = periode or FenetreSuivi.PERIODE,
        apparence = apparence,
        couleurs = FenetreSuivi.couleursConnecteur(apparence),
        tailles = tailles,
    }
    if defaut ~= nil and defaut ~= FenetreSuivi.LE_PLUS_FREQUENT then
        entree.defaut = defaut
    end
    return entree
end

-- La réponse : textes, menu et calques ------------------------------------------------------------

-- « décembre 2025 » d'un mois « 2025-12 » (Carnet.MOIS, seule copie des noms des mois).
local function nomDuMois(aaaamm)
    local a, m = tostring(aaaamm or ''):match('^(%d%d%d%d)%-(%d%d)$')
    local nom = m and Carnet.MOIS[tonumber(m)]
    return nom and (nom .. ' ' .. a) or nil
end

-- La ligne d'état d'une réponse : la période et ses photos, et ses remarques ; sans photo au relevé,
-- le texte d'accueil ; sans photo dans la période, ce qu'il faut choisir.
function FenetreSuivi.texteEtat(reponse, sansReleve)
    if sansReleve then
        return FenetreSuivi.ACCUEIL
    end
    local morceaux = {}
    local periode = type(reponse) == 'table' and type(reponse.periode) == 'table' and reponse.periode or {}
    local n = type(reponse) == 'table' and tonumber(reponse.photos) or 0
    if n == 0 then
        morceaux[1] = FenetreSuivi.SANS_PHOTO_PERIODE .. (periode.code ~= 'tout' and FenetreSuivi.VOIR_TOUT or '')
    else
        local debut, fin = nomDuMois(periode.debut), nomDuMois(periode.fin)
        local quand = (debut and fin) and (debut == fin and ("en " .. fin) or ("de " .. debut .. " à " .. fin)) or nil
        morceaux[1] = (texteOuNil(periode.libelle) or "Période") .. (quand and (" : " .. quand) or "")
            .. string.format(" · %d photo%s ouverte%s", n, n > 1 and "s" or "", n > 1 and "s" or "")
        local sansDate = tonumber(reponse.sans_date) or 0
        if sansDate > 0 then
            morceaux[1] = morceaux[1] .. string.format(", dont %d sans date de prise de vue (à leur date d'ajout)", sansDate)
        end
        morceaux[1] = morceaux[1] .. '.'
    end
    for _, r in ipairs(type(reponse) == 'table' and type(reponse.remarques) == 'table' and reponse.remarques or {}) do
        if texteOuNil(r) then
            morceaux[#morceaux + 1] = texteOuNil(r)
        end
    end
    return table.concat(morceaux, ' ')
end

-- Le libellé d'un défaut de la réponse (son menu), sinon son code.
local function libelleDefaut(reponse, code)
    for _, d in ipairs(type(reponse) == 'table' and type(reponse.defauts) == 'table' and reponse.defauts or {}) do
        if d.code == code then
            return texteOuNil(d.libelle) or tostring(code)
        end
    end
    return code and tostring(code) or nil
end

-- Les éléments du menu du défaut suivi (tables neuves) : « Le plus fréquent » (avec son libellé
-- quand il y en a un), puis les huit défauts comptés de la réponse, dans leur ordre, avec leur
-- pourcentage dans la période (« — » : cherché sur aucune photo).
function FenetreSuivi.elementsDefaut(reponse)
    local frequent
    for _, t in ipairs(type(reponse) == 'table' and type(reponse.tuiles) == 'table' and reponse.tuiles or {}) do
        if t.cle == 'defaut_frequent' and type(t.code) == 'string' then
            frequent = libelleDefaut(reponse, t.code)
        end
    end
    local items = { { title = FenetreSuivi.TITRE_PLUS_FREQUENT .. (frequent and (" : " .. frequent) or ""),
        value = FenetreSuivi.LE_PLUS_FREQUENT } }
    local defauts = type(reponse) == 'table' and type(reponse.defauts) == 'table' and reponse.defauts or {}
    if #defauts > 0 then
        items[#items + 1] = { separator = true }
    end
    for _, d in ipairs(defauts) do
        if type(d.code) == 'string' then
            items[#items + 1] = { title = (texteOuNil(d.libelle) or d.code) .. " · " .. (texteOuNil(d.texte) or "—"), value = d.code }
        end
    end
    return items
end

-- La barre qui occupe le créneau `i` du graphique `cle` dans la réponse montrée, nil sans barre.
function FenetreSuivi.barreDu(cle, i)
    local r = FenetreSuivi.reponse
    local g = type(r) == 'table' and type(r.graphiques) == 'table' and r.graphiques[cle]
    if type(g) ~= 'table' or not FenetreSuivi.calquesValides[cle] then
        return nil
    end
    local c = type(g.creneaux) == 'table' and g.creneaux[i]
    local rang = type(c) == 'table' and tonumber(c.barre) or 0
    local barre = rang > 0 and type(g.barres) == 'table' and g.barres[rang] or nil
    return type(barre) == 'table' and barre or nil
end

-- Les ids d'une barre, en nombres (une table neuve).
local function idsDe(barre)
    local ids = {}
    for _, id in ipairs(type(barre) == 'table' and type(barre.ids) == 'table' and barre.ids or {}) do
        if tonumber(id) then
            ids[#ids + 1] = tonumber(id)
        end
    end
    return ids
end

-- Les créneaux d'une réponse sont-ils ceux de la fenêtre (posés à la création) ? Sinon ses calques
-- restent cachés : un clic tomberait à côté de la barre dessinée.
local function memesCreneaux(g, rendu)
    local attendus = FenetreSuivi.creneaux(g)
    if type(rendu) ~= 'table' or #rendu ~= #attendus then
        return false
    end
    for i, c in ipairs(attendus) do
        local r = rendu[i]
        if type(r) ~= 'table' or tonumber(r.x) ~= c.x or tonumber(r.y) ~= c.y or tonumber(r.largeur) ~= c.largeur
            or tonumber(r.hauteur) ~= c.hauteur then
            return false
        end
    end
    return true
end

FenetreSuivi.calquesValides = {}

-- Montre une réponse du connecteur (ok vrai) : tuiles, titres, notes, images, menu du défaut, et
-- chaque calque d'après la barre de son créneau. Rend vrai.
function FenetreSuivi.montrer(reponse)
    local p = FenetreSuivi.p
    FenetreSuivi.reponse = reponse
    if not p then
        return false
    end
    local tuiles = type(reponse.tuiles) == 'table' and reponse.tuiles or {}
    for k, t in ipairs(FenetreSuivi.TUILES) do
        local rendue
        for _, x in ipairs(tuiles) do
            if type(x) == 'table' and x.cle == t.cle then
                rendue = x
            end
        end
        poser(p, 'tuileTitre' .. k, texteOuNil(rendue and rendue.titre) or t.titre)
        poser(p, 'tuileTexte' .. k, texteOuNil(rendue and rendue.texte) or "—")
        poser(p, 'tuileDetail' .. k, texteOuNil(rendue and rendue.detail) or '')
    end
    local graphiques = type(reponse.graphiques) == 'table' and reponse.graphiques or {}
    for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
        local rendu = graphiques[g.cle]
        local fichier = type(rendu) == 'table' and texteOuNil(rendu.fichier) or nil
        local pret = fichier ~= nil and Fichiers.existe(fichier)
        poser(p, 'titre_' .. g.cle, texteOuNil(type(rendu) == 'table' and rendu.titre) or g.titre)
        poser(p, 'note_' .. g.cle, texteOuNil(type(rendu) == 'table' and rendu.note) or '')
        if pret then
            poser(p, 'image_' .. g.cle, fichier)
        end
        poser(p, 'pret_' .. g.cle, pret)
        local valides = pret and memesCreneaux(g, rendu.creneaux)
        if pret and not valides then
            Journal.noter("Fenêtre Suivi : créneaux de " .. g.cle .. " autres que ceux de la fenêtre : ses barres ne se cliquent pas")
        end
        FenetreSuivi.calquesValides[g.cle] = valides or nil
        for i = 1, g.max_barres do
            local visible, infobulle = FenetreSuivi.cleCalque(g.cle, i)
            local barre = valides and FenetreSuivi.barreDu(g.cle, i) or nil
            local actif = barre ~= nil and #idsDe(barre) > 0
            poser(p, visible, actif)
            poser(p, infobulle, actif and ((texteOuNil(barre.detail) or texteOuNil(barre.libelle) or '') .. "\n"
                .. FenetreSuivi.INFOBULLE_BARRE) or '')
        end
    end
    p.elementsDefaut = FenetreSuivi.elementsDefaut(reponse)
    poser(p, 'attente', FenetreSuivi.SANS_GRAPHIQUE)
    poser(p, 'etat', FenetreSuivi.texteEtat(reponse, FenetreSuivi.sansReleve))
    return true
end

-- Le dessin ------------------------------------------------------------------------------------

-- Les dossiers des dessins de cette ouverture, du plus ancien au plus récent.
FenetreSuivi.dossiers = {}
local numeroDessin = 0

local function nouveauDossier()
    numeroDessin = numeroDessin + 1
    return LrPathUtils.child(LrPathUtils.child(Chemins.temporaire(), 'Suivi'), string.format('Graphiques-%d-%d', os.time(), numeroDessin))
end

-- Un dessin manqué : la fenêtre le dit ; les images d'avant restent (sans réponse, rien ne change).
local function echec(texte)
    FenetreSuivi.derniereErreur = texte
    if FenetreSuivi.p then
        poser(FenetreSuivi.p, 'etat', texte)
        poser(FenetreSuivi.p, 'attente', FenetreSuivi.SANS_GRAPHIQUE)
    end
    return false
end

-- Lance `mcp-developpeur --graphiques` (depuis une tâche) pour la période et le défaut choisis, puis
-- montre sa réponse. Rend vrai si les graphiques sont refaits.
function FenetreSuivi.dessiner()
    local p = FenetreSuivi.p
    local generation = FenetreSuivi.generation
    FenetreSuivi.aRedessiner = false
    -- Ce que le Suivi a rangé sans l'écrire encore (ses écritures sont espacées :
    -- Releve.DELAI_ECRITURE) s'écrit d'abord : --graphiques lit le fichier.
    local okEcrit, erreurEcrit = LrTasks.pcall(Releve.ecrire)
    if not okEcrit then
        Journal.noter("Fenêtre Suivi : relevé non écrit avant le dessin :", tostring(erreurEcrit))
    end
    FenetreSuivi.releveDessine, FenetreSuivi.carnetDessine = Releve.version, Carnet.version
    FenetreSuivi.dessineLe = os.time()
    FenetreSuivi.derniereErreur = nil
    local okNombre, n = LrTasks.pcall(Releve.nombre)
    FenetreSuivi.sansReleve = okNombre and n == 0
    local connecteur = Chemins.prefs().cheminConnecteur
    if type(connecteur) ~= 'string' or connecteur == '' or not Fichiers.existe(connecteur) then
        return echec(FenetreSuivi.CONNECTEUR_ABSENT)
    end
    local entree, raison = FenetreSuivi.entree(p and p.periode, p and p.defaut)
    if not entree then
        return echec(raison)
    end
    local dossier = nouveauDossier()
    Fichiers.creerDossier(dossier)
    local fichierReponse = LrPathUtils.child(dossier, 'reponse.json')
    LrTasks.execute(string.format("/usr/bin/perl -e 'alarm %d; exec @ARGV' %s --graphiques %s %s > %s 2>/dev/null", FenetreSuivi.ALARME,
        q(connecteur), q(Json.encode(entree)), q(dossier), q(fichierReponse)))
    -- La fenêtre fermée (ou rouverte) pendant le dessin : rien à montrer.
    if not FenetreSuivi.ouverte or FenetreSuivi.generation ~= generation or FenetreSuivi.p ~= p then
        Fichiers.supprimer(dossier)
        return false
    end
    -- La réponse se lit dans son fichier (avec tous les ids, elle peut dépasser 700 Ko).
    local ok, reponse = pcall(Json.decode, Fichiers.lire(fichierReponse) or '')
    if not ok or type(reponse) ~= 'table' then
        Fichiers.supprimer(dossier)
        return echec(FenetreSuivi.PAS_DE_REPONSE)
    end
    if reponse.ok ~= true then
        Fichiers.supprimer(dossier)
        local texte = texteOuNil(reponse.texte) or texteOuNil(reponse.raison) or "réponse sans texte"
        Journal.noter("Fenêtre Suivi : --graphiques refusé :", texte)
        return echec(FenetreSuivi.REFUS .. texte)
    end
    FenetreSuivi.montrer(reponse)
    -- Le nouveau dessin est montré : l'avant-dernier s'efface (le dernier peut encore être à l'écran
    -- le temps que Lightroom lise les nouvelles images).
    local dossiers = FenetreSuivi.dossiers
    dossiers[#dossiers + 1] = dossier
    while #dossiers > 2 do
        Fichiers.supprimer(table.remove(dossiers, 1))
    end
    return true
end

-- Efface les dossiers des dessins (à la fermeture).
function FenetreSuivi.effacerDessins()
    for _, dossier in ipairs(FenetreSuivi.dossiers) do
        Fichiers.supprimer(dossier)
    end
    FenetreSuivi.dossiers = {}
end

-- Un clic sur une barre : la Bibliothèque --------------------------------------------------------------

-- Sélectionne ces photos ; vrai si Lightroom les a toutes sélectionnées, et combien d'entre elles il
-- a sélectionnées. Seules comptent les photos demandées, et la photo active doit en être une (comme
-- Bibliotheque.selectionner) : sans sélection, getTargetPhotos rend tout le film fixe
-- (getMultipleSelectedOrAllPhotos, relevé en lecture seule dans le LrCatalog.lua compilé de
-- Lightroom 15.6), et setSelectedPhotos ne sélectionne que les photos qui ont une case dans la
-- grille (une photo d'un autre dossier laisse la sélection vide, ou telle quelle) : le nombre de
-- photos ciblées n'en dit rien.
local function selectionner(cat, photos)
    local autres, demandees = {}, {}
    for i, photo in ipairs(photos) do
        demandees[photo.localIdentifier] = true
        if i > 1 then
            autres[#autres + 1] = photo
        end
    end
    LrTasks.pcall(cat.setSelectedPhotos, cat, photos[1], autres)
    local okActive, active = LrTasks.pcall(cat.getTargetPhoto, cat)
    if not okActive or type(active) ~= 'table' or not demandees[active.localIdentifier] then
        return false, 0
    end
    local ok, cibles = LrTasks.pcall(cat.getTargetPhotos, cat)
    local n, comptees = 0, {}
    for _, cible in ipairs(ok and type(cibles) == 'table' and cibles or {}) do
        local id = type(cible) == 'table' and cible.localIdentifier or nil
        if id ~= nil and demandees[id] and not comptees[id] then
            comptees[id] = true
            n = n + 1
        end
    end
    return n == #photos, n
end

-- L'uuid de chaque photo, par une lecture groupée (sinon une à une).
local function uuidsDe(cat, photos)
    local ok, lus = LrTasks.pcall(function() return cat:batchGetRawMetadata(photos, { 'uuid' }) end)
    local r = {}
    for i, photo in ipairs(photos) do
        local uuid = ok and type(lus) == 'table' and type(lus[photo]) == 'table' and lus[photo].uuid or nil
        if uuid == nil then
            local okUn, u = LrTasks.pcall(photo.getRawMetadata, photo, 'uuid')
            uuid = okUn and u or nil
        end
        r[i] = uuid
    end
    return r
end

-- Le message du bas de la fenêtre.
local function dire(texte)
    FenetreSuivi.message = texte
    if FenetreSuivi.p then
        poser(FenetreSuivi.p, 'message', texte)
    end
end

-- Montre les photos de ces originaux dans la Bibliothèque (depuis une tâche) : chacun retrouvé par
-- son identifiant (getPhotoByLocalId) et vérifié par l'uuid de son entrée du relevé (une autre photo
-- sous ce numéro, ou une photo sortie du relevé, est sautée), puis sélectionnés en grille ; quand la
-- source affichée ne les a pas toutes, Toutes les photographies (catalog.kAllPhotos) devient la
-- source et la sélection se refait pendant DELAI_SOURCE. Rien n'est écrit au catalogue. `quoi` : le
-- détail de la barre, pour le message. Rend le nombre de photos sélectionnées.
function FenetreSuivi.montrerPhotos(ids, quoi)
    local cat = Photos.catalogue()
    local attendus = {}
    for _, e in ipairs(Releve.entrees()) do
        if tonumber(e.original) and type(e.uuid) == 'string' then
            attendus[tonumber(e.original)] = e.uuid
        end
    end
    local trouvees, uuids = {}, {}
    for _, id in ipairs(ids) do
        if attendus[id] then
            local ok, photo = LrTasks.pcall(cat.getPhotoByLocalId, cat, id)
            if ok and type(photo) == 'table' then
                trouvees[#trouvees + 1] = photo
                uuids[#uuids + 1] = attendus[id]
            end
        end
    end
    local lus = uuidsDe(cat, trouvees)
    local photos = {}
    for i, photo in ipairs(trouvees) do
        if lus[i] == uuids[i] then
            photos[#photos + 1] = photo
        end
    end
    local quoiTexte = texteOuNil(quoi) or "Ces photos"
    local absentes = #ids - #photos
    local suite = absentes > 1 and string.format(" %d photos ne sont plus au catalogue.", absentes)
        or absentes == 1 and " 1 photo n'est plus au catalogue." or ""
    if #photos == 0 then
        dire(quoiTexte .. " : aucune n'est plus au catalogue.")
        return 0
    end
    if LrApplicationView.getCurrentModuleName() ~= 'library' then
        LrTasks.pcall(LrApplicationView.switchToModule, 'library')
    end
    LrTasks.pcall(LrApplicationView.showView, 'grid')
    local toutes, n = selectionner(cat, photos)
    local sourceChangee = false
    if not toutes and cat.kAllPhotos ~= nil then
        LrTasks.pcall(cat.setActiveSources, cat, cat.kAllPhotos)
        sourceChangee = true
        local fin = LrDate.currentTime() + FenetreSuivi.DELAI_SOURCE
        repeat
            toutes, n = selectionner(cat, photos)
            if toutes then
                break
            end
            LrTasks.sleep(0.2)
        until LrDate.currentTime() > fin
    end
    local source = sourceChangee and " (source : Toutes les photographies)" or ""
    if toutes then
        dire(quoiTexte .. " : dans la Bibliothèque" .. source .. "." .. suite)
    elseif n > 0 then
        dire(string.format("%s : %d sur %d dans la Bibliothèque%s ; le filtre de la Bibliothèque cache les autres.%s", quoiTexte, n,
            #photos, source, suite))
    else
        dire(quoiTexte .. " : Lightroom ne les a pas montrées (le filtre de la Bibliothèque les cache ?)." .. suite)
    end
    return n
end

-- Le clic sur le calque `i` du graphique `cle` : les photos de la barre qui occupe ce créneau, dans
-- une tâche. Rend vrai si une tâche part (une barre qui a des photos).
function FenetreSuivi.cliquer(cle, i)
    local barre = FenetreSuivi.barreDu(cle, i)
    local ids = idsDe(barre)
    if #ids == 0 then
        return false
    end
    local quoi = texteOuNil(barre.detail) or texteOuNil(barre.libelle)
    LrTasks.startAsyncTask(function()
        local ok, erreur = LrTasks.pcall(FenetreSuivi.montrerPhotos, ids, quoi)
        if not ok then
            Journal.noter("Fenêtre Suivi :", tostring(erreur))
            dire("Les photos ne se montrent pas : " .. tostring(erreur))
        end
    end)
    return true
end

-- Les mouse_down des calques (les essais vérifient que tous y passent).
local parCalque = setmetatable({}, { __mode = 'k' })

-- Un calque : un texte vide de taille fixe posé sur l'image d'un graphique, qui en reçoit le clic
-- (un f:picture n'en reçoit aucun ; le calque, si : constaté le 21 octobre 2026, C1).
function FenetreSuivi.calque(f, args)
    args.title = ''
    parCalque[args.mouse_down] = true
    return f:static_text(args)
end

function FenetreSuivi.parCalque(fn)
    return parCalque[fn] == true
end

-- Le résumé du carnet, pour « Photos d'un défaut… » ---------------------------------------------

-- Le résumé lu (Carnet.resumer ; nil avant la première lecture, { erreur } s'il ne s'est pas lu) et
-- la version du registre qu'il a lue : « Photos d'un défaut… » en prend la liste des défauts.
FenetreSuivi.resume, FenetreSuivi.versionLue = nil, nil

-- Vrai quand le résumé lu a des défauts : « Photos d'un défaut… » actif.
function FenetreSuivi.aDefauts()
    local page = FenetreSuivi.resume
    return type(page) == 'table' and page.vide ~= true and type(page.defauts) == 'table' and #page.defauts > 0
end

-- Relit le résumé du carnet (depuis une tâche).
function FenetreSuivi.lire()
    FenetreSuivi.versionLue, FenetreSuivi.aRelire = Carnet.version, false
    local ok, page = LrTasks.pcall(Carnet.resumer, os.time())
    if not ok then
        Journal.noter("Carnet de progrès :", tostring(page))
        page = { erreur = tostring(page) }
    end
    FenetreSuivi.resume = page
    if FenetreSuivi.p then
        poser(FenetreSuivi.p, 'aDefauts', FenetreSuivi.aDefauts())
    end
    return page
end

-- Les photos d'un défaut du carnet ---------------------------------------------------------------

-- Le nom d'une photo du carnet (Carnet.photosDuDefaut) : son fichier, sinon son identifiant.
function FenetreSuivi.nomPhotoCarnet(x)
    return texteOuNil(x.fichier) or ("photo " .. Conversation.clePhoto(x.original or x.photo))
end

-- Une inclinaison en degrés, au dixième, sans signe (« 1,2° »), comme le carnet la note.
local function degres(x)
    local d = math.floor(math.abs(x) * 10 + 0.5)
    return string.format('%d,%d°', math.floor(d / 10), d % 10)
end

-- Une photo d'un défaut, sur une ligne : « octobre 2026 · DSCF4961.RAF · ciel brûlé : 4,2 % … »
-- (le constat, sinon sa mesure ; `angle` : une ligne penchée, dite en degrés).
function FenetreSuivi.textePhotoDuDefaut(x)
    local morceaux = { texteOuNil(x.mois_libelle) or tostring(x.mois or '?'), FenetreSuivi.nomPhotoCarnet(x) }
    local mesure = type(x.mesure) == 'number' and (x.angle and ("ligne penchée de " .. degres(x.mesure))
        or ("mesure : " .. Texte.nombre(x.mesure))) or nil
    local constat = texteOuNil(x.texte) or mesure
    if constat then
        morceaux[#morceaux + 1] = constat
    end
    return table.concat(morceaux, " · ")
end

-- Le défaut `code` du résumé lu (libellé, conseil), sinon du vocabulaire rangé au carnet.
local function defautDuCarnet(code)
    local page = FenetreSuivi.resume
    for _, d in ipairs(type(page) == 'table' and type(page.defauts) == 'table' and page.defauts or {}) do
        if d.code == code then
            return d
        end
    end
    for _, d in ipairs(Carnet.vocabulaire()) do
        if d.code == code then
            return d
        end
    end
    return { code = code }
end

-- La fenêtre des photos d'un défaut (depuis une tâche) : bâtie au clic, des tables neuves
-- (Carnet.photosDuDefaut, dans les mois du résumé), la plus récente d'abord, leurs constats
-- seulement (la leçon de la photo choisie, dessous, est retirée au correctif 1.3.6) ; « Retirer du
-- carnet… » retire la photo choisie (FenetreSuivi.retirerDuCarnet).
function FenetreSuivi.montrerDefaut(code)
    local photos = Carnet.photosDuDefaut(code, os.time())
    -- Une ligne penchée (measure_angle, read_composition) n'a que son inclinaison, sans texte :
    -- celle de l'angle rangé dans l'entrée de l'original sous ce code.
    for _, x in ipairs(photos) do
        if texteOuNil(x.texte) == nil and type(x.mesure) == 'number' then
            local e = Carnet.entree(x.original)
            x.angle = type(e) == 'table' and type(e.angle) == 'table' and e.angle.code == code or nil
        end
    end
    local d = defautDuCarnet(code)
    local libelle = texteOuNil(d.libelle) or tostring(code)
    local f = LrView.osFactory()
    local aRetirer
    LrFunctionContext.callWithContext('Claude · carnet', function(context)
        local qp = LrBinding.makePropertyTable(context)
        local items, parId = {}, {}
        for _, x in ipairs(photos) do
            items[#items + 1] = { title = FenetreSuivi.textePhotoDuDefaut(x), value = x.original }
            parId[x.original] = x
        end
        local function choisie(valeur)
            local id = type(valeur) == 'table' and valeur[1] or valeur
            return id ~= nil and parId[id] or nil
        end
        qp.choix = #photos > 0 and { photos[1].original } or {}
        local entete = #photos == 0 and "Aucune photo n'a ce défaut dans les mois du carnet."
            or #photos == 1 and "1 photo dans les mois du carnet."
            or string.format("%d photos dans les mois du carnet, la plus récente d'abord.", #photos)
        local contenu = {
            bind_to_object = qp,
            spacing = f:control_spacing(),
            f:static_text { title = entete, width = 640 },
        }
        if texteOuNil(d.conseil) then
            contenu[#contenu + 1] = f:static_text { title = "À la prise de vue : " .. texteOuNil(d.conseil), width = 640, height_in_lines = 2 }
        end
        if #photos > 0 then
            contenu[#contenu + 1] = f:simple_list { items = items, value = bind 'choix', allows_multiple_selection = false, width = 640, height = 160 }
        end
        local reponse = LrDialogs.presentModalDialog {
            title = FenetreSuivi.TITRE_CARNET .. " · " .. libelle,
            contents = f:column(contenu),
            actionVerb = "Fermer",
            cancelVerb = '< exclude >',
            otherVerb = #photos > 0 and "Retirer du carnet…" or nil,
        }
        if reponse == 'other' then
            aRetirer = choisie(qp.choix)
        end
    end)
    if aRetirer then
        return FenetreSuivi.retirerDuCarnet(aRetirer)
    end
    return false
end

-- Retire une photo du carnet, après confirmation : par appel direct au registre du module
-- (Carnet.commande, jamais une ligne de la liaison), avec l'identifiant de l'original (la clé de
-- son entrée). Le résumé et les graphiques se refont ensuite (Carnet.version). Rend vrai si elle est
-- retirée ; ce qui s'est passé se dit en bas de la fenêtre.
function FenetreSuivi.retirerDuCarnet(x)
    local nom = FenetreSuivi.nomPhotoCarnet(x)
    local reponse = LrDialogs.confirm("Retirer " .. nom .. " du carnet de progrès ?",
        "Ses constats sortent du carnet et ne comptent plus dans la fenêtre Suivi. La photo et ses retouches ne changent pas.",
        "Retirer", "Annuler")
    if reponse ~= 'ok' then
        return false
    end
    local ok, r = LrTasks.pcall(Carnet.commande, { action = 'retirer', photos = { x.original } })
    local retiree = ok and type(r) == 'table' and (tonumber(r.retirees) or 0) > 0
    dire(retiree and (nom .. " est retirée du carnet de progrès.")
        or ("Le carnet n'a pas retiré " .. nom .. (ok and " : elle n'y est plus." or (" : " .. tostring(r)))))
    return retiree
end

-- « Photos d'un défaut… » (depuis une tâche) : la liste des défauts du résumé lu (tables neuves :
-- libellé, photos où il est vu et sur combien il a été cherché), puis, le défaut choisi, la fenêtre
-- de ses photos (FenetreSuivi.montrerDefaut). Rend ce qu'elle rend, faux sans défaut ou sans choix.
function FenetreSuivi.choisirDefaut()
    if not FenetreSuivi.aDefauts() then
        return false
    end
    local defauts = FenetreSuivi.resume.defauts
    local f = LrView.osFactory()
    local code
    LrFunctionContext.callWithContext('Claude · défauts du carnet', function(context)
        local qp = LrBinding.makePropertyTable(context)
        local items = {}
        for _, d in ipairs(defauts) do
            local n, sur = tonumber(d.n) or 0, tonumber(d.sur) or 0
            items[#items + 1] = { title = string.format("%s · %d photo%s sur %d", texteOuNil(d.libelle) or tostring(d.code),
                n, n > 1 and "s" or "", sur), value = d.code }
        end
        qp.choix = { defauts[1].code }
        local reponse = LrDialogs.presentModalDialog {
            title = FenetreSuivi.TITRE_CARNET .. " · " .. FenetreSuivi.TITRE_DEFAUTS,
            contents = f:column {
                bind_to_object = qp,
                spacing = f:control_spacing(),
                f:static_text { title = "Choisissez un défaut : ses photos, dans les mois du carnet.", width = 480 },
                f:simple_list { items = items, value = bind 'choix', allows_multiple_selection = false, width = 480, height = 200 },
            },
            actionVerb = "Voir ses photos",
        }
        if reponse == 'ok' then
            local v = qp.choix
            code = type(v) == 'table' and v[1] or v
        end
    end)
    if code == nil then
        return false
    end
    return FenetreSuivi.montrerDefaut(code)
end

-- La fenêtre ---------------------------------------------------------------------------------------

-- Les couleurs de l'apparence, en LrColor, refaites à chaque ouverture (Dispositions.couleurs).
FenetreSuivi.COULEURS = {}

local function preparerCouleurs()
    -- Importé ici : liens.lua charge ce fichier sans LrColor (comme Dispositions, aucune couleur
    -- n'est créée au chargement).
    local LrColor = import 'LrColor'
    local C = {}
    for cle, t in pairs(Dispositions.couleurs(FenetreSuivi.apparence())) do
        C[cle] = LrColor(t[1], t[2], t[3])
    end
    FenetreSuivi.COULEURS = C
    return C
end

-- Un aplat : un f:picture sans image, à background_color (constaté le 21 octobre 2026, A4).
local function aplat(f, largeur, hauteur, couleur)
    return f:picture { width = largeur, height = hauteur, background_color = couleur }
end

local function texte(f, args)
    return f:static_text(args)
end

-- Une tuile : un cadre (deux aplats), son titre, son chiffre et son détail (l'infobulle le donne en
-- entier).
local function tuile(f, D, C, P, k)
    local L, H = D.tuile, D.hauteurTuile
    return f:view {
        place = 'overlapping',
        width = L,
        height = H,
        aplat(f, L, H, C.bordCarte),
        f:column { margin_left = 1, margin_top = 1, aplat(f, L - 2, H - 2, C.fondCarte) },
        f:column {
            margin_left = 12,
            margin_top = 10,
            spacing = 0,
            texte(f, { title = bind('tuileTitre' .. k), font = P.texte12, text_color = C.gris, width = L - 24, height = 16,
                truncation = 'tail' }),
            f:spacer { height = 2 },
            texte(f, { title = bind('tuileTexte' .. k), font = P.chiffre, text_color = k == 4 and C.orange or C.texte, width = L - 24,
                height = 30, truncation = 'tail' }),
            f:spacer { height = 2 },
            texte(f, { title = bind('tuileDetail' .. k), font = P.petit, text_color = C.gris, width = L - 24, height = 14,
                truncation = 'tail', tooltip = bind('tuileDetail' .. k) }),
        },
    }
end

-- L'image d'un graphique, à sa taille, et ses calques : un par créneau, chacun dans une colonne
-- poussée à sa place (FenetreSuivi.creneaux) ; « Dessin… » (ou « Pas de graphique. ») tant que
-- l'image n'est pas là.
local function image(f, C, P, g)
    local pieces = {
        place = 'overlapping',
        width = g.largeur,
        height = g.hauteur,
        texte(f, { title = bind 'attente', font = P.petit, text_color = C.gris, width = g.largeur, alignment = 'center',
            place_vertical = 0.5, visible = bind { key = 'pret_' .. g.cle, transform = function(v) return v ~= true end } }),
        f:picture { value = bind('image_' .. g.cle), width = g.largeur, height = g.hauteur, visible = bind('pret_' .. g.cle) },
    }
    for i, c in ipairs(FenetreSuivi.creneaux(g)) do
        local visible, infobulle = FenetreSuivi.cleCalque(g.cle, i)
        pieces[#pieces + 1] = f:column {
            margin_left = c.x,
            margin_top = c.y,
            spacing = 0,
            FenetreSuivi.calque(f, { width = c.largeur, height = c.hauteur, visible = bind(visible), tooltip = bind(infobulle),
                mouse_down = function() FenetreSuivi.cliquer(g.cle, i) end }),
        }
    end
    return f:view(pieces)
end

-- Un graphique et ce qui l'entoure : son titre (ou `entete`), son image et sa note.
local function bloc(f, D, C, P, cle, entete)
    local g = FenetreSuivi.graphique(cle)
    local lignes = g.lignesNote or 1
    return f:column {
        spacing = 0,
        width = g.largeur,
        entete or texte(f, { title = bind('titre_' .. cle), font = P.gras12, text_color = C.texte, width = g.largeur,
            height = D.titreGraphique, truncation = 'tail' }),
        f:spacer { height = D.sousTitre },
        image(f, C, P, g),
        f:spacer { height = D.sousGraphique },
        texte(f, { title = bind('note_' .. cle), font = P.petit, text_color = C.gris, width = g.largeur, height = lignes * D.ligneNote,
            height_in_lines = lignes, truncation = 'tail', tooltip = bind('note_' .. cle) }),
    }
end

local function section(f, D, C, P, titre)
    return texte(f, { title = titre, font = P.gras, text_color = C.texte, width = D.colonne, height = D.section })
end

-- Le contenu : l'aplat du fond, puis l'en-tête (titre, Période), la ligne d'état, les tuiles, et
-- les deux colonnes : Mes prises de vue, Mon carnet de progrès (avec le menu du défaut suivi, l'aide,
-- le message et « Photos d'un défaut… »).
function FenetreSuivi.construire(f, p)
    local D, C, P = FenetreSuivi.dimensions(), FenetreSuivi.COULEURS, FenetreSuivi.POLICES
    local tuiles = { spacing = D.ecartTuile }
    for k = 1, #FenetreSuivi.TUILES do
        tuiles[#tuiles + 1] = tuile(f, D, C, P, k)
    end
    local largeurTitre = D.interieur - D.etiquettePeriode - D.periode - 2 * 8
    local gauche = f:column {
        spacing = 0,
        width = D.colonne,
        section(f, D, C, P, FenetreSuivi.PRISES_DE_VUE),
        f:spacer { height = D.sousSection },
        bloc(f, D, C, P, 'photos_par_mois'),
        f:spacer { height = D.ecartBlocs },
        f:row { spacing = D.ecartPetits, bloc(f, D, C, P, 'focales'), bloc(f, D, C, P, 'iso') },
        f:spacer { height = D.ecartBlocs },
        bloc(f, D, C, P, 'heures'),
        f:spacer { height = D.ecartBlocs },
        bloc(f, D, C, P, 'objectifs'),
    }
    local enteteEvolution = f:row {
        spacing = 8,
        height = D.enteteEvolution,
        texte(f, { title = bind 'titre_evolution_defaut', font = P.gras12, text_color = C.texte, width = D.colonne - D.defaut - 8,
            truncation = 'tail', place_vertical = 0.5 }),
        f:popup_menu { items = bind 'elementsDefaut', value = bind 'defaut', width = D.defaut, place_vertical = 0.5,
            tooltip = "Le défaut suivi mois par mois : le plus fréquent, ou celui que vous choisissez" },
    }
    local droite = f:column {
        spacing = 0,
        width = D.colonne,
        section(f, D, C, P, FenetreSuivi.CARNET),
        f:spacer { height = D.sousSection },
        bloc(f, D, C, P, 'defauts_frequents'),
        f:spacer { height = D.ecartBlocs },
        bloc(f, D, C, P, 'evolution_defaut', enteteEvolution),
        f:spacer { height = D.ecartBlocs },
        texte(f, { title = FenetreSuivi.AIDE, font = P.petit, text_color = C.gris, width = D.colonne, height = D.aide, height_in_lines = 3 }),
        f:spacer { height = D.ecartBlocs },
        f:row {
            spacing = 8,
            height = D.bas,
            texte(f, { title = bind 'message', font = P.petit, text_color = C.texte, width = D.colonne - D.defautsBouton - 8, height = D.bas,
                height_in_lines = 2, truncation = 'tail', tooltip = bind 'message', place_vertical = 0.5 }),
            f:push_button { title = "Photos d'un défaut…", width = D.defautsBouton, enabled = bind 'aDefauts', place_vertical = 0.5,
                tooltip = "Les photos où un défaut du carnet a été vu par Claude, et « Retirer du carnet… »",
                action = function()
                    LrTasks.startAsyncTask(function()
                        local ok, erreur = LrTasks.pcall(FenetreSuivi.choisirDefaut)
                        if not ok then
                            Journal.noter("Fenêtre Suivi :", tostring(erreur))
                        end
                    end)
                end },
        },
    }
    return f:view {
        bind_to_object = p,
        place = 'overlapping',
        width = D.largeurContenu,
        height = D.hauteurContenu,
        aplat(f, D.largeurContenu, D.hauteurContenu, C.fondDroite),
        f:column {
            margin_left = D.marge,
            margin_top = D.marge,
            spacing = 0,
            f:row {
                spacing = 8,
                height = D.entete,
                texte(f, { title = FenetreSuivi.ENTETE, font = P.titre, text_color = C.texte, width = largeurTitre, place_vertical = 0.5 }),
                texte(f, { title = "Période :", font = P.texte12, text_color = C.gris, alignment = 'right', width = D.etiquettePeriode,
                    place_vertical = 0.5 }),
                f:popup_menu { items = FenetreSuivi.elementsPeriode(), value = bind 'periode', width = D.periode, place_vertical = 0.5,
                    tooltip = "Les photos de la période, par leur date de prise de vue" },
            },
            f:spacer { height = D.ecartEtat },
            texte(f, { title = bind 'etat', font = P.petit, text_color = C.gris, width = D.interieur, height = D.etat, height_in_lines = 2,
                truncation = 'tail', tooltip = bind 'etat' }),
            f:spacer { height = D.ecartTuiles },
            f:row(tuiles),
            f:spacer { height = D.sousTuiles },
            f:row { spacing = D.ecartColonnes, gauche, droite },
        },
    }
end

-- Les éléments du menu Période (tables neuves).
function FenetreSuivi.elementsPeriode()
    local items = {}
    for _, x in ipairs(FenetreSuivi.PERIODES) do
        items[#items + 1] = { title = x.title, value = x.value }
    end
    return items
end

-- Les valeurs de la fenêtre avant la première réponse (chaque clé liée en a une avant l'ouverture).
local function preparer(p)
    p.etat = FenetreSuivi.LECTURE
    p.message = ''
    p.attente = FenetreSuivi.ATTENTE
    p.periode = FenetreSuivi.PERIODE
    p.defaut = FenetreSuivi.LE_PLUS_FREQUENT
    p.elementsDefaut = FenetreSuivi.elementsDefaut(nil)
    p.aDefauts = false
    for k, t in ipairs(FenetreSuivi.TUILES) do
        p['tuileTitre' .. k] = t.titre
        p['tuileTexte' .. k] = "—"
        p['tuileDetail' .. k] = ''
    end
    local vide = Chemins.ressource(Dispositions.imageVide(FenetreSuivi.apparence()))
    for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
        p['titre_' .. g.cle] = g.titre
        p['note_' .. g.cle] = ''
        p['image_' .. g.cle] = vide
        p['pret_' .. g.cle] = false
        for i = 1, g.max_barres do
            local visible, infobulle = FenetreSuivi.cleCalque(g.cle, i)
            p[visible] = false
            p[infobulle] = ''
        end
    end
end

-- La boucle ------------------------------------------------------------------------------------

-- Un tour de la boucle (depuis une tâche) : le résumé du carnet quand le registre change ; à
-- l'ouverture, la note, le drapeau et « retouchée par Claude » relus (Releve.reclasser, avant le
-- premier dessin) ; puis le dessin, demandé (ouverture, période, défaut) ou quand le relevé ou le
-- carnet a changé (au plus toutes les DELAI_REDESSIN secondes) ; la file d'analyse relancée (comme
-- les boucles de la fenêtre Claude et de la Demande rapide).
function FenetreSuivi.suivre()
    if FenetreSuivi.aRelire or Carnet.version ~= FenetreSuivi.versionLue then
        FenetreSuivi.lire()
    end
    if FenetreSuivi.aReclasser then
        FenetreSuivi.aReclasser = false
        local ok, erreur = LrTasks.pcall(Releve.reclasser)
        if not ok then
            Journal.noter("Fenêtre Suivi : classement non relu :", tostring(erreur))
        end
        FenetreSuivi.aRedessiner = true
    end
    local change = Releve.version ~= FenetreSuivi.releveDessine or Carnet.version ~= FenetreSuivi.carnetDessine
    if FenetreSuivi.aRedessiner or (change and os.time() - (FenetreSuivi.dessineLe or 0) >= FenetreSuivi.DELAI_REDESSIN) then
        FenetreSuivi.dessiner()
    end
    LrTasks.pcall(Releve.relancer)
end

-- La boucle de la fenêtre ouverte (sa génération : une fenêtre rouverte a la sienne), deux fois par
-- seconde.
function FenetreSuivi.boucle(generation)
    while FenetreSuivi.ouverte and FenetreSuivi.generation == generation do
        local ok, erreur = LrTasks.pcall(FenetreSuivi.suivre)
        if not ok then
            FenetreSuivi.versionLue, FenetreSuivi.aRelire, FenetreSuivi.aRedessiner = Carnet.version, false, false
            FenetreSuivi.releveDessine, FenetreSuivi.carnetDessine = Releve.version, Carnet.version
            Journal.noter("Fenêtre Suivi :", tostring(erreur))
        end
        LrTasks.sleep(0.5)
    end
end

FenetreSuivi.generation = 0

-- Ouvre la fenêtre (le bouton Suivi de la fenêtre Claude) ; déjà ouverte, elle passe devant. Les
-- graphiques se refont à chaque ouverture (la boucle, dans une tâche) ; leurs dossiers s'effacent à
-- la fermeture.
function FenetreSuivi.afficher()
    if FenetreSuivi.ouverte then
        if FenetreSuivi.controle and FenetreSuivi.controle.toFront then
            FenetreSuivi.controle.toFront()
        end
        return
    end
    FenetreSuivi.ouverte = true
    FenetreSuivi.generation = FenetreSuivi.generation + 1
    local generation = FenetreSuivi.generation
    LrFunctionContext.postAsyncTaskWithContext('Claude · suivi', function(context)
        context:addFailureHandler(function(_, erreur)
            if FenetreSuivi.generation == generation then
                FenetreSuivi.ouverte = false
                FenetreSuivi.p = nil
                Carnet.desabonner('suivi')
                FenetreSuivi.effacerDessins()
            end
            Journal.noter("Fenêtre Suivi :", tostring(erreur))
            LrDialogs.message("La fenêtre Suivi n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)
        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
        FenetreSuivi.resume, FenetreSuivi.versionLue, FenetreSuivi.aRelire = nil, nil, false
        FenetreSuivi.reponse, FenetreSuivi.calquesValides, FenetreSuivi.derniereErreur = nil, {}, nil
        FenetreSuivi.releveDessine, FenetreSuivi.carnetDessine, FenetreSuivi.dessineLe = nil, nil, nil
        FenetreSuivi.aReclasser, FenetreSuivi.aRedessiner, FenetreSuivi.sansReleve = true, true, false
        FenetreSuivi.message = nil
        FenetreSuivi.effacerDessins()
        preparerCouleurs()
        preparer(p)
        FenetreSuivi.p = p
        local contenu = FenetreSuivi.construire(f, p)
        -- Une autre période ou un autre défaut choisi : les graphiques se refont au tour suivant.
        p:addObserver('periode', function() FenetreSuivi.aRedessiner = true end)
        p:addObserver('defaut', function() FenetreSuivi.aRedessiner = true end)
        Carnet.abonner('suivi', function() FenetreSuivi.aRelire = true end)
        LrTasks.startAsyncTask(function() FenetreSuivi.boucle(generation) end)
        LrDialogs.presentFloatingDialog(_PLUGIN, {
            title = FenetreSuivi.TITRE,
            contents = contenu,
            save_frame = FenetreSuivi.CADRE,
            blockTask = true,
            onShow = function(controle)
                if FenetreSuivi.generation == generation then
                    FenetreSuivi.controle = controle
                end
            end,
            windowWillClose = function()
                if FenetreSuivi.generation ~= generation then
                    return
                end
                FenetreSuivi.ouverte = false
                FenetreSuivi.controle = nil
                Carnet.desabonner('suivi')
            end,
        })
        -- Au cas où blockTask ne bloquerait pas : garder le contexte (et la table) en vie.
        while FenetreSuivi.ouverte and FenetreSuivi.generation == generation do
            LrTasks.sleep(0.5)
        end
        if FenetreSuivi.generation == generation then
            FenetreSuivi.p = nil
            FenetreSuivi.effacerDessins()
        end
    end)
end

return FenetreSuivi
