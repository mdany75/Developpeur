-- essais-mises-a-jour.lua : les mises à jour par le SSD (1.7, MisesAJour.lua ; demande de Dany du 3
-- novembre 2026 : deux Mac, l'autre parfois par cellulaire, tout s'installe depuis le SSD), hors de
-- Lightroom (LuaJIT, Lightroom simulé par Simulation.lua), avec un faux connecteur (un script qui
-- rend la comparaison et les comptes rendus du vrai, et note ses appels) : refus sans dossier commun
-- réglé ou présent (sans attente au lancement), la comparaison lue, ce qui se dépose ou s'installe,
-- la question « Mettre à jour depuis le SSD » (acceptée ou remise), l'avancement dans la barre, la
-- croix qui arrête le connecteur, la section du Gestionnaire et sa place dans Init.lua. Tout se
-- passe dans un dossier personnel temporaire : jamais le vrai connecteur, ni le vrai SSD.
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

local function contient(texte, morceau, quoi)
    if type(texte) ~= 'string' or not texte:find(morceau, 1, true) then
        error(string.format('%s : %q introuvable dans %q', quoi or 'texte', morceau, tostring(texte)), 2)
    end
end

assert(S.home:match('^/tmp/') or S.home:match('^/private/') or S.home:match('^/var/folders/'),
    'dossier personnel simulé inattendu : ' .. S.home)

local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Json = require 'Json'
local MisesAJour = require 'MisesAJour'

MisesAJour.PAUSE = 0.05
MisesAJour.DELAI_LANCEMENT = 0

local ssd = S.home .. '/Volumes/Photos/Développeur partagé'
local faux = S.home .. '/outils/faux connecteur'
local journal = S.home .. '/outils/journal'
local etat = S.home .. '/outils/etat.json'
local fin = S.home .. '/outils/fin.json'

-- Le faux connecteur : --mises-a-jour --json rend etat.json ; avec --deposer ou --installer, note ses
-- arguments, écrit deux lignes d'avancement sur stderr, attend (ATTENTE), puis rend fin.json.
Fichiers.ecrire(faux, table.concat({
    '#!/bin/bash',
    'J=' .. S.q(journal) .. '; E=' .. S.q(etat) .. '; F=' .. S.q(fin),
    'case " $* " in',
    '  *" --deposer "*|*" --installer "*)',
    '    printf "%s\\n" "$*" >> "$J"',
    '    echo \'{"avancement":{"element":"mflux","fait":1,"total":4,"texte":"mflux : un quart"}}\' >&2',
    '    echo \'{"avancement":{"element":"mflux","fait":2,"total":4,"texte":"mflux : la moitié"}}\' >&2',
    '    sleep "$(cat "$(dirname "$J")/attente" 2>/dev/null || echo 0.2)"',
    '    cat "$F" ;;',
    '  *" --json "*) printf "verifier\\n" >> "$J"; cat "$E" ;;',
    '  *) exit 2 ;;',
    'esac',
}, '\n') .. '\n')
S.executer('chmod +x ' .. S.q(faux))

local prefs = S.modules.LrPrefs.prefsForPlugin()
prefs.cheminConnecteur = faux
for id, p in pairs(S.prefs) do
    if type(p) == 'table' then p.cheminConnecteur = faux end
end
egal(faux, Chemins.prefs().cheminConnecteur, 'le faux connecteur, jamais le vrai')

local function element(nom, etatTexte, mac, ssdV, deposer, installer)
    return { element = nom, nom = nom, etat = etatTexte, etat_texte = etatTexte, mac = mac and { version = mac } or nil,
        ssd = ssdV and { version = ssdV } or nil, a_deposer = deposer, a_installer = installer }
end

