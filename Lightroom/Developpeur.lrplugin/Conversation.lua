-- Conversation.lua : une conversation de la fenêtre = une session Claude Code, reprise par
-- `--resume` : des éléments `dany`, `claude`, `outil`, `apercu`, `proposition`, `notation` et
-- `note`, dans l'ordre du fil. Les dates sont en secondes Unix. Une conversation d'avant le
-- correctif 1.3.6 peut porter aussi des éléments `lecon` (la leçon de la photo) et `exercice`
-- (« Je le fais »), retirés avec eux : gardés tels quels sur le disque, ils ne se montrent plus
-- (le fil n'en fait aucune ligne ; l'appel de leur outil garde la sienne).
-- Une conversation des anciennes séances de notation (genre = 'notation', fenêtre retirée le
-- 20 octobre 2026) reste sur le disque mais ne s'ouvre plus.
--
-- Une photo, une conversation (correctif 1.3.6, décidé avec Dany le 25 octobre 2026) : `photo`, le
-- localIdentifier de la photo seule dont c'est la conversation (une copie virtuelle a la sienne ;
-- une conversation d'avant le correctif dont la dernière demande portait sur une photo seule la
-- tire de sa clé « id:1:id », Conversation.photoDeLaCle) ; `vu`, ce qu'elle a vu de sa photo
-- (Historique.vu : la dernière entrée du journal de Claude, editCount et lastEditTime), d'où le
-- complément « Depuis la dernière fois » ; `ecartee`, vrai quand « Repartir à neuf » l'a mise de
-- côté (gardée sur le disque, plus jamais reprise ni montrée) ; `groupe`, la clé de la sélection
-- d'une conversation de plusieurs photos (l'ensemble des photos, sans l'ordre ni la photo active),
-- jamais gardée, comme une demande rapide sur plusieurs photos. Leurs éléments `historique` (sorte 'historique',
-- 'depuis' ou 'groupe' : ce que la fenêtre dit de la photo ou du groupe, sans Claude, Historique.lua)
-- se montrent dans le fil et partent une seule fois avec la demande suivante de Dany (`pourClaude`,
-- `envoye`) ; ils ne commencent pas la conversation (Conversation.commencee). Une demande faite par
-- la Demande rapide dans la conversation d'une photo, et ce qui y répond, portent `rapide` = true
-- (Moteur.envoyerRapide ; le fil le dit, Fil.MENTION_RAPIDE).
--
-- Élément : id, genre, texte, date, outil, appel, etat ('enCours', 'fait', 'erreur', 'enAttente',
-- 'acceptee', 'refusee', 'ajustee', 'faite' : une proposition que Dany faisait lui-même, Je le
-- fais, 1.3, retiré au correctif 1.3.6 ; 'appliquee', 'remplacee' : une proposition qu'une étape
-- de Claude sur sa photo a rendue sans objet, 1.3.2, Conversation.clorePropositions), detail,
-- images (chemins relatifs au dossier de la conversation), changements ({ cle, libelle, avant,
-- apres }), partiel (texte en train d'arriver) ; pour une notation : passe, pose (notes posées à la demande de Dany :
-- propose_ratings avec apply), notes (voir Conversation.notesDemandees). Pour un outil qui écrit
-- une étape (1.3, Conversation.OUTILS_ETAPES) : raison (reason de l'entrée), etape (step_name),
-- etapes (les étapes écrites, lues dans la réponse : { photo, id, nom, fichier, changements }) ;
-- pour undo_last : annule ({ photo, id, nom } de chaque étape défaite) ; pour
-- revert_to_original : revenu (les photos remises). Une conversation de la 1.2 n'a ni raison, ni
-- etape, ni etapes : elles se relisent dans `detail` (Conversation.infoEtape), sans id.
-- Pour une proposition de recadrage (1.3, Composition lue : preview_settings avec un crop, sauf
-- reset) : recadrage (vrai), puis d'après la réponse cadre (resume_cadre, le cadre que Lightroom a
-- gardé, en mots) et cadreDessine (vrai si l'image rendue est l'image entière, le cadre en
-- pointillés). Pour toute proposition (1.3.2) : photo (photo_id de l'entrée, sinon la photo que
-- dit la réponse ; nil tant qu'elle n'est pas connue) ; close par une étape de Claude, etapeClaude
-- (le nom de cette étape, sans « Claude · »).

require 'Compat'
local Consignes = require 'Consignes'
local Json = require 'Json'
local Texte = require 'Texte'

local Conversation = {}

Conversation.PREFIXE_OUTILS = 'mcp__developpeur__'
Conversation.TITRE_PAR_DEFAUT = "Nouvelle conversation"
-- Genre d'une conversation des anciennes séances de notation (absent pour une retouche).
Conversation.GENRE_SEANCE = 'notation'
-- Claude propose de 0 à 5 étoiles (standard de notation, correctif 1.3.2) : une note lue au-dessus
-- est ramenée.
Conversation.NOTE_MAXIMALE = 5

local compteur = 0

