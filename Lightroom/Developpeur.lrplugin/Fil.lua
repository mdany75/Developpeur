-- Fil.lua : le fil d'une conversation mis en lignes pour la fenêtre. Le SDK de Lightroom ne sait
-- pas ajouter de vues à une fenêtre ouverte, ni faire défiler une zone par programme, et une vue
-- masquée garde sa place : la fenêtre montre donc une grille de lignes de hauteur fixe, que ce
-- module remplit. Chaque ligne a un genre (sa police, sa couleur, son icône) et un texte coupé
-- à la largeur de la colonne d'après la chasse mesurée des polices (Metriques.lua).
--
-- Ligne : { genre, texte, icone, element (indice dans le fil), image (chemin relatif) }
--   genres : 'dany', 'claude', 'titre', 'outil', 'apercu', 'proposition', 'note', 'vide'
--   icones : 'dany', 'ok', 'cours', 'erreur', 'apercu', 'proposition', 'note' ou nil

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

-- Largeur d'un texte dans une police.
function Fil.largeur(texte, police)
    local m = Metriques[police] or Metriques.texte
    local chasse = m.chasse
    local defaut = chasse['M']
    local total = 0
    for c in Texte.caracteres(texte) do
        total = total + (chasse[c] or defaut)
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
        lignes[#lignes + 1] = ligne
    end
    local function tient(t)
        return Fil.largeur(t, police) <= largeur
    end
    -- Mots et espaces, dans l'ordre.
    for espace, mot in (texte:gsub('\t', '    ')):gmatch('(%s*)(%S*)') do
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
        local coupe = Fil.couper(texte, largeur, 'mono')
        local montre = coupe[1]
        if #coupe > 1 then
            montre = Texte.debut(montre, math.max(1, Texte.longueur(montre) - 1)) .. '…'
        end
        lignes[1] = { genre = 'outil', texte = montre, element = i, icone = icone }
    elseif g == 'apercu' then
        for n, chemin in ipairs(e.images or {}) do
            lignes[#lignes + 1] = { genre = 'apercu', texte = (#e.images > 1 and ("Aperçu " .. n) or "Aperçu") .. " de Claude · cliquer pour l'agrandir",
                element = i, image = chemin, icone = 'apercu' }
        end
    elseif g == 'proposition' then
        local etat = ({ enAttente = "en attente de votre accord", acceptee = "acceptée", refusee = "refusée",
            ajustee = "à ajuster" })[e.etat or ''] or ''
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
    elseif g == 'note' then
        ajouterTexte(lignes, e.texte or '', 'note', largeur, i, 'note')
    end
    return lignes
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
            #(e.changements or {}), e.style or '', e.texte or '' }, '\1')
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

-- La fenêtre de lignes à montrer : `nombre` lignes, `defilement` lignes au-dessus de la fin.
-- Rend l'indice de la première ligne montrée et le défilement ramené dans les bornes.
function Fil.fenetre(total, nombre, defilement)
    local maxi = math.max(0, total - nombre)
    defilement = math.max(0, math.min(defilement or 0, maxi))
    local premiere = math.max(1, total - nombre - defilement + 1)
    return premiere, defilement
end

return Fil
