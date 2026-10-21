-- essais-composition.lua : la composition lue dans la fenêtre Claude (1.3, lot 15), hors de
-- Lightroom (LuaJIT, Lightroom simulé par Simulation.lua, complété ici sans la toucher) : la
-- proposition de recadrage dans la conversation (drapeau recadrage, ligne « Recadrage » demandée,
-- cadre gardé lu dans la réponse : Conversation.cadreLu), son stockage, la carte Proposition (la
-- ligne « Cadre : … » et ce que montre son aperçu, à la place des bords Crop…), l'image de la
-- proposition remontrée par un vrai clic sur l'onglet Proposition et gardée par son crochet
-- (Fenetre.montrerImageProposition, Fenetre.apercuProposition, composé après la comparaison de
-- « Je le fais »), ◀ ▶ et Agrandir depuis elle, les ajustements du cadre dans Ajuster…, et la
-- section « Composition » des consignes. Les réponses du connecteur sont les vraies, produites par
-- le serveur sur l'exemple « proposer » de Tests/Contrats/composition.json (preview_settings avec
-- crop : un 3:2 redressé de 1,4°). Ni Claude, ni quota, ni photo : les fichiers vont dans un
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
        error(string.format('%s : %q ne devrait pas être dans %q', quoi or 'texte', morceau, texte), 2)
    end
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

-- Le calque d'Accepter de la carte Proposition (un bouton bleu en image, fenêtre B, lot B5).
local function calqueAccepter(contenu)
    for _, v in ipairs(vues(contenu)) do
        if v.genre == 'static_text' and v.args.tooltip == "Appliquer la proposition : la photo ne change qu'à ce clic" then
            return v
        end
    end
    error("calque d'Accepter introuvable", 2)
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
local Notation = require 'Notation'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition de note.
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'
local prefs = Chemins.prefs()
prefs.propositionAOuverture = false
prefs.nouvelleParPhoto = false

-- Le faux Claude Code dès le départ (une demande partie par erreur ne lance jamais le vrai), aucun
-- connecteur, et une petite image JPEG, copiée à la place de chaque image de la conversation.
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'
prefs.cheminConnecteur = '/bin/echo'
local imageJpeg = S.home .. '/image.jpg'
S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out ' .. S.q(imageJpeg) .. ' >/dev/null 2>&1')

