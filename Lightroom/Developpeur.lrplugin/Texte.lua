-- Texte.lua : outils de texte en UTF-8 pour le Lua 5.1 de Lightroom (qui ne connaît que les octets).

local Texte = {}

-- Un caractère UTF-8 : un octet de tête puis ses octets de suite.
Texte.MOTIF_CARACTERE = '[%z\1-\127\194-\244][\128-\191]*'

-- Itère sur les caractères d'un texte.
function Texte.caracteres(s)
    return s:gmatch(Texte.MOTIF_CARACTERE)
end

-- Nombre de caractères (pas d'octets).
function Texte.longueur(s)
    local n = 0
    for _ in Texte.caracteres(s) do
        n = n + 1
    end
    return n
end

-- Les n premiers caractères.
function Texte.debut(s, n)
    local morceaux = {}
    for c in Texte.caracteres(s) do
        if #morceaux >= n then
            break
        end
        morceaux[#morceaux + 1] = c
    end
    return table.concat(morceaux)
end

-- Raccourcit à n caractères au plus, avec « … » à la fin s'il a fallu couper.
function Texte.raccourcir(s, n)
    if Texte.longueur(s) <= n then
        return s
    end
    return Texte.debut(s, n - 1) .. '…'
end

function Texte.nettoyer(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Lettres accentuées → lettres simples, en minuscules (pour chercher sans tenir compte des
-- accents ni des majuscules).
local plis = {
    ['à'] = 'a', ['â'] = 'a', ['ä'] = 'a', ['á'] = 'a', ['ã'] = 'a', ['å'] = 'a',
    ['À'] = 'a', ['Â'] = 'a', ['Ä'] = 'a', ['Á'] = 'a', ['Ã'] = 'a', ['Å'] = 'a',
    ['ç'] = 'c', ['Ç'] = 'c',
    ['é'] = 'e', ['è'] = 'e', ['ê'] = 'e', ['ë'] = 'e', ['É'] = 'e', ['È'] = 'e', ['Ê'] = 'e', ['Ë'] = 'e',
    ['î'] = 'i', ['ï'] = 'i', ['í'] = 'i', ['ì'] = 'i', ['Î'] = 'i', ['Ï'] = 'i', ['Í'] = 'i', ['Ì'] = 'i',
    ['ô'] = 'o', ['ö'] = 'o', ['ó'] = 'o', ['ò'] = 'o', ['õ'] = 'o', ['Ô'] = 'o', ['Ö'] = 'o', ['Ó'] = 'o', ['Ò'] = 'o', ['Õ'] = 'o',
    ['ù'] = 'u', ['û'] = 'u', ['ü'] = 'u', ['ú'] = 'u', ['Ù'] = 'u', ['Û'] = 'u', ['Ü'] = 'u', ['Ú'] = 'u',
    ['ÿ'] = 'y', ['Ÿ'] = 'y', ['ñ'] = 'n', ['Ñ'] = 'n',
    ['œ'] = 'oe', ['Œ'] = 'oe', ['æ'] = 'ae', ['Æ'] = 'ae',
    ['’'] = "'", ['‘'] = "'",
}

function Texte.plier(s)
    local morceaux = {}
    for c in Texte.caracteres(tostring(s or '')) do
        morceaux[#morceaux + 1] = plis[c] or c:lower()
    end
    return table.concat(morceaux)
end

-- Découpe un texte en lignes (les fins de ligne Windows comprises).
function Texte.lignes(s)
    local lignes = {}
    s = tostring(s or ''):gsub('\r\n', '\n'):gsub('\r', '\n')
    for ligne in (s .. '\n'):gmatch('(.-)\n') do
        lignes[#lignes + 1] = ligne
    end
    return lignes
end

-- Entoure un texte de guillemets simples pour /bin/sh.
function Texte.shell(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Nombre écrit à la française (« 0,35 »), sans zéros inutiles.
function Texte.nombre(n)
    if type(n) ~= 'number' then
        return tostring(n)
    end
    if n == math.floor(n) and math.abs(n) < 1e15 then
        return string.format('%d', n)
    end
    -- La locale du système peut déjà écrire une virgule.
    local t = string.format('%.2f', n):gsub(',', '.'):gsub('0+$', ''):gsub('%.$', '')
    return (t:gsub('%.', ','))
end

return Texte
