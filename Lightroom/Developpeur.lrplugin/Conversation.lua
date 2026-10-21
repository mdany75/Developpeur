-- Conversation.lua : une conversation de la fenêtre = une session Claude Code, reprise par
-- `--resume` : des éléments `dany`, `claude`, `outil`, `apercu`, `proposition`, `notation`,
-- `lecon` (1.3), `exercice` (1.3) et `note`, dans l'ordre du fil. Les dates sont en secondes Unix.
-- Une conversation des anciennes séances de notation (genre = 'notation', fenêtre retirée le
-- 20 octobre 2026) reste sur le disque mais ne s'ouvre plus.
--
-- Élément : id, genre, texte, date, outil, appel, etat ('enCours', 'fait', 'erreur', 'enAttente',
-- 'acceptee', 'refusee', 'ajustee', 'faite' : une proposition que Dany fait lui-même, Je le fais,
-- 1.3), detail, images (chemins relatifs au dossier de la
-- conversation), changements ({ cle, libelle, avant, apres }), partiel (texte en train
-- d'arriver) ; pour une notation : passe, pose (notes posées à la demande de Dany :
-- propose_ratings avec apply), notes (voir Conversation.notesDemandees). Pour un outil qui écrit
-- une étape (1.3, Conversation.OUTILS_ETAPES) : raison (reason de l'entrée), etape (step_name),
-- etapes (les étapes écrites, lues dans la réponse : { photo, id, nom, fichier, changements }) ;
-- pour undo_last : annule ({ photo, id, nom } de chaque étape défaite) ; pour
-- revert_to_original : revenu (les photos remises). Une conversation de la 1.2 n'a ni raison, ni
-- etape, ni etapes : elles se relisent dans `detail` (Conversation.infoEtape), sans id.
-- Un élément `lecon` (1.3) suit un appel de photo_lesson avec ses points (jamais read_facts seul),
-- pour le fil seulement (la leçon est rangée par le module, carnet.json) : photo, points (dans
-- l'ordre Lumière, Couleur, Composition : { axe, nom, manque, prise_de_vue, defauts }), puis
-- d'après la réponse : fichier, rangee, remplacee, mois, remarque (« Leçon non rangée… ») ; en
-- erreur, la raison dans texte.
-- Un élément `exercice` (1.3, « Je le fais ») suit un appel de preview_settings avec my_turn, à la
-- place d'une proposition (rien n'est appliqué : Dany fait la retouche lui-même) : photo, fichier,
-- appel, etat ('enCours' jusqu'à la liste, 'aFaire', 'comparee', 'erreur'), aFaire (la liste du
-- connecteur, dans l'ordre du panneau Développement : { n, panneau, section, reglage, cle, cles,
-- de, a, texte, avant, apres }), instantane ; puis, d'après view_photo avec compare =
-- claude_version : appelComparaison (son appel, gardé ; comparaisonEnCours pendant l'appel),
-- ecarts ({ cle, panneau, reglage, sorte, texte }), commeClaude, resume, principal ({ visible, texte }),
-- aSavoir ; en erreur, la raison dans texte ; signatures (les tables au départ du suivi, pour cocher
-- ce qui a bougé : Fenetre.suivreExercice).

require 'Compat'
local Consignes = require 'Consignes'
local Json = require 'Json'
local Texte = require 'Texte'

local Conversation = {}

Conversation.PREFIXE_OUTILS = 'mcp__developpeur__'
Conversation.TITRE_PAR_DEFAUT = "Nouvelle conversation"
-- Genre d'une conversation des anciennes séances de notation (absent pour une retouche).
Conversation.GENRE_SEANCE = 'notation'
-- Claude ne propose jamais 5 étoiles (standard de notation) : une note lue au-dessus est ramenée.
Conversation.NOTE_MAXIMALE = 4

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
    if titre == '' or (titre:sub(1, 1) == '<' and titre:sub(-1) == '>') then
        return nil
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
    if c.titreChoisi ~= true and c.titreAuto ~= true and demandes == 1 then
        c.titre = Conversation.titreDepuis(texte)
    end
    c.modifiee = date
end

-- Renomme ; un titre vide ne change rien (rend false).
function Conversation.renommer(c, nouveau)
    local propre = Texte.nettoyer(nouveau)
    if propre == '' then
        return false
    end
    c.titre = propre
    c.titreChoisi = true
    return true
end

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

-- Le texte envoyé à Claude : la ligne de contexte de Lightroom, celle du style choisi, celle de la
-- leçon (« [Sans leçon] », case Leçon décochée), la demande, et tant que la conversation n'a pas de
-- titre tiré d'une photo ni choisi, le rappel du titre.
function Conversation.messagePourClaude(c, demande, contexte, ligneStyle, ligneLecon)
    local morceaux = {}
    if contexte and contexte ~= '' then
        morceaux[#morceaux + 1] = contexte
    end
    if ligneStyle and ligneStyle ~= '' then
        morceaux[#morceaux + 1] = ligneStyle
    end
    if ligneLecon and ligneLecon ~= '' then
        morceaux[#morceaux + 1] = ligneLecon
    end
    morceaux[#morceaux + 1] = demande
    if c.titreAuto ~= true and c.titreChoisi ~= true then
        morceaux[#morceaux + 1] = Consignes.rappelTitre
    end
    return table.concat(morceaux, '\n\n')
end

-- Recherche : chaque mot doit se trouver dans le titre, le résumé, les messages ou les leçons (sans
-- tenir compte des majuscules ni des accents). Une recherche vide garde tout.
function Conversation.correspond(c, recherche)
    local mots = {}
    for mot in Texte.plier(recherche):gmatch('%S+') do
        mots[#mots + 1] = mot
    end
    if #mots == 0 then
        return true
    end
    local textes = { c.titre or '', c.resume or '' }
    for _, e in ipairs(c.elements or {}) do
        if e.genre == 'dany' or e.genre == 'claude' then
            textes[#textes + 1] = e.texte or ''
        elseif e.genre == 'lecon' then
            for _, p in ipairs(type(e.points) == 'table' and e.points or {}) do
                if type(p) == 'table' then
                    textes[#textes + 1] = table.concat({ tostring(p.nom or ''), tostring(p.manque or ''), tostring(p.prise_de_vue or '') }, '\n')
                end
            end
        end
    end
    local botte = Texte.plier(table.concat(textes, '\n'))
    for _, mot in ipairs(mots) do
        if not botte:find(mot, 1, true) then
            return false
        end
    end
    return true
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

-- Changements d'une proposition, d'après ce que Claude demande (avant inconnu).
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
--   { photo, note (0 à 4) | nil, drapeau ('rejetee') | nil, criteres = { impact, qualites, plancher,
--     finition }, raison, a_verifier, etat = 'demandee' }
-- puis, d'après la réponse du connecteur : fichier, note_avant, drapeau_avant, etat 'proposee' ou
-- 'refusee' (refus : la raison). Une note au-dessus de 4 est ramenée à 4 (le connecteur la refuse).
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

-- Leçon de la photo (1.3) ---------------------------------------------------------------------
-- Un élément `lecon` suit un appel de photo_lesson qui donne ses points : la carte « Leçon de la
-- photo » du fil (Fil.lua) se fait de l'entrée de l'outil, visible avant la réponse, puis la
-- réponse du connecteur dit le fichier et si la leçon est rangée. Les faits mesurés restent dans
-- le détail de l'appel (un clic sur la carte l'ouvre). read_facts seul (les faits sans points) ne
-- fait pas de carte.

-- Les trois axes, dans l'ordre de la carte (clés de photo_lesson).
Conversation.AXES_LECON = {
    { cle = 'light', nom = "Lumière" },
    { cle = 'color', nom = "Couleur" },
    { cle = 'composition', nom = "Composition" },
}

-- Une moitié de point sur une ligne, sans gras ni code Markdown ; nil si elle est vide.
local function textePoint(v)
    if type(v) ~= 'string' then
        return nil
    end
    local t = Texte.nettoyer((v:gsub('%*%*', ''):gsub('`', ''):gsub('%s+', ' ')))
    return t ~= '' and t or nil
end

-- Les points demandés par Claude (entrée de photo_lesson), en tables neuves, dans l'ordre des axes
-- (Conversation.AXES_LECON) : { axe, nom, manque (nil : rien ne manquait), prise_de_vue, defauts }.
-- Un axe inconnu est écarté ; un axe donné deux fois garde son premier point (le connecteur refuse
-- l'appel, la carte passe en erreur).
function Conversation.leconDemandee(entree)
    entree = type(entree) == 'table' and entree or {}
    local parAxe = {}
    for _, p in ipairs(type(entree.points) == 'table' and entree.points or {}) do
        if type(p) == 'table' and type(p.axis) == 'string' and not parAxe[p.axis] then
            local defauts = {}
            for _, d in ipairs(type(p.defects) == 'table' and p.defects or {}) do
                if type(d) == 'string' and d ~= '' then
                    defauts[#defauts + 1] = d
                end
            end
            parAxe[p.axis] = { manque = textePoint(p.missing), prise_de_vue = textePoint(p.at_capture) or '', defauts = defauts }
        end
    end
    local points = {}
    for _, axe in ipairs(Conversation.AXES_LECON) do
        local p = parAxe[axe.cle]
        if p then
            points[#points + 1] = { axe = axe.cle, nom = axe.nom, manque = p.manque, prise_de_vue = p.prise_de_vue, defauts = p.defauts }
        end
    end
    return points
end

-- La réponse du connecteur à photo_lesson (`lecon` : photo, fichier, rangee, remplacee, mois ;
-- `remarques`) : { photo, fichier, rangee, remplacee, mois, remarque }, nil sans. `remarque` : la
-- remarque du connecteur sur le rangement (« Leçon non rangée… », « Leçon gardée pour cette
-- session… »), jamais celles des défauts mesurés, qui sont pour Claude.
function Conversation.leconLue(textes)
    for _, texte in ipairs(textes or {}) do
        local ok, json = pcall(Json.decode, texte)
        if ok and type(json) == 'table' and type(json.lecon) == 'table' then
            local l = json.lecon
            local lue = { photo = type(l.photo) == 'number' and l.photo or nil, fichier = chaine(l.fichier), rangee = l.rangee == true,
                remplacee = l.remplacee == true, mois = chaine(l.mois) }
            for _, r in ipairs(type(json.remarques) == 'table' and json.remarques or {}) do
                local t = chaine(r)
                if t and t:sub(1, #"Leçon ") == "Leçon " then
                    lue.remarque = t
                    break
                end
            end
            return lue
        end
    end
    return nil
end

-- Complète un élément `lecon` par le résultat de son appel : refusé (erreur du connecteur, la
-- raison dans texte), ou fait, avec le fichier et le rangement lus dans la réponse.
function Conversation.completerLecon(e, r)
    if r.erreur then
        e.etat = 'erreur'
        e.texte = Texte.nettoyer((table.concat(r.textes or {}, ' '):gsub('%s+', ' ')))
        return
    end
    e.etat = 'fait'
    local lue = Conversation.leconLue(r.textes)
    if lue then
        e.photo = lue.photo or e.photo
        e.fichier = lue.fichier or e.fichier
        e.rangee, e.remplacee, e.mois, e.remarque = lue.rangee, lue.remplacee, lue.mois, lue.remarque
    end
end

-- L'élément `outil` de l'appel `appel` (le dernier), nil sans appel ni élément : le détail d'une
-- carte (leçon) est celui de son appel.
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
-- (`etape_id` : celui de ses images avant/après, Etapes.lua). L'onglet Pourquoi ? de la fenêtre
-- les montre, photo par photo, dans l'ordre du fil (Conversation.etapes). Un outil appelé en
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
-- étapes de sa réponse ; ou en cours, avec son but (step_name). Sa ligne du fil porte
-- « · Pourquoi ? ».
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

-- Je le fais (1.3) ----------------------------------------------------------------------------
-- Dany fait la retouche lui-même, pour apprendre. preview_settings avec my_turn range la version de
-- Claude sans rien appliquer et rend a_faire, la liste des réglages dans l'ordre du panneau
-- Développement : un élément `exercice` à la place d'une proposition (rien à accepter). Quand Dany
-- a fini, view_photo avec compare = claude_version rend les deux versions côte à côte et
-- `exercice` : les écarts réglage par réglage et l'écart principal, notés sur l'exercice de la
-- photo. Le registre reste le module (mémoire variantesClaude) : l'élément ne sert qu'à la fenêtre.

-- Une valeur de la liste : nombre, texte ou booléen ; les autres (null, table) ne se gardent pas.
local function valeurSimple(v)
    local t = type(v)
    if t == 'number' or t == 'string' or t == 'boolean' then
        return v
    end
    return nil
end

-- Une valeur d'avant ou d'après : simple, ou (le cadre) une table neuve de valeurs simples par clé.
local function valeurListe(v)
    if type(v) ~= 'table' or v == Json.null then
        return valeurSimple(v)
    end
    local t = {}
    for cle, x in pairs(v) do
        if type(cle) == 'string' then
            t[cle] = valeurSimple(x)
        end
    end
    return t
end

-- Une liste de textes en table neuve (sans les autres valeurs).
local function textes(liste)
    local t = {}
    for _, x in ipairs(type(liste) == 'table' and liste or {}) do
        local s = chaine(x)
        if s then
            t[#t + 1] = s
        end
    end
    return t
end

-- La liste « à faire » du connecteur, en tables neuves, dans l'ordre reçu.
local function lireAFaire(liste)
    local lus = {}
    for _, x in ipairs(liste) do
        if type(x) == 'table' and chaine(x.cle) then
            local cles = type(x.cles) == 'table' and textes(x.cles) or nil
            lus[#lus + 1] = { n = tonumber(x.n) or (#lus + 1), panneau = chaine(x.panneau), section = chaine(x.section),
                reglage = chaine(x.reglage) or chaine(x.cle), cle = chaine(x.cle), cles = cles and #cles > 0 and cles or nil,
                de = chaine(x.de) or '', a = chaine(x.a) or '', texte = chaine(x.texte) or chaine(x.cle),
                avant = valeurListe(x.avant), apres = valeurListe(x.apres) }
        end
    end
    return lus
end

-- Les écarts de la comparaison, en tables neuves : { cle, panneau, reglage, sorte, texte }.
local function lireEcarts(liste)
    local lus = {}
    for _, x in ipairs(type(liste) == 'table' and liste or {}) do
        if type(x) == 'table' and (chaine(x.texte) or chaine(x.reglage)) then
            lus[#lus + 1] = { cle = chaine(x.cle), panneau = chaine(x.panneau), reglage = chaine(x.reglage) or chaine(x.cle) or '?',
                sorte = chaine(x.sorte), texte = chaine(x.texte) or chaine(x.reglage) }
        end
    end
    return lus
end

-- La photo d'une réponse (`photo` : { id, fichier }) : id et fichier.
local function photoDeLaReponse(json)
    if type(json.photo) == 'table' and json.photo ~= Json.null then
        return tonumber(json.photo.id), chaine(json.photo.fichier)
    end
    return tonumber(json.photo), nil
end

-- Ce que dit une réponse du connecteur sur un exercice : la liste (preview_settings avec my_turn :
-- { liste = true, aFaire, instantane, photo, fichier }) ou la comparaison (view_photo avec
-- compare = claude_version : { comparaison = true, ecarts, commeClaude, resume, principal,
-- aSavoir, instantane, photo, fichier }) ; nil sans l'une ni l'autre. Un texte qui n'est pas du
-- JSON (réponse d'attente, remarque de l'écran à part) est passé ; une remarque recollée après le
-- JSON est retirée (Conversation.teteJson).
function Conversation.exerciceLu(textesReponse)
    for _, texte in ipairs(textesReponse or {}) do
        local json = Conversation.teteJson(texte)
        if type(json) == 'table' and json ~= Json.null then
            local photo, fichier = photoDeLaReponse(json)
            if type(json.a_faire) == 'table' then
                return { liste = true, aFaire = lireAFaire(json.a_faire), instantane = chaine(json.instantane), photo = photo, fichier = fichier }
            end
            local x = json.exercice
            if type(x) == 'table' and x ~= Json.null then
                local p = type(x.ecart_principal) == 'table' and x.ecart_principal or {}
                return { comparaison = true, ecarts = lireEcarts(x.ecarts), commeClaude = textes(x.comme_claude), resume = chaine(x.resume),
                    principal = { visible = p.visible == true, texte = chaine(p.texte) }, aSavoir = chaine(x.a_savoir_exercice),
                    instantane = chaine(x.instantane), photo = photo, fichier = fichier }
            end
        end
    end
    return nil
end

-- Une raison sur une ligne, d'après les textes d'une réponse.
local function raisonDe(r)
    return Texte.nettoyer((table.concat(r.textes or {}, ' '):gsub('%s+', ' ')))
end

-- Complète un exercice par le résultat d'un de ses appels. La liste (my_turn) : 'aFaire' avec la
-- liste, ou 'erreur' (refus, ou réponse sans liste : la réponse d'attente d'un appel trop long,
-- que Claude rappelle, en fait un autre). La comparaison (claude_version) : 'comparee' avec les
-- écarts, 'erreur' sur un refus (aucune version rangée, module ancien) ; une réponse sans
-- `exercice` (attente) laisse l'exercice à faire.
function Conversation.completerExercice(e, r)
    local comparaison = e.appelComparaison ~= nil and r.idOutil == e.appelComparaison
    if comparaison then
        e.comparaisonEnCours = nil
    end
    if r.erreur then
        e.etat = 'erreur'
        e.texte = (comparaison and "comparaison impossible : " or "") .. raisonDe(r)
        return
    end
    local lu = Conversation.exerciceLu(r.textes)
    if comparaison then
        if lu and lu.comparaison then
            e.etat = 'comparee'
            e.ecarts, e.commeClaude, e.resume, e.principal, e.aSavoir = lu.ecarts, lu.commeClaude, lu.resume, lu.principal, lu.aSavoir
            e.photo, e.fichier = e.photo or lu.photo, e.fichier or lu.fichier
            e.texte = ''
        end
        return
    end
    if lu and lu.liste then
        e.etat = 'aFaire'
        e.aFaire, e.instantane = lu.aFaire, lu.instantane
        e.photo, e.fichier = lu.photo or e.photo, lu.fichier or e.fichier
        e.texte = ''
    else
        e.etat = 'erreur'
        e.texte = "liste non reçue : " .. raisonDe(r)
    end
end

-- Le dernier exercice du fil, sans proposition arrivée après lui (elle prend la carte) ; nil sinon.
function Conversation.dernierExercice(c)
    for i = #(c and c.elements or {}), 1, -1 do
        local e = c.elements[i]
        if e.genre == 'proposition' then
            return nil
        elseif e.genre == 'exercice' then
            return e
        end
    end
    return nil
end

-- L'exercice en cours : le dernier, à faire (sa liste arrivée, pas encore comparé), sans
-- proposition arrivée après lui. Le bouton de la carte dit alors « J'ai fini ».
function Conversation.exerciceEnCours(c)
    local e = Conversation.dernierExercice(c)
    return e and e.etat == 'aFaire' and e or nil
end

-- L'exercice d'une photo (le dernier, hors erreur) ; `photo` nil : le dernier. Une comparaison s'y
-- note ; nil sans exercice de cette photo dans la conversation.
function Conversation.exercicePour(c, photo)
    local cle = photo ~= nil and Conversation.clePhoto(photo) or nil
    for i = #(c and c.elements or {}), 1, -1 do
        local e = c.elements[i]
        if e.genre == 'exercice' and e.etat ~= 'erreur' and (cle == nil or e.photo == nil or Conversation.clePhoto(e.photo) == cle) then
            return e
        end
    end
    return nil
end

-- L'image de la comparaison d'un exercice (Claude à gauche, Dany à droite), en chemin relatif au
-- dossier de la conversation ; nil sans comparaison rendue.
function Conversation.imageComparaison(c, x)
    if not (c and x and x.appelComparaison) then
        return nil
    end
    for i = #c.elements, 1, -1 do
        local e = c.elements[i]
        if e.genre == 'apercu' and e.appel == x.appelComparaison and #(e.images or {}) > 0 then
            return e.images[#e.images]
        end
    end
    return nil
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
                -- La comparaison de « Je le fais » (1.3) : ses images se légendent « Claude | vous »
                -- (Conversation.images), et elle se note sur l'exercice de la photo.
                local comparaison = court == 'view_photo' and entree.compare == 'claude_version'
                if comparaison then
                    champs.comparaison = true
                end
                c.elements[#c.elements + 1] = nouvelElement('outil', champs, date)
                if comparaison then
                    local x = Conversation.exercicePour(c, tonumber(entree.photo_id))
                    if x then
                        x.appelComparaison, x.comparaisonEnCours = bloc.id, true
                    end
                end
                if court == 'preview_settings' and entree.my_turn == true then
                    -- « Je le fais » (1.3) : rien à accepter ; la liste arrive avec la réponse.
                    c.elements[#c.elements + 1] = nouvelElement('exercice', { outil = court, appel = bloc.id, etat = 'enCours',
                        photo = tonumber(entree.photo_id), aFaire = {}, ecarts = {} }, date)
                elseif court == 'preview_settings' then
                    local raison = type(bloc.entree.reason) == 'string' and bloc.entree.reason
                        or (type(bloc.entree.step_name) == 'string' and bloc.entree.step_name) or ''
                    c.elements[#c.elements + 1] = nouvelElement('proposition', { texte = raison, outil = court, appel = bloc.id,
                        etat = 'enAttente', changements = Conversation.changementsDemandes(bloc.entree) }, date)
                elseif court == 'propose_ratings' then
                    -- Les notes sont dans l'entrée : visibles dans le fil avant la réponse. Le
                    -- standard seul (read_standard sans ratings) ne range rien ; avec des ratings,
                    -- le connecteur les range aussi.
                    local notes = Conversation.notesDemandees(bloc.entree)
                    if #notes > 0 then
                        c.elements[#c.elements + 1] = nouvelElement('notation', { outil = court, appel = bloc.id, etat = 'enCours',
                            passe = tonumber(bloc.entree.pass), pose = bloc.entree.apply == true or nil, notes = notes }, date)
                    end
                elseif court == 'photo_lesson' then
                    -- La carte de la leçon, faite de l'entrée ; les faits seuls (read_facts) n'en
                    -- font pas.
                    local points = Conversation.leconDemandee(entree)
                    if #points > 0 and entree.read_facts ~= true then
                        c.elements[#c.elements + 1] = nouvelElement('lecon', { outil = court, appel = bloc.id, etat = 'enCours',
                            photo = type(entree.photo_id) == 'number' and entree.photo_id or nil, points = points }, date)
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
            local l = dernierIndice(c, function(e) return e.genre == 'lecon' and e.appel == r.idOutil end)
            if l then
                Conversation.completerLecon(c.elements[l], r)
            end
            -- « Je le fais » (1.3) : la liste (my_turn) ou la comparaison (claude_version).
            local x = dernierIndice(c, function(e)
                return e.genre == 'exercice' and (e.appel == r.idOutil or (e.appelComparaison ~= nil and e.appelComparaison == r.idOutil))
            end)
            if x then
                local exo = c.elements[x]
                Conversation.completerExercice(exo, r)
                -- La liste arrivée (Dany l'a demandée en mots, sans le bouton) : une proposition
                -- restée en attente avant elle est à faire lui-même, plus à accepter.
                if exo.etat == 'aFaire' and exo.appel == r.idOutil then
                    for k = 1, x - 1 do
                        local avant = c.elements[k]
                        if avant.genre == 'proposition' and avant.etat == 'enAttente' then
                            avant.etat = 'faite'
                        end
                    end
                end
            end
            if p then
                local e = c.elements[p]
                e.images = chemins
                local lus = Conversation.changementsLus(r.textes)
                if lus then
                    e.changements = lus
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
            if (e.genre == 'outil' or e.genre == 'notation' or e.genre == 'lecon') and e.etat == 'enCours' then
                e.etat = ev.interrompue and 'erreur' or 'fait'
            end
            -- Un exercice sans sa liste n'a pas abouti ; une comparaison sans réponse le laisse à faire.
            if e.genre == 'exercice' then
                if e.etat == 'enCours' then
                    e.etat = 'erreur'
                end
                e.comparaisonEnCours = nil
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

-- Marque un élément (une proposition que Dany fait lui-même : 'faite', Je le fais) ; vrai s'il
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

-- Images de la conversation, dans l'ordre du fil : { chemin, element (indice), outil, comparaison
-- (vrai pour celle de « Je le fais », la version de Claude à gauche, celle de Dany à droite) }.
function Conversation.images(c)
    local liste = {}
    for i, e in ipairs(c.elements) do
        for _, chemin in ipairs(e.images or {}) do
            local outil, comparaison
            if e.appel then
                local j = dernierIndice(c, function(x) return x.genre == 'outil' and x.appel == e.appel end)
                outil = j and c.elements[j].outil
                comparaison = j and c.elements[j].comparaison == true or nil
            end
            liste[#liste + 1] = { chemin = chemin, element = i, outil = outil or (e.genre == 'dany' and 'jointe'), comparaison = comparaison }
        end
    end
    return liste
end

-- Nombre d'outils terminés depuis la dernière demande.
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
