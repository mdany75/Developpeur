-- Simulation.lua : imitation minimale du SDK de Lightroom Classic, pour essayer la fenêtre Claude
-- du module hors de Lightroom avec LuaJIT (même Lua 5.1). Installe les globales `import` et
-- `_PLUGIN`. Les fichiers vont dans un dossier personnel temporaire (S.home), jamais dans le vrai.
-- La liaison avec le serveur (Liaison.lua, lue par la fenêtre) se charge sans ses prises : elle
-- n'est jamais démarrée ici (sa suite est Tests/Lua/Liaison).
-- Les tâches (LrTasks.startAsyncTask) ne tournent pas d'elles-mêmes : le test appelle ce qu'il
-- veut éprouver (Moteur.tic…).
--
-- Vues : les règles tirées des constats faits dans Lightroom (« constaté le … ») ou lus dans son
-- code (« relevé dans … ») refusent, à la création d'une vue ou à l'ouverture d'une fenêtre, ce que
-- Lightroom ignorerait ou rendrait mal. Une fenêtre flottante ouverte (S.pendantFenetre) se
-- manipule comme Dany le ferait : S.taper, S.retour et S.cliquer imitent la frappe, la touche Retour
-- et les clics tels qu'ils ont été constatés le 21 octobre 2026 (blocs D1 à D3, D10 et D11 du lot
-- B0 de la fenêtre B) ; un essai peut toujours appeler une action directement.

local S = { taches = {}, dialogues = {}, messages = {}, prefs = {} }

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function executer(commande)
    local r = os.execute(commande)
    return r == 0 or r == true
end

local function lireCommande(commande)
    local f = io.popen(commande)
    local texte = f:read('*a')
    f:close()
    return texte
end

S.home = os.getenv('SIMULATION_HOME') or lireCommande('mktemp -d /tmp/developpeur-fenetre-essai.XXXXXX'):gsub('%s+$', '')
S.plugin = os.getenv('PLUGIN_DIR')

local modules = {}

modules.LrPathUtils = {
    child = function(a, b) return (a:gsub('/$', '')) .. '/' .. b end,
    parent = function(p) return (p:gsub('/[^/]*$', '')) end,
    leafName = function(p) return (p:match('([^/]*)$')) end,
    removeExtension = function(p) return (p:gsub('%.[^./]*$', '')) end,
    getStandardFilePath = function(cle)
        assert(cle == 'home', "getStandardFilePath : " .. tostring(cle))
        return S.home
    end,
}

