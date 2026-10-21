-- essais-jelefais.lua : « Je le fais » dans la fenêtre Claude (1.3, lot 14), hors de Lightroom
-- (LuaJIT, Lightroom simulé par Simulation.lua, complété ici sans la toucher : photos avec leurs
-- réglages de développement, getDevelopSettings) : l'élément `exercice` du fil, de l'appel de
-- preview_settings avec my_turn à la comparaison de view_photo avec compare = claude_version
-- (Conversation : un exercice et non une proposition, liste en tables neuves, réponse d'attente et
-- remarque de l'écran passées, refus, interruption) ; ses lignes (Fil : genres existants, 12
-- réglages au plus) ; son stockage ; la lecture des réglages (Lightroom.valeurs : balance d'un
-- JPEG, profil par sa Look, courbe) ; la carte Proposition (liste groupée par panneau, cochée ✓
-- toutes les 2 s, page par page, puis les écarts), le bouton « Je le fais » puis « J'ai fini »
-- (Fenetre.bouton, Moteur.jeLeFais, Moteur.jaiFini), l'aperçu « Claude | vous » et Agrandir, une
-- autre photo pendant l'exercice ; la section « Je le fais » des consignes ; et les deux boutons
-- de bout en bout par relais.sh avec faux-claude.sh. Les réponses du connecteur sont les vraies,
-- produites par le serveur sur l'exemple RAW de Tests/Contrats/je-le-fais.json (photo 53636309).
-- Ni Claude, ni quota ; les fichiers vont dans un dossier personnel temporaire.
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

local function copie(valeur)
    if type(valeur) ~= 'table' then
        return valeur
    end
    local t = {}
    for cle, element in pairs(valeur) do
        t[cle] = copie(element)
    end
    return t
end

-- Toutes les vues d'un arbre.
local function vues(contenu)
    local liste = {}
    local function parcourir(v)
        liste[#liste + 1] = v
        for _, enfant in ipairs(v.args or {}) do
            if type(enfant) == 'table' and enfant.genre then
                parcourir(enfant)
            end
        end
    end
    parcourir(contenu)
    return liste
end

-- Le bouton de ce titre (titre lié lu dans `p`) ; `cleActif` : celui dont `enabled` suit cette clé.
local function bouton(contenu, p, titre, cleActif)
    for _, v in ipairs(vues(contenu)) do
        local t = v.args.title
        if type(t) == 'table' and t.liaison then
            t = p[t.key]
        end
        if S.BOUTONS[v.genre] and t == titre
            and (not cleActif or (type(v.args.enabled) == 'table' and v.args.enabled.key == cleActif)) then
            return v
        end
    end
    error('bouton introuvable : ' .. tostring(titre), 2)
end

-- Lance les tâches parties depuis `depuis` (et celles qu'elles lancent), dans l'ordre.
local function lancerTaches(depuis)
    local i = depuis + 1
    while i <= #S.taches do
        vrai(i - depuis <= 100, 'des tâches sans fin')
        local t = S.taches[i]
        S.taches[i] = function() end
        t()
        i = i + 1
    end
end

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Json = require 'Json'
local Lightroom = require 'Lightroom'
local Notation = require 'Notation'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
local propositionVraie = Notation.proposition
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'
local prefs = Chemins.prefs()
prefs.propositionAOuverture = false
prefs.nouvelleParPhoto = false

-- Le faux Claude Code dès le départ (une demande partie par erreur ne lance jamais le vrai), et
-- une petite image JPEG (en base64) pour ses résultats d'outils.
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'
prefs.cheminConnecteur = '/bin/echo'
local imageJpeg = S.home .. '/image.jpg'
local imageB64 = S.home .. '/image.b64'
S.executer('/usr/bin/sips -s format jpeg -z 60 180 ' .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out ' .. S.q(imageJpeg) .. ' >/dev/null 2>&1')
S.executer('/usr/bin/base64 -i ' .. S.q(imageJpeg) .. ' -o ' .. S.q(imageB64))
local env = 'FAUX_IMAGE_B64=' .. S.q(imageB64) .. ' '
local executerOriginal = S.modules.LrTasks.execute
S.modules.LrTasks.execute = function(commande)
    if commande:find('relais.sh', 1, true) then
        commande = env .. commande
    end
    return executerOriginal(commande)
end

-- La simulation complétée ici : des photos avec leurs réglages de développement (getDevelopSettings
-- rend une copie, comme Lightroom), trouvées par leur identifiant.
local photos = {}
local parIdOriginal = S.catalogue.getPhotoByLocalId
S.catalogue.getPhotoByLocalId = function(_, id)
    return photos[tonumber(id)] or S.photoActive
end

local function photoDev(id, nom, reglages, format)
    local photo = S.photo(id, nom)
    photo.reglages = reglages or {}
    photo.getDevelopSettings = function(self)
        S.lecturesReglages = (S.lecturesReglages or 0) + 1
        return copie(self.reglages)
    end
    local brut = photo.getRawMetadata
    photo.getRawMetadata = function(self, cle)
        if cle == 'fileFormat' then
            return format or 'RAW'
        end
        return brut(self, cle)
    end
    photos[id] = photo
    return photo
end

local function photoActive(photo)
    S.photoActive, S.selection = photo, { photo }
    return photo
end

-- Les réglages de la photo d'essai au départ de l'exercice (RAF, profil Adobe Color).
local function reglagesDepart()
    return { Temperature = 5350, Tint = 19, Exposure2012 = 0, Contrast2012 = 0, Vibrance = 0, CameraProfile = 'Adobe Standard',
        Look = { Name = 'Adobe Color', Amount = 1 }, WhiteBalance = 'As Shot', CropLeft = 0, CropTop = 0, CropRight = 1, CropBottom = 1,
        CropAngle = 0 }
end

-- La largeur du texte du fil (Fenetre.largeurTexte : D.texteFil dans la fenêtre B, après la colonne
-- auteur), et celle qu'une ligne ne dépasse jamais, son retrait compris (Fil.occupe).
local D = Dispositions.dimensions()
local LARGEUR = D.texteFil
local LARGEUR_LIGNE = LARGEUR - Fil.MARGE

-- Ouvre la fenêtre Claude et appelle fn(p, args) pendant qu'elle est ouverte ; une erreur de fn
-- remonte une fois la fenêtre fermée.
local function ouvrirFenetre(fn)
    local erreur
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function() fn(Fenetre.p, args) end, debug.traceback)
        erreur = not ok and e or nil
    end
    Fenetre.afficher()
    S.pendantFenetre = nil
    if erreur then
        error(erreur, 0)
    end
end

-- Les réponses du connecteur (Tools+Retouche.monTour, puis viewPhoto avec claude_version), telles
-- que le serveur les rend sur l'exemple RAW du contrat, pour la photo 53636309.
local TOUR = [=[{
  "a_faire": [
    {
      "a": "5 600 K",
      "apres": 5600,
      "avant": 5350,
      "cle": "Temperature",
      "de": "5 350 K",
      "n": 1,
      "panneau": "Réglages de base",
      "reglage": "Température",
      "section": "Balance des blancs",
      "texte": "Réglages de base › Balance des blancs › Température : 5 350 K → 5 600 K"
    },
    {
      "a": "+0,35",
      "apres": 0.35,
      "avant": 0,
      "cle": "Exposure2012",
      "de": "0",
      "n": 2,
      "panneau": "Réglages de base",
      "reglage": "Exposition",
      "section": "Tonalité",
      "texte": "Réglages de base › Tonalité › Exposition : 0 → +0,35"
    },
    {
      "a": "+10",
      "apres": 10,
      "avant": 0,
      "cle": "Contrast2012",
      "de": "0",
      "n": 3,
      "panneau": "Réglages de base",
      "reglage": "Contraste",
      "section": "Tonalité",
      "texte": "Réglages de base › Tonalité › Contraste : 0 → +10"
    },
    {
      "a": "+10",
      "apres": 10,
      "avant": 0,
      "cle": "Vibrance",
      "de": "0",
      "n": 4,
      "panneau": "Réglages de base",
      "reglage": "Vibrance",
      "section": "Présence",
      "texte": "Réglages de base › Présence › Vibrance : 0 → +10"
    },
    {
      "a": "3 points",
      "apres": "3 points",
      "avant": "linéaire",
      "cle": "ToneCurvePV2012",
      "de": "linéaire",
      "n": 5,
      "panneau": "Courbe des tonalités",
      "reglage": "Courbe par points : RVB",
      "section": null,
      "texte": "Courbe des tonalités › Courbe par points › RVB : linéaire → 3 points"
    }
  ],
  "base": "a_faire : dans l'ordre des panneaux du module Développement ; « de » : la valeur actuelle, « a » : celle de Claude ; texte : panneau › section › réglage. Réglages globaux seulement.",
  "ensuite": "Quand l'utilisateur a fini : view_photo avec compare = claude_version.",
  "etape": "Claude · essai : ma version (je le fais)",
  "instantane": "Claude · ma version",
  "mode": "appliquer directement",
  "photo": {
    "copie_virtuelle": true,
    "fichier": "DSCF4961.RAF",
    "id": 53636309
  },
  "rien_n_est_applique": "La photo est restée comme avant : la version de Claude est rangée en instantané « Claude · ma version » (choose_variant « ma version » la pose, seulement si l'utilisateur le demande)."
}]=]
local VUE = [=[{
  "bilan": {
    "depuis": "ma version (Claude, à gauche)"
  },
  "exercice": {
    "a_savoir_exercice": "Ce que l'utilisateur a ajouté ou changé à la main (masques) se voit dans les deux images : la version de Claude ne peut pas le retirer le temps du rendu (la photo en portait déjà au départ).",
    "comme_claude": [
      "Préréglage",
      "Température"
    ],
    "ecart_principal": {
      "claude": 42.4,
      "ecart": 1.05,
      "fois_le_seuil": 10.4,
      "mesure": "exposition",
      "reglage": {
        "claude": 0.35,
        "cle": "Exposure2012",
        "depart": 0,
        "panneau": "Réglages de base",
        "reglage": "Exposition",
        "section": "Tonalité",
        "sorte": "plus_fort",
        "texte": "Réglages de base › Tonalité › Exposition : départ 0, Claude +0,35, vous +0,8 — plus fort que Claude",
        "vous": 0.8
      },
      "seuil": 0.1,
      "texte": "Votre version est plus claire de 1,04 IL (visible dès 0,1 IL). Le réglage qui l'explique le mieux : Réglages de base › Tonalité › Exposition : départ 0, Claude +0,35, vous +0,8 — plus fort que Claude.",
      "visible": true,
      "vous": 58.3
    },
    "ecarts": [
      {
        "claude": "Adobe Color",
        "cle": "Look",
        "depart": "Adobe Color",
        "panneau": "Réglages de base",
        "reglage": "Profil (Look)",
        "section": "Profil",
        "sorte": "ajoute",
        "texte": "Réglages de base › Profil › Profil (Look) : départ Adobe Color, Claude Adobe Color, vous aucune — ajouté par vous (Claude n'y touchait pas)",
        "vous": "aucune"
      },
      {
        "claude": "Custom",
        "cle": "WhiteBalance",
        "depart": "As Shot",
        "panneau": "Réglages de base",
        "reglage": "Préréglage",
        "section": "Balance des blancs",
        "sorte": "comme_claude",
        "texte": "Réglages de base › Balance des blancs › Préréglage : départ Telle quelle, Claude Personnalisée, vous Personnalisée — comme Claude",
        "vous": "Custom"
      },
      {
        "claude": 5600,
        "cle": "Temperature",
        "depart": 5350,
        "panneau": "Réglages de base",
        "reglage": "Température",
        "section": "Balance des blancs",
        "sorte": "comme_claude",
        "texte": "Réglages de base › Balance des blancs › Température : départ 5 350 K, Claude 5 600 K, vous 5 650 K — comme Claude",
        "vous": 5650
      },
      {
        "claude": 0.35,
        "cle": "Exposure2012",
        "depart": 0,
        "panneau": "Réglages de base",
        "reglage": "Exposition",
        "section": "Tonalité",
        "sorte": "plus_fort",
        "texte": "Réglages de base › Tonalité › Exposition : départ 0, Claude +0,35, vous +0,8 — plus fort que Claude",
        "vous": 0.8
      },
      {
        "claude": 10,
        "cle": "Contrast2012",
        "depart": 0,
        "panneau": "Réglages de base",
        "reglage": "Contraste",
        "section": "Tonalité",
        "sorte": "oublie",
        "texte": "Réglages de base › Tonalité › Contraste : départ 0, Claude +10, vous 0 — pas fait (Claude l'avait changé)",
        "vous": 0
      },
      {
        "claude": 0,
        "cle": "Clarity2012",
        "depart": 0,
        "panneau": "Réglages de base",
        "reglage": "Clarté",
        "section": "Présence",
        "sorte": "ajoute",
        "texte": "Réglages de base › Présence › Clarté : départ 0, Claude 0, vous +20 — ajouté par vous (Claude n'y touchait pas)",
        "vous": 20
      },
      {
        "claude": 10,
        "cle": "Vibrance",
        "depart": 0,
        "panneau": "Réglages de base",
        "reglage": "Vibrance",
        "section": "Présence",
        "sorte": "oublie",
        "texte": "Réglages de base › Présence › Vibrance : départ 0, Claude +10, vous 0 — pas fait (Claude l'avait changé)",
        "vous": 0
      },
      {
        "claude": "changée",
        "cle": "ToneCurvePV2012",
        "depart": "inchangée",
        "panneau": "Courbe des tonalités",
        "reglage": "Courbe par points : RVB",
        "section": null,
        "sorte": "autre_choix",
        "texte": "Courbe des tonalités › Courbe par points › RVB : Claude changée, vous changée autrement — un autre choix que Claude",
        "vous": "changée autrement"
      },
      {
        "claude": {
          "CropLeft": 0,
          "CropRight": 1,
          "CropTop": 0
        },
        "cle": "Crop",
        "cles": [
          "CropLeft",
          "CropRight",
          "CropTop"
        ],
        "depart": {
          "CropLeft": 0,
          "CropRight": 1,
          "CropTop": 0
        },
        "panneau": "Outil Recadrage",
        "reglage": "Cadre",
        "section": null,
        "sorte": "ajoute",
        "texte": "Outil Recadrage › Cadre : départ sans rognage ; Claude sans rognage ; vous rogné à gauche 5 %, en haut 2 %, à droite 5 % — ajouté par vous (Claude n'y touchait pas)",
        "vous": {
          "CropLeft": 0.05,
          "CropRight": 0.95,
          "CropTop": 0.02
        }
      }
    ],
    "instantane": "Claude · ma version",
    "le": "2026-10-21 10:00",
    "listes": {
      "masques": {
        "depart": 1,
        "vous": 2
      },
      "taches": {
        "depart": 0,
        "vous": 0
      },
      "yeux_rouges": {
        "depart": 0,
        "vous": 0
      }
    },
    "restent": [
      "MaskGroupBasedCorrections"
    ],
    "resume": "9 réglages comparés : 2 comme Claude, 1 plus fort, 2 oubliés, 3 ajoutés, 1 autre choix.",
    "rien_change": false
  },
  "image": "À gauche ma version (Claude), à droite la vôtre.",
  "photo": {
    "copie_virtuelle": true,
    "fichier": "DSCF4961.RAF",
    "id": 53636309
  }
}]=]
local REMARQUE_ECRAN = "Écran : profil d'usine, non étalonné : dis-le une fois si tu demandes son avis sur les couleurs."

local function entreeTour(photo)
    return { photo_id = photo or 53636309, settings = { Exposure2012 = 0.35, Vibrance = 10, Temperature = 5600, Contrast2012 = 10 },
        my_turn = true, step_name = 'lumière et couleur' }
end

-- Un appel de preview_settings avec my_turn, et sa réponse s'il y en a une. Rend l'indice de
-- l'exercice et celui de l'élément outil.
local function appelTour(c, appel, textes, erreur, photo)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = appel, nom = 'mcp__developpeur__preview_settings',
        entree = entreeTour(photo) } } })
    local outil = #c.elements - 1
    local exercice = #c.elements
    if textes then
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = appel, textes = textes, images = {}, erreur = erreur == true } } })
    end
    return exercice, outil
