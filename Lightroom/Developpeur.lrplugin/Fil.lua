-- Fil.lua : le fil d'une conversation mis en lignes pour la fenêtre. Le SDK de Lightroom ne sait
-- pas ajouter de vues à une fenêtre ouverte, ni faire défiler une zone par programme, et une vue
-- masquée garde sa place : la fenêtre montre donc une grille de lignes de hauteur fixe, que ce
-- module remplit. Chaque ligne a un genre (sa police, sa couleur, son icône) et un texte coupé
-- à la largeur de la colonne d'après la chasse mesurée des polices (Metriques.lua).
--
-- Ligne : { genre, texte, icone, element (indice dans le fil), image (chemin relatif), defaut et
--   action (page Carnet de progrès) }
--   genres : 'dany', 'claude', 'titre', 'outil', 'apercu', 'proposition', 'note', 'vide'
--   icones : 'dany', 'ok', 'cours', 'erreur', 'apercu', 'proposition', 'note' ou nil
-- Un élément `notation` (notes proposées) reprend les genres `proposition` (titre) et `outil` (une
-- ligne par photo) : un genre de plus ajouterait une vue à chaque ligne de la fenêtre. De même, la
-- ligne d'une étape de Claude (1.3, Conversation.estEtape) reste une ligne d'outil, son texte
-- suivi du repère « · Pourquoi ? » (Fil.SUFFIXE_ETAPE) : un clic l'ouvre dans l'onglet Pourquoi ?.
-- La carte « Leçon de la photo » (1.3, élément `lecon`) se fait aussi de genres existants : le
-- titre en `proposition` (gras orange, ⓘ), chaque axe en `titre`, ses deux moitiés en `claude`
-- retirées de 4 espaces (deux lignes au plus chacune, sans Markdown), 16 lignes au plus (deux de
-- plus pour la remarque d'une leçon non rangée) ; une leçon refusée ou interrompue, une ligne
-- `note` « Leçon non rangée : … ». Un exercice « Je le fais » (1.3, élément `exercice`) se fait de
-- même : son titre en `proposition` (« Je le fais · 7 réglages, dans l'ordre du panneau
-- Développement », puis « Je le fais · comparée : 2 écarts sur 7 »), une ligne `outil` par réglage
-- ou par écart (Fil.REGLAGES_MONTRES au plus, puis « … et N autres »), l'écart principal en lignes
-- `outil` aussi ; refusé, son titre dit pourquoi, icône erreur.
-- La page Carnet de progrès (1.3, Fil.lignesCarnet) n'a que des genres existants aussi : ses
-- lignes ne sont pas d'une conversation (pas d'`element`) ; les rangées de son tableau portent
-- `defaut` (le code du défaut), sa ligne d'action `action = 'demander'`.

local Conversation = require 'Conversation'
local Metriques = require 'Metriques'
local Texte = require 'Texte'

local Fil = {}

-- Police de chaque genre de ligne (clé de Metriques).
Fil.polices = {
    dany = 'texte', claude = 'texte', titre = 'gras', outil = 'mono', apercu = 'texte',
    proposition = 'gras', changement = 'mono', note = 'texte', vide = 'texte',
}

-- Marge gardée à droite de chaque ligne : la chasse mesurée ne tient pas compte de tous les
-- réglages de rendu de Lightroom.
Fil.MARGE = 10

-- Photos montrées d'une notation ; les autres se résument en « … et N autres ».
Fil.NOTES_MONTREES = 12

-- Réglages (ou écarts) montrés d'un exercice « Je le fais » (1.3) ; les autres se résument en
-- « … et N autres » (la carte Proposition les donne tous, page par page).
Fil.REGLAGES_MONTRES = 12
-- Lignes au plus de l'écart principal d'un exercice comparé, et du titre d'un exercice refusé.
Fil.LIGNES_PRINCIPAL = 2
Fil.LIGNES_ERREUR_EXERCICE = 3