local comparaison = {
    ok = true, installation = ssd .. '/Installation',
    elements = {
        element('uv', 'a_jour', '0.13.5', '0.13.5', false, false),
        element('mflux', 'ssd_plus_recent', '0.23.0', '0.24.0', false, true),
        element('fibo2studio', 'absent_du_mac', nil, '2.8.1', false, true),
        element('claude_code', 'mac_plus_recent', '2.2.3', '2.1.295', true, false),
        element('developpeur', 'mac_plus_recent', '1.7', '1.6.7', true, false),
    },
}
Fichiers.ecrire(etat, Json.encode(comparaison))
Fichiers.ecrire(fin, Json.encode({ ok = true,
    faits = { { element = 'mflux', action = 'installe', texte = "mflux 0.24.0 installé hors ligne." } },
    relancer = { "Fibo 2 Studio : le rouvrir." } }))

local function poserPointeur(dossier)
    Fichiers.ecrire(Chemins.pointeur(), Json.encode({ format = 1, dossier = dossier }))
end

local function appels()
    local t = {}
    for ligne in (Fichiers.lire(journal) or ''):gmatch('[^\n]+') do
        t[#t + 1] = ligne
    end
    return t
end

local function remettre()
    Fichiers.supprimer(journal)
    S.messages = {}
    S.confirmation = nil
    S.reponseConfirm = nil
    S.barres = {}
    MisesAJour.enCours = false
    Chemins.prefs().misesAJourRefus = nil
end

-- Refus --------------------------------------------------------------------------------------------

essai('sans dossier commun : refus, et au lancement rien, sans attendre', function()
    remettre()
    Fichiers.supprimer(Chemins.pointeur())
    contient(MisesAJour.refus(), "Aucun dossier commun")
    local r, raison = MisesAJour.verifier()
    egal(nil, r)
    contient(raison, "Aucun dossier commun")
    MisesAJour.DELAI_LANCEMENT = 1000
    local debut = os.time()
    egal(false, MisesAJour.auLancement())
    vrai(os.time() - debut < 5, 'aucune attente sans dossier commun')
    MisesAJour.DELAI_LANCEMENT = 0
    egal(0, #appels(), 'le connecteur n\'est pas lancé')
end)

essai('dossier commun réglé mais débranché : le refus du contrat', function()
    remettre()
    poserPointeur(S.home .. '/Volumes/Débranché/Commun')
    egal(Chemins.messageAbsent(S.home .. '/Volumes/Débranché/Commun'), MisesAJour.refus())
    egal(false, MisesAJour.auLancement())
    egal(0, #appels())
end)

-- Comparaison ---------------------------------------------------------------------------------------

essai('comparaison lue : à installer, à déposer (Développeur seulement avec son archive), état', function()
    remettre()
    S.executer('mkdir -p ' .. S.q(ssd))
    poserPointeur(ssd)
    egal(nil, MisesAJour.refus())
    local r = assert(MisesAJour.verifier())
    egal(5, #r.elements)
    local installer, deposer = MisesAJour.aInstaller(r), MisesAJour.aDeposer(r)
    egal(2, #installer)
    egal('mflux', installer[1].element)
    egal('fibo2studio', installer[2].element)
    egal(1, #deposer, 'sans archive gardée, Développeur ne se dépose pas')
    egal('claude_code', deposer[1].element)
    Fichiers.ecrire(Chemins.locale() .. '/Archive/Developpeur.zip', 'zip')
    egal(2, #MisesAJour.aDeposer(r))
    Fichiers.supprimer(Chemins.locale() .. '/Archive/Developpeur.zip')
    egal('2 éléments plus récents sur le SSD ; 1 à déposer sur le SSD', MisesAJour.texteEtat(r))
    contient(MisesAJour.texteListe(installer, 'installer'), '• mflux : 0.24.0 sur le SSD (ce Mac : 0.23.0)')
    contient(MisesAJour.texteListe(installer, 'installer'), '• fibo2studio : 2.8.1 sur le SSD (absent de ce Mac)')
    egal(r, MisesAJour.derniere)
end)

essai('connecteur muet ou en refus : dit, sans rien d\'autre', function()
    remettre()
    poserPointeur(ssd)
    Fichiers.ecrire(etat, Json.encode({ ok = false, erreur = "Aucun dossier commun n'est réglé." }))
    local r, raison = MisesAJour.verifier()
    egal(nil, r)
    egal("Aucun dossier commun n'est réglé.", raison)
    Fichiers.ecrire(etat, 'pas du JSON')
    r, raison = MisesAJour.verifier()
    contient(raison, "n'a pas répondu")
    Fichiers.ecrire(etat, Json.encode(comparaison))
end)

-- Au lancement --------------------------------------------------------------------------------------

essai('au lancement : la question, l\'installation acceptée dans sa barre, puis le dépôt et ce qu\'il faut relancer', function()
    remettre()
    poserPointeur(ssd)
    S.reponseConfirm = 'ok'
    egal(true, MisesAJour.auLancement())
    vrai(S.confirmation, 'la question est posée')
    egal('Mettre à jour depuis le SSD', S.confirmation[1])
    contient(S.confirmation[2], '• mflux : 0.24.0 sur le SSD (ce Mac : 0.23.0)')
    contient(S.confirmation[2], 'sans téléchargement')
    egal('Mettre à jour', S.confirmation[3])
    egal('Plus tard', S.confirmation[4])
    local a = appels()
    egal('verifier', a[1])
    contient(a[2], '--mises-a-jour --json --installer mflux fibo2studio')
    contient(a[3], '--mises-a-jour --json --deposer claude_code')
    egal('verifier', a[4], 'l\'état relu à la fin')
    egal(2, #S.barres, 'une barre par action')
    vrai(S.barres[1].annulable and S.barres[1].finie, 'barre annulable, finie')
    egal('Mises à jour depuis le SSD', S.messages[1][1])
    contient(S.messages[1][2], '• mflux 0.24.0 installé hors ligne.')
    contient(S.messages[1][2], 'À relancer :\n• Fibo 2 Studio : le rouvrir.')
    egal(1, #S.messages, 'le dépôt réussi ne dit rien')
    egal(false, MisesAJour.enCours)
end)

essai('« Plus tard » : rien d\'installé, le dépôt se fait quand même', function()
    remettre()
    poserPointeur(ssd)
    S.reponseConfirm = 'cancel'
    MisesAJour.auLancement()
    local a = appels()
    egal(3, #a)
    vrai(not table.concat(a, '\n'):find('--installer', 1, true), 'rien d\'installé')
    contient(a[2], '--deposer claude_code')
end)

essai('la barre : avancement lu, la croix arrête le connecteur', function()
    remettre()
    poserPointeur(ssd)
    Fichiers.ecrire(S.home .. '/outils/attente', '5')
    local textes, portions = {}, {}
    local barre = { annulee = false }
    function barre:setCaption(t) textes[#textes + 1] = t end
    function barre:setPortionComplete(a, b) portions[#portions + 1] = a / b; if #portions >= 2 then self.annulee = true end end
    function barre:isCanceled() return self.annulee end
    local debut = os.time()
    local r, annule = MisesAJour.executer('deposer', { { element = 'modeles_hf' } }, barre)
    Fichiers.supprimer(S.home .. '/outils/attente')
    egal(true, annule)
    egal(nil, r)
    vrai(os.time() - debut < 4, 'arrêté sans attendre la fin')
    egal('mflux : la moitié', textes[#textes])
    egal(0.5, portions[#portions])
    contient(MisesAJour.texteFin(nil, true), 'reprendra')
end)

-- Gestionnaire --------------------------------------------------------------------------------------

essai('Gestionnaire : section Mises à jour par le SSD, état et trois boutons', function()
    remettre()
    poserPointeur(ssd)
    local PluginInfoProvider = require 'PluginInfoProvider'
    local f = S.modules.LrView.osFactory()
    local proprietes = S.modules.LrBinding.makePropertyTable()
    local sections = PluginInfoProvider.sectionsForTopOfDialog(f, proprietes)
    local section = sections[4]
    egal('Mises à jour par le SSD', section.title)
    local boutons = {}
    local function parcourir(v)
        if type(v) ~= 'table' then
            return
        end
        if v.genre and S.BOUTONS[v.genre] then
            boutons[v.args.title] = v
        end
        for _, enfant in ipairs(v.args or v) do
            parcourir(enfant)
        end
    end
    parcourir(section)
    vrai(boutons['Vérifier'] and boutons['Installer depuis le SSD'] and boutons['Déposer sur le SSD'], 'les trois boutons')
    local taches = #S.taches
    boutons['Vérifier'].args.action()
    egal(taches + 1, #S.taches, 'dans sa propre tâche')
    S.taches[#S.taches]()
    egal('Mises à jour par le SSD', S.messages[#S.messages][1])
    contient(S.messages[#S.messages][2], '• mflux : ssd_plus_recent')
    egal('2 éléments plus récents sur le SSD ; 1 à déposer sur le SSD', proprietes.misesAJour)
    -- Déposer : sans question, avec son compte rendu.
    boutons['Déposer sur le SSD'].args.action()
    S.taches[#S.taches]()
    contient(table.concat(appels(), '\n'), '--deposer claude_code')
    egal('Dépôt sur le SSD', S.messages[#S.messages][1])
    -- Sans dossier commun : le refus, rien de lancé.
    Fichiers.supprimer(Chemins.pointeur())
    remettre()
    boutons['Installer depuis le SSD'].args.action()
    S.taches[#S.taches]()
    egal(0, #appels())
    contient(proprietes.misesAJour, 'Aucun dossier commun')
end)

-- Constats de la revue (1.7) -----------------------------------------------------------------------

local finNormale = Fichiers.lire(fin)

essai('refus de tout le bloc (verrou, dossier commun disparu) : son erreur, jamais une fenêtre vide ; rien au lancement pour le verrou', function()
    remettre()
    poserPointeur(ssd)
    local verrou = "Une autre mise à jour par le SSD est déjà en cours sur ce Mac : attendre qu'elle finisse."
    egal(verrou, MisesAJour.texteFin({ ok = false, erreur = verrou }, false))
    Fichiers.ecrire(fin, Json.encode({ ok = false, erreur = verrou }))
    -- Depuis le Gestionnaire : dit.
    MisesAJour.deposer({ { element = 'modeles_hf' } }, true)
    egal(1, #S.messages)
    egal(verrou, S.messages[1][2])
    -- Au lancement : ni pour le dépôt ni pour l'installation acceptée.
    S.messages = {}
    S.reponseConfirm = 'ok'
    MisesAJour.auLancement()
    egal(0, #S.messages, 'aucune fenêtre pour le verrou au lancement')
    Fichiers.ecrire(fin, finNormale)
end)

essai('les notes d\'install.sh sous leur fait, sans deux-points qui pendent', function()
    local t = MisesAJour.texteFin({ ok = true, faits = { { element = 'developpeur', action = 'installe',
        texte = "Développeur IA 1.7 installé.", notes = { "Claude Desktop est ouvert : il réécrira sa configuration sans le connecteur." } } } })
    contient(t, "• Développeur IA 1.7 installé.\n   – Claude Desktop est ouvert : il réécrira sa configuration")
    vrai(not t:find('dit :', 1, true), 'plus de « install.sh dit : »')
end)

essai('au lancement : un refus durable dit une fois, puis plus retenté tant que rien ne change ; le Gestionnaire le relance', function()
    remettre()
    poserPointeur(ssd)
    S.reponseConfirm = 'cancel'
    Fichiers.ecrire(fin, Json.encode({ ok = false, faits = { { element = 'claude_code', action = 'refuse',
        texte = "Claude Code : place insuffisante sur le disque." } } }))
    MisesAJour.auLancement()
    egal(1, #S.messages, 'dit une fois')
    contient(S.messages[1][2], 'place insuffisante')
    contient(S.messages[1][2], 'ne sera plus retenté au lancement')
    -- Lancement suivant : même état, ni dépôt ni fenêtre.
    S.messages = {}
    Fichiers.supprimer(journal)
    MisesAJour.auLancement()
    egal(0, #S.messages, 'rien de redit')
    vrai(not table.concat(appels(), '\n'):find('--deposer', 1, true), 'le dépôt refusé n\'est pas relancé')
    -- Une autre version sur ce Mac : retenté.
    local autre = Json.decode(Json.encode(comparaison))
    autre.elements[4].mac.version = '2.3.0'
    Fichiers.ecrire(etat, Json.encode(autre))
    Fichiers.supprimer(journal)
    MisesAJour.auLancement()
    contient(table.concat(appels(), '\n'), '--deposer claude_code')
    Fichiers.ecrire(etat, Json.encode(comparaison))
    -- Le Gestionnaire relance, et sa réussite oublie le refus.
    Fichiers.ecrire(fin, Json.encode({ ok = true, faits = { { element = 'claude_code', action = 'depose', texte = "Claude Code déposé." } } }))
    MisesAJour.deposer({ comparaison.elements[4] }, true)
    egal(nil, next(MisesAJour.refusRetenus()), 'refus oubliés après la réussite')
    Fichiers.ecrire(fin, finNormale)
end)

essai('Claude Code au lancement : seulement absent de l\'autre côté ou une version mineure d\'écart', function()
    local proche = element('claude_code', 'ssd_plus_recent', '2.1.303', '2.1.305', false, true)
    local loin = element('claude_code', 'ssd_plus_recent', '2.1.303', '2.2.0', false, true)
    local absent = element('claude_code', 'absent_du_mac', nil, '2.1.305', false, true)
    local mflux = element('mflux', 'ssd_plus_recent', '0.24.0', '0.24.1', false, true)
    remettre()
    local garde = MisesAJour.pourLeLancement('installer', { proche, loin, absent, mflux })
    egal(3, #garde)
    egal(loin, garde[1])
    egal(absent, garde[2])
    egal(mflux, garde[3], 'les autres éléments, même à un petit écart')
end)

essai('le refus sans dossier commun renvoie à la section du dessus', function()
    remettre()
    Fichiers.supprimer(Chemins.pointeur())
    contient(MisesAJour.refus(), 'section Dossier commun, ci-dessus')
    local PluginInfoProvider = require 'PluginInfoProvider'
    local f = S.modules.LrView.osFactory()
    local sections = PluginInfoProvider.sectionsForTopOfDialog(f, S.modules.LrBinding.makePropertyTable())
    local avant
    for i, s in ipairs(sections) do
        if s.title == 'Dossier commun' then avant = i end
        if s.title == 'Mises à jour par le SSD' then vrai(avant and avant < i, 'Dossier commun est au-dessus') end
    end
end)

essai('Init.lua : les mises à jour par le SSD en dernier dans la tâche du lancement, à part', function()
    local f = assert(io.open(S.plugin .. '/Init.lua', 'rb'))
    local code = f:read('*a')
    f:close()
    local etapes = code:find("require('Etapes').menage()", 1, true)
    local maj = code:find("require('MisesAJour').auLancement()", 1, true)
    vrai(etapes and maj and maj > etapes, 'après le ménage des étapes')
    vrai(code:find("LrTasks.pcall(function()\n        require('MisesAJour').auLancement()", 1, true), 'dans sa propre protection')
    local liaison = code:find("require('Liaison').demarrer()", 1, true)
    vrai(liaison and liaison < maj, 'après le démarrage de la liaison')
end)

essai('Gestionnaire : MisesAJour.lua qui ne se charge pas (module rechargé sans relancer Lightroom) : les autres sections restent', function()
    local PluginInfoProvider = require 'PluginInfoProvider'
    local garde = package.loaded.MisesAJour
    package.loaded.MisesAJour = nil
    package.preload.MisesAJour = function() error('Could not load toolkit script: MisesAJour.lua', 0) end
    local ok, sections = pcall(PluginInfoProvider.sectionsForTopOfDialog, S.modules.LrView.osFactory(), S.modules.LrBinding.makePropertyTable())
    package.preload.MisesAJour = nil
    package.loaded.MisesAJour = garde
    vrai(ok, tostring(sections))
    egal(4, #sections)
    egal('Mises à jour par le SSD', sections[4].title)
    egal('indisponible', sections[4].synopsis)
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
