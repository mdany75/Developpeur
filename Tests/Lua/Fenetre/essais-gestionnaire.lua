-- essais-gestionnaire.lua : les réglages de la 1.3 dans le Gestionnaire de modules externes, hors
-- de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : la case Carnet dans la section de la
-- liaison, les cases Avant/après et Leçon et le menu Apparence (claire ou sombre) dans celle de la
-- fenêtre Claude, leurs valeurs par défaut, et le diagnostic (réglages de la 1.3 au bout de leur
-- ligne, apparence inconnue dite). Le registre du carnet (Carnet.lua) se charge ici aussi, sans
-- catalogue lisible : il se lit vide. Ni Claude, ni quota.
-- Lancé par scripts/tester-module.sh dans Tests/Lua/Fenetre, avec PLUGIN_DIR.

local S = require 'Simulation'

local reussis, echecs = 0, 0
local function essai(nom, fn)
    local ok, erreur = xpcall(fn, debug.traceback)
    if ok then
        reussis = reussis + 1
        print('ok     ' .. nom)
    else
        echecs = echecs + 1
        print('ÉCHEC  ' .. nom .. '\n' .. tostring(erreur))
    end
end

local function egal(attendu, obtenu, quoi)
    if attendu ~= obtenu then
        error(string.format('%s : attendu %q, obtenu %q', quoi or 'valeur', tostring(attendu), tostring(obtenu)), 2)
    end
end

local function vrai(condition, quoi)
    if not condition then
        error(quoi or 'condition fausse', 2)
    end
end

-- Toutes les vues d'un arbre.
local function vues(contenu)
    local liste = {}
    local function parcourir(v)
        liste[#liste + 1] = v
        for _, enfant in ipairs(v.args or {}) do
            if type(enfant) == 'table' and enfant.genre then
                parcourir(enfant)
            end
        end
    end
    parcourir(contenu)
    return liste
end

local Chemins = require 'Chemins'
local Dispositions = require 'Dispositions'
local Preferences = require 'Preferences'
local PluginInfoProvider = require 'PluginInfoProvider'

-- Les cases d'une section, par clé liée, avec l'étiquette de leur ligne et leur rang ; chaque
-- liaison a sa valeur avant l'ouverture (Lightroom l'exige).
local function cases(section, objet)
    local trouvees, rang = {}, 0
    for _, enfant in ipairs(section) do
        local etiquette = enfant.genre == 'row' and enfant.args[1] and enfant.args[1].genre == 'static_text'
            and enfant.args[1].args.title or nil
        for _, v in ipairs(vues(enfant)) do
            for cle, valeur in pairs(v.args) do
                if type(cle) == 'string' and type(valeur) == 'table' and valeur.liaison then
                    S.verifierLiaison(valeur, objet, v.genre .. '.' .. cle)
                end
            end
            if v.genre == 'checkbox' and type(v.args.value) == 'table' then
                rang = rang + 1
                trouvees[v.args.value.key] = { vue = v, etiquette = etiquette, rang = rang,
                    objet = v.args.value.bind_to_object or objet }
            end
        end
    end
    return trouvees
end

-- Les menus d'une section, par clé liée, avec l'étiquette de leur ligne et leur rang parmi les
-- menus ; chaque liaison a sa valeur avant l'ouverture.
local function menus(section, objet)
    local trouves, rang = {}, 0
    for _, enfant in ipairs(section) do
        local etiquette = enfant.genre == 'row' and enfant.args[1] and enfant.args[1].genre == 'static_text'
            and enfant.args[1].args.title or nil
        for _, v in ipairs(vues(enfant)) do
            if v.genre == 'popup_menu' and type(v.args.value) == 'table' and v.args.value.liaison then
                S.verifierLiaison(v.args.value, objet, 'popup_menu.value')
                rang = rang + 1
                trouves[v.args.value.key] = { vue = v, etiquette = etiquette, rang = rang, ligne = enfant,
                    objet = v.args.value.bind_to_object or objet }
            end
        end
    end
    return trouves
end

local function sections()
    local f = S.modules.LrView.osFactory()
    local proprietes = S.modules.LrBinding.makePropertyTable()
    return PluginInfoProvider.sectionsForTopOfDialog(f, proprietes), proprietes
end

