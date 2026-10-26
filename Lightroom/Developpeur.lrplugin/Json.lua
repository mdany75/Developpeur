-- Json.lua : lecture et écriture JSON (Lightroom n'en fournit pas aux modules externes).
-- Les nombres sont lus et écrits sans passer par la locale du système : avec une locale
-- française, la bibliothèque C écrirait « 0,35 ».
-- Json.decode(texte, rythme, pas) : avec `rythme`, une fonction appelée toutes les `pas` valeurs
-- lues dans un objet ou un tableau (5 000 par défaut), un grand texte se lit par morceaux : le relevé
-- du Suivi (Releve.lua, jusqu'à 250 000 originaux, plus de 100 Mo) et la réponse de --graphiques
-- (FenetreSuivi.lua) y rendent la main à Lightroom (correctif 1.3.8). Le compte est propre à chaque
-- lecture : deux lectures de deux tâches qui s'entremêlent ne se gênent pas. Json.ecrivain(ecrire)
-- écrit un objet morceau par morceau (le relevé du Suivi, entrée par entrée).

local Json = {}

-- Valeur JSON null, distincte de nil (qui efface une clé).
Json.null = setmetatable({}, { __tostring = function() return 'null' end })

local marqueTableau = {}

-- Marque une table comme tableau JSON, même vide (« [] » plutôt que « {} »).
function Json.tableau(t)
    return setmetatable(t or {}, marqueTableau)
end

-- Écriture -------------------------------------------------------------------

local echappements = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function chaine(s)
    local echappee = s:gsub('[%c"\\]', function(c)
        return echappements[c] or string.format('\\u%04x', c:byte())
    end)
    return '"' .. echappee .. '"'
end

local function nombre(n)
    if n ~= n or n == math.huge or n == -math.huge then
        return 'null'
    end
    if n == math.floor(n) and math.abs(n) < 1e15 then
        return string.format('%d', n)
    end
    local texte = string.format('%.10g', n)
    return (texte:gsub(',', '.'))
end

local function estTableau(t)
    if getmetatable(t) == marqueTableau then
        return true
    end
    local n = 0
    for cle in pairs(t) do
        if type(cle) ~= 'number' or cle <= 0 or cle % 1 ~= 0 then
            return false
        end
        n = n + 1
    end
    if n == 0 then
        return false
    end
    for i = 1, n do
        if t[i] == nil then
            return false
        end
    end
    return true
end

local ecrire

ecrire = function(valeur, parents)
    local genre = type(valeur)
    if valeur == nil or valeur == Json.null then
        return 'null'
    elseif genre == 'boolean' then
        return valeur and 'true' or 'false'
    elseif genre == 'number' then
        return nombre(valeur)
    elseif genre == 'string' then
        return chaine(valeur)
    elseif genre == 'table' then
        if parents[valeur] then
            error("Json : table circulaire", 0)
        end
        parents[valeur] = true
        local morceaux = {}
        local texte
        if estTableau(valeur) then
            for i = 1, #valeur do
                morceaux[i] = ecrire(valeur[i], parents)
            end
            texte = '[' .. table.concat(morceaux, ',') .. ']'
        else
            local cles = {}
            for cle in pairs(valeur) do
                cles[#cles + 1] = tostring(cle)
            end
            table.sort(cles)
            for _, cle in ipairs(cles) do
                local element = valeur[cle]
                if element == nil then
                    element = valeur[tonumber(cle)]
                end
                morceaux[#morceaux + 1] = chaine(cle) .. ':' .. ecrire(element, parents)
            end
            texte = '{' .. table.concat(morceaux, ',') .. '}'
        end
        parents[valeur] = nil
        return texte
    end
    error("Json : type non pris en charge (" .. genre .. ")", 0)
end

function Json.encode(valeur)
    return ecrire(valeur, {})
end

-- Un objet JSON écrit morceau par morceau par `ecrire(texte)` (correctif 1.3.8 : le relevé du Suivi,
-- jusqu'à 250 000 originaux, s'écrit entrée par entrée, Fichiers.ecrireParMorceaux) : `ouvrir()` et
-- `fermer()` un objet, `cle(k)` avant chaque valeur, puis `valeur(v)` (comme Json.encode) ou
-- `brut(t)` (un texte déjà rendu par Json.encode, écrit tel quel). Les accolades, les virgules et
-- les clés se font ici : le JSON passe toujours par Json.lua.
function Json.ecrivain(ecrireTexte)
    -- Pour chaque objet ouvert : vrai tant qu'il n'a aucune paire (pas de virgule avant la première).
    local vides = {}
    local w = {}
    function w.ouvrir()
        ecrireTexte('{')
        vides[#vides + 1] = true
    end
    function w.fermer()
        vides[#vides] = nil
        ecrireTexte('}')
    end
    function w.cle(k)
        local n = #vides
        if vides[n] then
            vides[n] = false
        else
            ecrireTexte(',')
        end
        ecrireTexte(chaine(tostring(k)))
        ecrireTexte(':')
    end
    function w.valeur(v)
        ecrireTexte(ecrire(v, {}))
    end
    function w.brut(t)
        ecrireTexte(t)
    end
    return w
end

-- Lecture --------------------------------------------------------------------

local function echec(s, i, message)
    error(string.format("Json : %s à la position %d", message, i), 0)
end

local function blancs(s, i)
    local _, fin = s:find('^[ \t\r\n]*', i)
    return fin + 1
end

local function utf8(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local lireValeur

local function lireChaine(s, i)
    -- s:sub(i, i) == '"'
    local morceaux = {}
    i = i + 1
    while true do
        local j = s:find('["\\]', i)
        if not j then
            echec(s, i, "chaîne non terminée")
        end
        morceaux[#morceaux + 1] = s:sub(i, j - 1)
        if s:sub(j, j) == '"' then
            return table.concat(morceaux), j + 1
        end
        local c = s:sub(j + 1, j + 1)
        local simples = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
        if simples[c] then
            morceaux[#morceaux + 1] = simples[c]
            i = j + 2
        elseif c == 'u' then
            local hex = s:match('^%x%x%x%x', j + 2)
            if not hex then
                echec(s, j, "échappement \\u invalide")
            end
            local code = tonumber(hex, 16)
            i = j + 6
            if code >= 0xD800 and code <= 0xDBFF then
                local bas = s:match('^\\u(%x%x%x%x)', i)
                local codeBas = bas and tonumber(bas, 16)
                if codeBas and codeBas >= 0xDC00 and codeBas <= 0xDFFF then
                    code = 0x10000 + (code - 0xD800) * 0x400 + (codeBas - 0xDC00)
                    i = i + 6
                end
            end
            morceaux[#morceaux + 1] = utf8(code)
        else
            echec(s, j, "échappement invalide")
        end
    end
end

local function chiffres(s, i)
    local texte = s:match('^%d+', i)
    if not texte then
        echec(s, i, "nombre invalide")
    end
    local valeur = 0
    for k = 1, #texte do
        valeur = valeur * 10 + (texte:byte(k) - 48)
    end
    return valeur, #texte
end

local function lireNombre(s, i)
    local negatif = false
    if s:sub(i, i) == '-' then
        negatif = true
        i = i + 1
    end
    local valeur, longueur = chiffres(s, i)
    i = i + longueur
    if s:sub(i, i) == '.' then
        local fraction, n = chiffres(s, i + 1)
        valeur = valeur + fraction / (10 ^ n)
        i = i + 1 + n
    end
    local e = s:sub(i, i)
    if e == 'e' or e == 'E' then
        i = i + 1
        local signe = 1
        local c = s:sub(i, i)
        if c == '-' then
            signe = -1
            i = i + 1
        elseif c == '+' then
            i = i + 1
        end
        local exposant, n = chiffres(s, i)
        valeur = valeur * 10 ^ (signe * exposant)
        i = i + n
    end
    if negatif then
        valeur = -valeur
    end
    return valeur, i
end

-- `r` : le rythme d'une lecture ({ n, pas, fn }), nil sans rythme.
local function compter(r)
    r.n = r.n + 1
    if r.n >= r.pas then
        r.n = 0
        r.fn()
    end
end

lireValeur = function(s, i, r)
    i = blancs(s, i)
    local c = s:sub(i, i)
    if c == '{' then
        local objet = {}
        i = blancs(s, i + 1)
        if s:sub(i, i) == '}' then
            return objet, i + 1
        end
        while true do
            i = blancs(s, i)
            if s:sub(i, i) ~= '"' then
                echec(s, i, "clé attendue")
            end
            local cle
            cle, i = lireChaine(s, i)
            i = blancs(s, i)
            if s:sub(i, i) ~= ':' then
                echec(s, i, "« : » attendu")
            end
            local valeur
            valeur, i = lireValeur(s, i + 1, r)
            if valeur ~= Json.null then
                objet[cle] = valeur
            end
            if r then
                compter(r)
            end
            i = blancs(s, i)
            local suite = s:sub(i, i)
            if suite == '}' then
                return objet, i + 1
            elseif suite ~= ',' then
                echec(s, i, "« , » ou « } » attendu")
            end
            i = i + 1
        end
    elseif c == '[' then
        local tableau = Json.tableau()
        i = blancs(s, i + 1)
        if s:sub(i, i) == ']' then
            return tableau, i + 1
        end
        while true do
            local valeur
            valeur, i = lireValeur(s, i, r)
            tableau[#tableau + 1] = valeur
            if r then
                compter(r)
            end
            i = blancs(s, i)
            local suite = s:sub(i, i)
            if suite == ']' then
                return tableau, i + 1
            elseif suite ~= ',' then
                echec(s, i, "« , » ou « ] » attendu")
            end
            i = i + 1
        end
    elseif c == '"' then
        return lireChaine(s, i)
    elseif c == '-' or c:match('%d') then
        return lireNombre(s, i)
    elseif s:sub(i, i + 3) == 'true' then
        return true, i + 4
    elseif s:sub(i, i + 4) == 'false' then
        return false, i + 5
    elseif s:sub(i, i + 3) == 'null' then
        return Json.null, i + 4
    end
    echec(s, i, "valeur attendue")
end

-- Dans un objet, null efface la clé ; dans un tableau, il reste Json.null. `rythme` (facultatif) :
-- appelé toutes les `pas` valeurs (voir l'en-tête).
function Json.decode(texte, rythme, pas)
    if type(texte) ~= 'string' then
        error("Json : texte attendu", 0)
    end
    local r = type(rythme) == 'function' and { n = 0, pas = math.max(1, tonumber(pas) or 5000), fn = rythme } or nil
    local valeur, i = lireValeur(texte, 1, r)
    i = blancs(texte, i)
    if i <= #texte then
        echec(texte, i, "caractères en trop")
    end
    return valeur
end

return Json