end

-- Un appel de view_photo avec compare = claude_version, et sa réponse (image côte à côte rangée
-- sous `nom`, dans le dossier de la conversation) s'il y en a une. Rend l'indice de l'élément outil.
local function appelComparaison(c, appel, textes, erreur, photo, nom)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = appel, nom = 'mcp__developpeur__view_photo',
        entree = { photo_id = photo or 53636309, compare = 'claude_version' } } } })
    local outil = #c.elements
    if textes then
        local images = erreur and {} or { { donnees = 'x', type = 'image/jpeg' } }
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = appel, textes = textes, images = images, erreur = erreur == true } } },
            nil, function()
                local chemin = nom or 'comparaison.jpg'
                Fichiers.creerDossier(Stockage.dossier(c.id))
                S.executer('cp ' .. S.q(imageJpeg) .. ' ' .. S.q(Stockage.image(c.id, chemin)))
                return chemin
            end)
    end
    return outil
end

-- Une proposition ordinaire en attente (preview_settings sans my_turn), avec sa réponse.
local function proposition(c, appel)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = appel, nom = 'mcp__developpeur__preview_settings',
        entree = { reason = 'Plus de lumière', settings = { Exposure2012 = 0.35 }, compare = true } } } })
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = appel, textes = { '{"changements": [{"cle": "Exposure2012", "avant": 0, "apres": 0.35}]}' },
        images = {}, erreur = false } } })
    return Conversation.propositionEnAttente(c)
end

