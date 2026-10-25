-- Fil.lua : le fil d'une conversation mis en lignes pour la fenêtre. Le SDK de Lightroom ne sait
-- pas ajouter de vues à une fenêtre ouverte, ni faire défiler une zone par programme, et une vue
-- masquée garde sa place : la fenêtre montre donc une grille de lignes de hauteur fixe, que ce
-- module remplit. Chaque ligne a un genre (sa police, sa couleur, son icône) et un texte coupé
-- à la largeur de la colonne d'après la chasse mesurée des polices (Metriques.lua).
--
-- Ligne : { genre, texte, icone, element (indice dans le fil), image (chemin relatif), etape (vrai :
--   la ligne d'une étape de Claude, qu'un clic ouvre dans l'onglet Aperçu), actions ('note',
--   'demande' ou 'note+demande' : la ligne des boutons « ☆ Voir
--   la note » et « ＋ Garder la demande », avec notation et demande, les indices de leurs éléments) ;
--   auteur ('dany' ou 'claude', sur la première ligne d'un tour de parole) et heure (« 19 h 42 »,
--   sur la ligne suivante), posés par Fil.lignes sur des copies }
--   genres : 'dany', 'claude', 'titre', 'outil', 'appel', 'apercu', 'proposition', 'note',
--   'actions', 'vide'
--   icones : 'ok', 'cours', 'erreur', 'apercu', 'proposition', 'note' ou nil (plus de › devant
--   Dany : la colonne auteur dit « Vous »)
-- La fenêtre B (1.3, lot B4) : une colonne auteur (« Vous », « Claude », puis l'heure), puis la
-- colonne du texte (Fenetre.largeurTexte), où l'icône se pose à gauche et le texte des genres qui en
-- portent une (Fil.RETRAITS) se pose à RETRAIT_ICONE de son bord. La ligne d'un appel d'outil (genre
-- 'appel') est un texte riche : le nom de l'outil en <EM> (Menlo 11, Fil.emphases), puis sa
-- description en petit gris (Fil.uneLigneOutil) ; celle d'une étape de Claude (1.3,
-- Conversation.estEtape) porte le drapeau `etape`, et un clic sur elle l'ouvre dans l'onglet Aperçu
-- (le bouton « Pourquoi ? » à sa droite, et la place qu'elle lui laissait, sont retirés au
-- correctif 1.3.6, décision de Dany du 25 octobre 2026). Les autres textes viennent sans balise
-- (Fil.sansBalises) : seules celles que pose ce module restent.
-- Un élément `notation` (notes proposées) reprend les genres `proposition` (titre) et `outil` (une
-- ligne par photo, en Menlo). Le tour de Claude qui a rangé des notes finit par sa ligne d'actions
-- (« ☆ Voir la note », comme dans la maquette : Fil.lignes). Les éléments `lecon` et `exercice`
-- d'une conversation d'avant le correctif 1.3.6 (leçon de la photo, « Je le fais », retirés) n'ont
-- aucune ligne : seul l'appel de leur outil (genre `appel`) reste dans le fil.
-- La page Carnet de progrès (1.3, Fil.lignesCarnet), que le fil montrait aussi, est devenue la
-- fenêtre Suivi au correctif 1.3.6 (Fil.texteSuivi : un texte riche, pas des lignes ; d'abord la
-- carte d'un onglet Suivi, devenu une fenêtre à part le 25 octobre 2026, FenetreSuivi.lua).
-- Un élément `historique` (correctif 1.3.6 : ce que la fenêtre dit de la photo ou du groupe,
-- Historique.lua) reprend le genre `note` (en gris, l'icône ⓘ sur sa première ligne), ses puces
-- en retrait sur leurs lignes de suite ; il n'est d'aucun tour de parole (ni « Vous » ni « Claude »,
-- ni heure : Fil.lignes).
-- Une demande faite par la Demande rapide dans la conversation d'une photo (correctif 1.3.6,
-- Moteur.envoyerRapide : elle et ce qui y répond portent `rapide`) se dit d'une ligne « Demande
-- rapide » sous son texte (Fil.MENTION_RAPIDE, en note, comme le style choisi).

local Conversation = require 'Conversation'
local Metriques = require 'Metriques'
local Texte = require 'Texte'

local Fil = {}

-- Police de chaque genre de ligne (clé de Metriques : la police du système en 13, 12 et 11, gras,
-- et Menlo 11).
Fil.polices = {
    dany = 'texte', claude = 'texte', titre = 'gras', outil = 'mono', apercu = 'texte',
    proposition = 'gras', changement = 'mono', note = 'texte', vide = 'texte', appel = 'texte12', actions = 'texte',
}

-- Police de l'emphase (<EM>) des genres balisés : le nom de l'outil d'une ligne d'appel.
Fil.emphases = { appel = 'mono' }

-- Retrait du texte des genres qui portent une icône : l'icône se pose au bord gauche de la
-- colonne du texte (Vues.ligneFil), le texte à RETRAIT_ICONE points (maquette : icône de 12, écart
-- de 8). Les autres genres (Dany, Claude, les titres, les lignes en Menlo, les actions) partent du
-- bord, comme dans la maquette.
Fil.RETRAIT_ICONE = 20
Fil.RETRAITS = { appel = Fil.RETRAIT_ICONE, apercu = Fil.RETRAIT_ICONE, proposition = Fil.RETRAIT_ICONE, note = Fil.RETRAIT_ICONE }

-- La mention d'une demande faite par la Demande rapide (Fil.lignesBrutes).
Fil.MENTION_RAPIDE = "Demande rapide"

function Fil.retrait(genre)
    return Fil.RETRAITS[genre] or 0
end

-- Marge gardée à droite de chaque ligne : la chasse mesurée ne tient pas compte de tous les
-- réglages de rendu de Lightroom (l'encre fait 1 à 2 points de moins que la chasse, constaté le
-- 21 octobre 2026, D9).
Fil.MARGE = 10

-- Photos montrées d'une notation ; les autres se résument en « … et N autres ».
Fil.NOTES_MONTREES = 12

-- L'espace insécable (U+00A0) : celle de la ponctuation haute, que la coupe garde avec son mot.
local INSECABLE = '\194\160'

-- Texte riche ---------------------------------------------------------------------------------
-- Une ligne balisée (<EM>…</EM>, constaté le 21 octobre 2026, B1 et D4) : les balises ne prennent
-- pas de place, la partie balisée se mesure dans la police d'emphase ; une coupe ne tombe jamais
-- dans une balise, et un passage balisé coupé en fin de ligne se ferme sur sa ligne et se rouvre au
-- début de la suivante (chaque ligne se lit seule : une page de carte en commence une).

-- Un texte sans balise <EM> (ce que donnent Dany, Claude ou le connecteur : seules les balises
-- posées par ce module restent).
function Fil.sansBalises(texte)
    return (tostring(texte or ''):gsub('</?EM>', ''))
end
local sans = Fil.sansBalises

-- L'état d'emphase après un texte, depuis `ouvert` (vrai : une <EM> reste ouverte).
local function ouvertApres(texte, ouvert)
    for fin in texte:gmatch('<(/?)EM>') do
        ouvert = fin == ''
    end
    return ouvert == true
end

-- Une ligne qui commence dans un passage balisé : la balise rouverte après ses espaces de tête.
local function rouvrir(texte)
    local blancs, reste = texte:match('^(%s*)(.*)$')
    return blancs .. '<EM>' .. reste
end

-- Les atomes d'un texte : ses caractères, une balise comptant pour un seul.
local function atomes(texte)
    local liste, pos = {}, 1
    while pos <= #texte do
        local a, b = texte:find('^</?EM>', pos)
        if a then
            liste[#liste + 1] = texte:sub(a, b)
            pos = b + 1
        else
            local c = texte:match('^' .. Texte.MOTIF_CARACTERE, pos) or texte:sub(pos, pos)
            liste[#liste + 1] = c
            pos = pos + #c
        end
    end
    return liste
end

local function mesurer(texte, m, total)
    local chasse = m.chasse
    local defaut = chasse['M']
    for c in Texte.caracteres(texte) do
        total = total + (chasse[c] or (c == INSECABLE and chasse[' ']) or defaut)
    end
    return total
end

-- Largeur d'un texte dans une police ; ses balises ne comptent pas, la partie balisée se mesure
-- dans `emphase` (sa police à lui sans `emphase`).
function Fil.largeur(texte, police, emphase)
    local m = Metriques[police] or Metriques.texte
    if not texte:find('<', 1, true) then
        return mesurer(texte, m, 0)
    end
    local me = Metriques[emphase or police] or m
    local total, pos, dedans = 0, 1, false
    while true do
        local a, b, fin = texte:find('<(/?)EM>', pos)
        total = mesurer(texte:sub(pos, (a or (#texte + 1)) - 1), dedans and me or m, total)
        if not a then
            break
        end
        dedans = fin == ''
        pos = b + 1
    end
    return total
end

-- La place qu'occupe une ligne du fil dans la colonne du texte : son retrait, puis son texte dans
-- sa police (balises comprises).
function Fil.occupe(l)
    return Fil.retrait(l.genre) + Fil.largeur(l.texte or '', Fil.polices[l.genre] or 'texte', Fil.emphases[l.genre])
end

-- Coupe un texte (sans saut de ligne) en lignes d'au plus `largeur` points. `retrait` : texte
-- placé devant les lignes de suite (puces). `emphase` : la police de ses passages balisés ;
-- `ouvert` : vrai si le texte commence dans un passage balisé (le paragraphe d'avant le laissait
-- ouvert). Rend les lignes, chacune aux balises fermées, et l'état d'emphase à la fin.
function Fil.couper(texte, largeur, police, retrait, emphase, ouvert)
    -- Assez de place pour quelques caractères après le retrait : sinon la coupe au caractère
    -- ne progresserait plus.
    largeur = math.max(largeur, 80)
    retrait = retrait or ''
    if Fil.largeur(retrait, police) > largeur / 2 then
        retrait = ''
    end
    local brutes = {}
    local courante = ''
    -- L'état d'emphase au début de la ligne en cours.
    local debut = ouvert == true
    local function pousser(ligne)
        brutes[#brutes + 1] = { texte = (ligne:gsub(INSECABLE, ' ')), ouvert = debut }
        debut = ouvertApres(ligne, debut)
    end
    local function tient(t)
        return Fil.largeur(debut and rouvrir(t) or t, police, emphase) <= largeur
    end
    local function visible(t)
        return (t:gsub('</?EM>', '')) ~= ''
    end
    -- Une ponctuation haute (; : ! ? ») reste avec le mot d'avant, « avec celui d'après : une ligne
    -- ne commence pas par « ; » (typographie française, constaté sur la carte Note).
    texte = texte:gsub('\t', '    '):gsub(' ([;:!?])', INSECABLE .. '%1'):gsub(' »', INSECABLE .. '»'):gsub('« ', '«' .. INSECABLE)
    -- Mots et espaces, dans l'ordre (une balise est dans son mot : jamais coupée par une espace).
    for espace, mot in texte:gmatch('(%s*)(%S*)') do
        if mot == '' and espace == '' then
            break
        end
        local essai = courante .. espace .. mot
        if courante == '' or tient(essai) then
            courante = (courante == '' and #brutes > 0) and (retrait .. mot) or essai
        else
            pousser(courante)
            courante = retrait .. mot
        end
        -- Un mot plus long que la ligne : coupé au caractère, jamais dans une balise.
        while not tient(courante) do
            local morceau = ''
            for _, c in ipairs(atomes(courante)) do
                if not tient(morceau .. c) and visible(morceau) then
                    break
                end
                morceau = morceau .. c
            end
            local reste = courante:sub(#morceau + 1)
            pousser(morceau)
            courante = retrait .. reste
            if reste == '' then
                courante = ''
                break
            end
        end
    end
    if courante ~= '' or #brutes == 0 then
        pousser(courante)
    end
    -- Chaque ligne aux balises fermées : rouverte au début (après ses espaces de tête) si la ligne
    -- d'avant la laissait ouverte, fermée à la fin si elle reste ouverte.
    local lignes = {}
    for k, l in ipairs(brutes) do
        local t = l.ouvert and rouvrir(l.texte) or l.texte
        if ouvertApres(t, false) then
            t = t .. '</EM>'
        end
        lignes[k] = (t:gsub('<EM></EM>', ''))
    end
    return lignes, debut
end

-- Les lignes d'un texte de carte dans `largeur` points (paragraphes gardés, lignes vides comprises,
-- sans ligne vide au bout), la marge de la ligne (Fil.MARGE) gardée, dans `police` (une clé de
-- Metriques ; 'texte' sans elle) ; `emphase` : la police de ses passages balisés (<EM>), chaque
-- ligne aux balises fermées, un passage coupé rouvert à la suivante. Pour les cartes de la fenêtre
-- Claude (Fenetre.lignesCarte), la fenêtre Suivi et les légendes en grand.
function Fil.lignesCarte(texte, largeur, police, emphase)
    local lignes = {}
    local ouvert = false
    for paragraphe in (tostring(texte or '') .. '\n'):gmatch('([^\n]*)\n') do
        if paragraphe == '' then
            lignes[#lignes + 1] = ''
        else
            local coupees
            coupees, ouvert = Fil.couper(paragraphe, largeur - Fil.MARGE, police or 'texte', nil, emphase, ouvert)
            for _, l in ipairs(coupees) do
                lignes[#lignes + 1] = l
            end
        end
    end
    while #lignes > 0 and lignes[#lignes] == '' do
        lignes[#lignes] = nil
    end
    return lignes
end

-- Un texte tronqué à `largeur` points : tel quel s'il tient, sinon son plus long début suivi de
-- « … » ('' si même « … » ne tient pas). Sans balise. Aussi pour les éléments du menu Mes demandes
-- (Fenetre.titreDemande).
function Fil.tronquer(texte, largeur, police)
    if Fil.largeur(texte, police) <= largeur then
        return texte
    end
    local n = Texte.longueur(texte)
    while n > 0 and Fil.largeur(Texte.debut(texte, n) .. '…', police) > largeur do
        n = n - 1
    end
    if n == 0 then
        return Fil.largeur('…', police) <= largeur and '…' or ''
    end
    return (Texte.debut(texte, n):gsub('%s+$', '')) .. '…'
end
local tronquer = Fil.tronquer

-- Un texte sur une seule ligne : coupé par « … » s'il dépasse.
local function uneLigne(texte, largeur, police)
    local coupe = Fil.couper(texte, largeur, police)
    local montre = coupe[1]
    if #coupe > 1 then
        montre = Texte.debut(montre, math.max(1, Texte.longueur(montre) - 1)) .. '…'
    end
    return montre
end

-- Un texte coupé en `maxi` lignes au plus : la dernière finit par « … » quand il dépasse (sans
-- balise).
function Fil.coupeBornee(texte, largeur, police, retrait, maxi)
    local coupe = Fil.couper(texte, largeur, police, retrait)
    if #coupe <= maxi then
        return coupe
    end
    local gardees = {}
    for k = 1, maxi do
        gardees[k] = coupe[k]
    end
    local derniere = gardees[maxi]
    local n = Texte.longueur(derniere)
    while n > 0 and Fil.largeur(Texte.debut(derniere, n) .. '…', police) > math.max(largeur, 80) do
        n = n - 1
    end
    gardees[maxi] = Texte.debut(derniere, n):gsub('%s+$', '') .. '…'
    return gardees
end

-- La ligne d'un appel d'outil, en texte riche : « <EM>apply_settings</EM>  étape « Claude · tons et
-- balance » · 6 réglages » ; le nom (sans balise) se mesure en Menlo, la description en petit, et
-- elle seule se coupe par « … » pour tenir dans `largeur` (le nom aussi, s'il ne tient pas seul).
function Fil.uneLigneOutil(nom, description, largeur)
    nom = tronquer(sans(nom), largeur, 'mono')
    if nom == '' then
        return ''
    end
    local texte = '<EM>' .. nom .. '</EM>'
    description = Texte.nettoyer(sans(description))
    if description ~= '' then
        local reste = largeur - Fil.largeur(nom, 'mono') - Fil.largeur('  ', 'texte12')
        local d = reste > 0 and tronquer(description, reste, 'texte12') or ''
        if d ~= '' and d ~= '…' then
            texte = texte .. '  ' .. d
        end
    end
    return texte
end

-- « 19 h 42 » : l'heure d'une date Unix, à l'heure locale (os.date, Compat) ; '' sans date.
function Fil.heure(t)
    if type(t) ~= 'number' then
        return ''
    end
    local d = os.date('*t', t)
    return string.format('%d h %02d', d.hour, d.min)
end

-- L'onglet Focus (demandé par Dany le 22 octobre 2026) ----------------------------------------

-- La mise au point d'une photo qui ne se lit pas, après « Mise au point : » : une autre marque que
-- Fujifilm ; un original introuvable, trop long à ouvrir, ou ouvert sans rien que la lecture sache
-- lire (un HEIF de l'appareil, un fichier sans les données de Fujifilm), d'après la raison que le
-- connecteur dit (Images.RAISONS_FOCUS) ; sans raison dite (connecteur muet, alarme de 5 s, erreur
-- de la lecture), la phrase qui couvre les trois ; un connecteur absent ; pendant la lecture.
Fil.FOCUS_AUTRE_MARQUE = "non lue (seulement les fichiers Fujifilm pour l'instant)"
Fil.FOCUS_NON_LUE = "non lue (original illisible, introuvable ou trop long à ouvrir)"
Fil.FOCUS_INTROUVABLE = "non lue (original introuvable)"
Fil.FOCUS_DELAI = "non lue (original trop long à ouvrir)"
Fil.FOCUS_ILLISIBLE = "non lue (format pas encore lu, comme le HEIF, ou fichier sans les données de l'appareil)"
Fil.FOCUS_SANS_CONNECTEUR = "non lue (connecteur introuvable : réinstaller Développeur)"
Fil.FOCUS_EN_COURS = "lecture dans l'original…"

-- « Focus · DSCF2402.RAF (Essai) » : le nom du fichier et celui de la copie virtuelle.
function Fil.titreFocus(infos)
    local nom = Texte.nettoyer(sans(infos and infos.nom))
    local copie = Texte.nettoyer(sans(infos and infos.copie))
    if nom == '' then
        return "Focus"
    end
    return "Focus · " .. nom .. (copie ~= '' and (" (" .. copie .. ")") or '')
end

-- Le texte de la carte Focus : les trois blocs Image, Prise de vue et Mise au point, comme les
-- sections Image Information, Shooting Information et Focus Information de Focus-Points, en
-- français. Le titre de chaque bloc en <EM> (l'emphase de la carte, gras 12), puis une ligne
-- « Titre : valeur » par valeur lue (une valeur absente n'a pas de ligne). `infos` : ce que
-- Lightroom donne (Lightroom.infosFocus) ; `boitier` : la réponse de `mcp-developpeur --focus`
-- (Images.lireFocus ; ses blocs sont des paires titre, valeur déjà en français), ajoutée au bout de
-- chaque bloc ; `etat` : 'lue', 'lecture' (en cours), 'autre_marque', 'introuvable', 'delai',
-- 'illisible', 'non_lue' ou 'sans_connecteur', d'où « Mise au point : non lue (…) » sans lecture.
-- Les textes reçus perdent leurs balises.
function Fil.texteFocus(infos, boitier, etat)
    infos = infos or {}
    local function propre(v)
        if type(v) ~= 'string' and type(v) ~= 'number' then
            return ''
        end
        return Texte.nettoyer(sans(tostring(v)))
    end
    local function ajouter(lignes, titre, valeur)
        valeur = propre(valeur)
        if valeur ~= '' then
            lignes[#lignes + 1] = titre .. " : " .. valeur
        end
    end
    local function duBoitier(lignes, bloc)
        for _, paire in ipairs(type(bloc) == 'table' and bloc or {}) do
            if type(paire) == 'table' then
                local titre = propre(paire[1])
                if titre ~= '' then
                    ajouter(lignes, titre, paire[2])
                end
            end
        end
    end
    local lue = etat == 'lue' and type(boitier) == 'table'

    local image = {}
    local copie = propre(infos.copie)
    ajouter(image, "Fichier", propre(infos.nom) ~= '' and (propre(infos.nom) .. (copie ~= '' and (" (" .. copie .. ")") or '')) or nil)
    ajouter(image, "Prise de vue", infos.date)
    ajouter(image, "Taille d'origine", infos.origine)
    ajouter(image, "Taille actuelle", infos.actuelle)
    if lue then
        duBoitier(image, boitier.image)
    end

    local prise = {}
    ajouter(prise, "Marque", infos.marque)
    ajouter(prise, "Modèle", infos.modele)
    ajouter(prise, "Objectif", infos.objectif)
    ajouter(prise, "Focale", infos.focale)
    local vitesse, ouverture = propre(infos.vitesse), propre(infos.ouverture)
    ajouter(prise, "Exposition", (vitesse ~= '' and ouverture ~= '') and (vitesse .. " à " .. ouverture) or (vitesse ~= '' and vitesse or ouverture))
    ajouter(prise, "ISO", infos.iso)
    ajouter(prise, "Correction d'exposition", infos.correction)
    ajouter(prise, "Programme d'exposition", infos.programme)
    ajouter(prise, "Mesure", infos.mesure)
    if lue then
        duBoitier(prise, boitier.prise_de_vue)
    end

    local blocs = {}
    for _, b in ipairs({ { "Image", image }, { "Prise de vue", prise } }) do
        if #b[2] > 0 then
            blocs[#blocs + 1] = '<EM>' .. b[1] .. '</EM>\n' .. table.concat(b[2], '\n')
        end
    end
    local focus = {}
    if lue then
        duBoitier(focus, boitier.mise_au_point)
    end
    if #focus > 0 then
        blocs[#blocs + 1] = "<EM>Mise au point</EM>\n" .. table.concat(focus, '\n')
    else
        local raison = ({ lecture = Fil.FOCUS_EN_COURS, autre_marque = Fil.FOCUS_AUTRE_MARQUE,
            sans_connecteur = Fil.FOCUS_SANS_CONNECTEUR, introuvable = Fil.FOCUS_INTROUVABLE, delai = Fil.FOCUS_DELAI,
            illisible = Fil.FOCUS_ILLISIBLE })[etat] or Fil.FOCUS_NON_LUE
        blocs[#blocs + 1] = "<EM>Mise au point :</EM> " .. raison
    end
    return table.concat(blocs, '\n\n')
end

-- « ★★★☆☆ » : une note de 0 à 5 étoiles.
function Fil.etoiles(note)
    local n = math.max(0, math.min(5, math.floor(tonumber(note) or 0)))
    return string.rep('★', n) .. string.rep('☆', 5 - n)
end

-- Une note proposée sur une ligne : « ★★★☆☆ DSCF4961.RAF · à vérifier · raison »,
-- « ⚑ Rejeter photo 53636310 · raison », « ✕ ★★☆☆☆ DSCF4962.RAF · photo introuvable ». Claude
-- propose de 0 à 5 étoiles : une note lue au-dessus de 5 se montre à 5.
function Fil.texteNote(x)
    local tete = x.drapeau == 'rejetee' and '⚑ Rejeter' or Fil.etoiles(math.min(tonumber(x.note) or 0, Conversation.NOTE_MAXIMALE))
    if x.etat == 'refusee' then
        tete = '✕ ' .. tete
    end
    local suite = { type(x.fichier) == 'string' and x.fichier ~= '' and x.fichier or ('photo ' .. Conversation.clePhoto(x.photo)) }
    if x.etat == 'posee' then
        suite[#suite + 1] = 'posée'
    elseif x.a_verifier == true then
        suite[#suite + 1] = 'à vérifier'
    end
    local raison = (x.etat == 'refusee' or x.refus) and x.refus or x.raison
    if type(raison) == 'string' and Texte.nettoyer(raison) ~= '' then
        suite[#suite + 1] = Texte.nettoyer(raison)
    end
    return tete .. ' ' .. table.concat(suite, ' · ')
end

-- Markdown léger d'une ligne de Claude : genre et texte à montrer, retrait des lignes de suite.
function Fil.ligneMarkdown(ligne)
    local titre = ligne:match('^%s*#+%s+(.*)$')
    if titre then
        return 'titre', (titre:gsub('%*%*', ''):gsub('`', '')), ''
    end
    local seul = ligne:match('^%s*%*%*([^*]+)%*%*%s*:?%s*$')
    if seul then
        return 'titre', Texte.nettoyer(ligne:gsub('%*%*', '')), ''
    end
    local propre = ligne:gsub('%*%*', ''):gsub('__', ''):gsub('`', '')
    local blancs, puce, reste = propre:match('^(%s*)([-*•])%s+(.*)$')
    if puce then
        local niveau = math.floor(#blancs / 2)
        local devant = string.rep('    ', niveau) .. '•  '
        return 'claude', devant .. reste, string.rep('    ', niveau) .. '    '
    end
    local numero, suite = propre:match('^%s*(%d+[.)])%s+(.*)$')
    if numero then
        return 'claude', numero .. ' ' .. suite, '     '
    end
    local cite = propre:match('^%s*>%s?(.*)$')
    if cite then
        return 'note', cite, ''
    end
    if propre:match('^%s*|') then
        -- Ligne de tableau (que la consigne évite) : les cellules séparées par « · ».
        if propre:match('^[%s|:%-]+$') then
            return nil
        end
        local cellules = {}
        for cellule in propre:gmatch('[^|]+') do
            local t = Texte.nettoyer(cellule)
            if t ~= '' then
                cellules[#cellules + 1] = t
            end
        end
        return 'claude', table.concat(cellules, ' · '), '    '
    end
    if propre:match('^%s*[-*_]%s*[-*_]%s*[-*_][%s%-*_]*$') then
        return 'vide', '', ''
    end
    return 'claude', propre, ''
end

-- La place du texte d'un genre dans une ligne de `largeur` points : sans son retrait.
local function place(genre, largeur)
    return largeur - Fil.retrait(genre)
end

local function ajouterTexte(lignes, texte, genre, largeur, element, icone)
    local premiere = true
    for _, brute in ipairs(Texte.lignes(texte)) do
        local g, montre, retrait = genre, brute, ''
        if genre == 'claude' then
            g, montre, retrait = Fil.ligneMarkdown(brute)
        end
        if g then
            if Texte.nettoyer(montre) == '' then
                lignes[#lignes + 1] = { genre = 'vide', texte = '', element = element }
            else
                for _, l in ipairs(Fil.couper(montre, place(g, largeur), Fil.polices[g] or 'texte', retrait)) do
                    lignes[#lignes + 1] = { genre = g, texte = l, element = element, icone = premiere and icone or nil }
                    premiere = false
                end
            end
        end
    end
end

-- Le nom et la description de la ligne d'un appel d'outil : « view_photo » et « photo 53636309 »
-- (le résumé de l'appel, Conversation.resumeOutil, sans le nom) ; pour une étape de Claude, quand
-- son but est connu, « étape « Claude · tons et balance » · 6 réglages » (les réglages changés,
-- lus dans la réponse ; les photos, s'il y en a plusieurs).
function Fil.descriptionOutil(e)
    local texte = Texte.nettoyer(sans(e.texte))
    local nom = Texte.nettoyer(sans(e.outil))
    if nom == '' then
        return texte ~= '' and texte or 'outil', ''
    end
    local description = ''
    if texte:sub(1, #nom + #' · ') == nom .. ' · ' then
        description = texte:sub(#nom + #' · ' + 1)
    elseif texte ~= nom then
        description = texte
    end
    if Conversation.estEtape(e) then
        local info = Conversation.infoEtape(e)
        local but = Conversation.nomEtape(info.etape or (info.etapes[1] and info.etapes[1].nom))
        if but ~= '' then
            description = "étape « Claude · " .. but .. " »"
            local reglages = #(e.changements or {})
            if reglages > 0 then
                description = description .. " · " .. (reglages == 1 and "1 réglage" or (reglages .. " réglages"))
            end
            local photos = #Conversation.photosEtape(e)
            if photos > 1 then
                description = description .. " · " .. photos .. " photos"
            end
        end
    end
    return nom, description
end

-- Les lignes d'un seul élément (sans les lignes vides qui l'entourent). Leurs textes viennent sans
-- balise, sauf la ligne d'un appel (genre 'appel', balisée par Fil.uneLigneOutil).
function Fil.lignesElement(e, i, largeur)
    local lignes = Fil.lignesBrutes(e, i, largeur)
    for _, l in ipairs(lignes) do
        if l.genre ~= 'appel' then
            l.texte = sans(l.texte)
        end
    end
    return lignes
end

-- Les lignes d'un élément, avant le retrait des balises venues d'ailleurs (Fil.lignesElement).
function Fil.lignesBrutes(e, i, largeur)
    local lignes = {}
    local g = e.genre
    if g == 'dany' then
        ajouterTexte(lignes, e.texte or '', 'dany', largeur, i)
        if e.rapide == true then
            lignes[#lignes + 1] = { genre = 'note', texte = Fil.MENTION_RAPIDE, element = i }
        end
        if type(e.style) == 'string' and e.style ~= '' then
            lignes[#lignes + 1] = { genre = 'note', texte = uneLigne("Style : " .. e.style, place('note', largeur), 'texte'), element = i }
        end
        for n, chemin in ipairs(e.images or {}) do
            lignes[#lignes + 1] = { genre = 'apercu', texte = "Photo jointe " .. n .. " · cliquer pour la voir", element = i, image = chemin, icone = 'apercu' }
        end
    elseif g == 'claude' then
        ajouterTexte(lignes, Conversation.texteAffiche(e), 'claude', largeur, i)
        -- Pas de ligne vide en tête ni en fin.
        while lignes[1] and lignes[1].genre == 'vide' do
            table.remove(lignes, 1)
        end
        while lignes[#lignes] and lignes[#lignes].genre == 'vide' do
            lignes[#lignes] = nil
        end
    elseif g == 'outil' then
        -- « <EM>apply_settings</EM>  étape « Claude · tons et balance » · 6 réglages » ; une étape
        -- porte `etape` (un clic l'ouvre dans l'onglet Aperçu), sur toute la largeur.
        local icone = e.etat == 'erreur' and 'erreur' or (e.etat == 'enCours' and 'cours' or 'ok')
        local etape = Conversation.estEtape(e)
        local nom, description = Fil.descriptionOutil(e)
        lignes[1] = { genre = 'appel', texte = Fil.uneLigneOutil(nom, description, place('appel', largeur)), element = i, icone = icone,
            etape = etape or nil }
    elseif g == 'apercu' then
        -- Une ligne d'image dit ce que fait son clic (correctif 1.3.6) : l'image dans l'onglet Aperçu,
        -- et pour une image de Claude, le pourquoi de l'étape qui la précède (Fenetre.voirImageDuFil) ;
        -- Agrandir est sous l'aperçu.
        for n, chemin in ipairs(e.images or {}) do
            lignes[#lignes + 1] = { genre = 'apercu', texte = (#e.images > 1 and ("Aperçu " .. n) or "Aperçu") .. " de Claude · cliquer pour le voir, avec son pourquoi",
                element = i, image = chemin, icone = 'apercu' }
        end
    elseif g == 'proposition' then
        local etat = ({ enAttente = "en attente de votre accord", acceptee = "acceptée", refusee = "refusée",
            ajustee = "à ajuster", faite = "à faire vous-même", appliquee = "appliquée par Claude",
            remplacee = "remplacée par une retouche de Claude" })[e.etat or ''] or ''
        ajouterTexte(lignes, "Proposition" .. (etat ~= '' and (" " .. etat) or "") .. (Texte.nettoyer(e.texte) ~= '' and (" : " .. e.texte) or ""),
            'proposition', largeur, i, 'proposition')
        for _, ch in ipairs(e.changements or {}) do
            local texte = string.format("%s : %s → %s", ch.libelle or '?', ch.avant or '—', ch.apres or '—')
            for _, l in ipairs(Fil.couper(texte, largeur - 16, 'mono', '  ')) do
                lignes[#lignes + 1] = { genre = 'outil', texte = '  ' .. l, element = i }
            end
        end
        for n, chemin in ipairs(e.images or {}) do
            lignes[#lignes + 1] = { genre = 'apercu', texte = (n == 1 and "Avant / après" or ("Rendu " .. n)) .. " · cliquer pour le voir",
                element = i, image = chemin, icone = 'apercu' }
        end
    elseif g == 'notation' then
        -- « Notes proposées · passe 2 · 14 photos », puis une ligne par photo. Quand Dany a demandé
        -- à Claude de les poser : « Notes à poser » pendant l'appel, puis « Notes posées » si au
        -- moins une l'est, sinon « Notes non posées » (pause, accord attendu : la raison est sur
        -- chaque ligne).
        local notes = e.notes or {}
        local icone = e.etat == 'erreur' and 'erreur' or (e.etat == 'enCours' and 'cours' or 'proposition')
        local titre = "Notes proposées"
        if e.etat == 'erreur' then
            titre = "Notes non rangées"
        elseif e.pose and e.etat == 'enCours' then
            titre = "Notes à poser"
        elseif e.pose then
            titre = "Notes non posées"
            for _, x in ipairs(notes) do
                if x.etat == 'posee' then
                    titre = "Notes posées"
                    break
                end
            end
        end
        if tonumber(e.passe) then
            titre = titre .. " · passe " .. Texte.nombre(tonumber(e.passe))
        end
        titre = titre .. " · " .. (#notes == 1 and "1 photo" or (#notes .. " photos"))
        if e.etat == 'erreur' and Texte.nettoyer(e.texte or '') ~= '' then
            titre = titre .. " : " .. Texte.nettoyer(e.texte)
        end
        ajouterTexte(lignes, titre, 'proposition', largeur, i, icone)
        for n, x in ipairs(notes) do
            if n > Fil.NOTES_MONTREES then
                local reste = #notes - Fil.NOTES_MONTREES
                lignes[#lignes + 1] = { genre = 'outil', texte = '  … et ' .. reste .. (reste == 1 and ' autre' or ' autres'), element = i }
                break
            end
            lignes[#lignes + 1] = { genre = 'outil', texte = uneLigne('  ' .. Fil.texteNote(x), largeur - 16, 'mono'), element = i }
        end
    elseif g == 'note' then
        ajouterTexte(lignes, e.texte or '', 'note', largeur, i, 'note')
    elseif g == 'historique' then
        -- L'en-tête, puis ses puces (« •  », Historique.PUCE), dont les lignes de suite s'alignent
        -- sur le texte de la puce.
        local premiere = true
        for _, brute in ipairs(Texte.lignes(e.texte or '')) do
            if Texte.nettoyer(brute) ~= '' then
                local retrait = brute:sub(1, #'•  ') == '•  ' and '    ' or ''
                for _, l in ipairs(Fil.couper(brute, place('note', largeur), Fil.polices.note, retrait)) do
                    lignes[#lignes + 1] = { genre = 'note', texte = l, element = i, icone = premiere and 'note' or nil }
                    premiere = false
                end
            end
        end
    end
    return lignes
end

-- Ce qui change l'affichage des notes d'une notation (pour la signature du cache).
local function signatureNotes(e)
    if type(e.notes) ~= 'table' then
        return ''
    end
    local morceaux = { tostring(e.passe), tostring(e.pose), #e.notes }
    for _, x in ipairs(e.notes) do
        morceaux[#morceaux + 1] = table.concat({ Conversation.clePhoto(x.photo), tostring(x.note), x.drapeau or '', x.etat or '',
            tostring(x.a_verifier), x.fichier or '', x.refus or '', x.raison or '' }, '\2')
    end
    return table.concat(morceaux, '\3')
end

-- Vrai si deux éléments voisins se suivent sans ligne vide (outils et aperçus d'une même série).
local function colles(a, b)
    local serie = { outil = true, apercu = true }
    return serie[a.genre] and serie[b.genre]
end

-- Une copie d'une ligne (les lignes gardées dans le cache ne portent jamais ce qui se pose ici).
local function copie(l, plus)
    local r = {}
    for cle, valeur in pairs(l) do
        r[cle] = valeur
    end
    for cle, valeur in pairs(plus) do
        r[cle] = valeur
    end
    return r
end

-- Toutes les lignes du fil. `cache` (facultatif) garde les lignes de chaque élément tant qu'il ne
-- change pas : pendant que Claude écrit, seul le dernier élément est recoupé.
-- Chaque tour de parole (une demande de Dany ; la suite de Claude : ses outils, ses aperçus, ses
-- notes et son texte) porte son auteur sur sa première ligne et son heure (celle de son premier
-- élément) sur la suivante, ligne vide comprise ; le dernier tour, d'une seule ligne, en reçoit une
-- vide pour son heure. Un tour de Claude qui a rangé des notes (élément `notation`) finit par sa
-- ligne d'actions, comme dans la maquette : « ☆ Voir la note » (`actions` : 'note' ; `notation` :
-- l'indice de la dernière notation du tour). Un tour qui a retouché (Conversation.estRetouche) et
-- dont le texte de Claude finit par « Demande à garder : « … » » (Conversation.demandeAGarder) y
-- gagne « ＋ Garder la demande » (Mes demandes, demandé par Dany le 22 octobre 2026) : `actions`
-- prend le suffixe '+demande' ('demande' seule, 'note+demande', Fil.valeurActions), `demande`
-- l'indice de ce texte. Ces lignes (auteur, heure, actions) sont faites à chaque appel, sur des
-- copies : les lignes gardées dans le cache ne changent pas. (« Leçon de la photo », 'lecon' et
-- 'les deux' : retirés avec la leçon au correctif 1.3.6.)

-- La valeur `actions` d'une ligne d'actions : 'note', avec '+demande' quand elle porte « ＋ Garder
-- la demande » ('demande' seule) ; nil sans rien.
function Fil.valeurActions(notation, demande)
    local base = notation and 'note' or nil
    if demande then
        return base and (base .. '+demande') or 'demande'
    end
    return base
end

-- Ce que montre une valeur `actions` : sa base ('note' ou '') et vrai si « ＋ Garder la demande » y
-- est (Vues.ligneFil).
function Fil.lireActions(valeur)
    valeur = tostring(valeur or '')
    if valeur == 'demande' then
        return '', true
    end
    local base = valeur:match('^(.-)%+demande$')
    if base then
        return base, true
    end
    return valeur, false
end

function Fil.lignes(c, largeur, cache)
    largeur = largeur - Fil.MARGE
    local lignes, tours = {}, {}
    local precedent, auteurPrecedent
    -- Les actions du tour de Claude en cours (notation, demande : des indices d'éléments ;
    -- retouche : vrai si le tour a retouché).
    local actions = {}
    local function pousser(e, siennes, auteur, date)
        if precedent and not colles(precedent, e) then
            lignes[#lignes + 1] = { genre = 'vide', texte = '' }
        end
        if auteur ~= 'fenetre' and (auteur == 'dany' or auteurPrecedent ~= 'claude') then
            tours[#tours + 1] = { ligne = #lignes + 1, auteur = auteur, heure = Fil.heure(date) }
        end
        for _, l in ipairs(siennes) do
            lignes[#lignes + 1] = l
        end
        precedent, auteurPrecedent = e, auteur
    end
    local function finirTour()
        local demande = actions.retouche and actions.demande or nil
        if not (actions.notation or demande) then
            actions = {}
            return
        end
        local quoi = Fil.valeurActions(actions.notation, demande)
        local ligne = { genre = 'actions', texte = '', element = actions.notation or demande, actions = quoi,
            notation = actions.notation, demande = demande }
        if auteurPrecedent == 'claude' then
            lignes[#lignes + 1] = ligne
        else
            pousser({ genre = 'actions' }, { ligne }, 'claude', actions.date)
        end
        actions = {}
    end
    for i, e in ipairs(c.elements or {}) do
        -- Un élément de la fenêtre (l'historique de la photo, correctif 1.3.6) clôt le tour de
        -- Claude d'avant, sans en commencer un.
        local auteur = e.genre == 'dany' and 'dany' or (e.genre == 'historique' and 'fenetre' or 'claude')
        if auteur ~= 'claude' then
            finirTour()
        end
        local signature = table.concat({ largeur, e.genre or '', e.etat or '', tostring(e.partiel), #(e.images or {}),
            #(e.changements or {}), e.style or '', e.texte or '', signatureNotes(e), #(e.etapes or {}),
            tostring(Conversation.estEtape(e)), tostring(e.rapide) }, '\1')
        local siennes
        if cache and cache[e.id] and cache[e.id].signature == signature then
            siennes = cache[e.id].lignes
            for _, l in ipairs(siennes) do
                l.element = i
            end
        else
            siennes = Fil.lignesElement(e, i, largeur)
            if cache and e.id then
                cache[e.id] = { signature = signature, lignes = siennes }
            end
        end
        if e.genre == 'notation' and e.etat ~= 'erreur' and e.etat ~= 'enCours' and #(e.notes or {}) > 0 then
            actions.notation, actions.date = i, actions.date or e.date
        elseif Conversation.estRetouche(e) then
            actions.retouche = true
        elseif e.genre == 'claude' and not e.partiel and Conversation.demandeAGarder(e.texte) then
            actions.demande, actions.date = i, actions.date or e.date
        end
        if #siennes > 0 then
            pousser(e, siennes, auteur, e.date)
        end
    end
    finirTour()
    for _, t in ipairs(tours) do
        lignes[t.ligne] = copie(lignes[t.ligne], { auteur = t.auteur })
        if t.heure ~= '' then
            local suivante = lignes[t.ligne + 1] or { genre = 'vide', texte = '' }
            lignes[t.ligne + 1] = copie(suivante, { heure = t.heure })
        end
    end
    return lignes
end

-- Suivi : le carnet de progrès (correctif 1.3.6) --------------------------------------------------
-- Le résumé du carnet (Carnet.resumer, du module), ses constats seulement, en un texte riche pour la
-- fenêtre Suivi (FenetreSuivi.lua, ouverte par le bouton Suivi de l'en-tête de la fenêtre Claude ;
-- d'abord la carte d'un onglet Suivi, devenu cette fenêtre le 25 octobre 2026), coupé page par page
-- à sa largeur en 12 (Fil.lignesCarte) : la note (sur quelles photos, par mois de prise de vue) et
-- la remarque ; les défauts
-- mois par mois, un par ligne (le libellé en <EM>, gras 12, puis « n/sur » par mois, « — » sans
-- photo où il a été cherché, le mois abrégé avec son année quand les mois en changent) ; « Ce qui
-- progresse » (ou « Ce qui recule ») et « À travailler à la prochaine sortie », intertitres en <EM>
-- et puces. Il remplace la page Carnet de progrès du fil (Fil.lignesCarnet, son tableau en Menlo
-- aligné par des espaces : la carte est en police proportionnelle, et le défaut porte ses mois sur
-- sa ligne). Les phrases et les titres viennent du résumé (Carnet.resumer, seule copie) ; seuls les
-- mots de la carte sont écrits ici. Les textes venus du registre perdent leurs balises (sans) : seules
-- celles posées ici restent.
-- `page` : le résumé ; nil pendant sa lecture ; { erreur = texte } s'il ne s'est pas lu.
Fil.LECTURE_CARNET = "Lecture du carnet de progrès…"
Fil.ERREUR_CARNET = "Le carnet de progrès ne s'est pas lu : "
Fil.MOIS_PAR_MOIS = "Mois par mois"
Fil.AIDE_DEFAUTS_SUIVI = "« Photos d'un défaut… », en bas de la fenêtre : ses photos, et les retirer du carnet."

local function texteOuNil(valeur)
    if type(valeur) == 'string' and Texte.nettoyer(sans(valeur)) ~= '' then
        return Texte.nettoyer(sans(valeur))
    end
    return nil
end

-- « n/sur » d'un mois, « — » quand le défaut n'y a été cherché sur aucune photo.
function Fil.celluleCarnet(m)
    local sur = type(m) == 'table' and tonumber(m.sur) or 0
    if not sur or sur <= 0 then
        return '—'
    end
    return string.format('%d/%d', tonumber(m.n) or 0, sur)
end

-- Les mois du résumé, abrégés (« oct. »), avec leur année quand ils en changent (« oct. 2025 »).
local function nomsDesMois(mois)
    local plusieurs = false
    for _, m in ipairs(mois) do
        if m.annee ~= (mois[1] or {}).annee then
            plusieurs = true
        end
    end
    local noms = {}
    for i, m in ipairs(mois) do
        local nom = tostring(m.court or m.nom or m.cle or '?')
        noms[i] = (plusieurs and m.annee) and (nom .. ' ' .. tostring(m.annee)) or nom
    end
    return noms
end

-- La ligne d'un défaut : « <EM>Ciel brûlé</EM> · sept. 1/4 · oct. 2/5 ».
function Fil.ligneDefautSuivi(d, noms)
    local morceaux = { '<EM>' .. (texteOuNil(d.libelle) or tostring(d.code or '?')) .. '</EM>' }
    for i, nom in ipairs(noms) do
        morceaux[#morceaux + 1] = nom .. ' ' .. Fil.celluleCarnet(type(d.par_mois) == 'table' and d.par_mois[i])
    end
    return table.concat(morceaux, ' · ')
end

function Fil.texteSuivi(page)
    if type(page) ~= 'table' then
        return Fil.LECTURE_CARNET
    end
    if page.erreur ~= nil then
        return Fil.ERREUR_CARNET .. (texteOuNil(tostring(page.erreur)) or '?')
    end
    local titres = type(page.titres) == 'table' and page.titres or {}
    local parties = {}
    local function ajouter(texte)
        parties[#parties + 1] = texte
    end
    local function intertitre(texte)
        ajouter('')
        ajouter('<EM>' .. texte .. '</EM>')
    end
    -- Une puce comme celles de Claude (Fil.ligneMarkdown) ; `suite` : une ligne retirée dessous.
    local function puce(texte, suite)
        ajouter('•  ' .. texte)
        if suite then
            ajouter('    ' .. suite)
        end
    end
    if texteOuNil(page.note) then
        ajouter(texteOuNil(page.note))
    end
    if texteOuNil(page.remarque) then
        ajouter(texteOuNil(page.remarque))
    end
    local defauts = type(page.defauts) == 'table' and page.defauts or {}
    if page.vide == true or #defauts == 0 then
        return table.concat(parties, '\n')
    end

    intertitre(Fil.MOIS_PAR_MOIS)
    local noms = nomsDesMois(type(page.mois) == 'table' and page.mois or {})
    for _, d in ipairs(defauts) do
        ajouter(Fil.ligneDefautSuivi(d, noms))
    end
    ajouter(Fil.AIDE_DEFAUTS_SUIVI)

    -- Ce qui progresse et ce qui recule (chacun s'il y en a) ; sans tendance, pourquoi.
    local progresse = type(page.progresse) == 'table' and page.progresse or {}
    local recule = type(page.recule) == 'table' and page.recule or {}
    if #progresse > 0 or #recule == 0 then
        intertitre(texteOuNil(titres.progresse) or "Ce qui progresse")
        for _, x in ipairs(progresse) do
            puce(texteOuNil(x.texte) or tostring(x.libelle or x.code or '?'))
        end
        if #progresse == 0 and texteOuNil(page.aucune_tendance) then
            ajouter(texteOuNil(page.aucune_tendance))
        end
    end
    if #recule > 0 then
        intertitre(texteOuNil(titres.recule) or "Ce qui recule")
        for _, x in ipairs(recule) do
            puce(texteOuNil(x.texte) or tostring(x.libelle or x.code or '?'))
        end
    end

    -- À travailler à la prochaine sortie : le défaut, puis ce qu'il faut faire à la prise de vue.
    local aTravailler = type(page.a_travailler) == 'table' and page.a_travailler or {}
    intertitre(texteOuNil(titres.a_travailler) or "À travailler à la prochaine sortie")
    for _, x in ipairs(aTravailler) do
        puce(texteOuNil(x.texte) or tostring(x.libelle or x.code or '?'), texteOuNil(x.prise_de_vue))
    end
    if #aTravailler == 0 and texteOuNil(page.rien_a_travailler) then
        ajouter(texteOuNil(page.rien_a_travailler))
    end
    return table.concat(parties, '\n')
end

-- La fenêtre de lignes à montrer : `nombre` lignes, `defilement` lignes au-dessus de la fin.
-- Rend l'indice de la première ligne montrée et le défilement ramené dans les bornes.
function Fil.fenetre(total, nombre, defilement)
    local maxi = math.max(0, total - nombre)
    defilement = math.max(0, math.min(defilement or 0, maxi))
    local premiere = math.max(1, total - nombre - defilement + 1)
    return premiere, defilement
end

return Fil