modules.LrFileUtils = {
    exists = function(p)
        if executer('test -d ' .. q(p)) then
            return 'directory'
        elseif executer('test -e ' .. q(p)) then
            return 'file'
        end
        return false
    end,
    createAllDirectories = function(p) return executer('mkdir -p ' .. q(p)) end,
    delete = function(p) return executer('rm -rf ' .. q(p)) end,
    move = function(a, b) return executer('mv ' .. q(a) .. ' ' .. q(b)) end,
    copy = function(a, b) return executer('cp ' .. q(a) .. ' ' .. q(b)) end,
    moveToTrash = function(p)
        executer('mkdir -p ' .. q(S.home .. '/.Trash'))
        return executer('mv ' .. q(p) .. ' ' .. q(S.home .. '/.Trash/'))
    end,
    directoryEntries = function(d)
        local noms = {}
        for nom in lireCommande('ls -1A ' .. q(d) .. ' 2>/dev/null'):gmatch('[^\n]+') do
            noms[#noms + 1] = d .. '/' .. nom
        end
        local i = 0
        return function()
            i = i + 1
            return noms[i]
        end
    end,
    fileAttributes = function(p)
        local t = lireCommande('stat -f "%m %z" ' .. q(p) .. ' 2>/dev/null')
        local m, z = t:match('(%d+) (%d+)')
        if not m then
            return nil
        end
        return { fileModificationDate = tonumber(m), fileSize = tonumber(z) }
    end,
}

modules.LrTasks = {
    execute = function(commande)
        -- Jamais le vrai presse-papiers du Mac (règle de CLAUDE.md) : presse-papiers.js ne se lance
        -- ici qu'avec un presse-papiers nommé, son troisième argument (Images.coller(nom)). Sans lui
        -- (le clic sur 📋 dans un essai de la fenêtre), la commande est refusée avant de partir.
        if commande:find('presse-papiers.js', 1, true) and not commande:match("presse%-papiers%.js' '[^']*' '[^']+'") then
            error("presse-papiers.js sans presse-papiers nommé : il lirait le vrai presse-papiers du Mac (jamais dans un essai) : "
                .. commande, 2)
        end
        S.dernieresCommandes = S.dernieresCommandes or {}
        S.dernieresCommandes[#S.dernieresCommandes + 1] = commande
        return executer(commande) and 0 or 1
    end,
    sleep = function(s) executer('sleep ' .. tostring(s)) end,
    startAsyncTask = function(fn) S.taches[#S.taches + 1] = fn end,
    pcall = pcall,
    yield = function() end,
    canYield = function() return true end,
}

modules.LrPrefs = {
    prefsForPlugin = function(id)
        id = id or 'module'
        S.prefs[id] = S.prefs[id] or {}
        return S.prefs[id]
    end,
}

modules.LrDate = {
    currentTime = function() return os.time() end,
    timeToUserFormat = function(t, format) return os.date(format, math.floor(t)) end,
}

-- Une photo simulée : nom de fichier, dimensions recadrées, nom par modèle de noms, note et
-- drapeau posés (champs `note` et `pickStatus` de la photo, à poser par l'essai), légende (champs
-- `copie`, `appareil` et `prise`, à poser par l'essai : copyName et cameraModel par
-- getFormattedMetadata, dateTimeOriginal par getRawMetadata, une date de LrDate, ici en secondes
-- Unix comme le LrDate simulé), champs du module (`proprietes`), qui ne s'écrivent que dans une
-- écriture du catalogue.
function S.photo(id, nom, largeur, hauteur)
    local proprietes = {}
    return {
        localIdentifier = id,
        proprietes = proprietes,
        getPropertyForPlugin = function(_, plugin, cle)
            assert(plugin == _PLUGIN, "getPropertyForPlugin : _PLUGIN attendu")
            return proprietes[cle]
        end,
        setPropertyForPlugin = function(_, plugin, cle, valeur)
            assert(plugin == _PLUGIN, "setPropertyForPlugin : _PLUGIN attendu")
            assert(S.enEcriture, "setPropertyForPlugin hors d'une écriture du catalogue")
            proprietes[cle] = valeur
        end,
        getFormattedMetadata = function(self, cle)
            if cle == 'fileName' then
                return nom
            elseif cle == 'copyName' then
                return self.copie
            elseif cle == 'cameraModel' then
                return self.appareil
            end
            return nil
        end,
        getRawMetadata = function(self, cle)
            if cle == 'croppedDimensions' then
                return { width = largeur or 6240, height = hauteur or 4160 }
            elseif cle == 'rating' then
                return self.note
            elseif cle == 'pickStatus' then
                return self.pickStatus
            elseif cle == 'dateTimeOriginal' then
                return self.prise
            end
        end,
        getNameViaPreset = function(_, idModele, texte, sequence)
            return string.format('%s-%s-%d', tostring(idModele), (nom:gsub('%.[^.]*$', '')), sequence)
        end,
        updateAISettings = function() S.calculsIA = (S.calculsIA or 0) + 1 end,
    }
end

-- Collections : l'ensemble « Développeur » avec la collection d'essai « Essais ».
S.collectionEssais = { localIdentifier = 900, getName = function() return 'Essais' end,
    isSmartCollection = function() return false end, getPhotos = function() return S.selection or {} end }
S.ensembleDeveloppeur = { getName = function() return 'Développeur' end, getChildCollections = function() return { S.collectionEssais } end,
    getChildCollectionSets = function() return {} end }

S.catalogue = {
    getTargetPhoto = function() return S.photoActive end,
    getTargetPhotos = function() return S.selection or {} end,
    getPhotoByLocalId = function(_, id) return S.photoActive end,
    setSelectedPhotos = function() end,
    getChildCollections = function() return {} end,
    getChildCollectionSets = function() return { S.ensembleDeveloppeur } end,
    getCollectionByLocalIdentifier = function(_, id) return id == 900 and S.collectionEssais or nil end,
    -- Écriture privée (champs du module seuls, hors de Édition › Annuler) : comptée dans
    -- S.ecrituresPrivees. Une écriture ordinaire n'est pas simulée : la fenêtre n'en fait pas.
    withPrivateWriteAccessDo = function(_, fonction)
        assert(not S.enEcriture, "écriture dans une écriture")
        S.ecrituresPrivees = (S.ecrituresPrivees or 0) + 1
        S.enEcriture = true
        local ok, erreur = pcall(fonction)
        S.enEcriture = false
        assert(ok, erreur)
        return 'executed'
    end,
}

modules.LrApplication = {
    activeCatalog = function() return S.catalogue end,
    versionString = function() return 'simulation' end,
    filenamePresets = function() return { ['Date - Nom du fichier'] = 'ID-DATE' } end,
}

-- Exportation : un fichier par photo, écrit dans le dossier demandé (ou un échec si S.echecRendu).
S.exports = {}
modules.LrExportSession = function(args)
    local session = { args = args }
    S.exports[#S.exports + 1] = session
    function session:renditions()
        local i = 0
        return function()
            i = i + 1
            local photo = args.photosToExport[i]
            if not photo then
                return nil
            end
            local r = args.exportSettings
            local rendu = { photo = photo }
            function rendu:waitForRender()
                if S.echecRendu then
                    return false, S.echecRendu
                end
                local dossier = r.LR_export_destinationPathPrefix .. (r.LR_export_useSubfolder and ('/' .. r.LR_export_destinationPathSuffix) or '')
                os.execute('mkdir -p ' .. q(dossier))
                local chemin = dossier .. '/' .. photo:getFormattedMetadata('fileName'):gsub('%.[^.]*$', '') .. '.jpg'
                local f = io.open(chemin, 'w')
                f:write('JPEG')
                f:close()
                return true, chemin
            end
            return i, rendu
        end
    end
    return session
end

modules.LrColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

modules.LrShell = { revealInShell = function() end }

-- Importé par Liaison.lua ; ses prises ne s'ouvrent pas ici (la liaison n'est jamais démarrée).
modules.LrSocket = {
    bind = function() error("LrSocket.bind : la liaison ne démarre pas dans la suite de la fenêtre") end,
}

-- Toute table donnée à Lightroom (éléments d'une liste ou d'un menu, valeur d'une propriété) est
-- neuve : une table relue par Json.decode porte une métatable, sur laquelle Lightroom bloque
-- (constaté par la liaison, voir docs/SPEC.md, Profil).
local function neuve(valeur, quoi)
    if type(valeur) ~= 'table' or valeur.liaison then
        return
    end
    assert(getmetatable(valeur) == nil, quoi .. " : table avec une métatable (relue par Json.decode ?)")
    for _, element in ipairs(valeur) do
        if type(element) == 'table' then
            assert(getmetatable(element) == nil, quoi .. " : élément avec une métatable (relu par Json.decode ?)")
        end
    end
end
S.neuve = neuve

-- Vues : chaque fabrique rend { genre, args } ; le test parcourt l'arbre.
-- square_button : dans la fabrique de LrView sans être documenté (relevé dans LrView.lua), rendu et
-- cliquable (constaté le 21 octobre 2026, B3 et D5).
S.GENRES_VUES = {
    row = true, column = true, view = true, group_box = true, tab_view = true, tab_view_item = true, scrolled_view = true,
    spacer = true, separator = true, static_text = true, edit_field = true, password_field = true, combo_box = true,
    checkbox = true, radio_button = true, push_button = true, square_button = true, popup_menu = true, simple_list = true,
    slider = true, color_well = true, picture = true, catalog_photo = true,
}

-- Les boutons : un essai qui rassemble les boutons d'une fenêtre (tout bouton passe par F.bouton,
-- recherche par titre…) compte les deux genres.
S.BOUTONS = { push_button = true, square_button = true }

-- Lightroom ignore `visible` lié posé sur ces conteneurs : leurs vues restent montrées (constaté le
-- 20 octobre 2026 : les trois onglets de la Conversation claire s'affichaient superposés). Seules
-- les vues simples se masquent (Vues.masquable), et le f:view : il se cache, se montre et garde sa
-- place (constaté le 21 octobre 2026, D10), ses vues avec lui.
S.CONTENEURS = { row = true, column = true, group_box = true, tab_view = true, scrolled_view = true }

-- `background_color` reste sans effet sur ces conteneurs, chacun avec sa source : row et view
-- constatés (21 octobre 2026, A5), column et group_box relevés dans AgUI (aucun NSView ordinaire
-- n'a de couleur de fond), sans avoir été vus. Il agit sur un scrolled_view (constaté, A2) et sur
-- un f:picture (aplat, constaté, A4).
S.SANS_FOND = {
    row = 'constaté le 21 octobre 2026, A5',
    view = 'constaté le 21 octobre 2026, A5',
    column = 'relevé dans AgUI',
    group_box = 'relevé dans AgUI',
}

-- Les attributs d'une static_text qui décident de son texte riche (<EM>), et celui d'un bouton qui
-- pose une icône : vérifiés à la création s'ils sont tous donnés tels quels, sinon à l'ouverture de
-- la fenêtre et à chaque changement de leurs clés liées.
local ATTRIBUTS_TEXTE = { 'title', 'font', 'emphasis_font', 'emphasis_color', 'height_in_lines', 'image_name' }

-- Taille en points d'une police de LrView : un nom réservé du système (« small » : 11 points,
-- constaté le 21 octobre 2026, D9 ; sinon la taille du système de macOS, 13), ou une table
-- { name, size }. Une static_text sans `font` est en '<system>'. Nil si la taille n'est pas connue,
-- dont « mini », ni documenté ni constaté.
local function taillePolice(police)
    if police == nil then
        return 13
    elseif type(police) == 'table' then
        return police.size or (type(police.name) == 'string' and police.name:match('^<system') and taillePolice(police.name)) or nil
    elseif type(police) == 'string' and police:match('^<system') then
        if police:find('mini', 1, true) then
            return nil
        end
        return police:find('small', 1, true) and 11 or 13
    end
end
S.taillePolice = taillePolice

-- Texte riche d'une static_text (balise <EM>…</EM>, emphasis_font, emphasis_color), d'après ses
-- valeurs `v` (title, font, emphasis_font, emphasis_color, height_in_lines). Rend nil si Lightroom
-- l'affiche comme voulu, sinon la raison du refus.
function S.refusEmphase(v)
    if v.emphasis_color ~= nil and v.emphasis_font == nil then
        -- Constaté le 21 octobre 2026 (D4), comme relevé dans AgUI : le style d'emphase n'est fait
        -- qu'avec sa police.
        return "emphasis_color sans emphasis_font : ni gras ni couleur (constaté le 21 octobre 2026, D4)"
    end
    local titre = v.title
    if type(titre) ~= 'string' or not titre:find('</?EM>') then
        return nil
    end
    -- Chaque <EM> se ferme par </EM> avant la suivante : seule, la balise disparaît sans rien
    -- d'autre (constaté le 21 octobre 2026, B1). Une balise peut se fermer sur la ligne suivante
    -- (les deux lignes passent en gras, constaté, D4). Deux <EM> de suite et un </EM> seul n'ont
    -- été ni vus ni relevés : refusés plutôt que devinés.
    local ouverte, debut = false, 1
    while true do
        local a, b, fin = titre:find('<(/?)EM>', debut)
        if not a then
            break
        end
        if fin == '' and ouverte then
            return "<EM> ouverte deux fois sans </EM> (non constaté) : " .. titre
        elseif fin == '/' and not ouverte then
            return "</EM> sans <EM> (non constaté) : " .. titre
        end
        ouverte = fin == ''
        debut = b + 1
    end
    if ouverte then
        return "<EM> sans </EM> : la balise disparaît, le texte reste sans emphase (constaté le 21 octobre 2026, B1) : " .. titre
    end
    if v.emphasis_font == nil then
        return "<EM> sans emphasis_font : ni gras ni couleur (constaté le 21 octobre 2026, B1 et D4) : " .. titre
    end
    -- « &lt; » et « &amp; » s'affichent tels quels (constaté le 21 octobre 2026, D4) ; aucune
    -- entité n'est décodée (relevé dans AgUI : le découpage par NSScanner ne cherche que les
    -- balises). Écrire les signes « < » et « & », affichés tels quels (constaté, D4).
    if titre:find('&%a+;') or titre:find('&#%d+;') or titre:find('&#[xX]%x+;') then
        return "entité dans un texte à <EM> : affichée telle quelle, écrire le signe (constaté le 21 octobre 2026, D4) : " .. titre
    end
    -- Une emphase plus grande que la police du texte allonge ses lignes (15 points au lieu de 14,5
    -- pour 12 sur 11), mais la hauteur se compte sur la police du texte : avec height_in_lines égal
    -- au nombre de lignes, la dernière est coupée (constaté le 21 octobre 2026, D4). Une ligne de plus
    -- à height_in_lines, ou une emphase de la même taille.
    local base, emphase = taillePolice(v.font), taillePolice(v.emphasis_font)
    local lignes = select(2, titre:gsub('\n', '')) + 1
    if base and emphase and emphase > base and type(v.height_in_lines) == 'number' and lignes >= v.height_in_lines then
        return string.format("emphase de %s points sur un texte de %s : la dernière des %d lignes (height_in_lines = %d) est coupée "
            .. "(constaté le 21 octobre 2026, D4) ; une ligne de plus, ou la même taille", tostring(emphase), tostring(base), lignes,
            v.height_in_lines)
    end
    return nil
end

-- Une icône posée par image_name chevauche le titre du bouton (constaté le 21 octobre 2026, B3) :
-- un bouton à icône n'a pas de titre (D5 : icônes seules, nettes). Rend nil, ou la raison.
function S.refusIcone(v)
    if v.image_name ~= nil and v.title ~= nil and v.title ~= '' then
        return "image_name avec un titre : l'icône chevauche le titre (constaté le 21 octobre 2026, B3) : " .. tostring(v.title)
    end
    return nil
end

-- Les éléments d'un popup_menu (relevé le 22 octobre 2026 dans AgViewUtils.getPopupMenu de
-- Lightroom 15.6, sans avoir été vu) : un élément-table est un séparateur ({ separator = true })
-- ou porte son titre (`title`, sinon Lightroom montrerait tostring(élément)) ; `value` (sinon
-- l'élément lui-même) et `enabled = false` (l'élément grisé) facultatifs ; un texte ou un nombre
-- est son propre titre et sa propre valeur. Rend nil, ou la raison du refus.
function S.refusElements(items)
    if type(items) ~= 'table' or items.liaison then
        return nil
    end
    for k, item in ipairs(items) do
        if type(item) == 'table' then
            if not item.separator and type(item.title) ~= 'string' then
                return string.format("élément %d d'un menu sans title ni separator (relevé dans AgViewUtils.getPopupMenu)", k)
            end
            if item.enabled ~= nil and type(item.enabled) ~= 'boolean' then
                return string.format("élément %d d'un menu : enabled doit être un booléen", k)
            end
        elseif type(item) ~= 'string' and type(item) ~= 'number' then
            return string.format("élément %d d'un menu : %s", k, type(item))
        end
    end
    return nil
end

-- Les attributs de ATTRIBUTS_TEXTE, tels quels ; nil si l'un est lié (vérifié à l'ouverture).
local function valeursSansLiaison(args)
    local v = {}
    for _, cle in ipairs(ATTRIBUTS_TEXTE) do
        local valeur = args[cle]
        if type(valeur) == 'table' and valeur.liaison then
            return nil
        end
        v[cle] = valeur
    end
    return v
end

-- Ce que Lightroom ignorerait ou rendrait mal, refusé à la création de la vue.
local function verifierCreation(genre, args)
    -- Un bouton radio sans valeur cochée ne se coche jamais.
    assert(genre ~= 'radio_button' or args.checked_value ~= nil, "radio_button sans checked_value : " .. tostring(args.title))
    assert(not (S.CONTENEURS[genre] and args.visible ~= nil),
        "visible sur un conteneur : sans effet dans Lightroom (constaté le 20 octobre 2026) : " .. genre)
    assert(not (S.SANS_FOND[genre] and args.background_color ~= nil),
        "background_color sur un " .. genre .. " : sans effet (" .. tostring(S.SANS_FOND[genre]) .. ") ; un aplat (f:picture) dessous")
    -- Sans effet sur un séparateur, la ligne restée #DBDBDB (constaté le 21 octobre 2026, A6) :
    -- un filet se fait par un aplat de 1 point. Refusé aussi ailleurs, où rien ne dit qu'il agirait.
    assert(args.primary_line_color == nil,
        "primary_line_color : sans effet sur un séparateur (constaté le 21 octobre 2026, A6), refusé partout : " .. genre)
    if genre == 'picture' then
        -- Aucun clic ne parvient à un f:picture (constaté le 21 octobre 2026, C1) : un calque
        -- (static_text vide de taille fixe) posé dessus le reçoit.
        assert(args.mouse_down == nil, "mouse_down sur un f:picture : sans effet (constaté le 21 octobre 2026, C1) ; poser un calque")
        -- Sans eux, l'image prend sa taille en pixels, deux fois trop grande pour une PNG en 2x
        -- (relevé dans AgPictureView, sans avoir été vu).
        assert(args.width ~= nil and args.height ~= nil, "f:picture sans width ou sans height (relevé dans AgPictureView)")
        -- Un f:picture sans image ne dessine que son fond : un aplat (constaté le 21 octobre 2026,
        -- A4) ; sans fond, il ne montre rien.
        assert(args.value ~= nil or args.background_color ~= nil, "f:picture sans value ni background_color : rien à montrer (A4)")
    end
    local v = valeursSansLiaison(args)
    if v then
        local refus = (genre == 'static_text' and S.refusEmphase(v)) or (S.BOUTONS[genre] and S.refusIcone(v)) or nil
        assert(not refus, refus)
    end
    if genre == 'popup_menu' then
        local refus = S.refusElements(args.items)
        assert(not refus, refus)
    end
end

local fabrique = setmetatable({}, {
    __index = function(_, genre)
        if genre == 'control_spacing' or genre == 'dialog_spacing' or genre == 'label_spacing' then
            return function() return 8 end
        end
        assert(S.GENRES_VUES[genre], "vue inconnue du SDK : " .. tostring(genre))
        return function(_, args)
            args = args or {}
            neuve(args.items, genre .. '.items')
            verifierCreation(genre, args)
            return { genre = genre, args = args }
        end
    end,
})

-- Une liaison : une clé (et son transform), ou plusieurs (`keys`, chaque clé un texte ou
-- { key, bind_to_object }) et leur `operation(binder, values, fromTable)`.
modules.LrView = {
    osFactory = function() return fabrique end,
    bind = function(x)
        if type(x) == 'string' then
            return { liaison = true, key = x }
        end
        if x.keys ~= nil then
            assert(type(x.keys) == 'table' and #x.keys > 0, "liaison à plusieurs clés sans clés")
            for _, k in ipairs(x.keys) do
                assert(type(k) == 'string' or (type(k) == 'table' and type(k.key) == 'string'), "clé de liaison invalide : " .. tostring(k))
            end
            assert(type(x.operation) == 'function', "liaison à plusieurs clés sans operation")
            return { liaison = true, keys = x.keys, operation = x.operation, transform = x.transform, bind_to_object = x.bind_to_object }
        end
        assert(type(x.key) == 'string', "liaison sans clé")
        return { liaison = true, key = x.key, transform = x.transform, bind_to_object = x.bind_to_object }
    end,
    share = function(nom) return { partage = nom } end,
}

-- Les clés d'une liaison : la sienne, ou ses `keys`.
function S.cles(liaison)
    if liaison.keys then
        local cles = {}
        for i, k in ipairs(liaison.keys) do
            cles[i] = type(k) == 'table' and k.key or k
        end
        return cles
    end
    return { liaison.key }
end

-- La valeur qu'une vue reçoit d'une liaison, lue dans `objet` (ou son bind_to_object) : la valeur
-- de sa clé passée par son transform, ou l'operation d'une liaison à plusieurs clés (values
-- indexées par clé, de la table vers la vue).
function S.evaluer(liaison, objet)
    objet = liaison.bind_to_object or objet
    if liaison.operation then
        local valeurs = {}
        for _, k in ipairs(S.cles(liaison)) do
            valeurs[k] = objet[k]
        end
        local valeur = liaison.operation({}, valeurs, true)
        if liaison.transform then
            return liaison.transform(valeur, true)
        end
        return valeur
    end
    if liaison.transform then
        return liaison.transform(objet[liaison.key], true)
    end
    return objet[liaison.key]
end

-- Contrôle d'une liaison posée sur une vue : chacune de ses clés a une valeur avant l'ouverture
-- (Lightroom l'exige), son transform ou son operation s'évaluent. Rend la valeur évaluée.
function S.verifierLiaison(liaison, objet, quoi)
    local o = liaison.bind_to_object or objet
    for _, k in ipairs(S.cles(liaison)) do
        if o[k] == nil then
            error('liaison sans valeur : ' .. tostring(k) .. (quoi and (' (' .. quoi .. ')') or ''), 2)
        end
    end
    return S.evaluer(liaison, objet)
end

-- Une vue est-elle montrée ? Sans `visible`, oui ; liée, d'après les valeurs de `objet`.
function S.montree(vue, objet)
    local v = vue.args.visible
    if type(v) == 'table' and v.liaison then
        v = S.evaluer(v, objet)
    end
    return v == nil or v == true
end

-- Table de propriétés : observateurs appelés quand une valeur change.
local function tableProprietes()
    local valeurs, observateurs = {}, {}
    local t = {}
    rawset(t, 'addObserver', function(self, cle, fn)
        observateurs[cle] = observateurs[cle] or {}
        table.insert(observateurs[cle], fn)
    end)
    rawset(t, '_valeurs', valeurs)
    return setmetatable(t, {
        __index = valeurs,
        __newindex = function(_, cle, valeur)
            neuve(valeur, 'propriété ' .. tostring(cle))
            local ancienne = valeurs[cle]
            valeurs[cle] = valeur
            if ancienne ~= valeur then
                for _, fn in ipairs(observateurs[cle] or {}) do
                    fn(t, cle, valeur)
                end
            end
        end,
    })
end

local contexte = { addFailureHandler = function() end, addCleanupHandler = function() end }

-- kUnsupportedDirection : ce que rend une operation pour un sens qu'elle ne prend pas en charge
-- (ici, de la vue vers la table).
modules.LrBinding = { makePropertyTable = function() return tableProprietes() end, kUnsupportedDirection = { sens = 'non pris en charge' } }

modules.LrFunctionContext = {
    callWithContext = function(_, fn, ...) return fn(contexte, ...) end,
    postAsyncTaskWithContext = function(_, fn) fn(contexte) end,
}

-- Mesures constatées, sans règle de refus ------------------------------------------------------
-- Ce que la simulation ne rend pas (pas de pixels), relevé le 21 octobre 2026 dans Lightroom
-- Classic 15.6 (lot B0 de la fenêtre B) : les lots B3 à B5 en tirent leurs dimensions.

-- Cadre d'une fenêtre flottante (constaté le 21 octobre 2026, D7) : barre de titre de 33 points
-- (32 blancs et un filet), le contenu juste dessous, sans marge en haut, avec 1 point à gauche, à
-- droite et en bas. Un contenu de 1 278 × 765 donne une fenêtre de 1 280 × 799 ; une fenêtre de
-- 1 280 × 800 a donc un contenu de 1 278 × 766.
S.CADRE_FENETRE = { barre = 33, haut = 0, gauche = 1, droite = 1, bas = 1 }

function S.fenetrePourContenu(largeur, hauteur)
    local c = S.CADRE_FENETRE
    return largeur + c.gauche + c.droite, hauteur + c.barre + c.haut + c.bas
end

function S.contenuPourFenetre(largeur, hauteur)
    local c = S.CADRE_FENETRE
    return largeur - c.gauche - c.droite, hauteur - c.barre - c.haut - c.bas
end

-- Bezel d'un square_button, mesuré d'un bord #B4B4B4 à l'autre (constaté le 21 octobre 2026, D5) :
-- sans height, 17 points en regular, 15 en small, 11 en mini ; avec height, toujours 2 de moins
-- (22, 24 et 26 donnent 20, 22 et 24, en regular comme en small ; en mini avec height, non relevé,
-- supposé de même). Un bezel de N points demande height = N + S.MARGE_BEZEL.
S.BEZEL_NATUREL = { regular = 17, small = 15, mini = 11 }
S.MARGE_BEZEL = 2

function S.bezelVisible(vue)
    local a = vue.args
    if type(a.height) == 'number' then
        return a.height - S.MARGE_BEZEL
    end
    return S.BEZEL_NATUREL[a.size or 'regular']
end

-- Encre et chasse (constaté le 21 octobre 2026, D9) : la largeur d'encre d'un texte rendu par
-- Lightroom fait 1 à 2 points de moins que sa chasse NSFont (approches des bords), pour '<system>',
-- '<system/bold>' et '<system/small>' en 13, 12 et 11, et Helvetica Neue 13 : les chasses de
-- Metriques.lua restent justes, sans correction.
S.ENCRE_SOUS_CHASSE = { min = 1, max = 2 }

-- Bouton radio inactif coché (constaté le 21 octobre 2026, D12) : à la première ouverture, un
-- radio_button à enabled lié faux et coché par sa valeur liée se dessine sans point (disque gris
-- uni) ; sa valeur reposée après l'ouverture, ou dès la création à une deuxième ouverture, le
-- dessine grisé et coché. La fenêtre repose donc la valeur une fois après l'ouverture, dans sa
-- première tâche (lot B3). La simulation ne dessine rien : aucune règle.
S.RADIO_INACTIF_A_REPOSER = true

-- Sans règle non plus (constaté le 21 octobre 2026) : une rangée posée sur un texte ne lui prend
-- pas ses clics, et un bouton masqué laisse le clic au texte dessous (D6) ; la simulation clique la
-- vue visée, sans géométrie. Les contrôles natifs sont lisibles sur blanc et sur #F2F2F2 en
-- apparence claire (D8) ; l'apparence sombre n'a pas été essayée.

-- Fenêtres ouvertes ----------------------------------------------------------------------------

-- Les fenêtres flottantes ouvertes, la dernière au-dessus : chacune avec l'index de ses vues
-- (parent et table de propriétés héritée de bind_to_object), ses vues qui portent `default`, le
-- champ qui a le focus et le texte tapé sans être validé.
S.fenetresOuvertes = {}

local CHAMPS = { edit_field = true, password_field = true, combo_box = true }

-- Toutes les vues d'un arbre, la racine d'abord.
function S.vues(racine)
    local liste = {}
    local function parcourir(v)
        liste[#liste + 1] = v
        for _, e in ipairs(v.args or {}) do
            if type(e) == 'table' and e.genre then
                parcourir(e)
            end
        end
    end
    if type(racine) == 'table' and racine.genre then
        parcourir(racine)
    end
    return liste
end

-- Les boutons d'un arbre, push_button et square_button.
function S.boutons(racine)
    local liste = {}
    for _, v in ipairs(S.vues(racine)) do
        if S.BOUTONS[v.genre] then
            liste[#liste + 1] = v
        end
    end
    return liste
end

-- La fenêtre ouverte qui contient cette vue, et ce qu'elle sait de la vue ; nil sinon.
local function chercherFenetre(vue)
    for i = #S.fenetresOuvertes, 1, -1 do
        local fenetre = S.fenetresOuvertes[i]
        if fenetre.vues[vue] then
            return fenetre, fenetre.vues[vue]
        end
    end
end

local function fenetreDe(vue, geste)
    local fenetre, info = chercherFenetre(vue)
    if not fenetre then
        error(geste .. " : vue hors d'une fenêtre ouverte (" .. tostring(type(vue) == 'table' and vue.genre) .. ")", 3)
    end
    return fenetre, info
end

-- La valeur d'un attribut : tel quel, ou sa liaison évaluée dans `objet`.
local function evaluerAttribut(valeur, objet)
    if type(valeur) == 'table' and valeur.liaison then
        return S.evaluer(valeur, objet)
    end
    return valeur
end

-- Le titre d'une vue, sa liaison évaluée (dans la table de sa fenêtre ouverte, sinon `objet`).
function S.titreDe(vue, objet)
    local _, info = chercherFenetre(vue)
    return evaluerAttribut(vue.args.title, info and info.objet or objet)
end

-- Le premier bouton (push_button ou square_button) de cet arbre qui porte ce titre.
function S.trouverBouton(racine, titre, objet)
    for _, v in ipairs(S.boutons(racine)) do
        if S.titreDe(v, objet) == titre then
            return v
        end
    end
end

-- Les attributs de texte riche et d'icône d'une vue, évalués ; une liaison qui ne s'évalue pas
-- (clé sans valeur : une autre règle le dit) compte pour absente.
local function valeursTexte(vue, objet)
    local v = {}
    for _, cle in ipairs(ATTRIBUTS_TEXTE) do
        local ok, valeur = pcall(evaluerAttribut, vue.args[cle], objet)
        if ok then
            v[cle] = valeur
        end
    end
    return v
end

local function refusTexte(fenetre, vue)
    local v = valeursTexte(vue, fenetre.vues[vue].objet)
    if vue.genre == 'static_text' then
        return S.refusEmphase(v)
    elseif S.BOUTONS[vue.genre] then
        return S.refusIcone(v)
    end
end

-- Les vues de la fenêtre dont `default` vaut vrai à cet instant : une valeur liée se relit à
-- chaque fois, comme toute liaison (non constaté pour default, qui n'est pas documenté).
local function parDefaut(fenetre)
    local liste = {}
    for _, vue in ipairs(fenetre.avecDefaut) do
        local ok, defaut = pcall(evaluerAttribut, vue.args.default, fenetre.vues[vue].objet)
        if ok and defaut == true then
            liste[#liste + 1] = vue
        end
    end
    return liste
end

-- Un seul bouton par défaut : la fenêtre n'en garde qu'un (relevé dans AgUI :
-- setDefaultButtonCell). Rend nil, ou la raison du refus.
local function refusDefaut(fenetre)
    local n = #parDefaut(fenetre)
    if n > 1 then
        return string.format("%d boutons default = true dans une fenêtre : elle n'en garde qu'un (relevé dans AgUI, "
            .. "setDefaultButtonCell)", n)
    end
end

-- Ouverture d'une fenêtre : l'index de ses vues, puis ce qui ne se voit qu'avec les valeurs.
local function ouvrirFenetre(args)
    local fenetre = { args = args, vues = {}, saisies = {}, libres = {}, refus = {}, avecDefaut = {}, ouverte = true }
    local function indexer(vue, parent, objet)
        objet = vue.args.bind_to_object or objet
        fenetre.vues[vue] = { parent = parent, objet = objet }
        for _, e in ipairs(vue.args) do
            if type(e) == 'table' and e.genre then
                indexer(e, vue, objet)
            end
        end
    end
    local liste = S.vues(args.contents)
    if liste[1] then
        indexer(liste[1], nil, nil)
    end
    -- Ce qui se relit à chaque nouvelle valeur d'une clé liée : suivies[table][clé] = vérifications.
    local suivies = {}
    local function suivre(lien, objet, verifier)
        local o = lien.bind_to_object or objet
        if type(o) == 'table' and type(rawget(o, 'addObserver')) == 'function' then
            for _, k in ipairs(S.cles(lien)) do
                suivies[o] = suivies[o] or {}
                suivies[o][k] = suivies[o][k] or {}
                table.insert(suivies[o][k], verifier)
            end
        end
    end
    -- Le bouton par défaut : un seul à l'ouverture, puis à chaque nouvelle valeur liée.
    for _, vue in ipairs(liste) do
        if vue.args.default ~= nil then
            fenetre.avecDefaut[#fenetre.avecDefaut + 1] = vue
            if type(vue.args.default) == 'table' and vue.args.default.liaison then
                suivre(vue.args.default, fenetre.vues[vue].objet, function() return refusDefaut(fenetre) end)
            end
        end
    end
    local refus = refusDefaut(fenetre)
    assert(not refus, refus)
    -- Texte riche et icônes liés : leurs valeurs à l'ouverture, puis chaque nouvelle valeur (un
    -- titre lié balisé garde son balisage quand il change, constaté le 21 octobre 2026, D4).
    for _, vue in ipairs(liste) do
        if vue.genre == 'static_text' or S.BOUTONS[vue.genre] then
            refus = refusTexte(fenetre, vue)
            assert(not refus, refus)
            for _, cle in ipairs(ATTRIBUTS_TEXTE) do
                local lien = vue.args[cle]
                if type(lien) == 'table' and lien.liaison then
                    suivre(lien, fenetre.vues[vue].objet, function() return refusTexte(fenetre, vue) end)
                end
            end
        end
    end
    -- Les éléments liés d'un menu : à l'ouverture, puis à chaque nouvelle valeur (S.refusElements).
    for _, vue in ipairs(liste) do
        local lien = vue.genre == 'popup_menu' and vue.args.items
        if type(lien) == 'table' and lien.liaison then
            local function verifier()
                return S.refusElements(evaluerAttribut(lien, fenetre.vues[vue].objet))
            end
            refus = verifier()
            assert(not refus, refus)
            suivre(lien, fenetre.vues[vue].objet, verifier)
        end
    end
    for o, cles in pairs(suivies) do
        for k, verifications in pairs(cles) do
            o:addObserver(k, function()
                if not fenetre.ouverte then
                    return
                end
                for _, verifier in ipairs(verifications) do
                    local refus = verifier()
                    if refus then
                        -- Gardé aussi pour la fermeture : une tâche du module (LrTasks.pcall)
                        -- n'avalera pas le refus.
                        fenetre.refus[#fenetre.refus + 1] = refus
                        error(refus, 0)
                    end
                end
            end)
        end
    end
    return fenetre
end

local function fermerFenetre(fenetre)
    fenetre.ouverte = false
    for i = #S.fenetresOuvertes, 1, -1 do
        if S.fenetresOuvertes[i] == fenetre then
            table.remove(S.fenetresOuvertes, i)
        end
    end
end

-- Les refus de valeurs liées gardés par la fenêtre ouverte du dessus, rendus puis oubliés (pour
-- l'essai qui les provoque exprès).
function S.refusDeLaFenetre()
    local fenetre = S.fenetresOuvertes[#S.fenetresOuvertes]
    assert(fenetre, "aucune fenêtre ouverte")
    local refus = fenetre.refus
    fenetre.refus = {}
    return refus
end

-- Le bouton par défaut de la fenêtre ouverte du dessus, à cet instant (nil s'il n'y en a pas).
function S.boutonParDefaut()
    local fenetre = S.fenetresOuvertes[#S.fenetresOuvertes]
    return fenetre and parDefaut(fenetre)[1]
end

-- Une vue est montrée si elle l'est, et toutes les vues qui la contiennent : un f:view caché
-- cache ses vues (constaté le 21 octobre 2026, D10).
local function montreeDans(fenetre, vue)
    local v = vue
    while v do
        local info = fenetre.vues[v]
        if not S.montree(v, info.objet) then
            return false
        end
        v = info.parent
    end
    return true
end

function S.montreeDansFenetre(vue)
    local fenetre = fenetreDe(vue, 'S.montreeDansFenetre')
    return montreeDans(fenetre, vue)
end

local function active(fenetre, vue)
    local e = evaluerAttribut(vue.args.enabled, fenetre.vues[vue].objet)
    return e == nil or e == true
end

-- Un geste (clic, frappe, Retour) sur une vue masquée ou inactive est refusé. Masquée : une vue
-- d'une variante cachée, par sa condition ou celle d'un f:view qui la contient, ne prend aucun clic
-- ; celles de la variante montrée répondent, quelle que soit sa place dans la superposition
-- (constaté le 21 octobre 2026, D11 ; D10 pour le f:view). Inactive : la simulation ne sait pas ce
-- qu'un tel clic validerait, elle le refuse plutôt que de l'inventer.
local function nomDe(vue)
    local ok, titre = pcall(S.titreDe, vue)
    return vue.genre .. ' « ' .. (ok and tostring(titre) or '?') .. ' »'
end

local function verifierGeste(fenetre, vue, geste)
    local nom = nomDe(vue)
    if not montreeDans(fenetre, vue) then
        error(geste .. " sur une vue masquée : " .. nom .. " (constaté le 21 octobre 2026, D11 : aucune réponse d'une variante cachée)", 3)
    end
    if not active(fenetre, vue) then
        error(geste .. " sur une vue inactive : " .. nom, 3)
    end
end

local function lireValeur(fenetre, vue)
    if fenetre.libres[vue] ~= nil then
        return fenetre.libres[vue]
    end
    return evaluerAttribut(vue.args.value, fenetre.vues[vue].objet)
end

-- Écrit la valeur d'une vue dans sa table de propriétés (les observateurs de la clé suivent) ; une
-- valeur non liée reste dans la vue.
local function ecrireValeur(fenetre, vue, valeur)
    local lien = vue.args.value
    if type(lien) ~= 'table' or not lien.liaison then
        fenetre.libres[vue] = valeur
        return
    end
    assert(not lien.keys, "valeur liée à plusieurs clés : non simulée")
    local o = lien.bind_to_object or fenetre.vues[vue].objet
    assert(type(o) == 'table', "valeur liée sans table de propriétés : " .. tostring(lien.key))
    if lien.transform then
        valeur = lien.transform(valeur, false)
        if valeur == modules.LrBinding.kUnsupportedDirection then
            return
        end
    end
    o[lien.key] = valeur
end

-- Le texte affiché par un champ : le texte tapé pas encore validé, sinon sa valeur.
local function texteChamp(fenetre, champ)
    if fenetre.saisies[champ] ~= nil then
        return fenetre.saisies[champ]
    end
    local valeur = lireValeur(fenetre, champ)
    return valeur == nil and '' or tostring(valeur)
end

function S.texteChamp(champ)
    local fenetre = fenetreDe(champ, 'S.texteChamp')
    return texteChamp(fenetre, champ)
end

-- Validation d'un champ (immediate = false) : son texte tapé passe à la table, son observateur
-- suit ; le texte reste dans le champ (constaté le 21 octobre 2026, D3).
local function valider(fenetre, champ)
    local texte = fenetre.saisies[champ]
    if texte ~= nil then
        fenetre.saisies[champ] = nil
        ecrireValeur(fenetre, champ, texte)
    end
end

-- Un champ qui perd le focus est validé (constaté le 21 octobre 2026, D1 : le champ de demande,
-- tapé puis quitté pour « Rechercher », était déjà envoyé quand Retour y a déclenché le bouton par
-- défaut).
local function prendreFocus(fenetre, champ)
    if fenetre.focus and fenetre.focus ~= champ then
        valider(fenetre, fenetre.focus)
    end
    fenetre.focus = champ
end

-- Frappe dans un champ (le focus y va). Avec immediate = true, chaque caractère passe à la table
-- (constaté le 21 octobre 2026, D1 : trois appels de l'observateur de « Rechercher » pour « abc ») ;
-- sinon le texte reste dans le champ jusqu'à Retour, un clic ou le focus qui part (D1, D3).
function S.taper(champ, texte)
    local fenetre = fenetreDe(champ, 'S.taper')
    assert(CHAMPS[champ.genre], "S.taper : pas un champ : " .. champ.genre)
    verifierGeste(fenetre, champ, 'frappe')
    prendreFocus(fenetre, champ)
    if champ.args.immediate == true then
        local courant = texteChamp(fenetre, champ)
        for c in tostring(texte):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
            courant = courant .. c
            ecrireValeur(fenetre, champ, courant)
        end
    else
        fenetre.saisies[champ] = texteChamp(fenetre, champ) .. tostring(texte)
    end
end

-- Retour dans un champ (constaté le 21 octobre 2026, D1 et D2) : un champ immediate = false est
-- validé (son observateur), puis l'action du bouton par défaut part, s'il est actif et montré, y
-- compris depuis un champ immediate = true (Retour dans « Rechercher » déclenche Envoyer) ; un
-- bouton par défaut inactif ou masqué ne la prend pas, et aucun autre bouton (Arrêter montré à la
-- place d'Envoyer) ne la prend jamais. Rend vrai si le bouton par défaut a reçu Retour.
function S.retour(champ)
    local fenetre = fenetreDe(champ, 'S.retour')
    assert(CHAMPS[champ.genre], "S.retour : pas un champ : " .. champ.genre)
    verifierGeste(fenetre, champ, 'Retour')
    prendreFocus(fenetre, champ)
    if champ.args.immediate ~= true then
        valider(fenetre, champ)
    end
    local defaut = parDefaut(fenetre)[1]
    if defaut and montreeDans(fenetre, defaut) and active(fenetre, defaut) then
        defaut.args.action(defaut)
        return true
    end
    return false
end

-- Un clic : un bouton (son action), un calque ou un texte (mouse_down), un bouton radio (sa valeur
-- cochée), une case (cochée ou décochée), un champ (le focus). Un champ tapé sans Retour est d'abord
-- validé (son observateur), puis le clic se fait et lit la valeur validée ; le texte reste dans le
-- champ (constaté le 21 octobre 2026, D3, pour un calque, un bouton radio, un segment en image sous
-- calque et un bouton). Rend ce que rend l'action.
function S.cliquer(vue)
    local fenetre = fenetreDe(vue, 'S.cliquer')
    assert(vue.genre ~= 'picture', "clic sur un f:picture : sans effet (constaté le 21 octobre 2026, C1) ; cliquer son calque")
    verifierGeste(fenetre, vue, 'clic')
    local a = vue.args
    local geste
    if S.BOUTONS[vue.genre] then
        assert(type(a.action) == 'function', "bouton sans action : " .. nomDe(vue))
        geste = function() return a.action(vue) end
    elseif vue.genre == 'radio_button' then
        geste = function() ecrireValeur(fenetre, vue, a.checked_value) end
    elseif vue.genre == 'checkbox' then
        geste = function()
            local coche, decoche = a.checked_value, a.unchecked_value
            if coche == nil then
                coche = true
            end
            if decoche == nil then
                decoche = false
            end
            if lireValeur(fenetre, vue) == coche then
                ecrireValeur(fenetre, vue, decoche)
            else
                ecrireValeur(fenetre, vue, coche)
            end
        end
    elseif CHAMPS[vue.genre] then
        geste = function() prendreFocus(fenetre, vue) end
    elseif type(a.mouse_down) == 'function' then
        geste = function() return a.mouse_down(vue) end
    else
        error("rien ne prend ce clic : " .. nomDe(vue), 2)
    end
    if fenetre.focus and fenetre.focus ~= vue then
        valider(fenetre, fenetre.focus)
    end
    return geste()
end

-- Un choix dans un popup_menu : l'élément de cette valeur (ni séparateur, ni grisé : relevé dans
-- AgViewUtils.getPopupMenu, un élément `enabled = false` ne se choisit pas), sur un menu montré et
-- actif. Comme un clic (S.cliquer), un champ tapé sans Retour est d'abord validé (supposé pour un
-- menu : constaté le 21 octobre 2026, D3, pour un calque, un bouton radio, un segment et un
-- bouton) ; puis la valeur passe de la vue à la table (son transform, puis ses observateurs, qui ne
-- suivent que si elle change, comme pour un radio déjà coché). Rend vrai.
function S.choisir(menu, valeur)
    local fenetre = fenetreDe(menu, 'S.choisir')
    assert(menu.genre == 'popup_menu', "S.choisir : pas un menu : " .. menu.genre)
    verifierGeste(fenetre, menu, 'choix')
    local items = evaluerAttribut(menu.args.items, fenetre.vues[menu].objet)
    local refus = S.refusElements(items)
    assert(not refus, refus)
    local trouve
    for _, item in ipairs(items or {}) do
        local v = type(item) == 'table' and (item.value == nil and item or item.value) or item
        if type(item) == 'table' and not item.separator and v == valeur then
            assert(item.enabled ~= false, "S.choisir : élément grisé : " .. tostring(item.title))
            trouve = item
        elseif type(item) ~= 'table' and item == valeur then
            trouve = item
        end
    end
    assert(trouve ~= nil, "S.choisir : aucun élément de valeur " .. tostring(valeur))
    if fenetre.focus and fenetre.focus ~= menu then
        valider(fenetre, fenetre.focus)
    end
    ecrireValeur(fenetre, menu, valeur)
    return true
end

-- Les éléments d'un menu, évalués dans la table de sa fenêtre ouverte (titres et valeurs).
function S.elementsDe(menu)
    local fenetre = fenetreDe(menu, 'S.elementsDe')
    return evaluerAttribut(menu.args.items, fenetre.vues[menu].objet)
end

modules.LrDialogs = {
    message = function(titre, detail) S.messages[#S.messages + 1] = { titre, detail } end,
    confirm = function(...)
        S.confirmation = { ... }
        return S.reponseConfirm or 'cancel'
    end,
    -- Une fenêtre modale : ses vues passent les règles d'une fenêtre ouverte, puis elle rend
    -- S.reponseModal sans attendre.
    presentModalDialog = function(args)
        S.dialogues[#S.dialogues + 1] = args
        fermerFenetre(ouvrirFenetre(args))
        return S.reponseModal or 'cancel'
    end,
    -- La fenêtre flottante : le test la parcourt pendant S.pendantFenetre, puis elle se ferme.
    -- `close` (demandé par la fenêtre, pour la rouvrir) et `toFront` sont comptés ; la fermeture
    -- (windowWillClose) vient après S.pendantFenetre. Pendant S.pendantFenetre, elle est ouverte :
    -- S.taper, S.retour et S.cliquer y agissent. Une valeur liée refusée pendant ce temps fait
    -- échouer la fermeture.
    presentFloatingDialog = function(_, args)
        -- Sans effet : le fond reste le gris de la fenêtre, #EFEFEF à l'écran (constaté le 21
        -- octobre 2026, A1) ; un aplat (f:picture) le remplace.
        assert(args.background_color == nil, "background_color de presentFloatingDialog : sans effet (constaté le 21 octobre 2026, A1)")
        local fenetre = ouvrirFenetre(args)
        S.fenetresOuvertes[#S.fenetresOuvertes + 1] = fenetre
        S.fenetre = args
        local ok, erreur = xpcall(function()
            if args.onShow then
                args.onShow({
                    toFront = function() S.devant = (S.devant or 0) + 1 end,
                    close = function() S.fermetures = (S.fermetures or 0) + 1 end,
                })
            end
            if S.pendantFenetre then
                S.pendantFenetre(args)
            end
        end, debug.traceback)
        if not ok then
            fermerFenetre(fenetre)
            error(erreur, 0)
        end
        if args.windowWillClose then
            args.windowWillClose()
        end
        fermerFenetre(fenetre)
        if #fenetre.refus > 0 then
            error("valeur liée refusée pendant que la fenêtre était ouverte : " .. fenetre.refus[1], 0)
        end
    end,
    runOpenPanel = function() return S.fichiersChoisis end,
    showBezel = function(texte) S.bezels = S.bezels or {}; S.bezels[#S.bezels + 1] = texte end,
}

function import(nom)
    local m = modules[nom]
    assert(m, "module du SDK non simulé : " .. tostring(nom))
    return m
end

_PLUGIN = { path = S.plugin, id = 'com.danymenard.developpeur' }

package.path = S.plugin .. '/?.lua;' .. package.path

S.modules = modules
S.executer = executer
S.lireCommande = lireCommande
S.q = q

return S