-- Les lignes d'un élément, en « genre|icône|texte ».
local function textes(lignes)
    local t = {}
    for _, l in ipairs(lignes) do
        t[#t + 1] = (l.genre or '') .. '|' .. (l.icone or '') .. '|' .. (l.texte or '')
    end
    return table.concat(t, '\n')
end

local function sansMetatables(valeur, quoi)
    if type(valeur) ~= 'table' then
        return
    end
    egal(nil, getmetatable(valeur), (quoi or 'table') .. ' : une table neuve')
    for cle, x in pairs(valeur) do
        sansMetatables(x, (quoi or 'table') .. '.' .. tostring(cle))
    end
end

-- Conversation ----------------------------------------------------------------------------------

essai("Conversation : preview_settings avec my_turn fait un exercice, pas une proposition ; sa liste arrive en tables neuves", function()
    local c = Conversation.nouvelle()
    local i, outil = appelTour(c, 't1')
    egal('outil', c.elements[outil].genre)
    egal('preview_settings · lumière et couleur', c.elements[outil].texte)
    local e = c.elements[i]
    egal('exercice', e.genre)
    egal('enCours', e.etat)
    egal('t1', e.appel)
    egal(53636309, e.photo)
    egal(nil, Conversation.propositionEnAttente(c), 'aucune proposition à accepter')
    for _, x in ipairs(c.elements) do
        vrai(x.genre ~= 'proposition', 'pas de proposition pour my_turn')
    end
    egal(nil, Conversation.exerciceEnCours(c), 'pas encore de liste')
    egal(e, Conversation.dernierExercice(c))
    -- La réponse : la liste dans l'ordre reçu (celui du panneau Développement).
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 't1', textes = { TOUR }, images = {}, erreur = false } } })
    egal('aFaire', e.etat)
    egal(5, #e.aFaire)
    local cles = {}
    for _, x in ipairs(e.aFaire) do
        cles[#cles + 1] = x.cle
    end
    egal('Temperature Exposure2012 Contrast2012 Vibrance ToneCurvePV2012', table.concat(cles, ' '))
    local expo = e.aFaire[2]
    egal(2, expo.n)
    egal('Réglages de base', expo.panneau)
    egal('Tonalité', expo.section)
    egal('Exposition', expo.reglage)
    egal('0', expo.de)
    egal('+0,35', expo.a)
    egal(0, expo.avant)
    egal(0.35, expo.apres)
    egal('Réglages de base › Tonalité › Exposition : 0 → +0,35', expo.texte)
    egal(5350, e.aFaire[1].avant)
    egal('linéaire', e.aFaire[5].avant, 'une table : son résumé')
    egal(nil, e.aFaire[5].section, 'section null : absente')
    egal('Claude · ma version', e.instantane)
    egal('DSCF4961.RAF', e.fichier)
    egal(53636309, e.photo)
    sansMetatables(e.aFaire, 'aFaire')
    egal(e, Conversation.exerciceEnCours(c))
    -- L'élément outil a sa réponse ; un preview_settings sans my_turn reste une proposition.
    egal('fait', c.elements[outil].etat)
    local p = proposition(c, 'p1')
    vrai(p and p.genre == 'proposition' and p.etat == 'enAttente', 'proposition ordinaire')
    egal(nil, Conversation.dernierExercice(c), 'une proposition après l\'exercice prend la carte')
    egal(nil, Conversation.exerciceEnCours(c))
end)

essai("Conversation : exerciceLu passe un texte non JSON et retire une remarque recollée ; refus, réponse sans liste, interruption", function()
    -- Blocs à part : un texte d'attente, puis le JSON, puis la remarque de l'écran.
    local lu = Conversation.exerciceLu({ "Pas du JSON", TOUR, REMARQUE_ECRAN })
    vrai(lu and lu.liste, 'la liste lue malgré le texte d\'avant')
    egal(5, #lu.aFaire)
    -- Les blocs recollés : la remarque suit le JSON dans le même texte.
    lu = Conversation.exerciceLu({ TOUR .. '\n' .. REMARQUE_ECRAN })
    vrai(lu and lu.liste, 'la remarque recollée est retirée')
    egal(53636309, lu.photo)
    lu = Conversation.exerciceLu({ VUE .. '\n\n' .. REMARQUE_ECRAN })
    vrai(lu and lu.comparaison, 'la comparaison lue malgré la remarque')
    egal(9, #lu.ecarts)
    -- Rien de lisible : nil.
    egal(nil, Conversation.exerciceLu({ "« preview_settings » n'est pas fini après 50 s : rappeler…" }))
    egal(nil, Conversation.exerciceLu({ '{"changements": []}' }))
    egal(nil, Conversation.exerciceLu({}))
    egal(nil, Conversation.exerciceLu(nil))
    -- Refus du connecteur : erreur, avec la raison.
    local c = Conversation.nouvelle()
    local i = appelTour(c, 't1', { 'Rien à faire : la proposition est l\'état actuel.' }, true)
    egal('erreur', c.elements[i].etat)
    egal("Rien à faire : la proposition est l'état actuel.", c.elements[i].texte)
    -- La réponse d'attente (appel trop long, que Claude rappelle) : pas de liste, en erreur.
    i = appelTour(c, 't2', { "« preview_settings » n'est pas fini après 50 s : rappeler preview_settings avec exactement les mêmes arguments." })
    egal('erreur', c.elements[i].etat)
    contient(c.elements[i].texte, 'liste non reçue : « preview_settings » n\'est pas fini')
    -- Le rappel en fait un autre, avec sa liste.
    i = appelTour(c, 't3', { TOUR })
    egal('aFaire', c.elements[i].etat)
    egal(c.elements[i], Conversation.exerciceEnCours(c))
    -- Interrompu pendant l'appel : en erreur ; fini sans réponse : en erreur aussi (pas de liste).
    local d = Conversation.nouvelle()
    i = appelTour(d, 't4')
    Conversation.appliquer(d, { genre = 'fin', reussie = false, interrompue = true, session = '' })
    egal('erreur', d.elements[i].etat)
    i = appelTour(d, 't5')
    Conversation.appliquer(d, { genre = 'fin', reussie = true, interrompue = false, session = '' })
    egal('erreur', d.elements[i].etat)
    egal(nil, Conversation.exerciceEnCours(d))
end)

essai("Conversation : la comparaison (claude_version) se note sur l'exercice de sa photo ; écarts, écart principal, image « Claude | vous »", function()
    local c = Conversation.nouvelle()
    local i = appelTour(c, 't1', { TOUR })
    local e = c.elements[i]
    -- Une comparaison d'une autre photo : rien ne se note sur cet exercice.
    local autre = appelComparaison(c, 'v0', nil, nil, 53636310)
    egal(true, c.elements[autre].comparaison, 'la ligne de l\'outil sait que c\'est une comparaison')
    egal(nil, e.appelComparaison, 'une autre photo')
    Conversation.appliquer(c, { genre = 'fin', reussie = true, interrompue = false, session = '' })
    -- Celle de la photo de l'exercice.
    local outil = appelComparaison(c, 'v1')
    egal(true, c.elements[outil].comparaison)
    egal('v1', e.appelComparaison)
    egal(true, e.comparaisonEnCours)
    egal('aFaire', e.etat, 'toujours à faire pendant la comparaison')
    contient(Fil.titreExercice(e), 'comparaison en cours')
    -- La réponse : l'image (rangée dans un élément aperçu), le JSON, la remarque de l'écran à part.
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'v1', textes = { VUE, REMARQUE_ECRAN },
        images = { { donnees = 'x' } }, erreur = false } } }, nil, function() return 'comparaison.jpg' end)
    egal('comparee', e.etat)
    egal(nil, e.comparaisonEnCours)
    egal(9, #e.ecarts)
    egal('Look', e.ecarts[1].cle)
    egal('ajoute', e.ecarts[1].sorte)
    egal('Réglages de base', e.ecarts[1].panneau)
    egal('comme_claude', e.ecarts[3].sorte)
    egal('Température', e.ecarts[3].reglage)
    egal('Crop', e.ecarts[9].cle)
    egal('Préréglage Température', table.concat(e.commeClaude, ' '))
    contient(e.resume, '9 réglages comparés')
    egal(true, e.principal.visible)
    contient(e.principal.texte, 'Votre version est plus claire de 1,04 IL')
    contient(e.aSavoir, 'masques')
    sansMetatables(e.ecarts, 'ecarts')
    sansMetatables(e.principal, 'principal')
    egal(nil, Conversation.exerciceEnCours(c), 'comparé : plus en cours')
    egal(e, Conversation.dernierExercice(c), 'toujours montré')
    -- L'image : dans un aperçu de l'appel, légendée comme une comparaison.
    egal('comparaison.jpg', Conversation.imageComparaison(c, e))
    local images = Conversation.images(c)
    egal('comparaison.jpg', images[#images].chemin)
    egal(true, images[#images].comparaison)
    egal('view_photo', images[#images].outil)
    -- Une comparaison refusée (aucune version rangée) : en erreur.
    local d = Conversation.nouvelle()
    i = appelTour(d, 't1', { TOUR })
    appelComparaison(d, 'v1', { "Aucune version de Claude rangée pour « Je le fais » sur cette photo." }, true)
    egal('erreur', d.elements[i].etat)
    contient(d.elements[i].texte, 'comparaison impossible : Aucune version de Claude rangée')
    egal(nil, Conversation.imageComparaison(d, d.elements[i]))
    -- Une réponse sans `exercice` (attente) : l'exercice reste à faire ; « J'ai fini » se refait.
    local f = Conversation.nouvelle()
    i = appelTour(f, 't1', { TOUR })
    appelComparaison(f, 'v1', { "« view_photo » n'est pas fini après 50 s." })
    egal('aFaire', f.elements[i].etat)
    egal(nil, f.elements[i].comparaisonEnCours)
    egal(f.elements[i], Conversation.exerciceEnCours(f))
    -- Une comparaison sans photo nommée : le dernier exercice.
    local g = Conversation.nouvelle()
    i = appelTour(g, 't1', { TOUR })
    Conversation.appliquer(g, { genre = 'assistant', blocs = { { genre = 'outil', id = 'v1', nom = 'mcp__developpeur__view_photo',
        entree = { compare = 'claude_version' } } } })
    egal('v1', g.elements[i].appelComparaison)
    -- Une fin sans réponse de la comparaison : l'exercice reste à faire, sans comparaison en cours.
    Conversation.appliquer(g, { genre = 'fin', reussie = true, interrompue = false, session = '' })
    egal('aFaire', g.elements[i].etat)
    egal(nil, g.elements[i].comparaisonEnCours)
end)

essai("Conversation : une liste demandée en mots rend « à faire vous-même » la proposition en attente ; marquer", function()
    local c = Conversation.nouvelle()
    local p = proposition(c, 'p1')
    egal(p, Conversation.propositionEnAttente(c))
    -- Une liste refusée ne touche pas la proposition.
    appelTour(c, 't0', { 'Rien à faire.' }, true)
    egal('enAttente', p.etat)
    local i = appelTour(c, 't1', { TOUR })
    egal('faite', p.etat, 'la proposition est à faire vous-même')
    egal(nil, Conversation.propositionEnAttente(c))
    egal(c.elements[i], Conversation.exerciceEnCours(c))
    -- marquer : un élément par son identifiant.
    local q = proposition(c, 'p2')
    egal(true, Conversation.marquer(c, q.id, 'faite'))
    egal('faite', q.etat)
    egal(false, Conversation.marquer(c, 'introuvable', 'faite'))
    egal(nil, Conversation.exerciceEnCours(c), 'une proposition arrivée après : plus d\'exercice en cours')
    -- Une proposition en attente arrivée pendant l'exercice prend la carte ; refusée (ou acceptée),
    -- elle la rend à l'exercice encore à faire : sa liste et « J'ai fini » reviennent.
    local h = Conversation.nouvelle()
    local exo = h.elements[appelTour(h, 't1', { TOUR })]
    local pendant = proposition(h, 'p1')
    egal(nil, Conversation.dernierExercice(h), 'la proposition en attente prend la carte')
    egal(nil, Conversation.exerciceEnCours(h))
    Conversation.decider(h, pendant.id, false)
    egal(exo, Conversation.dernierExercice(h), 'refusée : la carte revient à l\'exercice')
    egal(exo, Conversation.exerciceEnCours(h), "« J'ai fini » revient")
    -- Comparé, il est clos par une proposition décidée ensuite (la carte dit qu'il n'y a rien).
    appelComparaison(h, 'v1', { VUE })
    egal(exo, Conversation.dernierExercice(h))
    Conversation.decider(h, proposition(h, 'p2').id, true)
    egal(nil, Conversation.dernierExercice(h), 'comparé puis une proposition acceptée : clos')
    -- Seule la proposition juste avant la liste devient « à faire vous-même » : une plus ancienne
    -- restée en attente garde son état.
    local d = Conversation.nouvelle()
    local vieille = proposition(d, 'p0')
    local recente = proposition(d, 'p1')
    appelTour(d, 't1', { TOUR })
    egal('faite', recente.etat)
    egal('enAttente', vieille.etat, 'une proposition plus ancienne')
end)

essai("Conversation : une comparaison refusée qui peut se refaire laisse l'exercice où il en était (à faire, ou comparé avec son image) ; « Aucune version » le clôt", function()
    local c = Conversation.nouvelle()
    local i = appelTour(c, 't1', { TOUR })
    local e = c.elements[i]
    -- Un refus passager (liaison en pause) : l'exercice reste à faire, « J'ai fini » se refait, et
    -- la raison est dite (fil, état, carte).
    local outil = appelComparaison(c, 'v1', { "Liaison en pause dans Lightroom : reprendre la liaison." }, true)
    egal('erreur', c.elements[outil].etat, "l'appel, lui, en erreur")
    egal('aFaire', e.etat)
    egal(e, Conversation.exerciceEnCours(c), "toujours en cours : « J'ai fini » se refait")
    egal(e, Conversation.exercicePour(c, 53636309), 'la comparaison suivante se note sur lui')
    contient(e.comparaisonRefusee, 'Liaison en pause')
    contient(Fil.titreExercice(e), 'dans l\'ordre du panneau Développement · comparaison non aboutie : Liaison en pause')
    egal('Comparaison non aboutie : réessayez', Fenetre.etatExercice(e))
    contient(Fenetre.texteExercice(e), "La comparaison n'a pas abouti (Liaison en pause dans Lightroom : reprendre la liaison.) : "
        .. "cliquez de nouveau « J'ai fini ».")
    -- La comparaison suivante efface le refus dès son appel, puis aboutit.
    appelComparaison(c, 'v2')
    egal(nil, e.comparaisonRefusee)
    egal('Comparaison en cours…', Fenetre.etatExercice(e))
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'v2', textes = { VUE }, images = { { donnees = 'x' } }, erreur = false } } },
        nil, function() return 'premiere.jpg' end)
    egal('comparee', e.etat)
    egal('v2', e.appelCompare)
    egal('premiere.jpg', Conversation.imageComparaison(c, e))
    -- Une comparaison suivante refusée, ou restée sans réponse (attente) : la comparaison montrée
    -- reste, avec son image, sans nouvelle bascule.
    appelComparaison(c, 'v3', { "Lightroom ne répond pas." }, true)
    egal('comparee', e.etat)
    egal('premiere.jpg', Conversation.imageComparaison(c, e), "l'image de la comparaison aboutie")
    egal(e.id .. '/comparee/v2', Fenetre.cleExerciceVu(e), 'la même comparaison : pas de nouvelle bascule')
    contient(Fil.titreExercice(e), 'comparée : 7 écarts sur 9 · comparaison non aboutie : Lightroom ne répond pas.')
    contient(Fenetre.texteExercice(e), "La comparaison suivante n'a pas abouti (Lightroom ne répond pas.) : voici la précédente.")
    contient(Fenetre.texteExercice(e), 'Écart principal : Votre version est plus claire', 'les écarts gardés')
    egal('Comparée : 7 écarts sur 9', Fenetre.etatExercice(e))
    appelComparaison(c, 'v4')
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'v4', textes = { "« view_photo » n'est pas fini après 50 s." },
        images = {}, erreur = false } } })
    egal('comparee', e.etat)
    egal('premiere.jpg', Conversation.imageComparaison(c, e), 'une réponse d\'attente ne cache pas la comparaison')
    -- Relu sur le disque : le refus et l'appel de la comparaison aboutie restent.
    appelComparaison(c, 'v5', { "Lightroom ne répond pas." }, true)
    Stockage.enregistrer(c)
    local lue = Stockage.lire(c.id)
    egal('Lightroom ne répond pas.', lue.elements[i].comparaisonRefusee)
    egal('premiere.jpg', Conversation.imageComparaison(lue, lue.elements[i]))
    Stockage.supprimer(c.id)
    -- Le module n'a plus la version de Claude (revert_to_original) : l'exercice est clos. Le refus
    -- est celui du contrat (Tests/Contrats/je-le-fais.json, refus.sans_version), passé tel quel par
    -- le connecteur.
    local contrat = Json.decode(Fichiers.lire(dossierTests .. '/../../Contrats/je-le-fais.json'))
    local refus = contrat.refus.sans_version.apercu.erreur
    contient(refus, Conversation.SANS_VERSION, 'le refus du contrat')
    local d = Conversation.nouvelle()
    local j = appelTour(d, 't1', { TOUR })
    appelComparaison(d, 'v1', { refus }, true)
    egal('erreur', d.elements[j].etat)
    egal(nil, d.elements[j].comparaisonRefusee)
    egal(nil, Conversation.exerciceEnCours(d))
    contient(Fil.titreExercice(d.elements[j]), 'non abouti : comparaison impossible : Aucune version de Claude rangée')
