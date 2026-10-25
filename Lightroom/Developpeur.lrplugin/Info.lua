-- Développeur : module externe de Lightroom Classic. Il réunit deux choses :
--   - la liaison avec le serveur MCP « mcp-developpeur » (le connecteur MCP-Développeur, que Claude
--     Desktop et Claude Code lancent), par deux prises réseau locales (Liaison.lua) ;
--   - la fenêtre Claude (« Développeur » dans sa barre de titre) : une conversation avec Claude
--     Code et le forfait claude.ai (jamais de clé d'API), qui retouche par ce même connecteur, et
--     ses fenêtres Publication et Consommation.
-- La version doit rester identique à Resources/Info.plist et à Liaison.VERSION.

return {
    -- 13.3 au moins : photo:updateAISettings() calcule les réglages IA sans la fenêtre « Mises à jour
    -- IA recommandées », et isExported dit si une photo est exportée.
    LrSdkVersion = 13.3,
    LrSdkMinimumVersion = 13.3,

    LrToolkitIdentifier = 'com.danymenard.developpeur',
    LrPluginName = "Développeur",
    LrPluginInfoUrl = 'https://github.com/mdany75/Developpeur',

    LrInitPlugin = 'Init.lua',
    LrForceInitPlugin = true,
    LrEnablePlugin = 'Init.lua',
    LrShutdownPlugin = 'Arret.lua',
    LrDisablePlugin = 'Arret.lua',

    LrPluginInfoProvider = 'PluginInfoProvider.lua',
    LrMetadataProvider = 'Metadonnees.lua',

    -- Fichier › Module externe - Extras, et Bibliothèque › Module externe - Extras. Le titre
    -- « Ouvrir la fenêtre Claude » ne change pas : le raccourci ⌃⌥C le vise (Raccourcis.lua) ; ni
    -- « Demande rapide », que ⌘⌃⌥C vise.
    LrExportMenuItems = {
        { title = "Ouvrir la fenêtre Claude", file = 'MenuOuvrir.lua' },
        { title = "Demande rapide", file = 'MenuRapide.lua' },
        { title = "Publication…", file = 'MenuPublication.lua' },
        { title = "Consommation…", file = 'MenuConsommation.lua' },
        { title = "Afficher la fenêtre de la liaison", file = 'MenuSuivi.lua' },
        { title = "Revenir à « Avant Claude »", file = 'MenuRevenir.lua', enabledWhen = 'photosSelected' },
        { title = "Créer une copie virtuelle pour Claude", file = 'MenuCopie.lua', enabledWhen = 'photosSelected' },
        { title = "Démarrer la liaison avec Claude", file = 'MenuDemarrer.lua' },
        { title = "Arrêter la liaison avec Claude", file = 'MenuArreter.lua' },
    },
    LrLibraryMenuItems = {
        { title = "Ouvrir la fenêtre Claude", file = 'MenuOuvrir.lua' },
        { title = "Demande rapide", file = 'MenuRapide.lua' },
        { title = "Publication…", file = 'MenuPublication.lua' },
        { title = "Consommation…", file = 'MenuConsommation.lua' },
        { title = "Afficher la fenêtre de la liaison", file = 'MenuSuivi.lua' },
        { title = "Revenir à « Avant Claude »", file = 'MenuRevenir.lua', enabledWhen = 'photosSelected' },
        { title = "Créer une copie virtuelle pour Claude", file = 'MenuCopie.lua', enabledWhen = 'photosSelected' },
        { title = "Démarrer la liaison avec Claude", file = 'MenuDemarrer.lua' },
        { title = "Arrêter la liaison avec Claude", file = 'MenuArreter.lua' },
    },

    VERSION = { major = 1, minor = 3, revision = 6, build = 11 },
}