-- Les demandes envoyées à Claude, gardées ici (Moteur.envoyer remplacé le temps d'un essai).
local envoyerVrai = Moteur.envoyer
local envoyes = {}
local function remplacerEnvoyer()
    envoyes = {}
    Moteur.envoyer = function(texte, options)
        envoyes[#envoyes + 1] = { texte = texte, options = options }
        return true
    end
end
local function remettreEnvoyer()
    Moteur.envoyer = envoyerVrai
end

local function photoActive(id, nom)
    local photo = S.photo(id, nom)
    S.photoActive, S.selection = photo, { photo }
    return photo
end

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

-- La réponse du connecteur à preview_settings avec crop (Tools+Retouche.preview), telle que le
-- serveur la rend sur l'exemple « proposer » de Tests/Contrats/composition.json : l'image (l'image
-- entière, le cadre gardé en pointillés) vient avant ce texte.
local REPONSE_CADRE = [=[{
  "cadre_propose" : {
    "angle" : -1.4,
    "center_x" : 0.48,
    "center_y" : 0.52,
    "largeur" : 0.791,
    "ratio" : 1.5
  },
  "changements" : [
    {
      "apres" : -1.4,
      "avant" : 0,
      "cle" : "CropAngle",
      "libelle" : "Recadrage : angle"
    },
    {
      "apres" : 0.078055,
      "avant" : 0,
      "cle" : "CropLeft",
      "libelle" : "Recadrage : bord gauche"
    },
    {
      "apres" : 0.138998,
      "avant" : 0,
      "cle" : "CropTop",
      "libelle" : "Recadrage : bord haut"
    },
    {
      "apres" : 0.881945,
      "avant" : 1,
      "cle" : "CropRight",
      "libelle" : "Recadrage : bord droit"
    },
    {
      "apres" : 0.901002,
      "avant" : 1,
      "cle" : "CropBottom",
      "libelle" : "Recadrage : bord bas"
    }
  ],
  "etape" : "Claude · essai : cadre",
  "image" : "L'image entière : le cadre proposé en pointillés (celui que Lightroom a gardé), les tiers et le hors-cadre assombri. Rien n'est appliqué.",
  "mesures_proposition" : {
    "base" : "Aperçu sRGB rendu par Lightroom, réduit à 512 px. L* : 0 noir, 100 blanc ; histogramme par tranches de 10. a* : vert (−) à magenta (+) ; b* : bleu (−) à jaune (+).",
    "contraste_p95_moins_p5" : 0,
    "couleur" : {
      "chroma_moyenne" : 0,
      "tons_neutres" : {
        "a" : 0,
        "b" : 0,
        "lecture" : "neutre",
        "part_pct" : 100
      },
      "tres_saturee_pct" : 0
    },
    "eclairage" : {
      "ecart_regions" : 0,
      "lecture" : "une seule lumière (écart entre zones 0,0, sous 8)",
      "mixte" : false,
      "zones_tonales" : {
        "hautes_lumieres" : {
          "a" : 0,
          "b" : 0,
          "part_pct" : 100
        },
        "ombres" : "trop peu de tons neutres",
        "tons_moyens" : "trop peu de tons neutres"
      }
    },
    "ecretage_pct" : {
      "blanc_pur" : 0,
      "hautes_lumieres" : 0,
      "ombres_bouchees" : 0,
      "par_canal" : {
        "bleu" : 0,
        "rouge" : 0,
        "vert" : 0
      }
    },
    "histogramme_L_pct" : [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      100,
      0
    ],
    "luminosite_L" : {
      "mediane" : 80.6,
      "moyenne" : 80.6,
      "p1" : 80.6,
      "p25" : 80.6,
      "p5" : 80.6,
      "p75" : 80.6,
      "p95" : 80.6,
      "p99" : 80.6
    }
  },
  "mode" : "appliquer directement",
  "photo" : {
    "copie_virtuelle" : false,
    "fichier" : "XH2S0320.RAF (Copie 1)",
    "id" : 4
  },
  "remarques" : [

  ],
  "resume_cadre" : "3:2 (format d'origine), redressé de 1,4°, 79 % de la largeur gardée",
  "rien_n_est_applique" : "La photo a été remise comme avant ; apply_settings applique la proposition."
}]=]

-- La même proposition quand l'image entière ne se rend pas (exemple « proposer_sans_image_entiere »
-- du contrat) : le serveur rend alors exactement ce texte sans « image », avec la remarque du
-- module ; l'image est la proposition recadrée.
local function remplacerUneFois(texte, avant, apres)
    local debut, fin = texte:find(avant, 1, true)
    vrai(debut and not texte:find(avant, fin + 1, true), 'un seul ' .. avant)
    return texte:sub(1, debut - 1) .. apres .. texte:sub(fin + 1)
end
local REPONSE_SANS_IMAGE = remplacerUneFois(remplacerUneFois(REPONSE_CADRE,
    '  "image" : "L\'image entière : le cadre proposé en pointillés (celui que Lightroom a gardé), les tiers et le hors-cadre assombri. Rien n\'est appliqué.",\n', ''),
    '"remarques" : [\n\n  ]',
    '"remarques" : [\n    "Image entière non rendue : Lightroom n\'a pas pu rendre l\'aperçu : disque plein ; le cadre n\'est pas dessiné."\n  ]')

local RESUME = "3:2 (format d'origine), redressé de 1,4°, 79 % de la largeur gardée"
local RAISON = "L'horizon penche de 1,4° et coupe la photo en deux : redressé et posé sur le tiers bas."

-- L'entrée de preview_settings de l'exemple, avec sa raison.
local function entreeCadre(autres)
    local entree = { photo_id = 4, crop = { aspect = '3:2', angle = -1.4, size = 0.82, center_x = 0.48, center_y = 0.52 },
        step_name = 'cadre', reason = RAISON }
    for cle, valeur in pairs(autres or {}) do
        entree[cle] = valeur
    end
    return entree
end

-- Une image de la conversation `c`, rangée sous `nom` (une vraie petite image JPEG).
local function ranger(c, nom)
    return function()
        Fichiers.creerDossier(Stockage.dossier(c.id))
        S.executer('cp ' .. S.q(imageJpeg) .. ' ' .. S.q(Stockage.image(c.id, nom)))
        return nom
    end
end

-- Un appel de preview_settings, et sa réponse (textes, une image rangée sous `image`) s'il y en a
-- une. Rend l'élément proposition.
local function appelPropose(c, appel, entree, textes, image, erreur)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = appel, nom = 'mcp__developpeur__preview_settings',
        entree = entree } } })
    local e = c.elements[#c.elements]
    if textes then
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = appel, textes = textes,
            images = image and { { donnees = 'x', type = 'image/jpeg' } } or {}, erreur = erreur == true } } }, nil, image and ranger(c, image) or nil)
    end
    return e
end

-- Un appel de view_photo et son image, rangée sous `<appel>.jpg`.
local function vue(c, appel)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = appel, nom = 'mcp__developpeur__view_photo',
        entree = { photo_id = 4 } } } })
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = appel, textes = { '{}' },
        images = { { donnees = 'x', type = 'image/jpeg' } }, erreur = false } } }, nil, ranger(c, appel .. '.jpg'))
end

-- Le changement de ce libellé, nil sans.
local function changement(e, libelle)
    for _, ch in ipairs(e.changements or {}) do
        if ch.libelle == libelle then
            return ch
        end
    end
    return nil
end

-- Conversation ------------------------------------------------------------------------------------