end)

essai("Écart principal : « Écart principal : » seulement quand il se voit ; sinon le texte du connecteur tel quel (fil et carte)", function()
    local e = { genre = 'exercice', etat = 'comparee', ecarts = {}, commeClaude = {},
        principal = { visible = false, texte = "Écart principal non mesuré : une des deux images est illisible." } }
    egal("Écart principal non mesuré : une des deux images est illisible.", Fil.textePrincipal(e))
    local lignes = textes(Fil.lignesElement(e, 1, LARGEUR_LIGNE))
    contient(lignes, '|  Écart principal non mesuré')
    vrai(not lignes:find('Écart principal : Écart', 1, true), 'pas de préfixe redoublé dans le fil')
    vrai(not Fenetre.texteExercice(e):find('Écart principal : Écart', 1, true), 'ni dans la carte')
    e.principal = { visible = false, texte = "Aucun écart mesuré ne dépasse les seuils de visibilité du bilan." }
    contient(Fenetre.texteExercice(e), "\nAucun écart mesuré ne dépasse les seuils de visibilité du bilan.")
    e.principal = { visible = true, texte = "Votre version est plus claire de 1,04 IL." }
    egal("Écart principal : Votre version est plus claire de 1,04 IL.", Fil.textePrincipal(e))
    e.principal = nil
    egal('', Fil.textePrincipal(e))
end)

-- Fil ----------------------------------------------------------------------------------------------