local function finitPar(texte, suffixe)
    return texte:sub(-#suffixe) == suffixe
end

-- La ligne du diagnostic qui commence ainsi.
local function ligneDiagnostic(debut)
    for l in (PluginInfoProvider.diagnostic() .. '\n'):gmatch('([^\n]*)\n') do
        if l:sub(1, #debut) == debut then
            return l
        end
    end
    error('ligne du diagnostic introuvable : ' .. debut, 2)
end

essai('Gestionnaire, liaison : case Carnet, cochée par défaut, liée aux préférences du module', function()
    local liste, proprietes = sections()
    egal('Liaison avec Claude', liste[1].title)
    local c = cases(liste[1], proprietes)
    local carnet = c.carnet
    vrai(carnet, 'case Carnet')
    egal('Carnet :', carnet.etiquette)
    vrai(carnet.vue.args.title:find('Carnet de progrès', 1, true), 'titre de la case')
    egal(Chemins.prefs(), carnet.objet, 'liée aux préférences du module')
    egal(true, carnet.objet.carnet, 'cochée par défaut')
    egal(true, Preferences.defauts.carnet)
    vrai(c.pointMiseAuPoint and carnet.rang == c.pointMiseAuPoint.rang + 1, 'après la case Mise au point')
end)

essai('Gestionnaire, fenêtre Claude : cases Avant/après et Leçon, cochées par défaut, après À l\'ouverture', function()
    local liste = sections()
    local section = liste[2]
    egal('Fenêtre Claude', section.title)
    local prefs = section.bind_to_object
    egal(Chemins.prefs(), prefs)
    local c = cases(section, prefs)
    local avantApres, lecon = c.avantApresEtapes, c.leconFinRetouche
    vrai(avantApres and lecon, 'cases Avant/après et Leçon')
    egal('Avant/après :', avantApres.etiquette)
    egal('Leçon :', lecon.etiquette)
    vrai(avantApres.vue.args.title:find("avant/après de chaque étape de Claude", 1, true), 'titre Avant/après')
    vrai(lecon.vue.args.title:find('leçon de la photo', 1, true), 'titre Leçon')
    egal(c.propositionAOuverture.rang + 1, avantApres.rang, 'Avant/après après À l\'ouverture')
    egal(avantApres.rang + 1, lecon.rang, 'puis Leçon')
    egal(true, prefs.avantApresEtapes)
    egal(true, prefs.leconFinRetouche)
    egal(true, Chemins.defauts.avantApresEtapes)
    egal(true, Chemins.defauts.leconFinRetouche)
    -- Une case décochée reste décochée : la valeur par défaut ne s'impose qu'à une clé absente.
    prefs.leconFinRetouche = false
    egal(false, Chemins.prefs().leconFinRetouche)
    prefs.leconFinRetouche = nil
end)

essai('Gestionnaire, fenêtre Claude : menu Apparence (Claire, Sombre) après Effort, claire par défaut', function()
    local liste = sections()
    local section = liste[2]
    egal('Fenêtre Claude', section.title)
    local prefs = section.bind_to_object
    local m = menus(section, prefs)
    local apparence = m.apparence
    vrai(apparence, 'menu Apparence')
    egal('Apparence :', apparence.etiquette)
    egal(prefs, apparence.objet, 'lié aux préférences du module')
    egal(Chemins.prefs(), apparence.objet)
    -- Comme le modèle et l'effort (décision de Dany du 21 octobre 2026) : juste après Effort.
    vrai(m.modele and m.effort, 'menus Modèle et Effort')
    egal(m.modele.rang + 1, m.effort.rang, 'Effort après Modèle')
    egal(m.effort.rang + 1, apparence.rang, 'Apparence après Effort')
    local items = apparence.vue.args.items
    egal(2, #items, 'deux apparences')
    egal('Claire', items[1].title)
    egal('claire', items[1].value)
    egal('Sombre', items[2].title)
    egal('sombre', items[2].value)
    S.neuve(items, 'éléments du menu Apparence')
    vrai(items[1] ~= Dispositions.APPARENCES[1], 'éléments neufs, pas ceux de Dispositions')
    -- Claire par défaut, la même valeur que celle où retombe une préférence inconnue.
    egal('claire', Chemins.defauts.apparence)
    egal('claire', prefs.apparence)
    egal(Dispositions.apparence(nil), Chemins.defauts.apparence, 'défaut de Chemins et de Dispositions')
    egal(nil, Preferences.defauts.apparence, 'une clé de la fenêtre seulement')
    -- Le texte de la ligne dit que les contrôles natifs suivent macOS.
    local texte
    for _, v in ipairs(vues(apparence.ligne)) do
        if v.genre == 'static_text' and v.args.title ~= 'Apparence :' then
            texte = v.args.title
        end
    end
    vrai(texte and texte:find('suivent macOS', 1, true), 'texte de la ligne : ' .. tostring(texte))
    -- Sombre choisie reste choisie ; la valeur par défaut ne s'impose qu'à une clé absente.
    prefs.apparence = 'sombre'
    egal('sombre', Chemins.prefs().apparence)
    egal('sombre', Dispositions.apparence(Chemins.prefs().apparence))
    -- Une préférence inconnue (autre version, abîmée) reste telle quelle dans les préférences, et
    -- retombe sur la claire là où elle sert.
    prefs.apparence = 'bleue'
    egal('bleue', Chemins.prefs().apparence)
    egal('claire', Dispositions.apparence(Chemins.prefs().apparence))
    egal('images/loupe.png', Dispositions.image('loupe', Chemins.prefs().apparence))
    prefs.apparence = nil
    egal('claire', Chemins.prefs().apparence, 'clé retirée : la valeur par défaut')
end)

essai('Diagnostic : réglages de la 1.3 au bout de leur ligne, débuts de ligne intacts', function()
    local mode = ligneDiagnostic('Mode : ')
    -- Sans catalogue lisible (simulation de la fenêtre), le carnet se lit vide.
    vrai(finitPar(mode, ' ; point de mise au point en tout temps : false ; carnet de progrès : true (0 photo)'), mode)
    local fenetre = ligneDiagnostic('Fenêtre Claude : ')
    vrai(finitPar(fenetre, "proposition à l'ouverture : true ; avant/après des étapes : true ; leçon en fin de retouche : true ; apparence : claire"), fenetre)
    -- L'apparence telle qu'elle sert ; une préférence inconnue est dite à côté.
    local prefsApparence = Chemins.prefs()
    prefsApparence.apparence = 'sombre'
    vrai(finitPar(ligneDiagnostic('Fenêtre Claude : '), ' ; apparence : sombre'), 'apparence sombre')
    prefsApparence.apparence = 'bleue'
    local inconnue = ligneDiagnostic('Fenêtre Claude : ')
    vrai(finitPar(inconnue, ' ; apparence : claire (préférence « bleue » inconnue)'), inconnue)
    prefsApparence.apparence = nil
    -- Ce que lisent les essais des dispositions, inchangé.
    vrai(PluginInfoProvider.diagnostic():find('effort max ; nouvelle conversation par photo', 1, true), 'diagnostic')
    vrai(PluginInfoProvider.diagnostic():find('modèle opus, effort max', 1, true), 'diagnostic : modèle et effort')
    local prefs = Chemins.prefs()
    prefs.avantApresEtapes, prefs.carnet = false, false
    vrai(ligneDiagnostic('Fenêtre Claude : '):find('avant/après des étapes : false', 1, true), 'case décochée')
    vrai(ligneDiagnostic('Mode : '):find('carnet de progrès : false', 1, true), 'carnet décoché')
    prefs.avantApresEtapes, prefs.carnet = nil, nil
    -- Un carnet qui ne se lit pas ne fait pas échouer le diagnostic : « ? ».
    local Carnet = require 'Carnet'
    local nombre = Carnet.nombre
    Carnet.nombre = function() error('carnet.json illisible') end
    local ok, ligne = pcall(ligneDiagnostic, 'Mode : ')
    Carnet.nombre = nombre
    vrai(ok and finitPar(ligne, ' ; carnet de progrès : true (?)'), tostring(ligne))
end)

essai('Carnet : se charge dans la simulation de la fenêtre, se lit vide sans catalogue lisible', function()
    local Carnet = require 'Carnet'
    egal(0, Carnet.nombre())
    egal(0, #Carnet.entrees())
    S.neuve(Carnet.entrees(), 'entrées du carnet')
    egal(nil, Carnet.lecon(1))
    egal(nil, Carnet.entree(1))
    egal(nil, package.loaded.Bibliotheque, 'sans la Bibliothèque')
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
