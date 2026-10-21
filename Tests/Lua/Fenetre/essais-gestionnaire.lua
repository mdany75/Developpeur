-- essais-gestionnaire.lua : les réglages de la 1.3 dans le Gestionnaire de modules externes, hors
-- de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : la case Carnet dans la section de la
-- liaison, les cases Avant/après et Leçon dans celle de la fenêtre Claude, leurs valeurs par
-- défaut, et le diagnostic (réglages de la 1.3 au bout de leur ligne). Le registre du carnet
-- (Carnet.lua) se charge ici aussi, sans catalogue lisible : il se lit vide. Ni Claude, ni quota.
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

essai('Diagnostic : réglages de la 1.3 au bout de leur ligne, débuts de ligne intacts', function()
    local mode = ligneDiagnostic('Mode : ')
    -- Sans catalogue lisible (simulation de la fenêtre), le carnet se lit vide.
    vrai(finitPar(mode, ' ; point de mise au point en tout temps : false ; carnet de progrès : true (0 photo)'), mode)
    local fenetre = ligneDiagnostic('Fenêtre Claude : ')
    vrai(finitPar(fenetre, "proposition à l'ouverture : true ; avant/après des étapes : true ; leçon en fin de retouche : true"), fenetre)
    -- Ce que lisent les essais des dispositions, inchangé.
    vrai(PluginInfoProvider.diagnostic():find('effort max ; nouvelle conversation par photo', 1, true), 'diagnostic')
    vrai(PluginInfoProvider.diagnostic():find('modèle opus, effort max', 1, true), 'diagnostic : modèle et effort')
    local prefs = Chemins.prefs()
    prefs.avantApresEtapes, prefs.carnet = false, false
    vrai(ligneDiagnostic('Fenêtre Claude : '):find('avant/après des étapes : false', 1, true), 'case décochée')
    vrai(ligneDiagnostic('Mode : '):find('carnet de progrès : false', 1, true), 'carnet décoché')
    prefs.avantApresEtapes, prefs.carnet = nil, nil
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
