-- FenetreSuivi.lua : la fenêtre « Claude · Suivi », en graphiques (correctif 1.3.7, décidé avec Dany
-- le 25 octobre 2026 ; fiche build/conception/1-3-7-a-faire.md, contrat figé dans
-- Tests/Contrats/suivi.json). Le bouton Suivi de l'en-tête de la fenêtre Claude l'ouvre
-- (Fenetre.ouvrirSuivi) ; ouverte, il la remet devant. Elle montre le relevé du Suivi (suivi.json,
-- tenu par Releve.lua : toute photo ouverte dans la fenêtre Claude ou la Demande rapide, analysée
-- d'office par le connecteur) et le carnet de progrès (carnet.json, ce que Claude a vu), sur une
-- période choisie par deux champs, « Du » et « au », gardée d'une ouverture à l'autre (correctif
-- 1.3.8, demandé par Dany le 26 octobre 2026, à la place du menu Période et de ses trois périodes
-- fixes ; sans rien de choisi, les douze derniers mois, du 1er du mois onze mois plus tôt à
-- aujourd'hui) :
--
--   - quatre tuiles chiffrées : photos ouvertes, retouchées par Claude, notées 4 ★ ou plus, défaut
--     le plus fréquent ;
--   - « Mes prises de vue » : photos par mois (par trimestre, par année pour une longue période ;
--     par date de prise de vue), focales, ISO, heure de la prise de vue, objectifs, et les notes (de
--     0 ★ à 5 ★, correctif 1.3.8) ;
--   - « Mon carnet de progrès » : les défauts les plus fréquents (en % des photos où ils sont
--     cherchés) et l'évolution d'un défaut (le plus fréquent par défaut, un menu pour en choisir un
--     autre). « Photos d'un défaut… » et « Retirer du carnet… », de la fenêtre de la 1.3.6, sont
--     retirés au correctif 1.3.8 (demandé par Dany le 26 octobre 2026).
--
-- Lightroom ne trace pas de graphique : les huit images sont dessinées par le connecteur
-- (`mcp-developpeur --graphiques '<json>' <dossier>`, sous l'alarme de perl comme --focus), en PNG
-- 2x, dans les couleurs de l'apparence du module (Dispositions.PALETTES, seule table des couleurs,
-- passées au connecteur : FenetreSuivi.couleursConnecteur) ; il rend aussi, en une ligne JSON, les
-- tuiles et, pour chaque graphique, ses barres et ses créneaux. Les images se refont dans une tâche
-- (la boucle de la fenêtre, FenetreSuivi.suivre) : à l'ouverture, puis une fois Releve.reclasser
-- fini (il relit la note, le drapeau et « retouchée par Claude » de chaque famille, dans sa propre
-- tâche : à toute la bibliothèque, il dure, et la fenêtre montre déjà le classement gardé), au
-- changement de période ou de défaut, et quand le relevé ou le carnet change pendant qu'elle est
-- ouverte (Releve.version, Carnet.version ; FenetreSuivi.delaiRedessin entre deux) ; avant un dessin
-- demandé (ouverture, période, défaut, reclassement fini), ce que le Suivi a rangé sans l'écrire
-- encore s'écrit (Releve.ecrire : ses écritures sont espacées) ; un dessin fait de lui-même (le relevé
-- écrit, ou le carnet changé) lit le fichier tel quel : ce qui reste à écrire se montre après
-- l'écriture suivante, qui fait redessiner. La réponse (à toute la bibliothèque : plus de 10 Mo,
-- tous les identifiants de chaque barre) se décode en rendant la main (Json.decode avec un rythme,
-- correctif 1.3.8). Chaque dessin a son
-- dossier neuf (Temporaire/Suivi/Graphiques-…, Lightroom garde une image par chemin) ;
-- l'avant-dernier s'efface quand le nouveau est montré, tous à la fermeture. Sans réponse lisible
-- du connecteur, rien ne change et la fenêtre le dit ; sans connecteur, elle le dit aussi.
--
-- Structure fixe à la création (règle de la fenêtre B) : huit f:picture liées (`image_<g>`), et sur
-- chacune un calque par créneau possible (photos par mois 13, focales 8, ISO 8, heures 12,
-- objectifs 8, notes 6, défauts 8, évolution 13 : 76 calques). Les rectangles des créneaux ne dépendent que
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
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'
local Metriques = require 'Metriques'
local Photos = require 'Photos'
local Releve = require 'Releve'
local Texte = require 'Texte'

local FenetreSuivi = { ouverte = false }

