-- Simulation.lua : imitation minimale du SDK de Lightroom Classic, pour essayer la fenêtre Claude
-- du module hors de Lightroom avec LuaJIT (même Lua 5.1). Installe les globales `import` et
-- `_PLUGIN`. Les fichiers vont dans un dossier personnel temporaire (S.home), jamais dans le vrai.
-- La liaison avec le serveur (Liaison.lua, lue par la fenêtre) se charge sans ses prises : elle
-- n'est jamais démarrée ici (sa suite est Tests/Lua/Liaison).
-- Les tâches (LrTasks.startAsyncTask) ne tournent pas d'elles-mêmes : le test appelle ce qu'il
-- veut éprouver (Moteur.tic…).

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

-- Une photo simulée : nom de fichier, dimensions recadrées, nom par modèle de noms, champs du
-- module (`proprietes`), qui ne s'écrivent que dans une écriture du catalogue.
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
        getFormattedMetadata = function(_, cle) return cle == 'fileName' and nom or nil end,
        getRawMetadata = function(_, cle)
            if cle == 'croppedDimensions' then
                return { width = largeur or 6240, height = hauteur or 4160 }
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

-- Vues : chaque fabrique rend { genre, args } ; le test parcourt l'arbre.
S.GENRES_VUES = {
    row = true, column = true, view = true, group_box = true, tab_view = true, tab_view_item = true, scrolled_view = true,
    spacer = true, separator = true, static_text = true, edit_field = true, password_field = true, combo_box = true,
    checkbox = true, radio_button = true, push_button = true, popup_menu = true, simple_list = true, slider = true,
    color_well = true, picture = true, catalog_photo = true,
}

local fabrique = setmetatable({}, {
    __index = function(_, genre)
        if genre == 'control_spacing' or genre == 'dialog_spacing' or genre == 'label_spacing' then
            return function() return 8 end
        end
        assert(S.GENRES_VUES[genre], "vue inconnue du SDK : " .. tostring(genre))
        return function(_, args)
            return { genre = genre, args = args or {} }
        end
    end,
})

modules.LrView = {
    osFactory = function() return fabrique end,
    bind = function(x)
        if type(x) == 'string' then
            return { liaison = true, key = x }
        end
        return { liaison = true, key = x.key, transform = x.transform, bind_to_object = x.bind_to_object }
    end,
    share = function(nom) return { partage = nom } end,
}

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

modules.LrBinding = { makePropertyTable = function() return tableProprietes() end }

modules.LrFunctionContext = {
    callWithContext = function(_, fn, ...) return fn(contexte, ...) end,
    postAsyncTaskWithContext = function(_, fn) fn(contexte) end,
}

modules.LrDialogs = {
    message = function(titre, detail) S.messages[#S.messages + 1] = { titre, detail } end,
    confirm = function() return S.reponseConfirm or 'cancel' end,
    presentModalDialog = function(args)
        S.dialogues[#S.dialogues + 1] = args
        return S.reponseModal or 'cancel'
    end,
    -- La fenêtre flottante : le test la parcourt pendant S.pendantFenetre, puis elle se ferme.
    presentFloatingDialog = function(_, args)
        S.fenetre = args
        if args.onShow then
            args.onShow({ toFront = function() end, close = function() end })
        end
        if S.pendantFenetre then
            S.pendantFenetre(args)
        end
        if args.windowWillClose then
            args.windowWillClose()
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
