-- Compat.lua : le module emploie os.time et os.date (dates Unix des conversations). Le SDK ne
-- dit pas s'ils sont offerts aux modules externes : s'ils manquaient, ils sont remplacés ici par
-- LrDate (secondes depuis le 1er janvier 2001, d'où l'écart).

local LrDate = import 'LrDate'

local Compat = {}

local EPOQUE = 978307200

if type(os.time) ~= 'function' then
    os.time = function(t)
        if type(t) == 'table' then
            return math.floor(LrDate.timeFromComponents(t.year, t.month, t.day, t.hour or 12, t.min or 0, t.sec or 0, 'local') + EPOQUE)
        end
        return math.floor(LrDate.currentTime() + EPOQUE)
    end
    Compat.remplace = true
end

if type(os.date) ~= 'function' then
    os.date = function(format, t)
        local cocoa = (t or os.time()) - EPOQUE
        if format == '*t' then
            local annee, mois, jour, heure, minute, seconde = LrDate.timestampToComponents(cocoa)
            return { year = annee, month = mois, day = jour, hour = heure, min = minute, sec = math.floor(seconde or 0) }
        end
        return LrDate.timeToUserFormat(cocoa, format)
    end
    Compat.remplace = true
end

return Compat