essai("Conversation : preview_settings avec un crop fait une proposition de recadrage ; « Recadrage » demandé, puis le cadre gardé lu dans la réponse", function()
    local c = Conversation.nouvelle(1000)
    local e = appelPropose(c, 'p1', entreeCadre())
    egal('proposition', e.genre)
    egal(e, Conversation.propositionEnAttente(c))
    egal(true, e.recadrage, 'une proposition de recadrage')
    egal(RAISON, e.texte)
    -- Avant la réponse : le recadrage demandé, en mots (format, angle, taille).
    local demande = changement(e, 'Recadrage')
    vrai(demande, 'ligne Recadrage')
    egal('—', demande.avant)
    egal("format 3:2, redressé de 1,4°, 82 % du plus grand cadre", demande.apres)
    egal(nil, e.cadre, 'le cadre gardé arrive avec la réponse')
    -- La réponse : le cadre que Lightroom a gardé, dessiné sur l'image entière ; les changements
    -- du module, clés comprises.
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'p1', textes = { REPONSE_CADRE },
        images = { { donnees = 'x' } }, erreur = false } } }, nil, function() return 'p1.jpg' end)
    egal(RESUME, e.cadre)
    egal(true, e.cadreDessine, "l'image entière, le cadre en pointillés")
    egal('p1.jpg', e.images[1])
    egal('enAttente', e.etat)
    local cles = {}
    for _, ch in ipairs(e.changements) do
        cles[#cles + 1] = ch.cle
    end
    egal('CropAngle CropLeft CropTop CropRight CropBottom', table.concat(cles, ' '), 'les clés gardées')
    egal(nil, changement(e, 'Recadrage'), 'la demande remplacée par ce que Lightroom a gardé')
    egal('Recadrage : bord gauche', e.changements[2].libelle)
    -- Tout en textes et booléens : rien d'une table relue n'est gardé.
    vrai(type(e.cadre) == 'string' and type(e.cadreDessine) == 'boolean', 'textes et booléens')
end)

