-- Evenements.lua : lecture des lignes que Claude Code écrit en stream-json (`claude -p
-- --output-format stream-json --verbose --include-partial-messages`). Chaque ligne devient un
-- événement : une table dont `genre` dit ce qu'elle porte. Vérifié avec Claude Code 2.1.303.
--
--   init        session, modele, serveurs = { nom = état }
--   partiel     texte (morceau de texte en train d'arriver)
--   assistant   blocs = { { genre = 'texte', texte } | { genre = 'outil', id, nom, entree } | { genre = 'reflexion' } }
--   resultats   resultats = { { idOutil, textes, images = { { donnees (base64), type } }, erreur } }
--   fin         reussie, interrompue, texte, session, dureeMs, usage, modele, tours
--   limites     cinqHeures, semaine (de 0 à 1), repriseSemaine (secondes Unix)
--   controle    id, reussie (réponse à une interruption)
--   statut      statut
--   ignore

local Json = require 'Json'

local Evenements = {}

local function chaine(v)
    return type(v) == 'string' and v or nil
end

local function nombre(v)
    return type(v) == 'number' and v or nil
end

local function liste(v)
    return type(v) == 'table' and v or {}
end

local function lireUsage(u)
    u = type(u) == 'table' and u or {}
    return {
        entree = nombre(u.input_tokens) or 0,
        sortie = nombre(u.output_tokens) or 0,
        cacheCreation = nombre(u.cache_creation_input_tokens) or 0,
        cacheLecture = nombre(u.cache_read_input_tokens) or 0,
    }
end

-- Claude Code ajoute « [Image: source: …] » après chaque image d'un résultat : pas pour l'utilisateur.
local function texteMontre(t)
    return t:sub(1, 15) ~= '[Image: source:'
end

local function lireResultat(bloc)
    local textes, images = {}, {}
    local contenu = bloc.content
    if type(contenu) == 'string' then
        textes[#textes + 1] = contenu
    elseif type(contenu) == 'table' then
        for _, part in ipairs(contenu) do
            if type(part) == 'table' then
                if part.type == 'text' and chaine(part.text) then
                    if texteMontre(part.text) then
                        textes[#textes + 1] = part.text
                    end
                elseif part.type == 'image' and type(part.source) == 'table' and chaine(part.source.data) then
                    images[#images + 1] = { donnees = part.source.data, type = chaine(part.source.media_type) or 'image/jpeg' }
                end
            end
        end
    end
    return { idOutil = chaine(bloc.tool_use_id) or '', textes = textes, images = images, erreur = bloc.is_error == true }
end

-- L'événement d'un objet JSON déjà lu.
function Evenements.depuis(json)
    if type(json) ~= 'table' then
        return { genre = 'ignore' }
    end
    local genre = json.type
    if genre == 'system' then
        if json.subtype == 'init' then
            local serveurs = {}
            for _, s in ipairs(liste(json.mcp_servers)) do
                if type(s) == 'table' and chaine(s.name) then
                    serveurs[s.name] = chaine(s.status) or ''
                end
            end
            return { genre = 'init', session = chaine(json.session_id) or '', modele = chaine(json.model) or '', serveurs = serveurs }
        elseif json.subtype == 'status' then
            return { genre = 'statut', statut = chaine(json.status) or '' }
        end
        return { genre = 'ignore' }
    elseif genre == 'stream_event' then
        local e = json.event
        if type(e) == 'table' and e.type == 'content_block_delta' and type(e.delta) == 'table'
            and e.delta.type == 'text_delta' and chaine(e.delta.text) then
            return { genre = 'partiel', texte = e.delta.text }
        end
        return { genre = 'ignore' }
    elseif genre == 'assistant' then
        local blocs = {}
        local message = type(json.message) == 'table' and json.message or {}
        for _, b in ipairs(liste(message.content)) do
            if type(b) == 'table' then
                if b.type == 'text' and chaine(b.text) then
                    blocs[#blocs + 1] = { genre = 'texte', texte = b.text }
                elseif b.type == 'tool_use' then
                    blocs[#blocs + 1] = { genre = 'outil', id = chaine(b.id) or '', nom = chaine(b.name) or '',
                        entree = type(b.input) == 'table' and b.input or {} }
                elseif b.type == 'thinking' or b.type == 'redacted_thinking' then
                    blocs[#blocs + 1] = { genre = 'reflexion' }
                end
            end
        end
        return { genre = 'assistant', blocs = blocs }
    elseif genre == 'user' then
        local resultats = {}
        local message = type(json.message) == 'table' and json.message or {}
        for _, b in ipairs(liste(message.content)) do
            if type(b) == 'table' and b.type == 'tool_result' then
                resultats[#resultats + 1] = lireResultat(b)
            end
        end
        if #resultats == 0 then
            return { genre = 'ignore' }
        end
        return { genre = 'resultats', resultats = resultats }
    elseif genre == 'result' then
        local modele
        if type(json.modelUsage) == 'table' then
            local noms = {}
            for nom in pairs(json.modelUsage) do
                noms[#noms + 1] = nom
            end
            table.sort(noms)
            modele = noms[1]
        end
        local sousType = chaine(json.subtype) or ''
        return {
            genre = 'fin',
            reussie = sousType == 'success' and json.is_error ~= true,
            interrompue = sousType == 'error_during_execution',
            texte = chaine(json.result),
            session = chaine(json.session_id) or '',
            dureeMs = nombre(json.duration_ms) or 0,
            usage = lireUsage(json.usage),
            modele = modele,
            tours = nombre(json.num_turns) or 0,
        }
    elseif genre == 'rate_limit_event' then
        local info = type(json.rate_limit_info) == 'table' and json.rate_limit_info or {}
        local fenetres = type(info.unifiedWindows) == 'table' and info.unifiedWindows or {}
        local cinq = type(fenetres.five_hour) == 'table' and fenetres.five_hour or {}
        local sept = type(fenetres.seven_day) == 'table' and fenetres.seven_day or {}
        -- Sans unifiedWindows : la seule limite nommée par rateLimitType.
        if info.rateLimitType == 'five_hour' and cinq.utilization == nil then
            cinq = { utilization = info.utilization, resetsAt = info.resetsAt }
        elseif info.rateLimitType == 'seven_day' and sept.utilization == nil then
            sept = { utilization = info.utilization, resetsAt = info.resetsAt }
        end
        return { genre = 'limites', cinqHeures = nombre(cinq.utilization), semaine = nombre(sept.utilization),
            repriseSemaine = nombre(sept.resetsAt) }
    elseif genre == 'control_response' then
        local r = type(json.response) == 'table' and json.response or {}
        return { genre = 'controle', id = chaine(r.request_id) or '', reussie = r.subtype == 'success' }
    end
    return { genre = 'ignore' }
end

-- L'événement d'une ligne de la sortie ; nil pour une ligne qui n'est pas un objet JSON (Claude
-- Code écrit autre chose quand une option est mauvaise).
function Evenements.lire(ligne)
    if type(ligne) ~= 'string' then
        return nil
    end
    local texte = ligne:match('^%s*(.-)%s*$')
    if texte == '' or texte:sub(1, 1) ~= '{' then
        return nil
    end
    local ok, json = pcall(Json.decode, texte)
    if not ok or type(json) ~= 'table' then
        return nil
    end
    return Evenements.depuis(json)
end

-- Les lignes que la fenêtre écrit sur l'entrée de Claude Code ----------------------------------

-- Un message de l'utilisateur : les images jointes (base64), puis le texte.
function Evenements.messageUtilisateur(texte, images)
    local contenu = Json.tableau()
    for _, image in ipairs(images or {}) do
        contenu[#contenu + 1] = { type = 'image', source = { type = 'base64', media_type = image.type or 'image/jpeg', data = image.donnees } }
    end
    contenu[#contenu + 1] = { type = 'text', text = texte }
    return Json.encode({ type = 'user', message = { role = 'user', content = contenu } })
end

-- Demande d'interruption (réponse : control_response, puis un result « error_during_execution »).
function Evenements.interruption(id)
    return Json.encode({ type = 'control_request', request_id = id, request = { subtype = 'interrupt' } })
end

return Evenements