essai("Fil : lignes d'un exercice (genres proposition et outil, ordre reçu, 12 au plus), comparé, refusé ; proposition « à faire vous-même » ; cache", function()
    local c = Conversation.nouvelle()
    local i = appelTour(c, 't1')
    egal("proposition|cours|Je le fais · liste en préparation…", textes(Fil.lignesElement(c.elements[i], i, LARGEUR_LIGNE)))
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 't1', textes = { TOUR }, images = {}, erreur = false } } })
    local lignes = Fil.lignesElement(c.elements[i], i, LARGEUR_LIGNE)
    egal("proposition|proposition|Je le fais · 5 réglages, dans l'ordre du panneau Développement", textes({ lignes[1] }))
    egal(6, #lignes)
    for n, l in ipairs(lignes) do
        vrai(l.genre == 'proposition' or l.genre == 'outil', 'genres existants : ' .. tostring(l.genre))
        vrai(Fil.occupe(l) <= LARGEUR_LIGNE, 'largeur de la ligne ' .. n)
        egal(i, l.element)
    end
    egal('  2. Réglages de base › Tonalité › Exposition : 0 → +0,35', lignes[3].texte)
    egal('  5. Courbe des tonalités › Courbe par points › RVB : linéaire → 3 points', lignes[6].texte)
    -- Plus de douze réglages : les douze premiers, puis « … et N autres ».
    local long = copie(c.elements[i])
    for n = 6, 20 do
        long.aFaire[n] = { n = n, cle = 'Reglage' .. n, texte = 'Réglages de base › Présence › Réglage ' .. n .. ' : 0 → +' .. n }
    end
    lignes = Fil.lignesElement(long, i, LARGEUR_LIGNE)
    egal(1 + Fil.REGLAGES_MONTRES + 1, #lignes)
    egal(12, Fil.REGLAGES_MONTRES)
    egal('  … et 8 autres', lignes[#lignes].texte)
    -- Comparé : l'écart principal (deux lignes au plus), puis chaque écart, ✓ comme Claude.
    appelComparaison(c, 'v1', { VUE })
    lignes = Fil.lignesElement(c.elements[i], i, LARGEUR_LIGNE)
    egal("proposition|proposition|Je le fais · comparée : 7 écarts sur 9", textes({ lignes[1] }))
    contient(lignes[2].texte, '  Écart principal : Votre version est plus claire de 1,04 IL')
    local principal, ecarts = 0, {}
    for n = 2, #lignes do
        vrai(lignes[n].genre == 'outil', 'lignes d\'outil')
        if lignes[n].texte:find('Écart principal', 1, true) or (#ecarts == 0 and not lignes[n].texte:find('^  [✓•]')) then
            principal = principal + 1
        else
            ecarts[#ecarts + 1] = lignes[n].texte
        end
    end
    vrai(principal >= 1 and principal <= Fil.LIGNES_PRINCIPAL, 'écart principal : ' .. principal .. ' lignes')
    egal(9, #ecarts)
    contient(ecarts[3], '  ✓ Réglages de base › Balance des blancs › Température')
    contient(ecarts[4], '  • Réglages de base › Tonalité › Exposition')
    for _, l in ipairs(lignes) do
        vrai(Fil.occupe(l) <= LARGEUR_LIGNE, 'largeur : ' .. l.texte)
    end
    -- Refusé : le titre dit pourquoi, icône erreur, trois lignes au plus.
    local d = Conversation.nouvelle()
    local j = appelTour(d, 't1', { string.rep('Refus très long du connecteur. ', 40) }, true)
    lignes = Fil.lignesElement(d.elements[j], j, LARGEUR_LIGNE)
    vrai(#lignes <= Fil.LIGNES_ERREUR_EXERCICE, 'refus borné')
    egal('erreur', lignes[1].icone)
    contient(lignes[1].texte, 'Je le fais · non abouti : Refus très long')
    j = appelTour(d, 't2')
    Conversation.appliquer(d, { genre = 'fin', reussie = false, interrompue = true, session = '' })
    egal("proposition|erreur|Je le fais · non abouti : l'appel n'a pas abouti.", textes(Fil.lignesElement(d.elements[j], j, LARGEUR_LIGNE)))
    -- Une proposition que Dany fait lui-même.
    local f = Conversation.nouvelle()
    local p = proposition(f, 'p1')
    Conversation.marquer(f, p.id, 'faite')
    local n
    for k, e in ipairs(f.elements) do
        if e == p then
            n = k
        end
    end
    contient(Fil.lignesElement(p, n, LARGEUR_LIGNE)[1].texte, 'Proposition à faire vous-même : Plus de lumière')
    -- Le cache suit l'exercice : liste, comparaison en cours, comparaison (le titre lu d'un trait,
    -- ses lignes recollées : une coupe peut tomber dans la phrase cherchée).
    local g = Conversation.nouvelle()
    local k = appelTour(g, 't1')
    local cache = {}
    local function suivi()
        local t = {}
        for _, l in ipairs(Fil.lignes(g, LARGEUR, cache)) do
            t[#t + 1] = l.texte
        end
        return table.concat(t, ' ')
    end
    contient(suivi(), 'liste en préparation')
    Conversation.appliquer(g, { genre = 'resultats', resultats = { { idOutil = 't1', textes = { TOUR }, images = {}, erreur = false } } })
    contient(suivi(), '5 réglages')
    appelComparaison(g, 'v1')
    contient(suivi(), 'comparaison en cours')
    Conversation.appliquer(g, { genre = 'resultats', resultats = { { idOutil = 'v1', textes = { VUE }, images = {}, erreur = false } } })
    contient(suivi(), 'comparée : 7 écarts sur 9')
    egal('comparee', g.elements[k].etat)
end)

-- Stockage -------------------------------------------------------------------------------------

essai('Stockage : liste, écarts et réglages comme Claude en tableaux, même vides ; un exercice en cours relu en erreur', function()
    local c = Conversation.nouvelle()
    local fait = appelTour(c, 't1', { TOUR })
    appelComparaison(c, 'v1', { VUE })
    local vide = appelTour(c, 't2', { 'Refus.' }, true)
    local enCours = appelTour(c, 't3')
    -- Une comparaison restée en cours sur un exercice à faire.
    local afaire = appelTour(c, 't4', { TOUR })
    appelComparaison(c, 'v2')
    -- Le cadre a ses clés en tableau.
    c.elements[afaire].aFaire[#c.elements[afaire].aFaire + 1] = { n = 6, cle = 'Crop', cles = { 'CropLeft', 'CropRight' }, texte = 'Outil Recadrage › Cadre',
        avant = { CropLeft = 0, CropRight = 1 }, apres = { CropLeft = 0.05, CropRight = 0.95 } }
    egal(true, c.elements[afaire].comparaisonEnCours)
    Stockage.enregistrer(c)
    local texte = Fichiers.lire(Stockage.fichier(c.id))
    contient(texte, '"aFaire":[]', 'liste vide en tableau')
    contient(texte, '"ecarts":[]', 'écarts vides en tableau')
    contient(texte, '"commeClaude":[]', 'réglages comme Claude vides en tableau')
    contient(texte, '"cles":["CropLeft","CropRight"]', 'clés du cadre en tableau')
    contient(texte, '"commeClaude":["Préréglage","Température"]')
    vrai(not texte:find('comparaisonEnCours', 1, true), 'une comparaison en cours ne s\'écrit pas')
    local lue = Stockage.lire(c.id)
    local e = lue.elements[fait]
    egal('exercice', e.genre)
    egal('comparee', e.etat)
    egal(5, #e.aFaire)
    egal(9, #e.ecarts)
    egal('Tonalité', e.aFaire[2].section)
    egal(0.35, e.aFaire[2].apres)
    contient(e.principal.texte, 'plus claire')
    egal('erreur', lue.elements[vide].etat)
    egal('erreur', lue.elements[enCours].etat, 'resté en cours : relu en erreur')
    egal('aFaire', lue.elements[afaire].etat)
    egal(nil, lue.elements[afaire].comparaisonEnCours)
    egal(0.95, lue.elements[afaire].aFaire[6].apres.CropRight)
    -- Le fil de la conversation relue est celui d'avant.
    egal(textes(Fil.lignesElement(c.elements[fait], fait, LARGEUR_LIGNE)), textes(Fil.lignesElement(e, fait, LARGEUR_LIGNE)))
    -- Un fichier abîmé (liste en texte, écarts qui ne sont pas des tables, principal en texte) :
    -- relu sans bloquer le fil ni l'enregistrement suivant.
    local brut = Json.decode(texte)
    brut.elements[fait].aFaire = 'abîmé'
    brut.elements[fait].ecarts = { 3, 'x', { cle = 'Vibrance', reglage = 'Vibrance', sorte = 'oublie', texte = 'Vibrance — pas fait' } }
    brut.elements[fait].principal = 'abîmé'
    brut.elements[fait].commeClaude = 'abîmé'
    Fichiers.ecrire(Stockage.fichier(c.id), Json.encode(brut))
    local abimee = Stockage.lire(c.id)
    egal(0, #abimee.elements[fait].aFaire)
    egal(1, #abimee.elements[fait].ecarts)
    egal(nil, abimee.elements[fait].principal)
    egal(0, #abimee.elements[fait].commeClaude)
    contient(textes(Fil.lignesElement(abimee.elements[fait], fait, LARGEUR_LIGNE)), 'comparée : 1 écart sur 1')
    Stockage.enregistrer(abimee)
    contient(Fichiers.lire(Stockage.fichier(c.id)), '"aFaire":[]', 'réenregistrée')
    -- Des tables à la place des textes (résumé, fichier, panneau d'un écart, texte de l'écart
    -- principal, d'un réglage à faire) : la carte et le fil se font quand même, sans eux.
    brut = Json.decode(texte)
    local x = brut.elements[fait]
    x.resume, x.fichier, x.aSavoir, x.instantane = { 'abîmé' }, { 1 }, { 2 }, { 3 }
    x.ecarts[1].panneau, x.ecarts[2].texte = { 'abîmé' }, { 'abîmé' }
    x.principal = { visible = true, texte = { 'abîmé' } }
    brut.elements[afaire].aFaire[1].texte, brut.elements[afaire].aFaire[2].panneau = { 'abîmé' }, { 'abîmé' }
    Fichiers.ecrire(Stockage.fichier(c.id), Json.encode(brut))
    abimee = Stockage.lire(c.id)
    for _, k in ipairs({ fait, afaire }) do
        local ok, erreur = pcall(Fenetre.texteExercice, abimee.elements[k], nil)
        vrai(ok, 'carte : ' .. tostring(erreur))
        ok, erreur = pcall(Fil.lignesElement, abimee.elements[k], k, LARGEUR_LIGNE)
        vrai(ok, 'fil : ' .. tostring(erreur))
    end
    egal(nil, abimee.elements[fait].resume)
    egal(nil, abimee.elements[fait].principal.texte)
    contient(Fenetre.texteExercice(abimee.elements[fait]), '• Tonalité › Exposition : départ 0', 'les autres écarts restent')
    Stockage.supprimer(c.id)
end)

-- Lightroom ---------------------------------------------------------------------------------------

essai("Lightroom.valeurs : la balance d'un JPEG en relatif, le profil par sa Look, une courbe par son résumé et sa signature ; rien des réglages non suivis", function()
    local raw = photoDev(7001, 'DSCF7001.RAF', reglagesDepart())
    local cles = { 'Temperature', 'Tint', 'Exposure2012', 'CameraProfile', 'ToneCurvePV2012', 'WhiteBalance', 'CropRight', 'PerspectiveScale',
        'ProcessVersion', 'Preset', 'LensProfileName' }
    local valeurs, signatures = Lightroom.valeurs(7001, cles)
    egal(5350, valeurs.Temperature)
    egal(19, valeurs.Tint)
    egal(0, valeurs.Exposure2012)
    egal('Adobe Color', valeurs.CameraProfile, 'le profil par sa Look, comme le module')
    egal('linéaire', valeurs.ToneCurvePV2012, 'une courbe absente : linéaire')
    egal(nil, signatures.ToneCurvePV2012, 'sans signature')
    egal('As Shot', valeurs.WhiteBalance)
    egal(1, valeurs.CropRight)
    egal(100, valeurs.PerspectiveScale, 'absent : sa valeur par défaut')
    -- Ce que la liste dit autrement que Lightroom ne le range (« version 5 » pour « 11.0 », un nom
    -- d'objectif ou de paramètre prédéfini) n'est pas lu : il serait toujours coché.
    raw.reglages.ProcessVersion, raw.reglages.LensProfileName, raw.reglages.Preset = '15.4', 'XF16-55mmF2.8 R LM WR', 'Mon réglage'
    valeurs = Lightroom.valeurs(7001, cles)
    for _, cle in ipairs({ 'ProcessVersion', 'Preset', 'LensProfileName' }) do
        egal(nil, valeurs[cle], cle .. ' : non suivi')
    end
    raw.reglages.ProcessVersion, raw.reglages.LensProfileName, raw.reglages.Preset = nil, nil, nil
    -- Dany change la courbe et le profil.
    raw.reglages.ToneCurvePV2012 = { 0, 0, 128, 150, 255, 255 }
    raw.reglages.Look = {}
    valeurs, signatures = Lightroom.valeurs(7001, cles)
    egal('3 points', valeurs.ToneCurvePV2012)
    egal('[0,0,128,150,255,255]', signatures.ToneCurvePV2012)
    egal('Adobe Standard', valeurs.CameraProfile)
    -- Un JPEG : la balance relative, rangée sous IncrementalTemperature et IncrementalTint.
    photoDev(7002, 'IMG_7002.JPG', { IncrementalTemperature = 12, IncrementalTint = -4, Exposure2012 = 0.2 }, 'JPG')
    valeurs = Lightroom.valeurs(7002, { 'Temperature', 'Tint', 'Exposure2012' })
    egal(12, valeurs.Temperature)
    egal(-4, valeurs.Tint)
    egal(0.2, valeurs.Exposure2012)
    sansMetatables(valeurs, 'valeurs')
    -- Un booléen de Lightroom (ConvertToGrayscale) en 0 ou 1, comme `avant` dans la liste (le module
    -- le décrit par Reglages.valeurActuelle) : le noir et blanc fait se coche.
    local nb = photoDev(7004, 'DSCF7004.RAF', { Temperature = 5000, ConvertToGrayscale = false })
    egal(0, Lightroom.valeurs(7004, { 'ConvertToGrayscale' }).ConvertToGrayscale)
    local exoNb = { aFaire = { { n = 1, cle = 'ConvertToGrayscale', avant = 0, apres = 1 } } }
    egal(0, Fenetre.reglagesFaits(exoNb, Lightroom.valeurs(7004, { 'ConvertToGrayscale' }), {}).nombre)
    nb.reglages.ConvertToGrayscale = true
    egal(1, Lightroom.valeurs(7004, { 'ConvertToGrayscale' }).ConvertToGrayscale)
    egal(1, Fenetre.reglagesFaits(exoNb, Lightroom.valeurs(7004, { 'ConvertToGrayscale' }), {}).nombre, 'le noir et blanc fait')
    -- Une photo introuvable, ou qui ne se lit pas : deux tables vides.
    local parId = S.catalogue.getPhotoByLocalId
    S.catalogue.getPhotoByLocalId = function() return nil end
    valeurs, signatures = Lightroom.valeurs(7003, cles)
    egal(nil, next(valeurs))
    egal(nil, next(signatures))
    S.catalogue.getPhotoByLocalId = function() error('catalogue fermé') end
    valeurs = Lightroom.valeurs(7001, cles)
    egal(nil, next(valeurs))
    S.catalogue.getPhotoByLocalId = parId
end)

-- Fenêtre, fonctions pures -------------------------------------------------------------------------

essai("Fenêtre : texte de l'exercice groupé par panneau, coché ✓ ; état ; réglages faits (cadre, signatures)", function()
    local c = Conversation.nouvelle()
    local i = appelTour(c, 't1', { TOUR })
    local e = c.elements[i]
    local texte = Fenetre.texteExercice(e, nil)
    contient(texte, "À vous : faites ces réglages dans le module Développement, dans cet ordre, puis cliquez « J'ai fini ».")
    contient(texte, "« Claude · ma version »")
    -- Groupés par panneau, dans l'ordre reçu, le panneau une fois (les kelvins du connecteur : espace
    -- fine des milliers, espace insécable avant l'unité).
    local _, debut = texte:find('\n\n', 1, true)
    local fine, insecable = '\226\128\175', '\194\160'
    egal("Réglages de base\n○ 1. Balance des blancs › Température : 5" .. fine .. "350" .. insecable .. "K → 5" .. fine .. "600" .. insecable
        .. "K\n○ 2. Tonalité › Exposition : 0 → +0,35\n"
        .. "○ 3. Tonalité › Contraste : 0 → +10\n○ 4. Présence › Vibrance : 0 → +10\nCourbe des tonalités\n"
        .. "○ 5. Courbe par points › RVB : linéaire → 3 points", texte:sub(debut + 1))
    egal("À vous · 5 réglages à faire", Fenetre.etatExercice(e, nil))
    -- Les réglages faits : ce qui a bougé depuis `avant`.
    local valeurs = { Temperature = 5350, Exposure2012 = 0.35, Contrast2012 = 0, Vibrance = 0, ToneCurvePV2012 = 'linéaire' }
    local faits = Fenetre.reglagesFaits(e, valeurs, {})
    egal(1, faits.nombre)
    egal(true, faits.reglages[2])
    texte = Fenetre.texteExercice(e, faits)
    contient(texte, '✓ 2. Tonalité › Exposition')
    contient(texte, '○ 1. Balance des blancs')
    egal("À vous · 1 réglage fait sur 5", Fenetre.etatExercice(e, faits))
    -- La courbe : son résumé change (3 points), ou sa signature change depuis le début du suivi.
    valeurs.ToneCurvePV2012 = '3 points'
    egal(2, Fenetre.reglagesFaits(e, valeurs, {}).nombre)
    valeurs.ToneCurvePV2012 = 'linéaire'
    e.signatures = { ToneCurvePV2012 = '[0,0,255,255]' }
    egal(1, Fenetre.reglagesFaits(e, valeurs, { ToneCurvePV2012 = '[0,0,255,255]' }).nombre, 'même signature')
    egal(2, Fenetre.reglagesFaits(e, valeurs, { ToneCurvePV2012 = '[0,0,64,60,255,255]' }).nombre, 'signature changée')
    e.signatures = nil
    egal(1, Fenetre.reglagesFaits(e, valeurs, { ToneCurvePV2012 = '[0,0,64,60,255,255]' }).nombre, 'sans départ : le résumé seul')
    -- Une valeur non lue, ou d'une autre nature : pas cochée.
    egal(0, Fenetre.reglagesFaits(e, { Exposure2012 = '0,35' }, {}).nombre)
    egal(0, Fenetre.reglagesFaits(e, {}, {}).nombre)
    egal("À vous · 3 réglages faits sur 5", Fenetre.etatExercice(e, { nombre = 3, reglages = {} }))
    -- Le cadre : une de ses clés a bougé.
    local cadre = { aFaire = { { n = 1, cle = 'Crop', cles = { 'CropLeft', 'CropRight' }, avant = { CropLeft = 0, CropRight = 1 },
        apres = { CropLeft = 0.05, CropRight = 0.95 } } } }
    egal(0, Fenetre.reglagesFaits(cadre, { CropLeft = 0, CropRight = 1 }, {}).nombre)
    egal(1, Fenetre.reglagesFaits(cadre, { CropLeft = 0, CropRight = 0.97 }, {}).nombre)
    egal('CropLeft CropRight', table.concat(Fenetre.clesExercice(cadre), ' '))
    egal('Temperature Exposure2012 Contrast2012 Vibrance ToneCurvePV2012', table.concat(Fenetre.clesExercice(e), ' '))
    -- Comparé : le résumé, l'écart principal, les écarts groupés (✓ comme Claude), ce qui reste
    -- dans les deux images, l'instantané.
    appelComparaison(c, 'v1', { VUE })
    texte = Fenetre.texteExercice(e, nil)
    contient(texte, 'Votre version comparée à celle de Claude (DSCF4961.RAF).\n9 réglages comparés : 2 comme Claude')
    contient(texte, '\n\nÉcart principal : Votre version est plus claire de 1,04 IL')
    contient(texte, '\nRéglages de base\n• Profil › Profil (Look) : départ Adobe Color')
    contient(texte, '\n✓ Balance des blancs › Température : départ')
    contient(texte, '\n• Tonalité › Exposition : départ 0, Claude +0,35, vous +0,8 — plus fort que Claude')
    contient(texte, '\nOutil Recadrage\n• Cadre : départ sans rognage')
    contient(texte, 'masques')
    contient(texte, "« Claude · ma version » : demandez-lui de la poser si vous la préférez.")
    egal('Comparée : 7 écarts sur 9', Fenetre.etatExercice(e))
    -- En préparation, refusé.
    local d = Conversation.nouvelle()
    local j = appelTour(d, 't1')
    contient(Fenetre.texteExercice(d.elements[j]), 'Claude prépare la liste')
    egal('Liste en préparation…', Fenetre.etatExercice(d.elements[j]))
    Conversation.appliquer(d, { genre = 'resultats', resultats = { { idOutil = 't1', textes = { 'Rien à faire.' }, images = {}, erreur = true } } })
    egal("« Je le fais » n'a pas abouti : Rien à faire.\n\nCliquez « Je le fais » pour recommencer, ou demandez à Claude.",
        Fenetre.texteExercice(d.elements[j]))
    egal("Je le fais n'a pas abouti", Fenetre.etatExercice(d.elements[j]))
    egal('', Fenetre.etatExercice(nil))
end)

-- Fenêtre, ouverte ---------------------------------------------------------------------------------

-- Moteur.envoyer remplacé : les demandes envoyées, sans Claude Code.
local envoyerVrai = Moteur.envoyer
local envoyes = {}
local function remplacerEnvoyer(reponse)
    envoyes = {}
    Moteur.envoyer = function(texte, options)
        envoyes[#envoyes + 1] = { texte = texte, options = options }
        if reponse == false then
            return false, 'Budget de la semaine atteint.'
        end
        return true
    end
end
local function remettreEnvoyer()
    Moteur.envoyer = envoyerVrai
end

essai("Fenêtre : Je le fais avec une proposition en attente (par Fenetre.bouton, Consignes.jeLeFais(true), proposition à faire vous-même, Accepter inactif)", function()
    photoActive(photoDev(53636309, 'DSCF4961.RAF', reglagesDepart()))
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    local p0 = proposition(c, 'p1')
    remplacerEnvoyer()
    local ok, erreur = pcall(ouvrirFenetre, function(p, args)
        Fenetre.rafraichir()
        egal('Je le fais', p.titreJeLeFais)
        egal(true, p.peutJeLeFais, 'actif avec une proposition en attente')
        egal(true, p.enAttente, 'Accepter actif')
        local b = bouton(args.contents, p, 'Je le fais', 'peutJeLeFais')
        vrai(Fenetre.parBouton(b.args.action), 'par Fenetre.bouton')
        -- Le texte du champ, validé par le clic (son envoi automatique attend dans une tâche).
        local avant = #S.taches
        p.saisie = 'Texte validé par le clic'
        vrai(Fenetre.envoiAuto, 'envoi prévu')
        b.args.action()
        egal(nil, Fenetre.envoiAuto, "le clic n'envoie pas la demande tapée")
        egal(0, #envoyes, 'rien dans le clic : une tâche')
        p.saisie = ''
        lancerTaches(avant)
        egal(1, #envoyes, 'une demande')
        egal(Consignes.jeLeFais(true), envoyes[1].texte)
        egal('faite', p0.etat, 'la proposition est à faire vous-même')
        Fenetre.rafraichir()
        egal(false, p.enAttente, 'Accepter inactif')
        egal(false, p.aProposition)
        vrai(Fenetre.cleVue and c.cle == Fenetre.cleVue, 'la conversation est celle de la sélection')
        local fil = {}
        for _, l in ipairs(Fenetre.lignes) do
            fil[#fil + 1] = l.texte
        end
        contient(table.concat(fil, '\n'), 'Proposition à faire vous-même : Plus de lumière')
    end)
    remettreEnvoyer()
    vrai(ok, erreur)
end)

-- Une liste d'exercice de `n` réglages, en JSON (pour les pages de la carte).
local function tourLong(n)
    local liste = Json.tableau()
    for k = 1, n do
        liste[k] = { n = k, panneau = k <= n / 2 and 'Réglages de base' or 'Détail', section = 'Présence', reglage = 'Réglage ' .. k,
            cle = k == 1 and 'Exposure2012' or ('Reglage' .. k), de = '0', a = '+' .. k, avant = 0, apres = k,
            texte = (k <= n / 2 and 'Réglages de base' or 'Détail') .. ' › Présence › Réglage ' .. k .. ' : 0 → +' .. k }
    end
    return Json.encode({ a_faire = liste, instantane = 'Claude · ma version', photo = { id = 53636309, fichier = 'DSCF4961.RAF' } })
end

essai("Fenêtre : la liste arrive (une bascule), page par page, « J'ai fini » ; suivie toutes les 2 s (✓, page gardée) ; une autre photo ne change pas de conversation", function()
    local photo = photoActive(photoDev(53636309, 'DSCF4961.RAF', reglagesDepart()))
    Moteur.nouvelle()
    local c = Moteur.courante
    remplacerEnvoyer()
    local ok, erreur = pcall(ouvrirFenetre, function(p)
        Fenetre.majPhoto()
        Conversation.ajouterDemande(c, 'Je le fais')
        c.cle = Fenetre.cleVue
        egal('notation', p.onglet)
        local i = appelTour(c, 't1')
        Fenetre.rafraichir()
        egal('notation', p.onglet, 'pas de bascule avant la liste')
        egal('Liste en préparation…', p.exerciceEtat)
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 't1', textes = { TOUR }, images = {}, erreur = false } } })
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'la liste se montre')
        egal("J'ai fini", p.titreJeLeFais)
        egal(true, p.peutJeLeFais)
        egal(false, p.enAttente, 'rien à accepter')
        egal("À vous · 5 réglages à faire", p.exerciceEtat)
        contient(p.propositionTexte, '○ 2. Tonalité › Exposition : 0 → +0,35')
        vrai(p.propositionTexte:find('○ 1.', 1, true) < p.propositionTexte:find('○ 2.', 1, true), "dans l'ordre reçu")
        -- Dany revient à la note : une seule bascule.
        p.onglet = 'notation'
        Fenetre.rafraichir()
        egal('notation', p.onglet)
        p.onglet = 'proposition'
        -- Le suivi toutes les 2 s (Fenetre.periodique) : l'exposition faite.
        local lectures = S.lecturesReglages or 0
        Fenetre.periodique()
        vrai((S.lecturesReglages or 0) > lectures, 'les réglages relus dans le catalogue')
        egal("À vous · 5 réglages à faire", p.exerciceEtat, 'rien fait encore')
        photo.reglages.Exposure2012 = 0.5
        Fenetre.periodique()
        egal("À vous · 1 réglage fait sur 5", p.exerciceEtat)
        contient(p.propositionTexte, '✓ 2. Tonalité › Exposition')
        contient(p.propositionTexte, '○ 1. Balance des blancs')
        -- La courbe : changée, puis remise.
        photo.reglages.ToneCurvePV2012 = { 0, 0, 128, 140, 255, 255 }
        Fenetre.suivreExercice()
        egal("À vous · 2 réglages faits sur 5", p.exerciceEtat)
        egal(nil, c.elements[i].signatures.ToneCurvePV2012, 'courbe absente au début du suivi')
        -- Une autre photo choisie pendant l'exercice : la conversation reste.
        prefs.nouvelleParPhoto = true
        photoActive(photoDev(53636310, 'DSCF4962.RAF', {}))
        Fenetre.majPhoto()
        egal(c, Moteur.courante, "même conversation pendant l'exercice")
        egal("J'ai fini", p.titreJeLeFais)
        -- Le suivi lit toujours la photo de l'exercice.
        photo.reglages.Vibrance = 10
        Fenetre.suivreExercice()
        egal("À vous · 3 réglages faits sur 5", p.exerciceEtat)
        photoActive(photo)
        Fenetre.majPhoto()
        egal(c, Moteur.courante)
        prefs.nouvelleParPhoto = false
        -- Une longue liste : page par page (T.propLignes lignes), et la page gardée quand un
        -- réglage se coche.
        -- Deux fois plus de réglages que la carte n'a de lignes (Dispositions.TAILLES.propLignes, sur
        -- carte-proposition : provisoire jusqu'au lot 18).
        local nombre = 2 * Fenetre.T.propLignes
        appelTour(c, 't2', { tourLong(nombre) })
        Fenetre.rafraichir()
        egal(Dispositions.TAILLES.propLignes, Fenetre.T.propLignes, 'fenêtre B, sur carte-proposition')
        local lignes = select(2, p.propositionTexte:gsub('\n', '\n')) + 1
        egal(Fenetre.T.propLignes, lignes, 'une page pleine')
        egal(false, p.propositionMonte)
        egal(true, p.propositionDescend)
        Fenetre.defilerTexte('proposition', 1)
        local page2 = p.propositionTexte
        egal(true, p.propositionMonte, 'deuxième page')
        vrai(not page2:find('○ 1. ', 1, true), 'plus la première ligne')
        photo.reglages.Exposure2012 = 1
        Fenetre.suivreExercice()
        egal("À vous · 1 réglage fait sur " .. nombre, p.exerciceEtat)
        egal(true, p.propositionMonte, 'la page est gardée')
        egal(page2, p.propositionTexte, 'la même page (le réglage coché est sur la première)')
        Fenetre.defilerTexte('proposition', -1)
        contient(p.propositionTexte, '✓ 1. Présence › Réglage 1')
        -- Claude travaille : le bouton est inactif.
        Moteur.travaille = true
        Fenetre.rafraichir()
        egal(false, p.peutJeLeFais)
        Moteur.travaille = false
        Fenetre.rafraichir()
        egal(true, p.peutJeLeFais)
    end)
    prefs.nouvelleParPhoto = false
    Moteur.travaille = false
    remettreEnvoyer()
    vrai(ok, erreur)
end)

essai("Fenêtre : « J'ai fini » envoie Consignes.jaiFini(photo) ; la comparaison montre les écarts, l'aperçu « Claude | vous », Agrandir ; le bouton revient à Je le fais", function()
    photoActive(photoDev(53636309, 'DSCF4961.RAF', reglagesDepart()))
    Moteur.nouvelle()
    local c = Moteur.courante
    remplacerEnvoyer()
    local ok, erreur = pcall(ouvrirFenetre, function(p, args)
        Fenetre.majPhoto()
        Conversation.ajouterDemande(c, 'Je le fais')
        local cleExercice = Fenetre.cleVue
        c.cle = cleExercice
        local i = appelTour(c, 't1', { TOUR })
        -- Une autre photo active quand Dany clique : la photo de l'exercice part quand même, et la
        -- conversation reste la sienne.
        photoActive(photoDev(53636310, 'DSCF4962.RAF', {}))
        Fenetre.majPhoto()
        Fenetre.rafraichir()
        local b = bouton(args.contents, p, "J'ai fini", 'peutJeLeFais')
        local avant = #S.taches
        b.args.action()
        lancerTaches(avant)
        egal(1, #envoyes)
        egal(Consignes.jaiFini(53636309), envoyes[1].texte)
        egal(cleExercice, c.cle, "la conversation reste celle de la photo de l'exercice")
        contient(envoyes[1].texte, 'view_photo avec photo_id = 53636309 et compare = claude_version')
        -- La comparaison arrive : écarts et écart principal dans la carte.
        p.onglet = 'notation'
        appelComparaison(c, 'v1', { VUE, REMARQUE_ECRAN })
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'la comparaison se montre')
        egal('comparee', c.elements[i].etat)
        egal('Je le fais', p.titreJeLeFais, 'le bouton revient à Je le fais')
        egal(true, p.peutJeLeFais)
        egal('Comparée : 7 écarts sur 9', p.exerciceEtat)
        local tout = Fenetre.pages.proposition.texte
        contient(tout, 'Écart principal : Votre version est plus claire de 1,04 IL')
        contient(tout, '✓ Balance des blancs › Température')
        contient(tout, '• Tonalité › Exposition : départ 0, Claude +0,35, vous +0,8 — plus fort que Claude')
        -- L'aperçu de l'onglet : la comparaison, légendée, sans ◀ ▶.
        egal('Claude | vous · DSCF4961.RAF', p.legendeApercu)
        egal(false, p.peutPrecedente)
        egal(false, p.peutSuivante)
        egal(true, p.aImage)
        local avantVignette = #S.taches
        Fenetre.rafraichirApercu()
        lancerTaches(avantVignette)
        vrai(p.imageApercu ~= Fenetre.imageVide() and Fichiers.existe(p.imageApercu), 'la comparaison réduite au cadre de l\'aperçu')
        -- Dans l'onglet Note, la même image se légende « Claude | vous ».
        Fenetre.voirActive = false
        p.onglet = 'notation'
        contient(p.legendeApercu, '· Claude | vous')
        -- Agrandir, dans l'onglet Proposition : la comparaison en grand, même quand une autre image
        -- est arrivée ensuite dans la conversation.
        Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'v3', nom = 'mcp__developpeur__view_photo',
            entree = { photo_id = 53636309 } } } })
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'v3', textes = { '{}' }, images = { { donnees = 'x' } }, erreur = false } } },
            nil, function()
                S.executer('cp ' .. S.q(imageJpeg) .. ' ' .. S.q(Stockage.image(c.id, 'autre.jpg')))
                return 'autre.jpg'
            end)
        p.onglet = 'proposition'
        Fenetre.rafraichir()
        egal('Claude | vous · DSCF4961.RAF', p.legendeApercu, "l'onglet Proposition montre toujours la comparaison")
        local dialogues = #S.dialogues
        avant = #S.taches
        Fenetre.agrandir()
        lancerTaches(avant)
        egal(dialogues + 1, #S.dialogues)
        egal('Claude · Claude | vous · DSCF4961.RAF', S.dialogues[#S.dialogues].title)
        egal('picture', S.dialogues[#S.dialogues].contents.genre)
        contient(S.dialogues[#S.dialogues].contents.args.value, '/comparaison-', 'la comparaison, pas la dernière image')
        -- Une image cliquée dans le fil reste prioritaire.
        Fenetre.imageCliquee = true
        egal(nil, Fenetre.comparaisonMontree())
        Fenetre.imageCliquee = nil
        -- Une nouvelle proposition prend la carte (et l'aperçu revient à celui d'avant).
        proposition(c, 'p9')
        Fenetre.rafraichir()
        contient(p.propositionTexte, 'Plus de lumière')
        egal(nil, Fenetre.comparaisonMontree())
        -- Après l'exercice, une autre photo commence une nouvelle conversation.
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, false)
        prefs.nouvelleParPhoto = true
        c.cle = Fenetre.cleVue
        photoActive(photoDev(53636311, 'DSCF4963.RAF', {}))
        Fenetre.majPhoto()
        vrai(Moteur.courante ~= c, 'exercice fini : nouvelle conversation')
        prefs.nouvelleParPhoto = false
    end)
    prefs.nouvelleParPhoto = false
    remettreEnvoyer()
    vrai(ok, erreur)
end)

essai("Fenêtre : à l'ouverture, un exercice en cours montre sa liste ; un exercice déjà comparé ne prend pas l'onglet", function()
    photoActive(photoDev(53636309, 'DSCF4961.RAF', reglagesDepart()))
    Moteur.nouvelle()
    local c = Moteur.courante
    Conversation.ajouterDemande(c, 'Je le fais')
    appelTour(c, 't1', { TOUR })
    ouvrirFenetre(function(p)
        egal('proposition', p.onglet, 'la liste en cours se montre')
        egal("J'ai fini", p.titreJeLeFais)
    end)
    appelComparaison(c, 'v1', { VUE })
    ouvrirFenetre(function(p)
        egal('notation', p.onglet, 'un exercice comparé reste dans son onglet')
        egal('Comparée : 7 écarts sur 9', p.exerciceEtat)
        Fenetre.rafraichir()
        egal('notation', p.onglet, 'toujours la même comparaison')
        -- Une nouvelle comparaison (Dany a encore changé quelque chose) : elle se montre, une fois.
        appelComparaison(c, 'v2', { VUE })
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'une nouvelle comparaison se montre')
        p.onglet = 'notation'
        Fenetre.rafraichir()
        egal('notation', p.onglet, 'une seule fois')
    end)
end)

essai("Fenêtre : sans proposition, Je le fais demande une version sur la photo active ; sans photo, rien d'envoyé et pourquoi ; un envoi refusé rend la proposition", function()
    photoActive(photoDev(53636309, 'DSCF4961.RAF', reglagesDepart()))
    Moteur.nouvelle()
    remplacerEnvoyer()
    local ok, erreur = pcall(ouvrirFenetre, function(p, args)
        -- La photo active suivie par Fenetre.majPhoto (toutes les 2 s, ou au changement de
        -- sélection) : le bouton suit, sans autre rafraîchissement.
        local active = S.photoActive
        S.photoActive, S.selection = nil, {}
        Fenetre.majPhoto()
        egal(false, p.peutJeLeFais, 'sans photo active')
        photoActive(active)
        Fenetre.majPhoto()
        egal(true, p.peutJeLeFais, 'une photo active suffit')
        local avant = #S.taches
        bouton(args.contents, p, 'Je le fais', 'peutJeLeFais').args.action()
        lancerTaches(avant)
        egal(1, #envoyes)
        egal(Consignes.jeLeFais(false), envoyes[1].texte)
        -- Sans photo active, ni proposition, ni exercice : inactif ; forcé, rien d'envoyé, la
        -- raison dans le bandeau.
        S.photoActive, S.selection = nil, {}
        Moteur.nouvelle()
        Fenetre.majPhoto()
        Fenetre.rafraichir()
        egal(false, p.peutJeLeFais)
        Fenetre.jeLeFais()
        egal(1, #envoyes, 'rien de plus')
        contient(p.message, 'Aucune photo active')
        -- Un envoi refusé (budget atteint) : la proposition reste à accepter.
        local c = Moteur.courante
        local prop = proposition(c, 'p1')
        remplacerEnvoyer(false)
        Fenetre.rafraichir()
        egal(true, p.peutJeLeFais, 'une proposition en attente suffit')
        Fenetre.jeLeFais()
        egal(1, #envoyes)
        egal('enAttente', prop.etat, 'la proposition reste en attente')
        egal('Budget de la semaine atteint.', p.message)
        -- Claude travaille : rien.
        remplacerEnvoyer()
        Moteur.travaille = true
        Fenetre.jeLeFais()
        egal(0, #envoyes)
        egal('enAttente', prop.etat)
        Moteur.travaille = false
        p.message = ''
        -- Un second clic pendant le premier (la photo active se lit) : rien de plus, le bouton
        -- inactif dès le clic, puis rendu. (Une photo active : sans le garde, le second clic
        -- poserait la proposition et le premier demanderait une version de la photo active.)
        photoActive(active)
        Fenetre.majPhoto()
        local lirePhotos = Lightroom.photos
        local second
        Lightroom.photos = function(...)
            if not second then
                second = true
                egal(false, p.peutJeLeFais, 'inactif dès le clic')
                Fenetre.rafraichir()
                egal(false, p.peutJeLeFais, 'toujours inactif pendant le premier clic')
                Fenetre.jeLeFais()
            end
            return lirePhotos(...)
        end
        local okClic, erreurClic = pcall(Fenetre.jeLeFais)
        Lightroom.photos = lirePhotos
        vrai(okClic, erreurClic)
        vrai(second, 'le second clic a eu lieu')
        egal(1, #envoyes, 'une seule demande')
        egal('faite', prop.etat)
        egal(false, Fenetre.jeLeFaisEnCours)
        -- Une erreur pendant l'action rend aussi le bouton.
        prop.etat = 'enAttente'
        Lightroom.photos = function() error('catalogue fermé') end
        okClic = pcall(Fenetre.jeLeFais)
        Lightroom.photos = lirePhotos
        egal(false, okClic, "l'erreur remonte (journalisée par Fenetre.enTache)")
        egal(false, Fenetre.jeLeFaisEnCours, 'le bouton est rendu')
        Fenetre.rafraichir()
        egal(true, p.peutJeLeFais)
        p.message = ''
    end)
    Moteur.travaille = false
    remettreEnvoyer()
    vrai(ok, erreur)
end)

-- Moteur ------------------------------------------------------------------------------------------

essai("Moteur : jeLeFais et jaiFini refusés pendant le travail, sans photo, sans exercice", function()
    remplacerEnvoyer()
    Moteur.nouvelle()
    local c = Moteur.courante
    S.photoActive, S.selection = nil, {}
    local ok, raison = Moteur.jeLeFais()
    egal(false, ok)
    contient(raison, 'Aucune photo active')
    ok, raison = Moteur.jaiFini()
    egal(false, ok)
    contient(raison, "Aucun exercice en cours")
    Moteur.travaille = true
    ok, raison = Moteur.jeLeFais()
    egal(false, ok)
    contient(raison, 'Claude travaille')
    ok, raison = Moteur.jaiFini()
    egal(false, ok)
    contient(raison, 'Claude travaille')
    Moteur.travaille = false
    egal(0, #envoyes)
    -- Un exercice sans photo connue : « J'ai fini » nomme la photo de l'exercice.
    appelTour(c, 't1', { '{"a_faire": [], "instantane": "Claude · ma version"}' }, false, 'x')
    egal(nil, Conversation.exerciceEnCours(c).photo)
    vrai(Moteur.jaiFini())
    egal(Consignes.jaiFini(nil), envoyes[1].texte)
    contient(envoyes[1].texte, 'sur la photo de l\'exercice')
    remettreEnvoyer()
end)

-- Consignes ---------------------------------------------------------------------------------------

essai("Consignes : section Je le fais (600 caractères au plus) entre Garde-fous et Titre ; Proposer d'abord cite Je le fais ; messages des boutons", function()
    local texte = Consignes.texte
    local debut = texte:find('\n## Je le fais\n', 1, true)
    vrai(debut, 'section Je le fais')
    local fin = texte:find('\n## ', debut + 1, true)
    local section = texte:sub(debut + 1, fin - 1):gsub('\n$', '')
    vrai(Texte.longueur(section) <= 600, string.format('section : %d caractères pour 600', Texte.longueur(section)))
    -- La section dit quand elle s'applique (seulement quand Dany retouche lui-même), pas « n'applique
    -- rien » tout court.
    contient(section, "## Je le fais\nQuand Dany retouche lui-même pour apprendre, n'applique rien :", 'section Je le fais')
    for _, morceau in ipairs({ 'my_turn', 'claude_version', "ordre du panneau Développement", 'ne retouche pas la photo et ne défais rien',
        'choose_variant « ma version »', 'Suggestion pour le guide', "n'applique rien", "« J'ai fini »", 'ecart_principal',
        "d'abord ce qu'il a bien fait", "Un écart de goût n'est pas une faute", "que s'il le demande" }) do
        contient(section, morceau, 'section Je le fais')
    end
    local gardeFous = texte:find('\n## Garde-fous\n', 1, true)
    local titre = texte:find('\n## Titre de la conversation\n', 1, true)
    vrai(gardeFous < debut and debut < titre, 'entre Garde-fous et Titre')
    egal(fin, titre, 'juste avant Titre')
    contient(texte:sub(gardeFous, debut), "La fenêtre affiche Accepter, Refuser, Ajuster et Je le fais", 'la puce Proposer d\'abord')
    vrai(Texte.longueur(texte) <= 7500, string.format('plafond des consignes : %d', Texte.longueur(texte)))
    vrai(not texte:find('\\\n', 1, true), 'lignes recollées')
    -- Les messages des boutons : 400 caractères au plus, en clair.
    for _, message in ipairs({ Consignes.jeLeFais(true), Consignes.jeLeFais(false), Consignes.jaiFini(53636309), Consignes.jaiFini(nil) }) do
        vrai(Texte.longueur(message) <= 400, string.format('message de %d caractères', Texte.longueur(message)))
    end
    contient(Consignes.jeLeFais(true), "n'applique rien")
    contient(Consignes.jeLeFais(true), 'exactement les réglages de ta proposition en attente et my_turn = true')
    contient(Consignes.jeLeFais(true), 'a_faire dans son ordre')
    contient(Consignes.jeLeFais(false), 'view_photo')
    contient(Consignes.jeLeFais(false), 'my_turn = true')
    contient(Consignes.jeLeFais(false), "n'applique rien")
    contient(Consignes.jaiFini(53636309), "J'ai fini mes réglages sur la photo 53636309.")
    contient(Consignes.jaiFini(53636309), 'compare = claude_version')
    contient(Consignes.jaiFini(53636309), 'exercice.ecart_principal')
    contient(Consignes.jaiFini(53636309), 'sans rien changer à la photo')
    vrai(not Consignes.jaiFini(nil):find('photo_id', 1, true), 'sans photo : pas de photo_id')
    -- Le faux Claude Code les reconnaît (cas « Je le fais » et « J'ai fini ») : l'un n'est pas l'autre.
    vrai(Consignes.jeLeFais(true):find('Je le fais', 1, true) and Consignes.jeLeFais(false):find('Je le fais', 1, true), 'Je le fais')
    vrai(not Consignes.jeLeFais(true):find("J'ai fini", 1, true) and not Consignes.jaiFini(1):find('Je le fais', 1, true), 'distincts')
end)

-- Moteur, avec le faux Claude Code ----------------------------------------------------------------

local function attendre(condition, secondes)
    for _ = 1, (secondes or 10) * 10 do
        Moteur.tic()
        if condition() then
            return true
        end
        S.executer('sleep 0.1')
    end
    return false
end

-- Le texte du dernier message écrit pour Claude Code (entree.jsonl de la session).
local function dernierMessage()
    local entree = Fichiers.lire(Moteur.session.dossier .. '/entree.jsonl') or ''
    local derniere
    for ligne in entree:gmatch('[^\n]+') do
        derniere = ligne
    end
    local json = Json.decode(derniere)
    local contenu = json.message.content
    return contenu[#contenu].text
end

essai("Moteur : Je le fais puis J'ai fini de bout en bout par relais.sh (faux Claude Code), relus sur le disque", function()
    remettreEnvoyer()
    photoActive(photoDev(53636309, 'DSCF4961.RAF', reglagesDepart()))
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    local prop = proposition(c, 'p1')
    vrai(Moteur.jeLeFais(), 'Je le fais envoyé')
    egal('faite', prop.etat)
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    egal(c, Moteur.courante)
    contient(dernierMessage(), Consignes.jeLeFais(true))
    local consignes = Fichiers.lire(Moteur.session.dossier .. '/consignes.md')
    contient(consignes, '## Je le fais')
    contient(consignes, 'Accepter, Refuser, Ajuster et Je le fais')
    local exo = Conversation.exerciceEnCours(c)
    vrai(exo, "l'exercice est en cours")
    egal(5, #exo.aFaire)
    egal(53636309, exo.photo)
    egal('DSCF4961.RAF', exo.fichier)
    egal(nil, Conversation.propositionEnAttente(c))
    -- J'ai fini : la comparaison, son image rangée, la remarque de l'écran passée.
    vrai(Moteur.jaiFini(), "J'ai fini envoyé")
    vrai(attendre(function() return not Moteur.travaille end), 'la comparaison se termine')
    contient(dernierMessage(), 'view_photo avec photo_id = 53636309 et compare = claude_version')
    egal('comparee', exo.etat)
    egal(9, #exo.ecarts)
    contient(exo.principal.texte, 'plus claire')
    local chemin = Conversation.imageComparaison(c, exo)
    vrai(chemin and Fichiers.existe(Stockage.image(c.id, chemin)), 'image de la comparaison rangée')
    local images = Conversation.images(c)
    egal(true, images[#images].comparaison)
    egal(nil, Conversation.exerciceEnCours(c))
    -- Relu sur le disque.
    local lue = Stockage.lire(c.id)
    local relu = Conversation.dernierExercice(lue)
    vrai(relu, 'exercice relu')
    egal('comparee', relu.etat)
    egal(5, #relu.aFaire)
    egal(9, #relu.ecarts)
    egal(chemin, Conversation.imageComparaison(lue, relu))
end)

-- Fin ------------------------------------------------------------------------------------------

remettreEnvoyer()
if Moteur.session then
    Moteur.session:arreter()
end
S.executer('sleep 1.5')
S.catalogue.getPhotoByLocalId = parIdOriginal
Notation.proposition = propositionVraie
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
