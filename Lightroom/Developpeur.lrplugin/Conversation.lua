-- Conversation.lua : une conversation de la fenêtre = une session Claude Code, reprise par
-- `--resume` : des éléments `dany`, `claude`, `outil`, `apercu`, `proposition` et `note`, dans
-- l'ordre du fil. Les dates sont en secondes Unix.
--
-- Élément : id, genre, texte, date, outil, appel, etat ('enCours', 'fait', 'erreur', 'enAttente',
-- 'acceptee', 'refusee'), detail, images (chemins relatifs au dossier de la conversation),
-- changements ({ libelle, avant, apres }), partiel (texte en train d'arriver).

require 'Compat'
local Consignes = require 'Consignes'
local Json = require 'Json'
local Texte = require 'Texte'

local Conversation = {}

Conversation.PREFIXE_OUTILS = 'mcp__developpeur__'
Conversation.TITRE_PAR_DEFAUT = "Nouvelle conversation"

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

-- Le texte envoyé à Claude : la ligne de contexte de Lightroom, celle du style choisi, la demande,
-- et tant que la conversation n'a pas de titre tiré d'une photo ni choisi, le rappel du titre.
function Conversation.messagePourClaude(c, demande, contexte, ligneStyle)
    local morceaux = {}
    if contexte and contexte ~= '' then
        morceaux[#morceaux + 1] = contexte
    end
    if ligneStyle and ligneStyle ~= '' then
        morceaux[#morceaux + 1] = ligneStyle
    end
    morceaux[#morceaux + 1] = demande
    if c.titreAuto ~= true and c.titreChoisi ~= true then
        morceaux[#morceaux + 1] = Consignes.rappelTitre
    end
    return table.concat(morceaux, '\n\n')
end

-- Recherche : chaque mot doit se trouver dans le titre, le résumé ou les messages (sans tenir
-- compte des majuscules ni des accents). Une recherche vide garde tout.
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

-- « view_photo », « apply_settings · passe 1 : lumière », « view_photo · photo 53636309 ».
function Conversation.resumeOutil(nom, entree)
    entree = type(entree) == 'table' and entree or {}
    local precision
    if type(entree.step_name) == 'string' then
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

-- Changements renvoyés par le connecteur (`changements` : cle, avant, apres, libelle), nil sans.
function Conversation.changementsLus(textes)
    for _, texte in ipairs(textes or {}) do
        local ok, json = pcall(Json.decode, texte)
        if ok and type(json) == 'table' then
            local listes = { json.changements }
            for _, r in ipairs(type(json.resultats) == 'table' and json.resultats or {}) do
                if type(r) == 'table' then
                    listes[#listes + 1] = r.changements
                end
            end
            local lus = {}
            for _, l in ipairs(listes) do
                for _, ch in ipairs(type(l) == 'table' and l or {}) do
                    if type(ch) == 'table' and type(ch.cle) == 'string' then
                        lus[#lus + 1] = { libelle = type(ch.libelle) == 'string' and ch.libelle or Conversation.libelles[ch.cle] or ch.cle,
                            avant = affichage(ch.avant), apres = affichage(ch.apres) }
                    end
                end
            end
            if #lus > 0 then
                return lus
            end
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
                c.elements[#c.elements + 1] = nouvelElement('outil', { texte = Conversation.resumeOutil(court, bloc.entree),
                    outil = court, appel = bloc.id, etat = 'enCours', detail = ok and detail or '' }, date)
                if court == 'preview_settings' then
                    local raison = type(bloc.entree.reason) == 'string' and bloc.entree.reason
                        or (type(bloc.entree.step_name) == 'string' and bloc.entree.step_name) or ''
                    c.elements[#c.elements + 1] = nouvelElement('proposition', { texte = raison, outil = court, appel = bloc.id,
                        etat = 'enAttente', changements = Conversation.changementsDemandes(bloc.entree) }, date)
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
            end
            local p = dernierIndice(c, function(e) return e.genre == 'proposition' and e.appel == r.idOutil end)
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
            if e.genre == 'outil' and e.etat == 'enCours' then
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

function Conversation.propositionEnAttente(c)
    local i = dernierIndice(c, function(e) return e.genre == 'proposition' and e.etat == 'enAttente' end)
    return i and c.elements[i] or nil
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