-- Le titre de la fenêtre (les fenêtres du module gardent « Claude · … ») et son cadre gardé (un nom
-- neuf pour la fenêtre en graphiques : celle de la 1.3.6, « DeveloppeurCarnet », n'avait pas cette
-- taille ; le nom change avec la taille du contenu, que le correctif 1.3.8 ne change pas).
FenetreSuivi.TITRE = "Claude · Suivi"
FenetreSuivi.CADRE = 'DeveloppeurSuiviGraphiques-1'

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
FenetreSuivi.VOIR_TOUT = " Élargissez la période pour en voir d'autres (« Du » vide : depuis la première photo ; « au » : "
    .. "aujourd'hui)."
FenetreSuivi.DEBUT_ILLISIBLE = "« %s » ne se lit pas comme une date de début : écrivez par exemple 25 janvier 2025, 25/01/2025, "
    .. "2025-01-25, janvier 2025 ou 2025 (vide : depuis la première photo). La période ne change pas."
FenetreSuivi.FIN_ILLISIBLE = "« %s » ne se lit pas comme une date de fin : écrivez par exemple 25 janvier 2026, 25/01/2026, "
    .. "2026-01-25, janvier 2026 ou 2026, ou aujourd'hui (la fin avance alors chaque jour). La période ne change pas."
FenetreSuivi.DEBUT_APRES_FIN = "Le début (%s) viendrait après la fin (%s) : changez d'abord « au » (par exemple aujourd'hui). "
    .. "La période ne change pas."
FenetreSuivi.FIN_AVANT_DEBUT = "La fin (%s) viendrait avant le début (%s) : changez d'abord « Du ». La période ne change pas."
FenetreSuivi.INFOBULLE_DEBUT = "Le premier jour de la période : 25 janvier 2025, 25/01/2025, 2025-01-25, janvier 2025 ou 2025 ; "
    .. "vide : depuis la première photo. Gardé d'une ouverture à l'autre."
FenetreSuivi.INFOBULLE_FIN = "Le dernier jour de la période, compris ; « aujourd'hui » : la fin avance chaque jour. Gardé d'une "
    .. "ouverture à l'autre."
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

-- La période : un jour de début (ou la première photo) et un jour de fin (ou aujourd'hui, qui
-- avance chaque jour), gardés dans les préférences du module (suiviDebut : « AAAA-MM-JJ », ou '' :
-- depuis la première photo ; suiviFin : « AAAA-MM-JJ », ou FenetreSuivi.AUJOURDHUI). Sans rien de
-- gardé : les douze derniers mois, du 1er du mois onze mois plus tôt à aujourd'hui (des mois entiers,
-- comme les « 12 derniers mois » d'avant ; le même jour un an plus tôt ferait un premier mois de
-- quelques jours, et deux colonnes du même mois). Les textes que les champs montrent pour la
-- première photo et pour aujourd'hui.
FenetreSuivi.AUJOURDHUI = "aujourd'hui"
FenetreSuivi.PREMIERE_PHOTO = "première photo"

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

-- Les huit graphiques (contrat : graphiques.liste), dans l'ordre de la fenêtre : leur taille en
-- points (celle que la fenêtre demande au connecteur : graphiques.entree.tailles), leur nombre de
-- créneaux et leur sens, d'où les rectangles des créneaux ; le titre avant la première réponse. Les
-- notes (correctif 1.3.8) vont à côté des objectifs, de même taille ; les graphiques du temps ont
-- treize créneaux depuis le même correctif (douze avant : une année comptée d'un jour au même jour
-- de l'année suivante touche treize mois).
FenetreSuivi.GRAPHIQUES = {
    { cle = 'photos_par_mois', titre = "Photos par mois", largeur = 620, hauteur = 150, max_barres = 13, orientation = 'verticale' },
    { cle = 'focales', titre = "Focales (mm)", largeur = 300, hauteur = 130, max_barres = 8, orientation = 'verticale' },
    { cle = 'iso', titre = "Sensibilité (ISO)", largeur = 300, hauteur = 130, max_barres = 8, orientation = 'verticale' },
    { cle = 'heures', titre = "Heure de la prise de vue", largeur = 620, hauteur = 120, max_barres = 12, orientation = 'verticale' },
    { cle = 'objectifs', titre = "Objectifs", largeur = 300, hauteur = 170, max_barres = 8, orientation = 'horizontale' },
    { cle = 'notes', titre = "Notes", largeur = 300, hauteur = 170, max_barres = 6, orientation = 'verticale' },
    { cle = 'defauts_frequents', titre = "Défauts les plus fréquents", largeur = 620, hauteur = 180, max_barres = 8,
        orientation = 'horizontale', lignesNote = 2 },
    { cle = 'evolution_defaut', titre = "Évolution d'un défaut", largeur = 620, hauteur = 140, max_barres = 13, orientation = 'verticale' },
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
-- 60 s depuis le correctif 1.3.8 (20 avant) : à 250 000 originaux, --graphiques prend 2,9 s sur le
-- Mac de Dany, plus pendant que Lightroom travaille. Un relevé d'au moins SEUIL_GRAND originaux ne
-- se redessine de lui-même qu'au plus toutes les DELAI_REDESSIN_GRAND secondes (--graphiques le lit
-- en entier à chaque fois). PAS_JSON : les valeurs de la réponse décodées entre deux fois où la main
-- est rendue ; PAS_UNE_A_UNE : les photos retrouvées une à une au clic (getPhotoByLocalId) entre
-- deux.
FenetreSuivi.ALARME = 60
FenetreSuivi.DELAI_REDESSIN = 10
FenetreSuivi.DELAI_REDESSIN_GRAND = 60
FenetreSuivi.SEUIL_GRAND = 20000
FenetreSuivi.DELAI_SOURCE = 3
FenetreSuivi.PAS_JSON = 5000
FenetreSuivi.PAS_UNE_A_UNE = 200
-- Une sélection d'au moins tant de photos se refait moins souvent pendant DELAI_SOURCE (une
-- seconde entre deux essais au lieu de 0,2) : setSelectedPhotos et getTargetPhotos sur des dizaines
-- de milliers de photos.
FenetreSuivi.GRANDE_SELECTION = 5000

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
    champDate = 150, etiquetteDu = 24, etiquetteAu = 20, defaut = 290,
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
local rendreLaMain = Releve.rendreLaMain

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
        + T.ecartBlocs + bloc(G.heures) + T.ecartBlocs + math.max(bloc(G.objectifs), bloc(G.notes))
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