-- Un identifiant unique (pas de générateur d'UUID dans Lightroom).
function Conversation.identifiant(maintenant)
    compteur = compteur + 1
    return string.format('%X-%04X-%04X', math.floor(maintenant or os.time()), math.random(0, 0xFFFF), compteur % 0x10000)
end

function Conversation.nouvelle(maintenant)
    maintenant = maintenant or os.time()
    return {
        id = Conversation.identifiant(maintenant),
        titre = Conversation.TITRE_PAR_DEFAUT,
        resume = '',
        creee = maintenant,
        modifiee = maintenant,
        elements = {},
    }
end

function Conversation.estSeance(c)
    return type(c) == 'table' and c.genre == Conversation.GENRE_SEANCE
end

local function nouvelElement(genre, champs, date)
    local e = { id = Conversation.identifiant(date), genre = genre, texte = '', date = date or os.time(), images = {}, changements = {} }
    for cle, valeur in pairs(champs or {}) do
        e[cle] = valeur
    end
    return e
end

-- Marqueur du titre ----------------------------------------------------------------------------
-- Une ligne « [titre : …] » (entourée au besoin de gras ou de code Markdown), retirée de l'affichage.

local LONGUEUR_TITRE = 60

-- Morceaux d'un titre d'attente, en minuscules (« À » majuscule n'est pas abaissé par Lua 5.1 :
-- « définir » suffit).
local TITRES_D_ATTENTE = { 'définir', 'definir', 'à venir', 'a venir', 'après aperçu', 'apres apercu',
    'en attente', 'provisoire', 'inconnu', 'sans titre' }

-- Le titre, sans guillemets, point final ni espaces en trop ; nil pour un titre vide ou pour le
-- gabarit de la consigne répété tel quel (« <ce que montre la photo> »).
function Conversation.nettoyerTitre(brut)
    local titre = Texte.nettoyer(brut)
    local bords = { '«', '»', '"', '“', '”', "'", '’', '*', '_', '`', '.', ' ', '\194\160', '\226\128\175' }
    local change = true
    while change and titre ~= '' do
        change = false
        for _, b in ipairs(bords) do
            if titre:sub(1, #b) == b then
                titre, change = titre:sub(#b + 1), true
            end
            if #titre >= #b and titre:sub(-#b) == b then
                titre, change = titre:sub(1, -#b - 1), true
            end
        end
    end
    titre = titre:gsub('%s+', ' ')
    if titre == '' or titre:find('[<>]') then
        return nil
    end
    -- Un titre d'attente, écrit avant d'avoir vu la photo (constaté le 28 octobre 2026 :
    -- « à définir après aperçu ») : refusé, Claude en donnera un vrai à la vue suivante.
    local bas = titre:lower()
    for _, attente in ipairs(TITRES_D_ATTENTE) do
        if bas:find(attente, 1, true) then
            return nil
        end
    end
    return Texte.raccourcir(titre, LONGUEUR_TITRE)
end

-- Cherche le marqueur dans une ligne : début, fin (octets) et contenu.
local function trouverMarqueur(ligne)
    local debut, fin, contenu = ligne:find('[*_`]*%[%s*[Tt][Ii][Tt][Rr][Ee]%s*:%s*([^%]\n]*)%][*_`]*')
    return debut, fin, contenu
end

-- Le titre donné dans un texte de Claude (nil : pas de marqueur, ou un titre vide).
function Conversation.lireTitre(texte)
    for _, ligne in ipairs(Texte.lignes(texte)) do
        local debut, _, contenu = trouverMarqueur(ligne)
        if debut then
            return Conversation.nettoyerTitre(contenu)
        end
    end
    return nil
end

-- « [ti », « [titre : Pont de » : le début d'un marqueur dont la fin n'est pas encore arrivée.
function Conversation.debutMarqueur(ligne)
    local debut = ligne:gsub('^[%s*_`]+', '')
    if debut:sub(1, 1) ~= '[' or debut:find(']', 1, true) then
        return false
    end
    local mot = debut:sub(2):gsub('^%s+', ''):lower()
    if mot:sub(1, 5) ~= 'titre' then
        return ('titre'):sub(1, #mot) == mot
    end
    local apres = mot:sub(6):gsub('^%s+', '')
    return apres == '' or apres:sub(1, 1) == ':'
end

-- Le texte sans le marqueur. `partiel` (texte en train d'arriver) : sans la dernière ligne non
-- plus si elle commence comme un marqueur pas encore complet.
function Conversation.retirerMarqueur(texte, partiel)
    local retire = false
    local gardees = {}
    for _, ligne in ipairs(Texte.lignes(texte)) do
        local debut, fin = trouverMarqueur(ligne)
        if debut then
            retire = true
            local reste = Texte.nettoyer(ligne:sub(1, debut - 1) .. ligne:sub(fin + 1))
            if reste ~= '' then
                gardees[#gardees + 1] = reste
            end
        else
            gardees[#gardees + 1] = ligne
        end
    end
    if partiel and #gardees > 0 and Conversation.debutMarqueur(gardees[#gardees]) then
        gardees[#gardees] = nil
        retire = true
    end
    if not retire then
        return texte
    end
    return Texte.nettoyer(table.concat(gardees, '\n'))
end

-- Le texte d'un élément tel qu'il se montre (sans le marqueur du titre, même en train d'arriver).
function Conversation.texteAffiche(e)
    if e.genre == 'claude' then
        return Conversation.retirerMarqueur(e.texte or '', e.partiel)
    end
    return e.texte or ''
end

-- Demandes, titre, recherche ------------------------------------------------------------------

-- Les 48 premiers caractères de la première ligne d'une demande.
function Conversation.titreDepuis(texte)
    local ligne = Texte.lignes(Texte.nettoyer(texte))[1] or ''
    return Texte.raccourcir(ligne, 48)
end

-- Ajoute une demande de Dany ; la première donne son titre à la conversation. `images` : chemins
-- des images jointes (relatifs au dossier de la conversation) ; `style` : nom du style choisi
-- (rappelé dans le fil), nil pour Standard.
function Conversation.ajouterDemande(c, texte, date, images, style)
    date = date or os.time()
    c.elements[#c.elements + 1] = nouvelElement('dany', { texte = texte, images = images or {}, style = style }, date)
    local demandes = 0
    for _, e in ipairs(c.elements) do
        if e.genre == 'dany' then
            demandes = demandes + 1
        end
    end
    -- Une conversation de photo ou de groupe garde son titre provisoire (le nom de la photo, le
    -- nombre de photos) jusqu'à celui que Claude donne (Conversation.poserTitre).
    if c.titreChoisi ~= true and c.titreAuto ~= true and demandes == 1 and c.photo == nil and c.groupe == nil then
        c.titre = Conversation.titreDepuis(texte)
    end
    c.modifiee = date
end

-- (Renommer une conversation, Conversation.renommer, est retiré au correctif 1.3.6 : le titre est
-- celui que Claude donne ; un titre choisi avant, `titreChoisi`, reste.)

-- Le titre que Claude tire de la photo : seulement à la place du titre par défaut (jamais d'un
-- titre choisi par Dany), et une seule fois.
function Conversation.poserTitre(c, texte)
    if c.titreChoisi == true or c.titreAuto == true then
        return
    end
    local titre = Conversation.lireTitre(texte or '')
    if titre then
        c.titre = titre
        c.titreAuto = true
    end
end

-- Le texte envoyé à Claude : la ligne de contexte de Lightroom, celle du style choisi, les lignes
-- de l'historique pas encore envoyées (`historiques`, Conversation.historiquesAEnvoyer : comme
-- « [Sans leçon] » jusqu'au correctif 1.3.6), la demande, et tant que la conversation n'a pas de
-- titre tiré d'une photo ni choisi, le rappel du titre.
function Conversation.messagePourClaude(c, demande, contexte, ligneStyle, historiques)
    local morceaux = {}
    if contexte and contexte ~= '' then
        morceaux[#morceaux + 1] = contexte
    end
    if ligneStyle and ligneStyle ~= '' then
        morceaux[#morceaux + 1] = ligneStyle
    end
    for _, e in ipairs(historiques or {}) do
        if type(e.pourClaude) == 'string' and e.pourClaude ~= '' then
            morceaux[#morceaux + 1] = e.pourClaude
        end
    end
    morceaux[#morceaux + 1] = demande
    if c.titreAuto ~= true and c.titreChoisi ~= true then
        morceaux[#morceaux + 1] = Consignes.rappelTitre
    end
    return table.concat(morceaux, '\n\n')
end

-- (La recherche dans les conversations, Conversation.correspond, est retirée avec le champ
-- Rechercher du volet au correctif 1.3.6.)

-- Une photo, une conversation (correctif 1.3.6) ------------------------------------------------

-- Ajoute un élément de la fenêtre (Historique.lua) : `sorte` 'historique' (l'historique de la photo,
-- en tête d'une conversation neuve), 'depuis' (ce qui a changé depuis que la conversation a vu la
-- photo) ou 'groupe' (le résumé court d'un groupe) ; `texte`, ses lignes pour le fil ; `pourClaude`,
-- la ligne jointe à la demande suivante de Dany, une seule fois (`envoye`). Ne change pas la date de
-- la conversation (son rang parmi les autres).
function Conversation.ajouterHistorique(c, sorte, texte, pourClaude, date)
    local e = nouvelElement('historique', { sorte = sorte, texte = texte, pourClaude = pourClaude, envoye = false }, date)
    c.elements[#c.elements + 1] = e
    return e
end

-- Les éléments de la fenêtre pas encore envoyés à Claude, dans l'ordre du fil (Moteur.envoyer les
-- marque envoyés une fois la demande partie).
function Conversation.historiquesAEnvoyer(c)
    local liste = {}
    for _, e in ipairs(c.elements or {}) do
        if e.genre == 'historique' and e.envoye ~= true then
            liste[#liste + 1] = e
        end
    end
    return liste
end

-- Vrai quand la conversation a commencé : un élément autre que ceux de la fenêtre (l'historique ne
-- compte pas : une photo dont la conversation n'a que lui est une photo sans conversation).
function Conversation.commencee(c)
    for _, e in ipairs(type(c) == 'table' and c.elements or {}) do
        if e.genre ~= 'historique' then
            return true
        end
    end
    return false
end

-- La photo seule d'une clé de sélection (Lightroom.photos : « active:nombre:ids… ») : « 4961:1:4961 »
-- donne 4961 ; nil pour un groupe ou une clé d'une autre forme.
function Conversation.photoDeLaCle(cle)
    local active, seule = tostring(cle or ''):match('^(%d+):1:(%d+)$')
    if active and active == seule then
        return tonumber(active)
    end
    return nil
end

-- Vrai si `c` est la conversation de la photo `id` (jamais celle d'un groupe).
function Conversation.dePhoto(c, id)
    return type(c) == 'table' and c.groupe == nil and c.photo ~= nil and id ~= nil
        and Conversation.clePhoto(c.photo) == Conversation.clePhoto(id)
end

-- Outils et propositions ----------------------------------------------------------------------

-- « view_photo », « apply_settings · passe 1 : lumière », « view_photo · photo 53636309 »,
-- « propose_ratings · 14 photos ».
function Conversation.resumeOutil(nom, entree)
    entree = type(entree) == 'table' and entree or {}
    local precision
    if type(entree.ratings) == 'table' and #entree.ratings > 0 then
        precision = #entree.ratings == 1 and '1 photo' or (#entree.ratings .. ' photos')
    elseif type(entree.step_name) == 'string' then
        precision = entree.step_name
    elseif type(entree.photo_id) == 'number' then
        precision = 'photo ' .. Texte.nombre(entree.photo_id)
    elseif type(entree.photo_ids) == 'table' and #entree.photo_ids > 0 then
        precision = #entree.photo_ids == 1 and ('photo ' .. tostring(entree.photo_ids[1])) or (#entree.photo_ids .. ' photos')
    elseif entree.selection == true then
        precision = 'sélection'
    end
    return precision and (nom .. ' · ' .. precision) or nom
end

-- Libellés français des réglages les plus courants (le reste garde sa clé).
Conversation.libelles = {
    Exposure2012 = "Exposition", Contrast2012 = "Contraste", Highlights2012 = "Hautes lumières",
    Shadows2012 = "Ombres", Whites2012 = "Blancs", Blacks2012 = "Noirs", Temperature = "Température",
    Tint = "Teinte", Vibrance = "Vibrance", Saturation = "Saturation", Clarity2012 = "Clarté",
    Dehaze = "Correction du voile", Texture = "Texture", PostCropVignetteAmount = "Vignetage",
    GrainAmount = "Grain", Sharpness = "Netteté", LuminanceSmoothing = "Réduction du bruit",
}

local function affichage(v)
    if v == nil or v == Json.null then
        return '—'
    elseif type(v) == 'number' then
        return Texte.nombre(v)
    elseif type(v) == 'boolean' then
        return v and 'oui' or 'non'
    elseif type(v) == 'table' then
        local ok, t = pcall(Json.encode, v)
        return ok and Texte.raccourcir(t, 40) or '…'
    end
    return tostring(v)
end

local function cles(t)
    local liste = {}
    for cle in pairs(t) do
        liste[#liste + 1] = cle
    end
    table.sort(liste, function(a, b) return tostring(a) < tostring(b) end)
    return liste
end

-- Les formats que le connecteur lit comme le format d'origine (crop.aspect).
local FORMATS_ORIGINE = { [''] = true, original = true, originale = true, origine = true, ["d'origine"] = true, ['as shot'] = true }

-- Le recadrage demandé à preview_settings (crop), en mots, avant la réponse (1.3, Composition
-- lue) : format, angle et taille demandés (« format 3:2, redressé de 1,4°, 82 % du plus grand
-- cadre ») ; « retiré » pour un reset. La taille est une part du plus grand cadre possible, pas de
-- la largeur de l'image (le résumé du cadre gardé, Conversation.cadreLu, dit celle-là).
function Conversation.cadreDemande(crop)
    crop = type(crop) == 'table' and crop or {}
    if crop.reset == true then
        return "retiré"
    end
    local parties = {}
    if type(crop.aspect) == 'string' then
        local format = Texte.nettoyer(crop.aspect)
        parties[#parties + 1] = FORMATS_ORIGINE[format:lower()] and "format d'origine" or ("format " .. format)
    end
    local angle = tonumber(crop.angle)
    if angle and angle ~= 0 then
        parties[#parties + 1] = "redressé de " .. Texte.nombre(math.abs(angle)) .. "°"
    end
    local taille = tonumber(crop.size)
    if taille then
        parties[#parties + 1] = Texte.nombre(math.floor(taille * 100 + 0.5)) .. " % du plus grand cadre"
    end
    return #parties > 0 and table.concat(parties, ", ") or "cadre demandé"
end

-- Le libellé de la ligne du recadrage demandé (sans clé) : la carte Proposition la saute quand le
-- cadre gardé est dit (Fenetre.texteProposition).
Conversation.LIBELLE_RECADRAGE = "Recadrage"

-- Changements d'une proposition, d'après ce que Claude demande (avant inconnu) ; un recadrage
-- demandé (crop) en une ligne « Recadrage », remplacée à la réponse par le cadre gardé.
function Conversation.changementsDemandes(entree)
    local liste = {}
    entree = type(entree) == 'table' and entree or {}
    if type(entree.profile) == 'string' then
        liste[#liste + 1] = { libelle = "Profil", avant = '—', apres = entree.profile }
    end
    local reglages = type(entree.settings) == 'table' and entree.settings or {}
    for _, cle in ipairs(cles(reglages)) do
        liste[#liste + 1] = { libelle = Conversation.libelles[cle] or cle, avant = '—', apres = affichage(reglages[cle]) }
    end
    if type(entree.crop) == 'table' then
        liste[#liste + 1] = { libelle = Conversation.LIBELLE_RECADRAGE, avant = '—', apres = Conversation.cadreDemande(entree.crop) }
    end
    return liste
end

-- Ajoute à `lus` les changements d'une liste du connecteur (cle, avant, apres, libelle) : { cle,
-- libelle, avant, apres }, la clé gardée (1.3), les valeurs en texte.
local function lireChangements(liste, lus)
    for _, ch in ipairs(type(liste) == 'table' and liste or {}) do
        if type(ch) == 'table' and type(ch.cle) == 'string' then
            lus[#lus + 1] = { cle = ch.cle, libelle = type(ch.libelle) == 'string' and ch.libelle or Conversation.libelles[ch.cle] or ch.cle,
                avant = affichage(ch.avant), apres = affichage(ch.apres) }
        end
    end
    return lus
end

-- Changements renvoyés par le connecteur (`changements` : cle, avant, apres, libelle), nil sans.
function Conversation.changementsLus(textes)
    for _, texte in ipairs(textes or {}) do
        local ok, json = pcall(Json.decode, texte)
        if ok and type(json) == 'table' then
            local lus = lireChangements(json.changements, {})
            for _, r in ipairs(type(json.resultats) == 'table' and json.resultats or {}) do
                if type(r) == 'table' then
                    lireChangements(r.changements, lus)
                end
            end
            if #lus > 0 then
                return lus
            end
        end
    end
    return nil
end

-- Le cadre d'une proposition de recadrage (1.3, Composition lue), lu dans la réponse de
-- preview_settings : son résumé (resume_cadre : le cadre que Lightroom a gardé, « 3:2 (format
-- d'origine), redressé de 1,4°, 79 % de la largeur gardée »), nettoyé, et vrai si l'image rendue
-- est l'image entière avec ce cadre en pointillés (le champ image de la réponse le dit ; absent
-- quand l'image entière n'a pas pu se rendre, ou avec overlay = false). nil sans résumé. Une
-- remarque recollée après le JSON ne gêne pas (Conversation.teteJson).
function Conversation.cadreLu(textes)
    for _, texte in ipairs(textes or {}) do
        local json = Conversation.teteJson(texte)
        if type(json) == 'table' and type(json.resume_cadre) == 'string' then
            local resume = Texte.nettoyer(json.resume_cadre)
            if resume ~= '' then
                return resume, type(json.image) == 'string' and json.image:find('pointillés', 1, true) ~= nil
            end
        end
    end
    return nil
end

-- Notes proposées -----------------------------------------------------------------------------
-- Un élément `notation` suit un appel de propose_ratings, pour le fil seulement : le registre du
-- module (Notation.lua) reste la source des fenêtres Note et Séance.

local function chaine(v)
    if type(v) ~= 'string' then
        return nil
    end
    local t = Texte.nettoyer(v)
    return t ~= '' and t or nil
end

-- La clé d'une photo (identifiant du catalogue), en texte : nombre et texte se rejoignent.
function Conversation.clePhoto(photo)
    if type(photo) == 'number' then
        return string.format('%d', photo)
    end
    return photo ~= nil and tostring(photo) or ''
end

-- Les notes demandées par Claude (entrée de propose_ratings) :
--   { photo, note (0 à 5) | nil, drapeau ('rejetee') | nil, criteres = { impact, qualites, plancher,
--     finition }, raison, a_verifier, etat = 'demandee' }
-- puis, d'après la réponse du connecteur : fichier, note_avant, drapeau_avant, etat 'proposee' ou
-- 'refusee' (refus : la raison). Une note au-dessus de 5 est ramenée à 5 (le connecteur la refuse).
function Conversation.notesDemandees(entree)
    local notes = {}
    entree = type(entree) == 'table' and entree or {}
    for _, r in ipairs(type(entree.ratings) == 'table' and entree.ratings or {}) do
        if type(r) == 'table' then
            local criteres = type(r.criteria) == 'table' and r.criteria or {}
            local note = tonumber(r.rating)
            if note then
                note = math.max(0, math.min(Conversation.NOTE_MAXIMALE, math.floor(note)))
            end
            notes[#notes + 1] = {
                photo = r.photo_id,
                note = note,
                drapeau = r.flag == 'reject' and 'rejetee' or nil,
                criteres = { impact = chaine(criteres.impact), qualites = chaine(criteres.qualities),
                    plancher = chaine(criteres.technical_floor), finition = chaine(criteres.finish) },
                raison = chaine(r.reason) or '',
                a_verifier = r.to_check == true,
                etat = 'demandee',
            }
        end
    end
    return notes
end

-- La réponse du connecteur à propose_ratings (`propositions` : photo, fichier, note_avant,
-- drapeau_avant, etat ; `refusees` : photo, raison ; `posees` avec apply : photo, etat, erreur),
-- par clé de photo ; nil sans.
function Conversation.notesLues(textes)
    for _, texte in ipairs(textes or {}) do
        local ok, json = pcall(Json.decode, texte)
        if ok and type(json) == 'table' and (type(json.propositions) == 'table' or type(json.refusees) == 'table') then
            local lues = { propositions = {}, refusees = {}, posees = {} }
            for _, p in ipairs(type(json.propositions) == 'table' and json.propositions or {}) do
                if type(p) == 'table' and p.photo ~= nil then
                    lues.propositions[Conversation.clePhoto(p.photo)] = { fichier = chaine(p.fichier),
                        note_avant = tonumber(p.note_avant), drapeau_avant = chaine(p.drapeau_avant), etat = chaine(p.etat) }
                end
            end
            for _, r in ipairs(type(json.refusees) == 'table' and json.refusees or {}) do
                if type(r) == 'table' and r.photo ~= nil then
                    lues.refusees[Conversation.clePhoto(r.photo)] = chaine(r.raison) or "refusée"
                end
            end
            for _, x in ipairs(type(json.posees) == 'table' and json.posees or {}) do
                if type(x) == 'table' and x.photo ~= nil then
                    lues.posees[Conversation.clePhoto(x.photo)] = { etat = chaine(x.etat), erreur = chaine(x.erreur) }
                end
            end
            return lues
        end
    end
    return nil
end

-- Complète un élément `notation` par le résultat de son appel : refusé en entier (erreur du
-- connecteur), ou photo par photo.
function Conversation.completerNotation(e, r)
    if r.erreur then
        e.etat = 'erreur'
        e.texte = Texte.nettoyer(table.concat(r.textes or {}, ' '))
        for _, x in ipairs(e.notes or {}) do
            x.etat = 'refusee'
        end
        return
    end
    e.etat = 'fait'
    local lues = Conversation.notesLues(r.textes) or { propositions = {}, refusees = {}, posees = {} }
    for _, x in ipairs(e.notes or {}) do
        local cle = Conversation.clePhoto(x.photo)
        local p = lues.propositions[cle]
        if lues.refusees[cle] then
            x.etat = 'refusee'
            x.refus = lues.refusees[cle]
        else
            -- Une réponse sans la photo (ou illisible) : l'outil a réussi, la note est rangée ; posée
            -- si la réponse le dit (apply), sinon la raison de l'échec.
            x.etat = 'proposee'
            local posee = lues.posees[cle]
            if posee and (posee.etat == 'acceptee' or posee.etat == 'changee') then
                x.etat = 'posee'
            elseif posee and posee.erreur then
                x.refus = "non posée : " .. posee.erreur
            end
            if p then
                x.fichier = p.fichier or x.fichier
                x.note_avant = p.note_avant
                x.drapeau_avant = p.drapeau_avant
            end
        end
    end
end

-- L'élément `outil` de l'appel `appel` (le dernier), nil sans appel ni élément (l'appel d'un
-- aperçu : Conversation.dernierZoom).
function Conversation.outilDeLAppel(c, appel)
    if appel == nil then
        return nil
    end
    for i = #(c.elements or {}), 1, -1 do
        local e = c.elements[i]
        if e.genre == 'outil' and e.appel == appel then
            return e
        end
    end
    return nil
end

-- Étapes de Claude (1.3, « Pourquoi ? ») ------------------------------------------------------
-- Un outil qui écrit une étape « Claude · … » (Ecriture.nouvelleEtape du module) : son élément du
-- fil garde la raison (reason) et le but (step_name) que Claude donne, puis, d'après la réponse du
-- connecteur, les étapes écrites, chacune avec l'identifiant que le module lui a donné
-- (`etape_id` : celui de ses images avant/après, Etapes.lua). L'onglet Aperçu de la fenêtre
-- (l'ancien onglet Pourquoi ?) les montre, photo par photo, dans l'ordre du fil (Conversation.etapes). Un outil appelé en
-- proposition seulement (preview = true) n'écrit pas d'étape.

Conversation.OUTILS_ETAPES = {
    apply_settings = true, add_mask = true, edit_mask = true, retouch_spots = true, copy_settings = true, enhance_photo = true,
    remove_distractions = true, choose_variant = true, match_series = true, set_metadata = true, manage_collections = true,
}

-- Des classements : leur étape ne change pas l'image (pas d'avant/après).
Conversation.CLASSEMENTS = { set_metadata = true, manage_collections = true }

-- La réponse de match_series ne porte pas d'etape_id (une série ne garde pas d'avant/après) : pas
-- de repère pendant l'appel, qui disparaîtrait à sa réponse.
local SANS_REPERE_EN_COURS = { match_series = true }

local PREFIXE_ETAPE = 'Claude · '

-- Le nom d'une étape sans le préfixe « Claude · » ('' sans nom).
function Conversation.nomEtape(nom)
    local t = chaine(nom) or ''
    while t:sub(1, #PREFIXE_ETAPE) == PREFIXE_ETAPE do
        t = Texte.nettoyer(t:sub(#PREFIXE_ETAPE + 1))
    end
    return t
end

-- L'identifiant d'une étape (etape_id), en texte ; nil s'il manque (null : rien d'écrit).
local function identifiantEtape(v)
    if type(v) == 'number' then
        return string.format('%d', v)
    end
    return type(v) == 'string' and v ~= '' and v or nil
end

-- La photo d'un objet de réponse (`photo` : { id, fichier } ou un identifiant) : id et fichier.
local function photoDe(objet)
    local photo = objet.photo
    if type(photo) == 'table' and photo ~= Json.null then
        return tonumber(photo.id) or chaine(photo.id), chaine(photo.fichier)
    end
    return tonumber(photo) or chaine(photo), nil
end

-- L'étape que porte un objet de la réponse : { photo, id, nom, fichier, changements } ; nil sans
-- etape_id. `sansId` (conversation de la 1.2) : le nom de l'étape suffit, sans id.
local function etapeLue(objet, sansId)
    if type(objet) ~= 'table' or objet == Json.null then
        return nil
    end
    local id = identifiantEtape(objet.etape_id)
    if not id and not (sansId and chaine(objet.etape)) then
        return nil
    end
    local photo, fichier = photoDe(objet)
    if photo == nil then
        return nil
    end
    return { photo = photo, id = id, nom = chaine(objet.etape), fichier = fichier, changements = lireChangements(objet.changements, {}) }
end

-- Les étapes écrites, lues dans la réponse du connecteur : les objets de `resultats` (ou la
-- réponse elle-même, pour choose_variant) qui portent un etape_id.
function Conversation.etapesLues(textes, sansId)
    local lues = {}
    for _, texte in ipairs(textes or {}) do
        local ok, json = pcall(Json.decode, texte)
        if ok and type(json) == 'table' then
            lues[#lues + 1] = etapeLue(json, sansId)
            for _, r in ipairs(type(json.resultats) == 'table' and json.resultats or {}) do
                lues[#lues + 1] = etapeLue(r, sansId)
            end
        end
    end
    return lues
end

-- Les étapes défaites par undo_last (`resultats` : photo, annulee, etape, etape_id) : { photo, id,
-- nom } ; id nil pour une mémoire d'avant la 1.3.
function Conversation.annulationsLues(textes)
    local lues = {}
    for _, texte in ipairs(textes or {}) do
        local ok, json = pcall(Json.decode, texte)
        if ok and type(json) == 'table' then
            for _, r in ipairs(type(json.resultats) == 'table' and json.resultats or {}) do
                if type(r) == 'table' and r.annulee == true then
                    local photo = photoDe(r)
                    if photo ~= nil then
                        lues[#lues + 1] = { photo = photo, id = identifiantEtape(r.etape_id), nom = chaine(r.etape) }
                    end
                end
            end
        end
    end
    return lues
end

-- Les photos remises par revert_to_original (`resultats` : photo, remise).
function Conversation.retoursLus(textes)
    local lues = {}
    for _, texte in ipairs(textes or {}) do
        local ok, json = pcall(Json.decode, texte)
        if ok and type(json) == 'table' then
            for _, r in ipairs(type(json.resultats) == 'table' and json.resultats or {}) do
                if type(r) == 'table' and r.remise == true then
                    local photo = photoDe(r)
                    if photo ~= nil then
                        lues[#lues + 1] = photo
                    end
                end
            end
        end
    end
    return lues
end

-- Lignes de remarques retirées au plus de la fin d'une réponse de la 1.2 pour trouver son JSON :
-- chaque essai relit tout le JSON, et une réponse illisible (coupée) en a des milliers de lignes.
Conversation.LIGNES_REMARQUES = 12

-- Le JSON du connecteur en tête d'un texte : le texte entier s'il se lit, sinon la plus longue tête
-- qui se lit, en retirant au plus LIGNES_REMARQUES lignes de la fin (une remarque du connecteur,
-- bloc de texte à part, suit le JSON quand les blocs sont recollés). Rend la valeur lue et la tête
-- (nil, nil : rien ne se lit).
function Conversation.teteJson(texte)
    texte = tostring(texte or '')
    local ok, valeur = pcall(Json.decode, texte)
    if ok then
        return valeur, texte
    end
    local fin, essais = #texte, 0
    while fin > 0 and essais < Conversation.LIGNES_REMARQUES do
        essais = essais + 1
        local pos = texte:sub(1, fin):match('.*()\n')
        if not pos then
            break
        end
        local tete = texte:sub(1, pos - 1)
        local lu, v = pcall(Json.decode, tete)
        if lu then
            return v, tete
        end
        fin = pos - 1
    end
    return nil, nil
end

-- L'entrée et la réponse gardées dans `detail` (« … — Réponse — … ») : l'entrée décodée, et la
-- réponse en textes (le JSON du connecteur, sans les remarques qui le suivent).
local function lireDetail(detail)
    local entree, reponse = tostring(detail or ''):match('^(.-)\n\n— Réponse —\n(.*)$')
    if not entree then
        return nil, {}
    end
    local ok, e = pcall(Json.decode, entree)
    local _, tete = Conversation.teteJson(reponse)
    return ok and type(e) == 'table' and e or nil, { tete or reponse }
end

-- Ce qu'un élément d'une conversation de la 1.2 dit de ses étapes, relu une fois dans `detail`.
local anciennes = setmetatable({}, { __mode = 'k' })

local function lireAncienne(e)
    local deja = anciennes[e]
    if deja and deja.detail == e.detail then
        return deja
    end
    local info = { detail = e.detail, etapes = {}, annule = {}, revenu = {} }
    if e.etat ~= 'erreur' then
        local entree, textes = lireDetail(e.detail)
        if Conversation.OUTILS_ETAPES[e.outil] and entree and entree.preview ~= true then
            info.raison, info.etape = chaine(entree.reason), chaine(entree.step_name)
            info.etapes = Conversation.etapesLues(textes, true)
        elseif e.outil == 'undo_last' then
            info.annule = Conversation.annulationsLues(textes)
        elseif e.outil == 'revert_to_original' then
            info.revenu = Conversation.retoursLus(textes)
        end
    end
    anciennes[e] = info
    return info
end

-- Les étapes d'un élément outil : { etapes, raison, etape, annule, revenu, ancienne } ; celles d'une
-- conversation de la 1.2 (sans `etapes`, `annule` ni `revenu`) relues dans son détail, sans id.
function Conversation.infoEtape(e)
    if type(e) ~= 'table' or e.genre ~= 'outil' then
        return { etapes = {}, annule = {}, revenu = {} }
    end
    local candidat = Conversation.OUTILS_ETAPES[e.outil]
    if (candidat and e.etapes == nil) or (e.outil == 'undo_last' and e.annule == nil)
        or (e.outil == 'revert_to_original' and e.revenu == nil) then
        local a = lireAncienne(e)
        return { etapes = a.etapes, raison = a.raison, etape = a.etape, annule = a.annule, revenu = a.revenu, ancienne = true }
    end
    return { etapes = e.etapes or {}, raison = e.raison, etape = e.etape, annule = e.annule or {}, revenu = e.revenu or {} }
end

-- Vrai pour l'élément d'une étape de Claude : un outil qui en écrit, pas en erreur, avec les
-- étapes de sa réponse ; ou en cours, avec son but (step_name). Sa ligne du fil porte le drapeau
-- `etape` : un clic sur elle l'ouvre dans l'onglet Aperçu (le bouton « Pourquoi ? » à son bout est
-- retiré au correctif 1.3.6).
function Conversation.estEtape(e)
    if type(e) ~= 'table' or e.genre ~= 'outil' or e.etat == 'erreur' or not Conversation.OUTILS_ETAPES[e.outil] then
        return false
    end
    local info = Conversation.infoEtape(e)
    if #info.etapes > 0 then
        return true
    end
    return e.etat == 'enCours' and not info.ancienne and info.etape ~= nil and not SANS_REPERE_EN_COURS[e.outil]
end

-- (Conversation.estRetouche, Conversation.demandeAGarder et Conversation.preparerDemande sont
-- retirées au correctif 1.3.6, avec « ＋ Garder la demande » et la ligne « Demande à garder : « … » »
-- que Claude écrivait à la fin d'une retouche : deuxième retour de Dany du 25 octobre 2026. Le menu
-- Mes demandes reste, avec Ajouter…, Renommer… et Supprimer….)

-- Les étapes de la conversation pour une photo, dans l'ordre du fil : { element (indice),
-- elementId, photo, id, nom, fichier, etape, raison, changements, outil, annulee, enCours,
-- ancienne }. Un appel en cours compte pour toute photo (sa photo n'est connue qu'à la réponse).
-- `annulee` : 'undo_last' (défaite par un undo_last suivant, retrouvée par son id ; une étape sans
-- id, de la 1.2, par son nom en remontant) ou 'revert' (un revert_to_original suivant a remis la
-- photo).
function Conversation.etapes(c, photo)
    local cle = Conversation.clePhoto(photo)
    local liste = {}
    local function marquer(test, motif)
        for k = #liste, 1, -1 do
            local x = liste[k]
            if not x.annulee and not x.enCours and test(x) then
                x.annulee = motif
                return true
            end
        end
        return false
    end
    for i, e in ipairs(type(c) == 'table' and c.elements or {}) do
        if e.genre == 'outil' and e.etat ~= 'erreur' then
            local info = Conversation.infoEtape(e)
            if Conversation.estEtape(e) then
                if #info.etapes == 0 then
                    liste[#liste + 1] = { element = i, elementId = e.id, photo = photo, outil = e.outil, etape = info.etape,
                        raison = info.raison, changements = {}, enCours = true }
                end
                for _, x in ipairs(info.etapes) do
                    if Conversation.clePhoto(x.photo) == cle then
                        liste[#liste + 1] = { element = i, elementId = e.id, photo = x.photo, id = x.id, nom = x.nom, fichier = x.fichier,
                            etape = info.etape, raison = info.raison, outil = e.outil, ancienne = info.ancienne,
                            changements = (#(x.changements or {}) > 0 or #info.etapes > 1) and (x.changements or {}) or (e.changements or {}) }
                    end
                end
            end
            -- Par le nom, seulement une étape sans id (conversation de la 1.2) : une étape qui a un
            -- id l'aurait rendu à son annulation. Un undo_last qui défait une étape absente de ce
            -- fil (faite par Claude Desktop, une série, une note posée) ne marque donc pas une
            -- étape du même nom.
            for _, a in ipairs(info.annule) do
                if Conversation.clePhoto(a.photo) == cle then
                    local nom = Conversation.nomEtape(a.nom)
                    local trouvee = a.id and marquer(function(x) return x.id == a.id end, 'undo_last')
                    if not trouvee and nom ~= '' then
                        marquer(function(x) return x.id == nil and Conversation.nomEtape(x.nom or x.etape) == nom end, 'undo_last')
                    end
                end
            end
            for _, p in ipairs(info.revenu) do
                if Conversation.clePhoto(p) == cle then
                    for _, x in ipairs(liste) do
                        if not x.annulee and not x.enCours then
                            x.annulee = 'revert'
                        end
                    end
                end
            end
        end
    end
    return liste
end

-- Les photos des étapes d'un élément, dans l'ordre de la réponse (sans doublon).
function Conversation.photosEtape(e)
    local photos, vues = {}, {}
    for _, x in ipairs(Conversation.infoEtape(e).etapes) do
        local cle = Conversation.clePhoto(x.photo)
        if not vues[cle] then
            vues[cle] = true
            photos[#photos + 1] = x.photo
        end
    end
    return photos
end

-- Événements de Claude Code -------------------------------------------------------------------

local function dernier(c)
    return c.elements[#c.elements]
end

local function dernierIndice(c, test)
    for i = #c.elements, 1, -1 do
        if test(c.elements[i]) then
            return i
        end
    end
    return nil
end

local function premiereLigne(texte)
    for _, ligne in ipairs(Texte.lignes(texte)) do
        local propre = Texte.nettoyer(ligne:gsub('^#+', ''):gsub('%*%*', ''))
        if propre ~= '' then
            return propre
        end
    end
    return ''
end

-- Applique un événement (Evenements.lua) au fil. `enregistrerImage(image)` range une image
-- ({ donnees, type }) et rend son chemin relatif (nil : image ignorée).
function Conversation.appliquer(c, ev, date, enregistrerImage)
    date = date or os.time()
    enregistrerImage = enregistrerImage or function() return nil end
    local genre = ev.genre
    if genre == 'init' then
        if ev.session ~= '' then
            c.sessionID = ev.session
        end
    elseif genre == 'partiel' then
        local d = dernier(c)
        if d and d.genre == 'claude' and d.partiel then
            d.texte = d.texte .. ev.texte
        else
            c.elements[#c.elements + 1] = nouvelElement('claude', { texte = ev.texte, partiel = true }, date)
        end
        -- Le titre change dès que son marqueur est arrivé, avant la fin du message.
        Conversation.poserTitre(c, dernier(c).texte)
    elseif genre == 'assistant' then
        for _, bloc in ipairs(ev.blocs) do
            if bloc.genre == 'texte' then
                Conversation.poserTitre(c, bloc.texte)
                local texte = Conversation.retirerMarqueur(bloc.texte)
                local d = dernier(c)
                if d and d.genre == 'claude' and d.partiel then
                    if texte == '' then
                        c.elements[#c.elements] = nil
                    else
                        d.texte = texte
                        d.partiel = false
                    end
                elseif texte ~= '' then
                    c.elements[#c.elements + 1] = nouvelElement('claude', { texte = texte }, date)
                end
            elseif bloc.genre == 'outil' then
                local court = bloc.nom
                if court:sub(1, #Conversation.PREFIXE_OUTILS) == Conversation.PREFIXE_OUTILS then
                    court = court:sub(#Conversation.PREFIXE_OUTILS + 1)
                end
                local ok, detail = pcall(Json.encode, bloc.entree)
                local champs = { texte = Conversation.resumeOutil(court, bloc.entree), outil = court, appel = bloc.id, etat = 'enCours',
                    detail = ok and detail or '' }
                -- Un outil qui écrit une étape (1.3) : sa raison et son but, et la liste de ses
                -- étapes, remplie à la réponse ; rien pour une proposition seulement (preview).
                local entree = type(bloc.entree) == 'table' and bloc.entree or {}
                if Conversation.OUTILS_ETAPES[court] and entree.preview ~= true then
                    champs.raison, champs.etape, champs.etapes = chaine(entree.reason), chaine(entree.step_name), {}
                end
                c.elements[#c.elements + 1] = nouvelElement('outil', champs, date)
                if court == 'preview_settings' then
                    local raison = type(bloc.entree.reason) == 'string' and bloc.entree.reason
                        or (type(bloc.entree.step_name) == 'string' and bloc.entree.step_name) or ''
                    -- Une proposition de recadrage (1.3, Composition lue) : Ajuster… propose les
                    -- ajustements du cadre ; un recadrage retiré n'en est pas une.
                    local recadrage = type(entree.crop) == 'table' and entree.crop.reset ~= true or nil
                    c.elements[#c.elements + 1] = nouvelElement('proposition', { texte = raison, outil = court, appel = bloc.id,
                        etat = 'enAttente', changements = Conversation.changementsDemandes(bloc.entree), recadrage = recadrage,
                        photo = tonumber(entree.photo_id) }, date)
                elseif court == 'propose_ratings' then
                    -- Les notes sont dans l'entrée : visibles dans le fil avant la réponse. Le
                    -- standard seul (read_standard sans ratings) ne range rien ; avec des ratings,
                    -- le connecteur les range aussi.
                    local notes = Conversation.notesDemandees(bloc.entree)
                    if #notes > 0 then
                        c.elements[#c.elements + 1] = nouvelElement('notation', { outil = court, appel = bloc.id, etat = 'enCours',
                            passe = tonumber(bloc.entree.pass), pose = bloc.entree.apply == true or nil, notes = notes }, date)
                    end
                end
            end
        end
    elseif genre == 'resultats' then
        for _, r in ipairs(ev.resultats) do
            local chemins = {}
            for _, image in ipairs(r.images) do
                local chemin = enregistrerImage(image)
                if chemin then
                    chemins[#chemins + 1] = chemin
                end
            end
            local i = dernierIndice(c, function(e) return e.genre == 'outil' and e.appel == r.idOutil end)
            if i then
                local e = c.elements[i]
                e.etat = r.erreur and 'erreur' or 'fait'
                local reponse = table.concat(r.textes, '\n')
                e.detail = (e.detail or '') .. '\n\n— Réponse —\n' .. (reponse == '' and '(images seulement)' or reponse)
                -- Les étapes écrites (1.3), les étapes défaites (undo_last), les photos remises
                -- (revert_to_original) : lues dans la réponse, toujours en tableau.
                if not r.erreur then
                    if e.etapes ~= nil then
                        e.etapes = Conversation.etapesLues(r.textes)
                        e.changements = Conversation.changementsLus(r.textes) or {}
                        -- Une proposition encore en attente sur ces photos n'attend plus (1.3.2).
                        Conversation.clorePropositions(c, i, r.textes)
                    elseif e.outil == 'undo_last' then
                        e.annule = Conversation.annulationsLues(r.textes)
                    elseif e.outil == 'revert_to_original' then
                        e.revenu = Conversation.retoursLus(r.textes)
                    end
                end
            end
            local p = dernierIndice(c, function(e) return e.genre == 'proposition' and e.appel == r.idOutil end)
            local n = dernierIndice(c, function(e) return e.genre == 'notation' and e.appel == r.idOutil end)
            if n then
                Conversation.completerNotation(c.elements[n], r)
            end
            if p then
                local e = c.elements[p]
                e.images = chemins
                local lus = Conversation.changementsLus(r.textes)
                if lus then
                    e.changements = lus
                end
                -- Le cadre que Lightroom a gardé (1.3, Composition lue), en mots : la carte
                -- Proposition le dit à la place des bords du recadrage.
                if not r.erreur then
                    local cadre, dessine = Conversation.cadreLu(r.textes)
                    e.cadre, e.cadreDessine = cadre, cadre and dessine or nil
                    -- Sa photo, sans photo_id dans l'entrée (la photo active) : celle de la réponse.
                    e.photo = e.photo or Conversation.photoLue(r.textes)
                end
                if r.erreur then
                    e.etat = 'refusee'
                    e.texte = "Proposition impossible : " .. table.concat(r.textes, ' ')
                end
            elseif #chemins > 0 then
                c.elements[#c.elements + 1] = nouvelElement('apercu', { appel = r.idOutil, images = chemins }, date)
            end
        end
    elseif genre == 'fin' then
        local gardes = {}
        for _, e in ipairs(c.elements) do
            if e.partiel then
                e.texte = Conversation.texteAffiche(e)
                e.partiel = false
            end
            if (e.genre == 'outil' or e.genre == 'notation') and e.etat == 'enCours' then
                e.etat = ev.interrompue and 'erreur' or 'fait'
            end
            if not (e.genre == 'claude' and (e.texte or '') == '') then
                gardes[#gardes + 1] = e
            end
        end
        c.elements = gardes
        if ev.session ~= '' then
            c.sessionID = ev.session
        end
        if ev.interrompue then
            c.elements[#c.elements + 1] = nouvelElement('note', { texte = "Interrompu à votre demande." }, date)
        elseif not ev.reussie then
            c.elements[#c.elements + 1] = nouvelElement('note', { texte = "Claude a rencontré une erreur" .. (ev.texte and (" : " .. ev.texte) or ".") }, date)
        end
        local i = dernierIndice(c, function(e) return e.genre == 'claude' end)
        if i then
            c.resume = Texte.raccourcir(premiereLigne(c.elements[i].texte), 90)
        end
        c.modifiee = date
    end
end

-- Une note de la fenêtre (erreur de lancement, arrêt de Claude Code…).
function Conversation.ajouterNote(c, texte, date)
    c.elements[#c.elements + 1] = nouvelElement('note', { texte = texte }, date)
end

-- Marque une proposition (Accepter / Refuser).
function Conversation.decider(c, id, acceptee)
    for _, e in ipairs(c.elements) do
        if e.id == id then
            e.etat = acceptee and 'acceptee' or 'refusee'
        end
    end
end

-- Marque un élément (une proposition) ; vrai s'il
-- existe.
function Conversation.marquer(c, id, etat)
    for _, e in ipairs(c.elements) do
        if e.id == id then
            e.etat = etat
            return true
        end
    end
    return false
end

function Conversation.propositionEnAttente(c)
    local i = dernierIndice(c, function(e) return e.genre == 'proposition' and e.etat == 'enAttente' end)
    return i and c.elements[i] or nil
end

-- Une proposition dépassée par Claude (1.3.2) ---------------------------------------------------
-- Constaté le 22 octobre 2026 : la proposition préparée à l'ouverture attendait dans l'onglet
-- Proposition ; Dany a écrit « Applique ta proposition, puis termine par la leçon de la photo »
-- (la leçon, retirée au correctif 1.3.6), Claude a posé les mêmes réglages par apply_settings,
-- puis la leçon ; la carte offrait toujours Accepter (un clic les aurait posés une seconde fois),
-- et la leçon ne s'ouvrait pas (une proposition attendait). Règle : dès qu'un outil d'étape qui
-- change l'image (Conversation.OUTILS_ETAPES, sauf les classements, qui ne la changent pas) écrit
-- une étape sur la photo d'une proposition en attente arrivée avant lui (sur n'importe laquelle de
-- ses photos quand celle de la proposition n'est pas connue), elle n'attend plus : 'appliquee' si cette
-- première étape pose chacun de ses réglages à la même valeur (clé et valeur d'après, telles que
-- les deux réponses les disent ; il en faut au moins un de lu), sinon 'remplacee'. Accepter,
-- Refuser et Ajuster… ne s'offrent plus (Conversation.propositionEnAttente ne la rend plus) ; la
-- carte dit pourquoi (Conversation.propositionClose). Une proposition acceptée, refusée, ajustée
-- ou faite par Dany garde son état.

-- Les états d'une proposition close par Claude, et leur phrase (la carte Proposition, le fil).
Conversation.ETATS_CLAUDE = {
    appliquee = "Appliquée par Claude",
    remplacee = "Remplacée par une retouche de Claude",
}

-- La photo que dit une réponse du connecteur (son champ photo : { id, fichier } ou un
-- identifiant), nil sans elle.
function Conversation.photoLue(textes)
    for _, texte in ipairs(textes or {}) do
        local json = Conversation.teteJson(texte)
        if type(json) == 'table' and json.photo ~= nil and json.photo ~= Json.null then
            local photo = photoDe(json)
            if photo ~= nil then
                return photo
            end
        end
    end
    return nil
end

-- Vrai si `changements` (ceux d'une étape) posent chaque réglage lu de la proposition à la même
-- valeur ; faux sans réglage lu (rien à comparer).
local function memesReglages(prop, changements)
    local poses = {}
    for _, ch in ipairs(changements or {}) do
        if type(ch.cle) == 'string' then
            poses[ch.cle] = ch.apres
        end
    end
    local lus = 0
    for _, ch in ipairs(prop.changements or {}) do
        if type(ch.cle) == 'string' then
            lus = lus + 1
            if poses[ch.cle] ~= ch.apres then
                return false
            end
        end
    end
    return lus > 0
end

-- Les photos que match_series a harmonisées, lues dans sa réponse (`textes`) : sa réponse ne porte
-- pas d'etape_id (SANS_REPERE_EN_COURS), mais chaque élément de `photos` écrit porte ses étapes,
-- `etapes` (par la mesure) ou `etape` (by = exif) ; un plan (sans confirm), une photo déjà proche
-- de la référence et la référence elle-même n'en ont pas. Rend { photo, nom, changements = {} }
-- (les réglages relatifs de match_series ne se comparent pas à ceux d'une proposition).
function Conversation.photosHarmonisees(textes)
    local lues = {}
    for _, texte in ipairs(textes or {}) do
        local json = Conversation.teteJson(texte)
        for _, x in ipairs(type(json) == 'table' and type(json.photos) == 'table' and json.photos or {}) do
            if type(x) == 'table' then
                local nom = chaine(x.etape) or (type(x.etapes) == 'table' and chaine(x.etapes[1])) or nil
                local photo = tonumber(x.id) or chaine(x.id)
                if nom and photo ~= nil then
                    lues[#lues + 1] = { photo = photo, nom = nom, changements = {} }
                end
            end
        end
    end
    return lues
end

-- L'élément i (un outil dont la réponse vient d'arriver, `textes`) clôt les propositions en attente
-- arrivées avant lui sur les photos de ses étapes (celles que match_series a harmonisées :
-- Conversation.photosHarmonisees). Une proposition sans photo connue (enregistrée avant le
-- correctif 1.3.2, ou dont la réponse n'a pas dit sa photo) attend, comme avant le correctif :
-- une étape sur une autre photo la clorait à tort. Rend leur nombre.
function Conversation.clorePropositions(c, i, textes)
    local e = c and c.elements[i]
    if not (e and e.genre == 'outil' and e.etat ~= 'erreur' and Conversation.OUTILS_ETAPES[e.outil]
        and not Conversation.CLASSEMENTS[e.outil]) then
        return 0
    end
    local etapes = e.etapes or {}
    if e.outil == 'match_series' then
        etapes = Conversation.photosHarmonisees(textes)
    end
    if #etapes == 0 then
        return 0
    end
    -- La première étape de chaque photo, avec ses réglages (ceux de toute la réponse pour une
    -- seule étape qui ne dit pas les siens, comme Conversation.etapes).
    local parPhoto = {}
    for _, x in ipairs(etapes) do
        local cle = Conversation.clePhoto(x.photo)
        if not parPhoto[cle] then
            local propres = #(x.changements or {}) > 0 or #etapes > 1
            parPhoto[cle] = { nom = x.nom, changements = propres and (x.changements or {}) or (e.changements or {}) }
        end
    end
    local closes = 0
    for k = i - 1, 1, -1 do
        local p = c.elements[k]
        if p.genre == 'proposition' and p.etat == 'enAttente' and p.photo ~= nil then
            local etape = parPhoto[Conversation.clePhoto(p.photo)]
            if etape then
                p.etat = memesReglages(p, etape.changements) and 'appliquee' or 'remplacee'
                local nom = Conversation.nomEtape(etape.nom or e.etape)
                p.etapeClaude = nom ~= '' and nom or nil
                closes = closes + 1
            end
        end
    end
    return closes
end

-- La dernière proposition du fil si une étape de Claude l'a close ('appliquee', 'remplacee') ;
-- nil sinon (aucune, ou la dernière en attente, décidée par Dany, faite par lui).
function Conversation.propositionClose(c)
    local i = dernierIndice(c, function(e) return e.genre == 'proposition' end)
    local e = i and c.elements[i]
    return e and Conversation.ETATS_CLAUDE[e.etat] and e or nil
end

-- Images de la conversation, dans l'ordre du fil : { chemin, element (indice), outil }.
function Conversation.images(c)
    local liste = {}
    for i, e in ipairs(c.elements) do
        for _, chemin in ipairs(e.images or {}) do
            local outil
            if e.appel then
                local j = dernierIndice(c, function(x) return x.genre == 'outil' and x.appel == e.appel end)
                outil = j and c.elements[j].outil
            end
            liste[#liste + 1] = { chemin = chemin, element = i, outil = outil or (e.genre == 'dany' and 'jointe') }
        end
    end
    return liste
end

-- Le dernier zoom d'une photo dans la conversation (1.3, « Voir à 100 % » de la carte Note : le
-- zoom que Claude a pris pour la noter) : l'image la plus récente d'un appel réussi de view_photo
-- avec `region`, sur cette photo (son photo_id ; sans lui, la photo que dit la réponse). Un aperçu
-- entier (sans region), une comparaison (compare) ou une autre photo n'en sont pas. Lecture pure :
-- rien n'est demandé à Lightroom ni à Claude. Rend { chemin (relatif au dossier de la
-- conversation), element (indice de l'aperçu dans le fil), appel, zone (la region) }, nil sans
-- zoom de cette photo.
function Conversation.dernierZoom(c, photo)
    if not c or photo == nil then
        return nil
    end
    local cle = Conversation.clePhoto(photo)
    for i = #(c.elements or {}), 1, -1 do
        local e = c.elements[i]
        if e.genre == 'apercu' and e.appel ~= nil and #(e.images or {}) > 0 then
            local outil = Conversation.outilDeLAppel(c, e.appel)
            if outil and outil.outil == 'view_photo' and outil.etat ~= 'erreur' then
                -- L'entrée seule d'abord (petite) ; la réponse, plus longue, seulement sans photo_id.
                local texteEntree, reponse = tostring(outil.detail or ''):match('^(.-)\n\n— Réponse —\n(.*)$')
                local lu, entree = pcall(Json.decode, texteEntree or '')
                entree = lu and type(entree) == 'table' and entree or nil
                if entree and type(entree.region) == 'table' then
                    local quelle = entree.photo_id
                    if quelle == nil then
                        local tete = Conversation.teteJson(reponse)
                        quelle = type(tete) == 'table' and type(tete.photo) == 'table' and tete.photo.id or nil
                    end
                    if quelle ~= nil and Conversation.clePhoto(quelle) == cle then
                        local zone = {}
                        for _, k in ipairs({ 'x', 'y', 'width', 'height' }) do
                            zone[k] = tonumber(entree.region[k])
                        end
                        return { chemin = e.images[#e.images], element = i, appel = e.appel, zone = zone }
                    end
                end
            end
        end
    end
    return nil
end

-- Nombre d'outils terminés depuis la dernière demande.
-- Les photos que vise un appel d'outil, d'après son entrée (la partie de `detail` avant la
-- réponse) : photo_id, photo_ids, ou les photo_id de ratings ; chacune une fois, dans l'ordre. Lu
-- une fois par élément (l'entrée ne change plus).
local ciblesLues = setmetatable({}, { __mode = 'k' })

local function cibles(e)
    local deja = ciblesLues[e]
    if deja then
        return deja
    end
    local liste, vues = {}, {}
    local function ajouter(id)
        id = tonumber(id)
        if id and not vues[id] then
            vues[id] = true
            liste[#liste + 1] = id
        end
    end
    local texte = tostring(e.detail or '')
    local ok, entree = pcall(Json.decode, texte:match('^(.-)\n\n— Réponse —\n') or texte)
    if ok and type(entree) == 'table' then
        ajouter(entree.photo_id)
        if type(entree.photo_ids) == 'table' then
            for _, id in ipairs(entree.photo_ids) do
                ajouter(id)
            end
        end
        if type(entree.ratings) == 'table' then
            for _, r in ipairs(entree.ratings) do
                if type(r) == 'table' then
                    ajouter(r.photo_id)
                end
            end
        end
    end
    ciblesLues[e] = liste
    return liste
end

-- La tranche d'une série que montre une planche contact, d'après sa réponse (`planche` : positions
-- dans la série, vidéos comprises, et son total) ; nil avant la réponse ou sans elle.
local planchesLues = setmetatable({}, { __mode = 'k' })

local function planche(e)
    if e.outil ~= 'contact_sheet' then
        return nil
    end
    local deja = planchesLues[e]
    if deja ~= nil then
        return deja or nil
    end
    local reponse = tostring(e.detail or ''):match('\n\n— Réponse —\n(.*)$')
    if not reponse then
        return nil
    end
    local ok, r = pcall(Json.decode, reponse)
    local p = ok and type(r) == 'table' and type(r.planche) == 'table' and r.planche or {}
    local premier, dernier, total = tonumber(p.premiere), tonumber(p.derniere), tonumber(p.sur)
    planchesLues[e] = premier and dernier and total and { premier = premier, dernier = math.min(dernier, total), total = total } or false
    return planchesLues[e] or nil
end

-- Où en est le tour de Claude dans les photos, pour la ligne d'état (demandé par Dany le 26 octobre
-- 2026 : « sur quelle photo de la sélection il travaille ») : la photo que vise le dernier outil du
-- tour, s'il n'en vise qu'une, avec son rang dans l'ordre où le tour a visé les photos la première
-- fois ; sinon la dernière planche contact du tour (le parcours d'une grande série : Claude note la
-- planche après l'avoir vue), avec son total ; sinon les photos que vise le dernier outil. Rend
-- { premier, dernier, nombre, id } (`id` : une seule photo ; `total` : celui d'une planche), ou nil
-- (un dernier outil qui ne nomme aucune photo : la photo active, la sélection entière).
function Conversation.photosEnCours(c)
    local debut = #c.elements + 1
    for i = #c.elements, 1, -1 do
        if c.elements[i].genre == 'dany' then
            break
        end
        debut = i
    end
    local rangs, n, derniere, tranche = {}, 0, nil, nil
    for i = debut, #c.elements do
        local e = c.elements[i]
        if e.genre == 'outil' then
            derniere = cibles(e)
            tranche = planche(e) or tranche
            for _, id in ipairs(derniere) do
                if not rangs[id] then
                    n = n + 1
                    rangs[id] = n
                end
            end
        end
    end
    if tranche and not (derniere and #derniere == 1) then
        return { premier = tranche.premier, dernier = tranche.dernier, nombre = tranche.dernier - tranche.premier + 1, total = tranche.total }
    end
    if not derniere or #derniere == 0 then
        return nil
    end
    local premier, dernier = math.huge, 0
    for _, id in ipairs(derniere) do
        premier, dernier = math.min(premier, rangs[id]), math.max(dernier, rangs[id])
    end
    return { premier = premier, dernier = dernier, nombre = #derniere, id = #derniere == 1 and derniere[1] or nil }
end

function Conversation.outilsFaits(c)
    local n = 0
    for i = #c.elements, 1, -1 do
        local e = c.elements[i]
        if e.genre == 'dany' then
            break
        end
        if e.genre == 'outil' and e.etat ~= 'enCours' then
            n = n + 1
        end
    end
    return n
end

return Conversation