essai("Conversation : image entière non rendue, remarque d'écran à part, refus, réponse sans résumé du cadre", function()
    local c = Conversation.nouvelle(1000)
    -- L'image entière n'a pas pu se rendre : le cadre se dit quand même, sans dessin.
    local e = appelPropose(c, 'p1', entreeCadre(), { REPONSE_SANS_IMAGE }, 'p1.jpg')
    egal(RESUME, e.cadre)
    egal(nil, e.cadreDessine, "pas d'image entière : pas de dessin")
    -- Une remarque d'écran (bloc de texte à part) ne gêne pas.
    e = appelPropose(c, 'p2', entreeCadre(), { REPONSE_CADRE, "Remarque : l'écran principal n'est pas étalonné." }, 'p2.jpg')
    egal(RESUME, e.cadre)
    egal(true, e.cadreDessine)
    -- Ni l'une recollée après le JSON (Conversation.teteJson).
    e = appelPropose(c, 'p3', entreeCadre(), { REPONSE_CADRE .. "\nRemarque : l'écran principal n'est pas étalonné." }, 'p3.jpg')
    egal(RESUME, e.cadre)
    -- Un refus : la proposition est refusée, sans cadre.
    e = appelPropose(c, 'p4', entreeCadre(), { 'Photo agrandie : Claude ne la recadre pas.' }, nil, true)
    egal('refusee', e.etat)
    egal(nil, e.cadre)
    -- overlay = false (ou un cadre que Lightroom n'a pas gardé) : pas de résumé, les bords restent.
    e = appelPropose(c, 'p5', entreeCadre({ overlay = false }),
        { '{"changements": [{"cle": "CropLeft", "avant": 0, "apres": 0.078055, "libelle": "Recadrage : bord gauche"}]}' }, 'p5.jpg')
    egal(true, e.recadrage)
    egal(nil, e.cadre)
    egal(nil, e.cadreDessine)
    egal('CropLeft', e.changements[1].cle)
end)

essai("Conversation : un recadrage retiré n'est pas une proposition de cadre ; sans crop, rien ; le recadrage demandé en mots", function()
    local c = Conversation.nouvelle(1000)
    local e = appelPropose(c, 'r1', { photo_id = 4, crop = { reset = true }, reason = 'Recadrage retiré.' })
    egal(nil, e.recadrage, 'un recadrage retiré')
    egal('retiré', changement(e, 'Recadrage').apres)
    e = appelPropose(c, 'r2', { photo_id = 4, settings = { Exposure2012 = 0.35 }, reason = 'Plus de lumière.' })
    egal(nil, e.recadrage, 'sans crop')
    egal(nil, changement(e, 'Recadrage'))
    egal('Exposition', e.changements[1].libelle)
    -- « Je le fais » (my_turn) : un exercice, pas une proposition, même avec un crop.
    local avant = #c.elements
    appelPropose(c, 'r3', entreeCadre({ my_turn = true }))
    egal('exercice', c.elements[#c.elements].genre)
    egal(avant + 2, #c.elements)
    -- Le recadrage demandé, en mots.
    egal("format d'origine, redressé de 2°", Conversation.cadreDemande({ aspect = 'original', angle = 2 }))
    egal("format d'origine", Conversation.cadreDemande({ aspect = "D'origine" }))
    egal("format 4:5, 76 % du plus grand cadre", Conversation.cadreDemande({ aspect = ' 4:5 ', size = 0.755 }))
    egal("redressé de 0,75°", Conversation.cadreDemande({ angle = -0.75, aspect = Json.null }))
    egal("cadre demandé", Conversation.cadreDemande({ center_x = 0.4 }))
    egal("cadre demandé", Conversation.cadreDemande({ angle = 0 }))
    egal("cadre demandé", Conversation.cadreDemande('pas une table'))
    -- Le cadre lu : nil sans résumé, texte nettoyé, dessin d'après la réponse.
    egal(nil, Conversation.cadreLu({}))
    egal(nil, Conversation.cadreLu({ 'pas du JSON' }))
    egal(nil, Conversation.cadreLu({ '{"resume_cadre": "   "}' }))
    egal(nil, Conversation.cadreLu({ '{"resume_cadre": 3}' }))
    local resume, dessine = Conversation.cadreLu({ '{"resume_cadre": "  4:5, 70 % de la largeur gardée \n"}' })
    egal('4:5, 70 % de la largeur gardée', resume)
    egal(false, dessine)
    -- Avec compare : l'image entière à droite, le cadre en pointillés.
    resume, dessine = Conversation.cadreLu({ Json.encode({ resume_cadre = RESUME,
        image = "À gauche l'état actuel, à droite l'image entière avec le cadre proposé en pointillés (tiers, hors-cadre assombri)." }) })
    egal(RESUME, resume)
    egal(true, dessine)
    resume, dessine = Conversation.cadreLu({ Json.encode({ resume_cadre = RESUME, image = "À gauche l'état actuel, à droite la proposition." }) })
    egal(false, dessine)
end)

essai("Stockage : recadrage, cadre et cadreDessine relus tels quels", function()
    Moteur.charger()
    local c = Conversation.nouvelle(2000)
    appelPropose(c, 's1', entreeCadre(), { REPONSE_CADRE }, 's1.jpg')
    appelPropose(c, 's2', entreeCadre(), { REPONSE_SANS_IMAGE }, 's2.jpg')
    Stockage.enregistrer(c)
    local relue = Stockage.lire(c.id)
    vrai(relue, 'conversation relue')
    local premiere, seconde
    for _, e in ipairs(relue.elements) do
        if e.genre == 'proposition' then
            if not premiere then premiere = e else seconde = e end
        end
    end
    egal(true, premiere.recadrage)
    egal(RESUME, premiere.cadre)
    egal(true, premiere.cadreDessine)
    egal(RESUME, seconde.cadre)
    egal(nil, seconde.cadreDessine)
    egal('CropAngle', premiere.changements[1].cle)
    egal('s1.jpg', premiere.images[1])
end)

-- Carte Proposition --------------------------------------------------------------------------------

essai("Carte : la raison, « Cadre : … » et ce que montre son aperçu, sans les bords Crop… ; les autres changements dessous", function()
    local c = Conversation.nouvelle(1000)
    local e = appelPropose(c, 'p1', entreeCadre(), { REPONSE_CADRE }, 'p1.jpg')
    local texte = Fenetre.texteProposition(e)
    egal(RAISON .. "\n\nCadre : " .. RESUME .. "\n" .. Fenetre.CADRE_DESSINE, texte)
    contient(Fenetre.CADRE_DESSINE, "l'image entière, le cadre proposé en pointillés, les tiers et le hors-cadre assombri")
    contient(Fenetre.CADRE_DESSINE, 'Rien ne change avant Accepter.')
    absent(texte, 'Recadrage : bord')
    absent(texte, 'Recadrage : angle')
    -- Un recadrage avec d'autres réglages : ceux-là restent, dessous.
    table.insert(e.changements, 3, { cle = 'Exposure2012', libelle = 'Exposition', avant = '0', apres = '0,35' })
    e.changements[#e.changements + 1] = { cle = 'CropConstrainToWarp', libelle = "Recadrage : contraindre à l'image (sans coins vides)", avant = '0', apres = '1' }
    texte = Fenetre.texteProposition(e)
    egal(RAISON .. "\n\nCadre : " .. RESUME .. "\n" .. Fenetre.CADRE_DESSINE .. "\n\nExposition : 0 → 0,35", texte)
    -- Sans l'image entière : pas de pointillés promis.
    e = appelPropose(c, 'p2', entreeCadre(), { REPONSE_SANS_IMAGE }, 'p2.jpg')
    texte = Fenetre.texteProposition(e)
    egal(RAISON .. "\n\nCadre : " .. RESUME .. "\n" .. Fenetre.CADRE_SANS_DESSIN, texte)
    absent(texte, 'pointillés')
    -- Sans résumé du cadre (overlay = false) : les bords sont seuls à dire le cadre, ils restent.
    e = appelPropose(c, 'p3', entreeCadre({ overlay = false }),
        { '{"changements": [{"cle": "CropLeft", "avant": 0, "apres": 0.078055, "libelle": "Recadrage : bord gauche"}]}' }, 'p3.jpg')
    texte = Fenetre.texteProposition(e)
    egal(RAISON .. "\n\nRecadrage : bord gauche : 0 → 0,08", texte)
    -- Avant la réponse : le recadrage demandé.
    e = appelPropose(c, 'p4', entreeCadre())
    contient(Fenetre.texteProposition(e), "Recadrage : — → format 3:2, redressé de 1,4°, 82 % du plus grand cadre")
    -- Une remarque recollée après le JSON : le cadre se lit (Conversation.teteJson), pas les
    -- changements ; la ligne « Recadrage » demandée, restée, ne double pas « Cadre : … ».
    e = appelPropose(c, 'p6', entreeCadre(), { REPONSE_CADRE .. "\nRemarque : l'écran principal n'est pas étalonné." }, 'p6.jpg')
    egal(RESUME, e.cadre)
    vrai(changement(e, 'Recadrage'), 'la demande reste dans les changements')
    egal(RAISON .. "\n\nCadre : " .. RESUME .. "\n" .. Fenetre.CADRE_DESSINE, Fenetre.texteProposition(e))
    -- Avec un autre réglage demandé : lui seul reste dessous.
    table.insert(e.changements, 1, { libelle = 'Exposition', avant = '—', apres = '0,35' })
    egal(RAISON .. "\n\nCadre : " .. RESUME .. "\n" .. Fenetre.CADRE_DESSINE .. "\n\nExposition : — → 0,35", Fenetre.texteProposition(e))
    -- Une proposition de tons : comme avant.
    e = appelPropose(c, 'p5', { photo_id = 4, settings = { Exposure2012 = 0.35 } },
        { '{"changements": [{"cle": "Exposure2012", "avant": 0, "apres": 0.35}]}' })
    egal("Claude propose :\n\nExposition : 0 → 0,35", Fenetre.texteProposition(e))
end)

essai("Fenêtre : la proposition de cadre arrive dans la carte (une bascule), coupée à sa largeur, page par page", function()
    photoActive(4, 'XH2S0320.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    ouvrirFenetre(function(p)
        local T = Fenetre.T
        Fenetre.majPhoto()
        egal('notation', p.onglet)
        appelPropose(c, 'p1', entreeCadre(), { REPONSE_CADRE }, 'p1.jpg')
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'la proposition se montre')
        egal(true, p.enAttente, 'Accepter actif')
        local tout = Fenetre.pages.proposition.texte
        egal(Fenetre.texteProposition(Conversation.propositionEnAttente(c)), tout)
        vrai(p.propositionTexte:sub(1, #"L'horizon penche") == "L'horizon penche", 'la carte commence par la raison')
        contient(tout, 'Cadre : ' .. RESUME)
        absent(p.propositionTexte, 'Recadrage : bord')
        local lignes = 0
        for l in (p.propositionTexte .. '\n'):gmatch('([^\n]*)\n') do
            lignes = lignes + 1
            vrai(Fil.largeur(l, 'texte12') <= T.largeurProposition - Fil.MARGE, 'ligne trop large : ' .. l)
        end
        vrai(lignes <= T.propLignes, 'une page au plus')
        egal(false, p.propositionMonte)
        egal(false, p.propositionDescend, 'le cadre tient dans la carte')
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, false)
    end)
end)

-- Aperçu de l'onglet Proposition ------------------------------------------------------------------

essai("Aperçu : l'image de la proposition arrive ; un vrai clic sur Proposition la remontre et la garde ; ◀ ▶, image nouvelle, proposition décidée", function()
    photoActive(4, 'XH2S0320.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    ouvrirFenetre(function(p)
        Fenetre.majPhoto()
        egal('notation', p.onglet)
        vue(c, 'v1')
        Fenetre.rafraichir()
        egal('1 sur 1 · view_photo', p.legendeApercu)
        local prop = appelPropose(c, 'p1', entreeCadre(), { REPONSE_CADRE }, 'p1.jpg')
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'la proposition se montre (bascule de la fenêtre)')
        egal('2 sur 2 · preview_settings', p.legendeApercu, 'son image, la dernière arrivée')
        egal(nil, Fenetre.imageProposition, 'une bascule ne la demande pas')
        -- Une image arrivée ensuite se montre, même dans l'onglet Proposition.
        vue(c, 'v2')
        Fenetre.rafraichir()
        egal('3 sur 3 · view_photo', p.legendeApercu)
        -- Dany va sur Note, puis clique Proposition : l'image de la proposition revient.
        p.onglet = 'notation'
        egal('3 sur 3 · view_photo', p.legendeApercu)
        p.onglet = 'proposition'
        egal('2 sur 3 · preview_settings', p.legendeApercu, "le clic remontre l'image de la proposition")
        -- Ce que montre Note ne change pas : l'aperçu appartient à l'onglet.
        egal(nil, Fenetre.indiceImage, "l'image choisie de Note ne change pas")
        egal(false, Fenetre.voirActive)
        vrai(Fenetre.imageProposition and Fenetre.imageProposition.proposition == prop.id, 'la demande du clic')
        egal(true, p.peutPrecedente)
        egal(true, p.peutSuivante)
        egal(true, p.aImage)
        Fenetre.rafraichir()
        egal('2 sur 3 · preview_settings', p.legendeApercu, 'gardée aux rafraîchissements')
        p.onglet = 'notation'
        egal('3 sur 3 · view_photo', p.legendeApercu, 'Note montre toujours la dernière image')
        p.onglet = 'proposition'
        egal('2 sur 3 · preview_settings', p.legendeApercu)
        -- Une autre photo active : l'onglet Proposition garde l'image de la proposition ; Note
        -- montre la photo active, comme avant, et la garde après un clic sur Proposition.
        photoActive(5, 'XH2S0321.RAF')
        Fenetre.majPhoto()
        egal(c, Moteur.courante, 'Autre photo décochée : même conversation')
        egal(true, Fenetre.voirActive)
        egal('2 sur 3 · preview_settings', p.legendeApercu, "gardée quand la photo active change")
        p.onglet = 'notation'
        egal('<EM>XH2S0321.RAF</EM>', p.legendeApercu)
        p.onglet = 'proposition'
        egal('2 sur 3 · preview_settings', p.legendeApercu)
        egal(true, Fenetre.voirActive, 'Note garde la photo active')
        p.onglet = 'notation'
        egal('<EM>XH2S0321.RAF</EM>', p.legendeApercu, 'Note inchangée par le clic sur Proposition')
        p.onglet = 'proposition'
        egal('2 sur 3 · preview_settings', p.legendeApercu)
        -- Agrandir : l'image de la proposition, pas la photo active (sa vignette prête, comme une
        -- fois sa tâche finie) ni la dernière image.
        Fenetre.apercuActif = { id = 5, T = Fenetre.T, chemin = imageJpeg, dossier = S.home, fichier = 'image.jpg' }
        local avant, dialogues = #S.taches, #S.dialogues
        Fenetre.agrandir()
        lancerTaches(avant)
        egal(dialogues + 1, #S.dialogues)
        egal('Claude · 2 sur 3 · preview_settings', S.dialogues[#S.dialogues].title)
        contient(S.dialogues[#S.dialogues].contents.args.value, '/p1-', "l'image de la proposition en grand")
        -- ◀ depuis elle, la photo active ayant changé : l'image d'avant la proposition.
        Fenetre.changerImage(-1)
        egal('1 sur 3 · view_photo', p.legendeApercu, '◀ part de la proposition')
        egal(nil, Fenetre.imageProposition)
        -- ◀ ▶ partis d'elle choisissent l'image : Note la montre ensuite.
        egal(false, Fenetre.voirActive)
        egal(1, Fenetre.indiceImage)
        p.onglet = 'notation'
        egal('1 sur 3 · view_photo', p.legendeApercu)
        p.onglet = 'proposition'
        egal('2 sur 3 · preview_settings', p.legendeApercu)
        -- ◀ part d'elle, et la demande est oubliée : l'aperçu redevient celui d'avant.
        Fenetre.changerImage(-1)
        egal('1 sur 3 · view_photo', p.legendeApercu)
        egal(nil, Fenetre.imageProposition)
        Fenetre.rafraichir()
        egal('1 sur 3 · view_photo', p.legendeApercu, "l'aperçu d'avant")
        -- ▶ aussi.
        p.onglet = 'notation'
        p.onglet = 'proposition'
        egal('2 sur 3 · preview_settings', p.legendeApercu)
        Fenetre.changerImage(1)
        egal('3 sur 3 · view_photo', p.legendeApercu)
        egal(nil, Fenetre.imageProposition)
        -- Une image cliquée dans le fil reste prioritaire.
        p.onglet = 'notation'
        p.onglet = 'proposition'
        egal('2 sur 3 · preview_settings', p.legendeApercu)
        Fenetre.rafraichir()
        local ligneV1
        for i = 1, Fenetre.T.lignes do
            local l = Fenetre.lignes[Fenetre.premiere + i - 1]
            if l and l.image == 'v1.jpg' then
                ligneV1 = ligneV1 or i
            end
        end
        vrai(ligneV1, "ligne de l'image v1 dans le fil")
        Fenetre.cliquerLigne(ligneV1)
        egal('1 sur 3 · view_photo', p.legendeApercu, "l'image cliquée")
        Fenetre.rafraichir()
        egal('1 sur 3 · view_photo', p.legendeApercu, "l'image cliquée reste")
        -- Une image nouvelle : elle se montre, la demande est oubliée.
        p.onglet = 'notation'
        p.onglet = 'proposition'
        egal('2 sur 3 · preview_settings', p.legendeApercu)
        vue(c, 'v3')
        Fenetre.rafraichir()
        egal('4 sur 4 · view_photo', p.legendeApercu, 'une image nouvelle se montre')
        egal(nil, Fenetre.imageProposition)
        -- Une image arrivée juste avant le clic, pas encore montrée : le clic l'emporte.
        p.onglet = 'notation'
        vue(c, 'v4')
        p.onglet = 'proposition'
        egal('2 sur 5 · preview_settings', p.legendeApercu, "le clic, pas l'image arrivée")
        Fenetre.rafraichir()
        egal('2 sur 5 · preview_settings', p.legendeApercu)
        -- Une autre proposition demandée, sans réponse encore : la carte parle d'elle, l'image de la
        -- précédente n'est plus gardée.
        local autre = appelPropose(c, 'p9', entreeCadre())
        Fenetre.rafraichir()
        egal(nil, Fenetre.imageProposition, 'une autre proposition attend : demande oubliée')
        Conversation.decider(c, autre.id, false)
        Fenetre.rafraichir()
        -- La proposition décidée : la demande ne vaut plus.
        p.onglet = 'notation'
        p.onglet = 'proposition'
        egal('2 sur 5 · preview_settings', p.legendeApercu)
        Conversation.decider(c, prop.id, false)
        Fenetre.rafraichir()
        egal(nil, Fenetre.imageProposition, 'proposition décidée : demande oubliée')
        -- Sans proposition en attente, un clic ne demande rien.
        p.onglet = 'notation'
        p.onglet = 'proposition'
        egal(nil, Fenetre.imageProposition)
        egal(false, Fenetre.montrerImageProposition())
        -- Une proposition encore sans réponse (pas d'image) : rien non plus.
        appelPropose(c, 'p2', entreeCadre())
        egal(false, Fenetre.montrerImageProposition())
        egal(nil, Fenetre.imageProposition)
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, false)
    end)
end)

essai("Aperçu : une bascule de la fenêtre ne demande pas l'image ; une autre conversation l'oublie ; la fenêtre rouverte aussi", function()
    photoActive(4, 'XH2S0320.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    local appels = 0
    local montrer = Fenetre.montrerImageProposition
    Fenetre.montrerImageProposition = function(...)
        appels = appels + 1
        return montrer(...)
    end
    local ok, erreur = pcall(ouvrirFenetre, function(p)
        Fenetre.majPhoto()
        vue(c, 'v1')
        appelPropose(c, 'p1', entreeCadre(), { REPONSE_CADRE }, 'p1.jpg')
        Fenetre.rafraichir()
        egal('proposition', p.onglet)
        egal(0, appels, 'la bascule vers Proposition ne la demande pas')
        Fenetre.choisirOnglet('notation')
        Fenetre.choisirOnglet('proposition')
        egal(0, appels, 'Fenetre.choisirOnglet non plus')
        p.onglet = 'notation'
        p.onglet = 'proposition'
        egal(1, appels, 'un vrai clic, si')
        vrai(Fenetre.imageProposition, 'demandée')
        egal('2 sur 2 · preview_settings', p.legendeApercu)
        -- Une autre conversation : la demande est oubliée.
        Moteur.nouvelle()
        Fenetre.rafraichir()
        egal(nil, Fenetre.imageProposition)
        egal("Aucun aperçu pour l'instant", p.legendeApercu)
        -- … même montrée depuis l'onglet Note, et la conversation d'avant rouverte ensuite (liste) :
        -- seul un nouveau clic la redemande.
        vue(c, 'v2')
        Moteur.courante = c
        Fenetre.rafraichir()
        p.onglet = 'notation'
        p.onglet = 'proposition'
        egal('2 sur 3 · preview_settings', p.legendeApercu)
        p.onglet = 'notation'
        local autre = Conversation.nouvelle()
        Moteur.courante = autre
        Fenetre.rafraichir()
        Moteur.courante = c
        Fenetre.rafraichir()
        Fenetre.choisirOnglet('proposition')
        egal(nil, Fenetre.imageProposition, 'oubliée avec la conversation')
        egal('3 sur 3 · view_photo', p.legendeApercu, "l'aperçu d'avant")
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, false)
    end)
    Fenetre.montrerImageProposition = montrer
    vrai(ok, erreur)
    -- À la réouverture, rien de demandé.
    Fenetre.imageProposition = { conversation = c, proposition = 'x', chemin = 'p1.jpg' }
    ouvrirFenetre(function()
        egal(nil, Fenetre.imageProposition, 'la demande ne survit pas à la fenêtre')
    end)
end)

essai("Aperçu : un seul crochet pour l'onglet Proposition ; la comparaison de « Je le fais » passe d'abord, l'image de la proposition ensuite", function()
    photoActive(4, 'XH2S0320.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    vrai(type(Fenetre.apercuOnglet.proposition) == 'function', 'crochet de l\'aperçu')
    vrai(type(Fenetre.surOnglet.proposition) == 'function', 'crochet du clic')
    local exercice = Fenetre.apercuExercice
    local ok, erreur = pcall(ouvrirFenetre, function(p)
        Fenetre.majPhoto()
        appelPropose(c, 'p1', entreeCadre(), { REPONSE_CADRE }, 'p1.jpg')
        Fenetre.rafraichir()
        p.onglet = 'notation'
        p.onglet = 'proposition'
        egal('1 sur 1 · preview_settings', p.legendeApercu)
        -- Une comparaison montrée (Fenetre.apercuExercice) l'emporte.
        Fenetre.apercuExercice = function(q)
            q.legendeApercu = 'Claude | vous · XH2S0320.RAF'
            return true
        end
        Fenetre.rafraichirApercu()
        egal('Claude | vous · XH2S0320.RAF', p.legendeApercu, "la comparaison d'abord")
        Fenetre.apercuExercice = exercice
        Fenetre.rafraichirApercu()
        egal('1 sur 1 · preview_settings', p.legendeApercu, "puis l'image de la proposition")
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, false)
    end)
    Fenetre.apercuExercice = exercice
    vrai(ok, erreur)
end)

-- Ajuster… et Accepter -----------------------------------------------------------------------------

-- Ouvre Ajuster… par son bouton (dans une tâche) ; `choisir(rapides, q)` reçoit les boutons
-- d'un clic et la table de la boîte, et rend sa réponse. Rend ce que la boîte montrait.
local function ajuster(args, p, choisir)
    local presenter = S.modules.LrDialogs.presentModalDialog
    local vu
    S.modules.LrDialogs.presentModalDialog = function(d)
        local colonne = d.contents
        local q = colonne.args.bind_to_object
        local invite, rangee
        for _, v in ipairs(colonne.args) do
            if type(v) == 'table' and v.genre == 'static_text' then
                invite = v.args.title
            elseif type(v) == 'table' and v.genre == 'row' then
                rangee = v
            end
        end
        local rapides = {}
        for _, b in ipairs(rangee.args) do
            if type(b) == 'table' and S.BOUTONS[b.genre] then
                rapides[#rapides + 1] = b
            end
        end
        local titres = {}
        for _, b in ipairs(rapides) do
            titres[#titres + 1] = b.args.title
        end
        vu = { titre = d.title, invite = invite, titres = table.concat(titres, ' | ') }
        return choisir(rapides, q)
    end
    local avant = #S.taches
    local ok, erreur = pcall(function()
        bouton(args.contents, p, 'Ajuster…', 'enAttente').args.action()
        lancerTaches(avant)
    end)
    S.modules.LrDialogs.presentModalDialog = presenter
    vrai(ok, erreur)
    return vu
end

essai("Ajuster… : les ajustements du cadre pour une proposition de recadrage, les autres sinon ; le choix part à Claude ; Accepter reste Accepter", function()
    photoActive(4, 'XH2S0320.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    remplacerEnvoyer()
    local ok, erreur = pcall(ouvrirFenetre, function(p, args)
        Fenetre.majPhoto()
        local prop = appelPropose(c, 'p1', entreeCadre(), { REPONSE_CADRE }, 'p1.jpg')
        Fenetre.rafraichir()
        egal(true, p.enAttente)
        local vu = ajuster(args, p, function(rapides)
            for _, b in ipairs(rapides) do
                if b.args.title == 'Plus serré' or b.args.title == 'Horizon au tiers haut' then
                    b.args.action()
                end
            end
            return 'ok'
        end)
        egal('Ajuster la proposition', vu.titre)
        egal(table.concat(Consignes.ajustementsCadre, ' | '), vu.titres, 'les ajustements du cadre')
        egal("Ce qu'il faut changer au cadre avant de l'appliquer :", vu.invite)
        egal(1, #envoyes, 'une demande')
        egal(Consignes.ajuster('Plus serré, horizon au tiers haut'), envoyes[1].texte)
        egal('ajustee', prop.etat)
        -- Annuler : rien n'est envoyé.
        local tons = appelPropose(c, 'p2', { photo_id = 4, settings = { Exposure2012 = 0.35 }, reason = 'Plus de lumière.' },
            { '{"changements": [{"cle": "Exposure2012", "avant": 0, "apres": 0.35}]}' }, 'p2.jpg')
        Fenetre.rafraichir()
        vu = ajuster(args, p, function() return 'cancel' end)
        egal(table.concat(Consignes.ajustementsRapides, ' | '), vu.titres, 'une proposition de tons : les ajustements d\'avant')
        egal("Ce qu'il faut changer avant d'appliquer :", vu.invite)
        egal(1, #envoyes, 'annulé : rien envoyé')
        egal('enAttente', tons.etat)
        -- Accepter applique la proposition montrée, par la réponse habituelle.
        local cadre = appelPropose(c, 'p3', entreeCadre(), { REPONSE_CADRE }, 'p3.jpg')
        Fenetre.rafraichir()
        -- Accepter : un bouton bleu en image (fenêtre B, lot B5), cliqué par son calque.
        local accepter = calqueAccepter(args.contents)
        contient(accepter.args.tooltip, "la photo ne change qu'à ce clic")
        local avant = #S.taches
        S.cliquer(accepter)
        lancerTaches(avant)
        egal(2, #envoyes)
        egal(Consignes.accepter, envoyes[2].texte)
        egal('acceptee', cadre.etat)
        egal('enAttente', tons.etat, 'la proposition de tons, plus ancienne, reste à décider')
        Conversation.decider(c, tons.id, false)
    end)
    remettreEnvoyer()
    vrai(ok, erreur)
end)

-- Consignes ----------------------------------------------------------------------------------------

essai("Consignes : section Composition (400 caractères au plus) entre Garde-fous et Je le fais ; ajustements du cadre", function()
    local texte = Consignes.texte
    local debut = texte:find('\n## Composition\n', 1, true)
    vrai(debut, 'section Composition')
    local fin = texte:find('\n## ', debut + 1, true)
    local section = texte:sub(debut + 1, fin - 1):gsub('\n$', '')
    vrai(Texte.longueur(section) <= 400, string.format('section : %d caractères pour 400', Texte.longueur(section)))
    for _, morceau in ipairs({ 'read_composition', 'preview_settings', 'sans compare', 'nettement', 'son crop seul', 'à la prise de vue',
        'reason = la règle',
        'Accepter', '« Appliquer directement »', 'Une proposition à la fois', 'la leçon suit', "retouche entière", "cadre ou d'horizon" }) do
        contient(section, morceau, 'section Composition')
    end
    -- « N'applique ce cadre qu'au clic » : la seule application du cadre attend ; la leçon suit.
    contient(section, "N'applique ce cadre qu'au clic de Dany sur Accepter", 'section Composition')
    -- Entre Garde-fous et Je le fais, qui reste juste avant Titre.
    local gardeFous = texte:find('\n## Garde-fous\n', 1, true)
    local jeLeFais = texte:find('\n## Je le fais\n', 1, true)
    vrai(gardeFous < debut and debut < jeLeFais, 'entre Garde-fous et Je le fais')
    egal(fin, jeLeFais, 'juste avant Je le fais')
    egal(texte:find('\n## ', jeLeFais + 1, true), texte:find('\n## Titre de la conversation\n', 1, true), 'Je le fais juste avant Titre')
    vrai(Texte.longueur(texte) <= 7500, string.format('plafond des consignes : %d', Texte.longueur(texte)))
    vrai(not texte:find('\\\n', 1, true), 'lignes recollées')
    -- Les ajustements du cadre, à la place des autres pour une proposition de recadrage.
    egal('Plus serré | Plus large | Horizon au tiers haut | Format 4:5 | Seulement redresser', table.concat(Consignes.ajustementsCadre, ' | '))
    egal('Moins chaud | Peau plus naturelle | Garder le ciel | Plus de contraste', table.concat(Consignes.ajustementsRapides, ' | '))
    -- L'invite Composition ne change pas : sans chiffre, avant Sports.
    egal('composition', Consignes.invites[6].id)
    egal('sports', Consignes.invites[7].id)
end)

-- Fin ---------------------------------------------------------------------------------------------

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