-- La date du jour à l'heure locale (« AAAA-MM-JJ ») : la fin « aujourd'hui » et la période par
-- défaut ne dépendent pas de l'horloge du connecteur (contrat : graphiques.entree.fin).
function FenetreSuivi.aujourdhui()
    return os.date('%Y-%m-%d')
end

-- La période ------------------------------------------------------------------------------------------

-- Le nombre de jours d'un mois.
local function joursDuMois(annee, mois)
    if mois == 2 then
        return (annee % 4 == 0 and (annee % 100 ~= 0 or annee % 400 == 0)) and 29 or 28
    end
    return (mois == 4 or mois == 6 or mois == 9 or mois == 11) and 30 or 31
end

-- Une date { annee, mois, jour } en « AAAA-MM-JJ », et en français (« 25 janvier 2025 », « 1er mars
-- 2026 » : Carnet.MOIS, seule copie des noms des mois).
function FenetreSuivi.iso(d)
    return string.format('%04d-%02d-%02d', d.annee, d.mois, d.jour)
end

function FenetreSuivi.texteDate(d)
    return (d.jour == 1 and '1er' or tostring(d.jour)) .. ' ' .. Carnet.MOIS[d.mois] .. ' ' .. d.annee
end

-- Une date « AAAA-MM-JJ » qui existe, de 1900 à 9999 (comme le connecteur) ; nil sinon.
local function versDate(texte)
    local a, m, j = tostring(texte or ''):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    a, m, j = tonumber(a), tonumber(m), tonumber(j)
    if not a or a < 1900 or m < 1 or m > 12 or j < 1 or j > joursDuMois(a, m) then
        return nil
    end
    return { annee = a, mois = m, jour = j }
end