-- Le repère d'une ligne d'étape (1.3), après le texte de l'outil coupé à la place qui reste : un
-- but (step_name) long ne le fait jamais disparaître.
Fil.SUFFIXE_ETAPE = '  · Pourquoi ?'

-- La carte d'une leçon (1.3) : le retrait des moitiés de point sous leur axe, et les lignes au plus
-- de chaque moitié (une phrase de 140 caractères en tient deux ; au-delà, « … », et le détail de
-- l'appel la donne entière), soit 1 + 3 × (1 + 2 + 2) = 16 lignes ; puis la remarque du rangement
-- (« Leçon non rangée… », rare) en deux lignes au plus ; une leçon refusée, en trois au plus.
Fil.RETRAIT_LECON = '    '
Fil.LIGNES_MOITIE_LECON = 2
Fil.LIGNES_REMARQUE_LECON = 2
Fil.LIGNES_ERREUR_LECON = 3

-- L'espace insécable (U+00A0) : celle de la ponctuation haute, que la coupe garde avec son mot.
local INSECABLE = '\194\160'

-- Largeur d'un texte dans une police.
function Fil.largeur(texte, police)
    local m = Metriques[police] or Metriques.texte
    local chasse = m.chasse
    local defaut = chasse['M']
    local total = 0
    for c in Texte.caracteres(texte) do
        total = total + (chasse[c] or (c == INSECABLE and chasse[' ']) or defaut)
    end
    return total
end

-- Coupe un texte (sans saut de ligne) en lignes d'au plus `largeur` points. `retrait` : texte
-- placé devant les lignes de suite (puces).
function Fil.couper(texte, largeur, police, retrait)
    -- Assez de place pour quelques caractères après le retrait : sinon la coupe au caractère
    -- ne progresserait plus.
    largeur = math.max(largeur, 80)
    retrait = retrait or ''
    if Fil.largeur(retrait, police) > largeur / 2 then
        retrait = ''
    end
    local lignes = {}
    local courante = ''
    local function pousser(ligne)
        lignes[#lignes + 1] = (ligne:gsub(INSECABLE, ' '))
    end
    local function tient(t)
        return Fil.largeur(t, police) <= largeur
    end
    -- Une ponctuation haute (; : ! ? ») reste avec le mot d'avant, « avec celui d'après : une ligne
    -- ne commence pas par « ; » (typographie française, constaté sur la carte Note).
    texte = texte:gsub('\t', '    '):gsub(' ([;:!?])', INSECABLE .. '%1'):gsub(' »', INSECABLE .. '»'):gsub('« ', '«' .. INSECABLE)
    -- Mots et espaces, dans l'ordre.
    for espace, mot in texte:gmatch('(%s*)(%S*)') do
        if mot == '' and espace == '' then
            break
        end
        local essai = courante .. espace .. mot
        if courante == '' or tient(essai) then
            courante = (courante == '' and #lignes > 0) and (retrait .. mot) or essai
        else
            pousser(courante)
            courante = retrait .. mot
        end
        -- Un mot plus long que la ligne : coupé au caractère.
        while not tient(courante) do
            local morceau = ''
            local reste = courante
            for c in Texte.caracteres(courante) do
                if not tient(morceau .. c) and morceau ~= '' then
                    break
                end
                morceau = morceau .. c
            end
            reste = courante:sub(#morceau + 1)
            pousser(morceau)
            courante = retrait .. reste
            if reste == '' then
                courante = ''
                break
            end
        end
    end
    if courante ~= '' or #lignes == 0 then
        pousser(courante)
    end
    return lignes
end

-- Un texte sur une seule ligne : coupé par « … » s'il dépasse.
local function uneLigne(texte, largeur, police)
    local coupe = Fil.couper(texte, largeur, police)
    local montre = coupe[1]
    if #coupe > 1 then
        montre = Texte.debut(montre, math.max(1, Texte.longueur(montre) - 1)) .. '…'
    end
    return montre
end

-- Un texte coupé en `maxi` lignes au plus : la dernière finit par « … » quand il dépasse.
local function coupeBornee(texte, largeur, police, retrait, maxi)
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

-- Le nom d'un axe de leçon (« Lumière »), relu au besoin d'après sa clé.
local function nomAxe(p)
    if type(p.nom) == 'string' and p.nom ~= '' then
        return p.nom
    end
    for _, axe in ipairs(Conversation.AXES_LECON) do
        if axe.cle == p.axe then
            return axe.nom
        end
    end
    return tostring(p.axe or '?')
end

-- « ★★★☆☆ » : une note de 0 à 5 étoiles.
function Fil.etoiles(note)
    local n = math.max(0, math.min(5, math.floor(tonumber(note) or 0)))
    return string.rep('★', n) .. string.rep('☆', 5 - n)
end

-- Une note proposée sur une ligne : « ★★★☆☆ DSCF4961.RAF · à vérifier · raison »,
-- « ⚑ Rejeter photo 53636310 · raison », « ✕ ★★☆☆☆ DSCF4962.RAF · photo introuvable ». Claude ne
-- propose jamais 5 étoiles : une note lue au-dessus de 4 se montre à 4.
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
                for _, l in ipairs(Fil.couper(montre, largeur, Fil.polices[g] or 'texte', retrait)) do
                    lignes[#lignes + 1] = { genre = g, texte = l, element = element, icone = premiere and icone or nil }
                    premiere = false
                end
            end
        end
    end
end

-- Les lignes d'un seul élément (sans les lignes vides qui l'entourent).
function Fil.lignesElement(e, i, largeur)
    local lignes = {}
    local g = e.genre
    if g == 'dany' then
        ajouterTexte(lignes, e.texte or '', 'dany', largeur, i, 'dany')
        if type(e.style) == 'string' and e.style ~= '' then
            lignes[#lignes + 1] = { genre = 'note', texte = "Style : " .. e.style, element = i }
        end
        for n, chemin in ipairs(e.images or {}) do
            lignes[#lignes + 1] = { genre = 'apercu', texte = "Photo jointe " .. n .. " · cliquer pour l'agrandir", element = i, image = chemin, icone = 'apercu' }
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
        local icone = e.etat == 'erreur' and 'erreur' or (e.etat == 'enCours' and 'cours' or 'ok')
        local texte = e.texte ~= '' and e.texte or (e.outil or 'outil')
        if Conversation.estEtape(e) then
            texte = uneLigne(texte, largeur - Fil.largeur(Fil.SUFFIXE_ETAPE, 'mono'), 'mono') .. Fil.SUFFIXE_ETAPE
        else
            texte = uneLigne(texte, largeur, 'mono')
        end
        lignes[1] = { genre = 'outil', texte = texte, element = i, icone = icone }
    elseif g == 'apercu' then
        for n, chemin in ipairs(e.images or {}) do
            lignes[#lignes + 1] = { genre = 'apercu', texte = (#e.images > 1 and ("Aperçu " .. n) or "Aperçu") .. " de Claude · cliquer pour l'agrandir",
                element = i, image = chemin, icone = 'apercu' }
        end
    elseif g == 'proposition' then
        local etat = ({ enAttente = "en attente de votre accord", acceptee = "acceptée", refusee = "refusée",
            ajustee = "à ajuster", faite = "à faire vous-même" })[e.etat or ''] or ''
        ajouterTexte(lignes, "Proposition" .. (etat ~= '' and (" " .. etat) or "") .. (Texte.nettoyer(e.texte) ~= '' and (" : " .. e.texte) or ""),
            'proposition', largeur, i, 'proposition')
        for _, ch in ipairs(e.changements or {}) do
            local texte = string.format("%s : %s → %s", ch.libelle or '?', ch.avant or '—', ch.apres or '—')
            for _, l in ipairs(Fil.couper(texte, largeur - 16, 'mono', '  ')) do
                lignes[#lignes + 1] = { genre = 'outil', texte = '  ' .. l, element = i }
            end
        end
        for n, chemin in ipairs(e.images or {}) do
            lignes[#lignes + 1] = { genre = 'apercu', texte = (n == 1 and "Avant / après" or ("Rendu " .. n)) .. " · cliquer pour l'agrandir",
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
    elseif g == 'lecon' then
        -- La carte « Leçon de la photo » (1.3) : refusée ou interrompue, une ligne « Leçon non
        -- rangée : … » ; sinon le titre (● pendant l'appel, puis ⓘ), et pour chaque axe, dans
        -- l'ordre Lumière, Couleur, Composition, ce qui manquait puis la prise de vue (« Rien ne
        -- manquait. » puis « À refaire : … » pour un axe sans défaut). Le texte de Claude ne passe
        -- pas par le Markdown du fil : il reste une phrase, jamais une puce.
        if e.etat == 'erreur' then
            local raison = Texte.nettoyer(e.texte or '')
            local texte = "Leçon non rangée : " .. (raison ~= '' and raison or "l'appel n'a pas abouti.")
            for n, t in ipairs(coupeBornee(texte, largeur, 'texte', '', Fil.LIGNES_ERREUR_LECON)) do
                lignes[#lignes + 1] = { genre = 'note', texte = t, element = i, icone = n == 1 and 'erreur' or nil }
            end
        else
            local titre = "Leçon de la photo"
            if type(e.fichier) == 'string' and e.fichier ~= '' then
                titre = titre .. " · " .. e.fichier
            end
            lignes[1] = { genre = 'proposition', texte = uneLigne(titre, largeur, 'gras'), element = i,
                icone = e.etat == 'enCours' and 'cours' or 'note' }
            for _, p in ipairs(e.points or {}) do
                lignes[#lignes + 1] = { genre = 'titre', texte = uneLigne(nomAxe(p), largeur, 'gras'), element = i }
                local manque = type(p.manque) == 'string' and Texte.nettoyer(p.manque) or ''
                local prise = type(p.prise_de_vue) == 'string' and Texte.nettoyer(p.prise_de_vue) or ''
                local moities = manque ~= '' and { "Ce qui manquait : " .. manque, "À la prise de vue : " .. prise }
                    or { "Rien ne manquait.", "À refaire : " .. prise }
                for _, m in ipairs(moities) do
                    for _, t in ipairs(coupeBornee(Fil.RETRAIT_LECON .. m, largeur, 'texte', Fil.RETRAIT_LECON, Fil.LIGNES_MOITIE_LECON)) do
                        lignes[#lignes + 1] = { genre = 'claude', texte = t, element = i }
                    end
                end
            end
            -- Fait, mais pas rangé (module d'avant la 1.3) ou gardé pour la session seulement : la
            -- remarque du connecteur ; non rangé sans remarque, la carte le dit quand même.
            local remarque = type(e.remarque) == 'string' and Texte.nettoyer(e.remarque) or ''
            if remarque == '' and e.rangee == false then
                remarque = "Leçon non rangée dans le carnet de progrès."
            end
            if remarque ~= '' then
                for n, t in ipairs(coupeBornee(remarque, largeur, 'texte', '', Fil.LIGNES_REMARQUE_LECON)) do
                    lignes[#lignes + 1] = { genre = 'note', texte = t, element = i,
                        icone = n == 1 and (e.rangee == false and 'erreur' or 'note') or nil }
                end
            end
        end
    elseif g == 'exercice' then
        -- « Je le fais » (1.3) : le titre (● pendant un appel), puis la liste dans l'ordre du
        -- panneau Développement, ou, comparé, l'écart principal et chaque écart (✓ comme Claude).
        local icone = e.etat == 'erreur' and 'erreur'
            or ((e.etat == 'enCours' or e.comparaisonEnCours) and 'cours' or 'proposition')
        for n, t in ipairs(coupeBornee(Fil.titreExercice(e), largeur, 'gras', '', Fil.LIGNES_ERREUR_EXERCICE)) do
            lignes[#lignes + 1] = { genre = 'proposition', texte = t, element = i, icone = n == 1 and icone or nil }
        end
        local liste = {}
        if e.etat == 'comparee' then
            local principal = Fil.textePrincipal(e)
            if principal ~= '' then
                for _, t in ipairs(coupeBornee('  ' .. principal, largeur - 16, 'mono', '  ', Fil.LIGNES_PRINCIPAL)) do
                    lignes[#lignes + 1] = { genre = 'outil', texte = t, element = i }
                end
            end
            for _, x in ipairs(e.ecarts or {}) do
                liste[#liste + 1] = (x.sorte == 'comme_claude' and '✓ ' or '• ') .. tostring(x.texte or x.reglage or '?')
            end
        elseif e.etat == 'aFaire' then
            for k, x in ipairs(e.aFaire or {}) do
                liste[#liste + 1] = tostring(tonumber(x.n) or k) .. '. ' .. tostring(x.texte or x.reglage or x.cle or '?')
            end
        end
        for n, t in ipairs(liste) do
            if n > Fil.REGLAGES_MONTRES then
                local reste = #liste - Fil.REGLAGES_MONTRES
                lignes[#lignes + 1] = { genre = 'outil', texte = '  … et ' .. reste .. (reste == 1 and ' autre' or ' autres'), element = i }
                break
            end
            lignes[#lignes + 1] = { genre = 'outil', texte = uneLigne('  ' .. t, largeur - 16, 'mono'), element = i }
        end
    elseif g == 'note' then
        ajouterTexte(lignes, e.texte or '', 'note', largeur, i, 'note')
    end
    return lignes
end

-- « 2 écarts », « 1 réglage », « aucun écart ».
local function compte(n, un, plusieurs, aucun)
    if n == 0 then
        return aucun
    end
    return n .. ' ' .. (n > 1 and plusieurs or un)
end

-- Les écarts d'un exercice comparé (ceux qui ne sont pas « comme Claude ») et le nombre de réglages
-- comparés.
function Fil.ecartsExercice(e)
    local n = 0
    for _, x in ipairs(e.ecarts or {}) do
        if x.sorte ~= 'comme_claude' then
            n = n + 1
        end
    end
    return n, #(e.ecarts or {})
end

-- L'écart principal d'un exercice comparé, prêt à montrer : « Écart principal : … » quand il se
-- voit ; sinon le texte du connecteur tel quel (« Aucun écart mesuré ne dépasse… », « Écart
-- principal non mesuré… »), sans le préfixe redoublé ; '' sans texte.
function Fil.textePrincipal(e)
    local p = type(e.principal) == 'table' and e.principal or nil
    local texte = p and Texte.nettoyer(p.texte or '') or ''
    if texte == '' then
        return ''
    end
    return p.visible == true and ("Écart principal : " .. texte) or texte
end

-- Le titre d'un exercice « Je le fais » dans le fil.
function Fil.titreExercice(e)
    if e.etat == 'erreur' then
        local raison = Texte.nettoyer(e.texte or '')
        return "Je le fais · non abouti : " .. (raison ~= '' and raison or "l'appel n'a pas abouti.")
    elseif e.etat == 'enCours' then
        return "Je le fais · liste en préparation…"
    end
    local titre
    if e.etat == 'comparee' then
        local ecarts, total = Fil.ecartsExercice(e)
        titre = "Je le fais · comparée : " .. compte(ecarts, "écart", "écarts", "aucun écart") .. " sur " .. total
    else
        titre = "Je le fais · " .. compte(#(e.aFaire or {}), "réglage", "réglages", "aucun réglage") .. ", dans l'ordre du panneau Développement"
    end
    if e.comparaisonEnCours then
        titre = titre .. " · comparaison en cours…"
    elseif type(e.comparaisonRefusee) == 'string' then
        -- Un refus qui peut se refaire (Conversation.completerExercice) : l'exercice reste.
        titre = titre .. " · comparaison non aboutie : " .. Texte.nettoyer(e.comparaisonRefusee)
    end
    return titre
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

-- Ce qui change l'affichage d'une leçon (pour la signature du cache) : son fichier, sa photo, son
-- rangement et ses points.
local function signatureLecon(e)
    if e.genre ~= 'lecon' then
        return ''
    end
    local morceaux = { tostring(e.fichier), tostring(e.photo), tostring(e.rangee), tostring(e.remarque) }
    for _, p in ipairs(type(e.points) == 'table' and e.points or {}) do
        morceaux[#morceaux + 1] = table.concat({ tostring(p.axe), tostring(p.nom), tostring(p.manque), tostring(p.prise_de_vue) }, '\2')
    end
    return table.concat(morceaux, '\3')
end

-- Ce qui change l'affichage d'un exercice « Je le fais » (pour la signature du cache) : son titre,
-- sa liste, ses écarts et l'écart principal.
local function signatureExercice(e)
    if e.genre ~= 'exercice' then
        return ''
    end
    local morceaux = { Fil.titreExercice(e), tostring(e.comparaisonEnCours) }
    for _, x in ipairs(type(e.aFaire) == 'table' and e.aFaire or {}) do
        morceaux[#morceaux + 1] = tostring(x.n) .. '\2' .. tostring(x.texte)
    end
    for _, x in ipairs(type(e.ecarts) == 'table' and e.ecarts or {}) do
        morceaux[#morceaux + 1] = tostring(x.sorte) .. '\2' .. tostring(x.texte)
    end
    morceaux[#morceaux + 1] = Fil.textePrincipal(e)
    return table.concat(morceaux, '\3')
end

-- Vrai si deux éléments voisins se suivent sans ligne vide (outils et aperçus d'une même série).
local function colles(a, b)
    local serie = { outil = true, apercu = true }
    return serie[a.genre] and serie[b.genre]
end

-- Toutes les lignes du fil. `cache` (facultatif) garde les lignes de chaque élément tant qu'il ne
-- change pas : pendant que Claude écrit, seul le dernier élément est recoupé.
function Fil.lignes(c, largeur, cache)
    largeur = largeur - Fil.MARGE
    local lignes = {}
    local precedent
    for i, e in ipairs(c.elements or {}) do
        local signature = table.concat({ largeur, e.genre or '', e.etat or '', tostring(e.partiel), #(e.images or {}),
            #(e.changements or {}), e.style or '', e.texte or '', signatureNotes(e), #(e.etapes or {}),
            tostring(Conversation.estEtape(e)), signatureLecon(e), signatureExercice(e) }, '\1')
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
        if #siennes > 0 then
            if precedent and not colles(precedent, e) then
                lignes[#lignes + 1] = { genre = 'vide', texte = '' }
            end
            for _, l in ipairs(siennes) do
                lignes[#lignes + 1] = l
            end
            precedent = e
        end
    end
    return lignes
end

-- La page Carnet de progrès (1.3) ----------------------------------------------------------------
-- Le résumé du carnet (Carnet.resumer, du module) mis en lignes de genres existants, sans
-- élément de conversation : le titre ; la note (sur quelles photos, par mois de prise de vue) et
-- la remarque ; le tableau des défauts en `outil` (police mono : colonnes alignées par des
-- espaces, « n/sur » par mois, « — » sans photo), une rangée par défaut qui porte son code
-- (`defaut` : un clic donne ses photos) ; « Ce qui progresse » (ou « Ce qui recule ») et « À
-- travailler à la prochaine sortie », titres et puces ; puis la ligne d'action `apercu` (bleue)
-- « Demander à Claude ce qu'il en pense › » (`action = 'demander'`). Les phrases et les titres
-- viennent du résumé (Carnet.resumer, seule copie) ; seuls les mots de la page sont écrits ici. Pas
-- de barres ▁…█ : elles demanderaient de remesurer les polices (Metriques.lua).
-- `page` : le résumé ; nil pendant sa lecture ; { erreur = texte } s'il ne s'est pas lu.
-- `titre` : celui de la page tant que le résumé ne le donne pas (Carnet.TITRES.carnet).
Fil.DEMANDER_CARNET = "Demander à Claude ce qu'il en pense ›"
Fil.AIDE_TABLEAU_CARNET = "Un clic sur une ligne du tableau donne ses photos."
Fil.LECTURE_CARNET = "Lecture du carnet de progrès…"
Fil.ERREUR_CARNET = "Le carnet de progrès ne s'est pas lu : "
-- Espaces entre deux colonnes du tableau ; caractères au plus de la colonne Défaut (les libellés du
-- connecteur en font 40 au plus, PriseDeVue.swift).
Fil.ECART_COLONNES = 3
Fil.LIBELLE_CARNET_MAX = 40

local function texteOuNil(valeur)
    if type(valeur) == 'string' and Texte.nettoyer(valeur) ~= '' then
        return Texte.nettoyer(valeur)
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

local function aGauche(texte, n)
    return texte .. string.rep(' ', n - Texte.longueur(texte))
end

local function aDroite(texte, n)
    return string.rep(' ', n - Texte.longueur(texte)) .. texte
end

-- Les rangées du tableau, en texte aligné par des espaces (un caractère par colonne de la police
-- mono) : l'en-tête (« Défaut », puis le mois abrégé, avec l'année quand les mois en changent),
-- puis une rangée par défaut, { texte, defaut = code }.
function Fil.tableauCarnet(page)
    local mois = type(page.mois) == 'table' and page.mois or {}
    local defauts = type(page.defauts) == 'table' and page.defauts or {}
    local plusieurs = false
    for _, m in ipairs(mois) do
        if m.annee ~= (mois[1] or {}).annee then
            plusieurs = true
        end
    end
    local entetes = {}
    for i, m in ipairs(mois) do
        local nom = tostring(m.court or m.nom or m.cle or '?')
        entetes[i] = (plusieurs and m.annee) and (nom .. ' ' .. tostring(m.annee)) or nom
    end
    local premiere = texteOuNil(type(page.titres) == 'table' and page.titres.defaut) or "Défaut"
    local large = Texte.longueur(premiere)
    local libelles = {}
    for k, d in ipairs(defauts) do
        local l = texteOuNil(d.libelle) or tostring(d.code or '?')
        if Texte.longueur(l) > Fil.LIBELLE_CARNET_MAX then
            l = Texte.debut(l, Fil.LIBELLE_CARNET_MAX - 1) .. '…'
        end
        libelles[k] = l
        large = math.max(large, Texte.longueur(l))
    end
    local larges = {}
    for i, e in ipairs(entetes) do
        local w = Texte.longueur(e)
        for _, d in ipairs(defauts) do
            w = math.max(w, Texte.longueur(Fil.celluleCarnet(type(d.par_mois) == 'table' and d.par_mois[i])))
        end
        larges[i] = w
    end
    local ecart = string.rep(' ', Fil.ECART_COLONNES)
    local function rangee(tete, cellules)
        local morceaux = { aGauche(tete, large) }
        for i, c in ipairs(cellules) do
            morceaux[#morceaux + 1] = aDroite(c, larges[i])
        end
        return table.concat(morceaux, ecart)
    end
    local rangees = { { texte = rangee(premiere, entetes) } }
    for k, d in ipairs(defauts) do
        local cellules = {}
        for i = 1, #mois do
            cellules[i] = Fil.celluleCarnet(type(d.par_mois) == 'table' and d.par_mois[i])
        end
        rangees[#rangees + 1] = { texte = rangee(libelles[k], cellules), defaut = d.code }
    end
    return rangees
end

function Fil.lignesCarnet(page, largeur, titre)
    largeur = largeur - Fil.MARGE
    local lignes = {}
    local function paragraphe(genre, texte, icone, retrait)
        for n, l in ipairs(Fil.couper(texte, largeur, Fil.polices[genre], retrait)) do
            lignes[#lignes + 1] = { genre = genre, texte = l, icone = n == 1 and icone or nil }
        end
    end
    local function vide()
        lignes[#lignes + 1] = { genre = 'vide', texte = '' }
    end
    local function intertitre(texte)
        lignes[#lignes + 1] = { genre = 'titre', texte = uneLigne(texte, largeur, 'gras') }
    end
    -- Une puce comme celles de Claude (Fil.ligneMarkdown) ; `suite` : une ligne retirée dessous.
    local function puce(texte, suite)
        paragraphe('claude', '•  ' .. texte, nil, '    ')
        if suite then
            paragraphe('claude', '    ' .. suite, nil, '    ')
        end
    end
    local titres = type(page) == 'table' and type(page.titres) == 'table' and page.titres or {}
    intertitre(texteOuNil(titres.carnet) or texteOuNil(titre) or "Carnet de progrès")
    if type(page) ~= 'table' then
        paragraphe('note', Fil.LECTURE_CARNET, 'cours')
        return lignes
    end
    if page.erreur ~= nil then
        paragraphe('note', Fil.ERREUR_CARNET .. (texteOuNil(tostring(page.erreur)) or '?'), 'erreur')
        return lignes
    end
    if texteOuNil(page.note) then
        paragraphe('note', texteOuNil(page.note), 'note')
    end
    if texteOuNil(page.remarque) then
        paragraphe('note', texteOuNil(page.remarque))
    end
    local defauts = type(page.defauts) == 'table' and page.defauts or {}
    if page.vide == true or #defauts == 0 then
        return lignes
    end

    vide()
    for _, r in ipairs(Fil.tableauCarnet(page)) do
        lignes[#lignes + 1] = { genre = 'outil', texte = uneLigne(r.texte, largeur, 'mono'), defaut = r.defaut }
    end
    paragraphe('note', Fil.AIDE_TABLEAU_CARNET)

    -- Ce qui progresse et ce qui recule (chacun s'il y en a) ; sans tendance, pourquoi.
    local progresse = type(page.progresse) == 'table' and page.progresse or {}
    local recule = type(page.recule) == 'table' and page.recule or {}
    vide()
    if #progresse > 0 or #recule == 0 then
        intertitre(texteOuNil(titres.progresse) or "Ce qui progresse")
        for _, x in ipairs(progresse) do
            puce(texteOuNil(x.texte) or tostring(x.libelle or x.code or '?'))
        end
        if #progresse == 0 and texteOuNil(page.aucune_tendance) then
            paragraphe('note', texteOuNil(page.aucune_tendance))
        end
    end
    if #recule > 0 then
        if #progresse > 0 then
            vide()
        end
        intertitre(texteOuNil(titres.recule) or "Ce qui recule")
        for _, x in ipairs(recule) do
            puce(texteOuNil(x.texte) or tostring(x.libelle or x.code or '?'))
        end
    end

    -- À travailler à la prochaine sortie : le défaut, puis ce qu'il faut faire à la prise de vue.
    local aTravailler = type(page.a_travailler) == 'table' and page.a_travailler or {}
    vide()
    intertitre(texteOuNil(titres.a_travailler) or "À travailler à la prochaine sortie")
    for _, x in ipairs(aTravailler) do
        puce(texteOuNil(x.texte) or tostring(x.libelle or x.code or '?'), texteOuNil(x.prise_de_vue))
    end
    if #aTravailler == 0 and texteOuNil(page.rien_a_travailler) then
        paragraphe('note', texteOuNil(page.rien_a_travailler))
    end

    vide()
    lignes[#lignes + 1] = { genre = 'apercu', texte = uneLigne(Fil.DEMANDER_CARNET, largeur, 'texte'), action = 'demander' }
    return lignes
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