-- Le mois d'un mot : son nom (Carnet.MOIS) ou le début de son nom, trois lettres au moins, sans tenir
-- compte des accents, des majuscules ni d'un point final (« janv. », « fevrier », « AOÛT ») ; nil
-- s'il n'en désigne aucun, ou deux (« jui »).
local function moisDuMot(mot)
    mot = mot:gsub('%.$', '')
    if #mot < 3 then
        return nil
    end
    local trouve
    for i, nom in ipairs(Carnet.MOIS) do
        if Texte.plier(nom):sub(1, #mot) == mot then
            if trouve then
                return nil
            end
            trouve = i
        end
    end
    return trouve
end

-- Une date tapée dans « Du » (`borne` 'debut') ou « au » ('fin'), lue (pure) : { annee, mois, jour }.
-- Se lisent « 25 janvier 2025 », « 1er janv. 2025 », « 25/01/2025 », « 25-01-2025 », « 2025-01-25 »,
-- un mois seul (« janvier 2025 ») et une année seule (« 2025 ») : leur premier jour pour le début,
-- leur dernier pour la fin. Vide, ou « première photo », pour le début : { premiere = true } ; vide,
-- ou « aujourd'hui », pour la fin : { aujourdhui = true } ; « aujourd'hui » pour le début : le jour
-- `aujourdhui` (« AAAA-MM-JJ »). Rend nil pour une date qui ne se lit pas ou n'existe pas (le 31 avril).
function FenetreSuivi.lireDate(texte, borne, aujourdhui)
    local t = Texte.plier(Texte.nettoyer(texte)):gsub('%s+', ' ')
    if t == '' or (borne == 'debut' and (t == 'premiere photo' or t == 'la premiere photo' or t == 'depuis la premiere photo')) then
        return borne == 'debut' and { premiere = true } or { aujourdhui = true }
    end
    if t == "aujourd'hui" or t == 'aujourdhui' then
        if borne ~= 'debut' then
            return { aujourdhui = true }
        end
        return versDate(aujourdhui)
    end
    local a, m, j
    local x, y, z = t:match('^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$')
    if x then
        a, m, j = tonumber(x), tonumber(y), tonumber(z)
    else
        x, y, z = t:match('^(%d%d?)[/%.%-](%d%d?)[/%.%-](%d%d%d%d)$')
        if x then
            j, m, a = tonumber(x), tonumber(y), tonumber(z)
        end
    end
    if not a then
        local jour, suffixe, mot, annee = t:match('^(%d%d?)(%a*) (%S+) (%d%d%d%d)$')
        if jour and (suffixe == '' or (suffixe == 'er' and tonumber(jour) == 1)) then
            j, m, a = tonumber(jour), moisDuMot(mot), tonumber(annee)
        end
    end
    if not a then
        local mot, annee = t:match('^(%a[%a%.]*) (%d%d%d%d)$')
        local mois = mot and moisDuMot(mot)
        if mois then
            a, m = tonumber(annee), mois
            j = borne == 'fin' and joursDuMois(a, m) or 1
        end
    end
    if not a then
        local annee = t:match('^(%d%d%d%d)$')
        if annee then
            a, m, j = tonumber(annee), borne == 'fin' and 12 or 1, borne == 'fin' and 31 or 1
        end
    end
    if not (a and m and j) or a < 1900 or m < 1 or m > 12 or j < 1 or j > joursDuMois(a, m) then
        return nil
    end
    return { annee = a, mois = m, jour = j }
end

-- Le début par défaut d'une fin : le 1er du mois onze mois plus tôt (douze mois entiers, le dernier
-- jusqu'à la fin).
local function debutParDefaut(fin)
    local rang = fin.annee * 12 + (fin.mois - 1) - 11
    return { annee = math.floor(rang / 12), mois = rang % 12 + 1, jour = 1 }
end

-- La période gardée (préférences suiviDebut et suiviFin), lue : { debut (une date, nil : depuis la
-- première photo), fin (une date), finAujourdhui (vrai : la fin avance chaque jour) } ; des tables
-- neuves. Sans rien de gardé, ou une préférence qui ne se lit pas (éditée à la main) : la fin est
-- aujourd'hui, le début celui par défaut (debutParDefaut) ; un début gardé après la fin, de même.
function FenetreSuivi.periode()
    local prefs = Chemins.prefs()
    local fin = versDate(prefs.suiviFin)
    local finAujourdhui = fin == nil
    fin = fin or versDate(FenetreSuivi.aujourdhui())
    local debut
    if prefs.suiviDebut ~= '' then
        debut = versDate(prefs.suiviDebut) or debutParDefaut(fin)
        if FenetreSuivi.iso(debut) > FenetreSuivi.iso(fin) then
            debut = debutParDefaut(fin)
        end
    end
    return { debut = debut, fin = fin, finAujourdhui = finAujourdhui }
end

-- Les textes des champs « Du » et « au » pour une période.
function FenetreSuivi.textesPeriode(periode)
    return periode.debut and FenetreSuivi.texteDate(periode.debut) or FenetreSuivi.PREMIERE_PHOTO,
        periode.finAujourdhui and FenetreSuivi.AUJOURDHUI or FenetreSuivi.texteDate(periode.fin)
end

-- Écrit les champs « Du » et « au » d'après une période, sans les relire, et retient ce qu'ils
-- montrent (FenetreSuivi.champsEcrits) : FenetreSuivi.changerDate y prend l'autre borne, telle que la
-- fenêtre la montre, et y reconnaît l'écho de cette écriture (un observateur appelé plus tard).
function FenetreSuivi.poserChamps(periode)
    local debut, fin = FenetreSuivi.textesPeriode(periode)
    FenetreSuivi.champsEcrits = { debut = debut, fin = fin }
    local p = FenetreSuivi.p
    if not p then
        return
    end
    FenetreSuivi.ecritChamps = true
    local ok, erreur = pcall(function()
        poser(p, 'debutTexte', debut)
        poser(p, 'finTexte', fin)
    end)
    FenetreSuivi.ecritChamps = false
    if not ok then
        error(erreur, 0)
    end
end

-- La période que montrent les champs (FenetreSuivi.champsEcrits), lue au jour présent ; sinon la
-- période gardée. Une table neuve, comme FenetreSuivi.periode.
local function periodeMontree()
    local ecrits = FenetreSuivi.champsEcrits
    local aujourdhui = FenetreSuivi.aujourdhui()
    local d = type(ecrits) == 'table' and FenetreSuivi.lireDate(ecrits.debut, 'debut', aujourdhui) or nil
    local f = type(ecrits) == 'table' and FenetreSuivi.lireDate(ecrits.fin, 'fin', aujourdhui) or nil
    if not d or not f then
        return FenetreSuivi.periode()
    end
    local finAujourdhui = f.aujourdhui == true
    return { debut = not d.premiere and d or nil, fin = finAujourdhui and versDate(aujourdhui) or f, finAujourdhui = finAujourdhui }
end

-- Une date validée dans « Du » ou « au » (l'observateur du champ ; `borne` 'debut' ou 'fin') : lue,
-- elle se garde dans les préférences avec l'autre borne telle que la fenêtre la montre (même si un
-- jour ou un mois a passé depuis), les champs se réécrivent au propre et, si la période gardée
-- change, les graphiques se refont ; la date affichée retapée autrement se garde donc aussi (« Du »
-- ne suit plus le mois). L'écho de ce que la fenêtre vient d'écrire dans le champ (un observateur
-- appelé plus tard) ne fait rien. Une date qui ne se lit pas, ou une période à l'envers : la ligne
-- d'état le dit, avec le champ à changer d'abord, et les champs reprennent ce qu'ils montraient.
-- Rend vrai si la période gardée change.
function FenetreSuivi.changerDate(borne, texte)
    if FenetreSuivi.ecritChamps or not FenetreSuivi.p then
        return false
    end
    local ecrits = FenetreSuivi.champsEcrits
    if type(ecrits) == 'table' and texte == ecrits[borne] then
        return false
    end
    local actuelle = periodeMontree()
    local debut, fin, finAujourdhui = actuelle.debut, actuelle.fin, actuelle.finAujourdhui
    local lue = FenetreSuivi.lireDate(texte, borne, FenetreSuivi.aujourdhui())
    local refus
    if not lue then
        refus = string.format(borne == 'debut' and FenetreSuivi.DEBUT_ILLISIBLE or FenetreSuivi.FIN_ILLISIBLE, Texte.nettoyer(texte))
    elseif borne == 'debut' then
        debut = not lue.premiere and lue or nil
    else
        finAujourdhui = lue.aujourdhui == true
        fin = finAujourdhui and versDate(FenetreSuivi.aujourdhui()) or lue
    end
    if not refus and debut and FenetreSuivi.iso(debut) > FenetreSuivi.iso(fin) then
        refus = borne == 'debut'
            and string.format(FenetreSuivi.DEBUT_APRES_FIN, FenetreSuivi.texteDate(debut), FenetreSuivi.texteDate(fin))
            or string.format(FenetreSuivi.FIN_AVANT_DEBUT, FenetreSuivi.texteDate(fin), FenetreSuivi.texteDate(debut))
    end
    if refus then
        poser(FenetreSuivi.p, 'etat', refus)
        FenetreSuivi.poserChamps(actuelle)
        return false
    end
    local prefs = Chemins.prefs()
    local avant = tostring(prefs.suiviDebut) .. '|' .. tostring(prefs.suiviFin)
    prefs.suiviDebut = debut and FenetreSuivi.iso(debut) or ''
    prefs.suiviFin = finAujourdhui and FenetreSuivi.AUJOURDHUI or FenetreSuivi.iso(fin)
    FenetreSuivi.poserChamps(FenetreSuivi.periode())
    if avant == prefs.suiviDebut .. '|' .. prefs.suiviFin then
        return false
    end
    FenetreSuivi.aRedessiner = true
    return true
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

-- L'entrée de --graphiques (contrat : graphiques.entree), pour la période gardée et ce défaut (nil :
-- le plus fréquent). Rend nil et la raison sans catalogue lisible.
function FenetreSuivi.entree(defaut)
    local catalogue = cheminCatalogue()
    if not catalogue then
        return nil, FenetreSuivi.SANS_CATALOGUE
    end
    local apparence = FenetreSuivi.apparence()
    local tailles = {}
    for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
        tailles[g.cle] = { largeur = g.largeur, hauteur = g.hauteur }
    end
    local periode = FenetreSuivi.periode()
    local entree = {
        suivi = Releve.fichier(),
        carnet = Carnet.fichier(),
        catalogue = catalogue,
        debut = periode.debut and FenetreSuivi.iso(periode.debut) or nil,
        fin = FenetreSuivi.iso(periode.fin),
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

-- La ligne d'état d'une réponse : la période (son libellé, que le connecteur donne : « du 20 novembre
-- 2025 au 20 novembre 2026 ») et ses photos, et ses remarques ; sans photo au relevé, le texte
-- d'accueil ; sans photo dans la période, ce qu'il faut faire.
function FenetreSuivi.texteEtat(reponse, sansReleve)
    if sansReleve then
        return FenetreSuivi.ACCUEIL
    end
    local morceaux = {}
    local periode = type(reponse) == 'table' and type(reponse.periode) == 'table' and reponse.periode or {}
    local n = type(reponse) == 'table' and tonumber(reponse.photos) or 0
    if n == 0 then
        local toutes = periode.depuis_le_debut == true and periode.fin == FenetreSuivi.aujourdhui()
        morceaux[1] = FenetreSuivi.SANS_PHOTO_PERIODE .. (toutes and '' or FenetreSuivi.VOIR_TOUT)
    else
        local libelle = texteOuNil(periode.libelle)
        morceaux[1] = (libelle and (libelle:sub(1, 1):upper() .. libelle:sub(2)) or "Période")
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

-- Vrai si la barre a au moins un id (sans les copier : à toute la bibliothèque, une barre en a des
-- dizaines de milliers, et chacun des 76 calques le demande à chaque réponse).
local function aDesIds(barre)
    for _, id in ipairs(type(barre) == 'table' and type(barre.ids) == 'table' and barre.ids or {}) do
        if tonumber(id) then
            return true
        end
    end
    return false
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
            local actif = barre ~= nil and aDesIds(barre)
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

-- L'écart entre deux dessins faits d'eux-mêmes (le relevé ou le carnet a changé) : DELAI_REDESSIN,
-- DELAI_REDESSIN_GRAND pour un relevé d'au moins SEUIL_GRAND originaux (celui du dernier dessin).
function FenetreSuivi.delaiRedessin()
    if (FenetreSuivi.originauxDessines or 0) >= FenetreSuivi.SEUIL_GRAND then
        return FenetreSuivi.DELAI_REDESSIN_GRAND
    end
    return FenetreSuivi.DELAI_REDESSIN
end

-- Lance `mcp-developpeur --graphiques` (depuis une tâche) pour la période et le défaut choisis, puis
-- montre sa réponse. Rend vrai si les graphiques sont refaits.
function FenetreSuivi.dessiner()
    local p = FenetreSuivi.p
    local generation = FenetreSuivi.generation
    -- Un dessin demandé (l'ouverture, une autre période, un autre défaut, le reclassement fini).
    local demande = FenetreSuivi.aRedessiner == true
    FenetreSuivi.aRedessiner = false
    -- Un dessin demandé : ce que le Suivi a rangé sans l'écrire encore (ses écritures sont espacées :
    -- Releve.delaiEcriture) s'écrit d'abord, --graphiques lit le fichier. Un dessin fait de lui-même
    -- (le relevé écrit, Releve.version, ou le carnet changé, Carnet.version) lit le fichier tel quel :
    -- rien à forcer (l'écriture suivante fera redessiner).
    if demande then
        local okEcrit, erreurEcrit = LrTasks.pcall(Releve.ecrire)
        if not okEcrit then
            Journal.noter("Fenêtre Suivi : relevé non écrit avant le dessin :", tostring(erreurEcrit))
        end
    end
    FenetreSuivi.releveDessine, FenetreSuivi.carnetDessine = Releve.version, Carnet.version
    FenetreSuivi.dessineLe = os.time()
    FenetreSuivi.derniereErreur = nil
    local okNombre, n = LrTasks.pcall(Releve.nombre)
    FenetreSuivi.sansReleve = okNombre and n == 0
    FenetreSuivi.originauxDessines = okNombre and tonumber(n) or 0
    local connecteur = Chemins.prefs().cheminConnecteur
    if type(connecteur) ~= 'string' or connecteur == '' or not Fichiers.existe(connecteur) then
        return echec(FenetreSuivi.CONNECTEUR_ABSENT)
    end
    -- Les champs disent la période dessinée (sans rien de gardé, elle suit le jour : une fenêtre
    -- restée ouverte après minuit).
    FenetreSuivi.poserChamps(FenetreSuivi.periode())
    local entree, raison = FenetreSuivi.entree(p and p.defaut)
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
    -- La réponse se lit dans son fichier (avec tous les ids : à toute la bibliothèque, « Du » vide,
    -- elle dépasse 10 Mo), et se décode en rendant la main (LrTasks.pcall : un pcall simple l'en
    -- empêcherait, Lua 5.1).
    local texteReponse = Fichiers.lire(fichierReponse) or ''
    local ok, reponse = LrTasks.pcall(function() return Json.decode(texteReponse, rendreLaMain, FenetreSuivi.PAS_JSON) end)
    texteReponse = nil
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

-- L'uuid de chaque photo, par des lectures groupées de Releve.LOT_LECTURE photos (sinon une à une),
-- la main rendue entre deux.
local function uuidsDe(cat, photos)
    local r = {}
    for debut = 1, #photos, Releve.LOT_LECTURE do
        local morceau = {}
        for i = debut, math.min(#photos, debut + Releve.LOT_LECTURE - 1) do
            morceau[#morceau + 1] = photos[i]
        end
        local ok, lus = LrTasks.pcall(function() return cat:batchGetRawMetadata(morceau, { 'uuid' }) end)
        rendreLaMain()
        for j, photo in ipairs(morceau) do
            local uuid = ok and type(lus) == 'table' and type(lus[photo]) == 'table' and lus[photo].uuid or nil
            if uuid == nil then
                local okUn, u = LrTasks.pcall(photo.getRawMetadata, photo, 'uuid')
                uuid = okUn and u or nil
                if j % FenetreSuivi.PAS_UNE_A_UNE == 0 then
                    rendreLaMain()
                end
            end
            r[debut + j - 1] = uuid
        end
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
-- détail de la barre, pour le message. Rend le nombre de photos sélectionnées. Une barre de toute la
-- bibliothèque se montre par tranches, la main rendue (Releve.uuidsDe lit le relevé sans le copier,
-- PAS_UNE_A_UNE photos retrouvées entre deux, les uuid par lectures groupées), et la sélection posée
-- ne se range pas au relevé (Releve.poserSelection : ses photos y sont déjà).
function FenetreSuivi.montrerPhotos(ids, quoi)
    local cat = Photos.catalogue()
    local attendus = Releve.uuidsDe(ids)
    local trouvees, uuids = {}, {}
    for k, id in ipairs(ids) do
        if attendus[id] then
            local ok, photo = LrTasks.pcall(cat.getPhotoByLocalId, cat, id)
            if ok and type(photo) == 'table' then
                trouvees[#trouvees + 1] = photo
                uuids[#uuids + 1] = attendus[id]
            end
        end
        if k % FenetreSuivi.PAS_UNE_A_UNE == 0 then
            rendreLaMain()
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
    -- Une sélection que la fenêtre pose : ses photos viennent du relevé, le Suivi ne la range pas
    -- (Releve.poserSelection ; à toute la bibliothèque, une vue entière à chaque clic).
    local toutes, n, sourceChangee = Releve.poserSelection(function()
        local toutesLa, nLa = selectionner(cat, photos)
        local changee = false
        if not toutesLa and cat.kAllPhotos ~= nil then
            LrTasks.pcall(cat.setActiveSources, cat, cat.kAllPhotos)
            changee = true
            local fin = LrDate.currentTime() + FenetreSuivi.DELAI_SOURCE
            repeat
                toutesLa, nLa = selectionner(cat, photos)
                if toutesLa then
                    break
                end
                LrTasks.sleep(#photos >= FenetreSuivi.GRANDE_SELECTION and 1 or 0.2)
            until LrDate.currentTime() > fin
        end
        return toutesLa, nLa, changee
    end)
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

-- Le contenu : l'aplat du fond, puis l'en-tête (titre, « Du » et « au »), la ligne d'état, les
-- tuiles, et les deux colonnes : Mes prises de vue (les notes à côté des objectifs), Mon carnet de
-- progrès (avec le menu du défaut suivi, l'aide et le message).
function FenetreSuivi.construire(f, p)
    local D, C, P = FenetreSuivi.dimensions(), FenetreSuivi.COULEURS, FenetreSuivi.POLICES
    local tuiles = { spacing = D.ecartTuile }
    for k = 1, #FenetreSuivi.TUILES do
        tuiles[#tuiles + 1] = tuile(f, D, C, P, k)
    end
    local largeurTitre = D.interieur - D.etiquetteDu - D.etiquetteAu - 2 * D.champDate - 4 * 8
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
        f:row { spacing = D.ecartPetits, bloc(f, D, C, P, 'objectifs'), bloc(f, D, C, P, 'notes') },
    }
    local enteteEvolution = f:row {
        spacing = 8,
        height = D.enteteEvolution,
        texte(f, { title = bind 'titre_evolution_defaut', font = P.gras12, text_color = C.texte, width = D.colonne - D.defaut - 8,
            truncation = 'tail', place_vertical = 0.5 }),
        f:popup_menu { items = bind 'elementsDefaut', value = bind 'defaut', width = D.defaut, place_vertical = 0.5,
            tooltip = "Le défaut suivi au fil de la période : le plus fréquent, ou celui que vous choisissez" },
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
        texte(f, { title = bind 'message', font = P.petit, text_color = C.texte, width = D.colonne, height = D.bas, height_in_lines = 2,
            truncation = 'tail', tooltip = bind 'message' }),
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
                texte(f, { title = "Du", font = P.texte12, text_color = C.gris, alignment = 'right', width = D.etiquetteDu,
                    place_vertical = 0.5 }),
                f:edit_field { value = bind 'debutTexte', immediate = false, width = D.champDate, place_vertical = 0.5,
                    tooltip = FenetreSuivi.INFOBULLE_DEBUT },
                texte(f, { title = "au", font = P.texte12, text_color = C.gris, alignment = 'right', width = D.etiquetteAu,
                    place_vertical = 0.5 }),
                f:edit_field { value = bind 'finTexte', immediate = false, width = D.champDate, place_vertical = 0.5,
                    tooltip = FenetreSuivi.INFOBULLE_FIN },
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

-- Les valeurs de la fenêtre avant la première réponse (chaque clé liée en a une avant l'ouverture).
local function preparer(p)
    p.etat = FenetreSuivi.LECTURE
    p.message = ''
    p.attente = FenetreSuivi.ATTENTE
    p.debutTexte, p.finTexte = FenetreSuivi.textesPeriode(FenetreSuivi.periode())
    FenetreSuivi.champsEcrits = { debut = p.debutTexte, fin = p.finTexte }
    p.defaut = FenetreSuivi.LE_PLUS_FREQUENT
    p.elementsDefaut = FenetreSuivi.elementsDefaut(nil)
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

-- La note, le drapeau et « retouchée par Claude » relus (Releve.reclasser) dans une tâche à part : à
-- toute la bibliothèque, ce sont des centaines de milliers de lectures du catalogue, et la boucle de
-- la fenêtre doit suivre la période et le défaut choisis pendant ce temps. Fini, la fenêtre (encore
-- ouverte, la même) se redessine s'il a changé des entrées (Releve.reclasser rend leur nombre : sans
-- rien de changé dans le catalogue, ni écriture ni dessin). Rend vrai si la tâche part.
function FenetreSuivi.reclasserEnFond()
    local generation = FenetreSuivi.generation
    LrTasks.startAsyncTask(function()
        local ok, n = LrTasks.pcall(Releve.reclasser)
        if not ok then
            Journal.noter("Fenêtre Suivi : classement non relu :", tostring(n))
        elseif (tonumber(n) or 0) > 0 and FenetreSuivi.ouverte and FenetreSuivi.generation == generation then
            FenetreSuivi.aRedessiner = true
        end
    end)
    return true
end

-- Un tour de la boucle (depuis une tâche) : le dessin, demandé (ouverture, période, défaut,
-- reclassement fini) ou quand le relevé ou le carnet a
-- changé (au plus toutes les FenetreSuivi.delaiRedessin secondes) ; après le premier dessin de
-- l'ouverture, la note, le drapeau et « retouchée par Claude » relus en arrière-plan
-- (FenetreSuivi.reclasserEnFond) ; la file d'analyse relancée (comme les boucles de la fenêtre
-- Claude et de la Demande rapide).
function FenetreSuivi.suivre()
    local change = Releve.version ~= FenetreSuivi.releveDessine or Carnet.version ~= FenetreSuivi.carnetDessine
    if FenetreSuivi.aRedessiner or (change and os.time() - (FenetreSuivi.dessineLe or 0) >= FenetreSuivi.delaiRedessin()) then
        FenetreSuivi.dessiner()
    end
    if FenetreSuivi.aReclasser and FenetreSuivi.dessineLe ~= nil then
        FenetreSuivi.aReclasser = false
        FenetreSuivi.reclasserEnFond()
    end
    LrTasks.pcall(Releve.relancer)
end

-- La boucle de la fenêtre ouverte (sa génération : une fenêtre rouverte a la sienne), deux fois par
-- seconde.
function FenetreSuivi.boucle(generation)
    while FenetreSuivi.ouverte and FenetreSuivi.generation == generation do
        local ok, erreur = LrTasks.pcall(FenetreSuivi.suivre)
        if not ok then
            FenetreSuivi.aRedessiner = false
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
                FenetreSuivi.effacerDessins()
            end
            Journal.noter("Fenêtre Suivi :", tostring(erreur))
            LrDialogs.message("La fenêtre Suivi n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)
        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
        FenetreSuivi.reponse, FenetreSuivi.calquesValides, FenetreSuivi.derniereErreur = nil, {}, nil
        FenetreSuivi.releveDessine, FenetreSuivi.carnetDessine, FenetreSuivi.dessineLe = nil, nil, nil
        FenetreSuivi.originauxDessines = 0
        FenetreSuivi.aReclasser, FenetreSuivi.aRedessiner, FenetreSuivi.sansReleve = true, true, false
        FenetreSuivi.message = nil
        FenetreSuivi.effacerDessins()
        preparerCouleurs()
        preparer(p)
        FenetreSuivi.p = p
        local contenu = FenetreSuivi.construire(f, p)
        -- Une autre date (gardée : FenetreSuivi.changerDate) ou un autre défaut choisi : les graphiques
        -- se refont au tour suivant.
        p:addObserver('debutTexte', function(_, _, valeur) FenetreSuivi.changerDate('debut', valeur) end)
        p:addObserver('finTexte', function(_, _, valeur) FenetreSuivi.changerDate('fin', valeur) end)
        p:addObserver('defaut', function() FenetreSuivi.aRedessiner = true end)
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
