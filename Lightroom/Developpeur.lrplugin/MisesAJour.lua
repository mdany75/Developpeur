-- MisesAJour.lua : les mises à jour par le SSD (1.7, demande de Dany du 3 novembre 2026 : deux Mac,
-- l'autre parfois connecté par cellulaire, « je veux tout sur le SSD »). Le connecteur fait tout le
-- travail (`mcp-developpeur --mises-a-jour`, Sources/DeveloppeurKit/Installation.swift) dans le
-- dossier Installation du dossier commun : ce module le lance, lit sa réponse et parle à Dany.
--   - Au lancement de Lightroom (Init.lua, en dernier dans sa tâche, après le démarrage de la
--     liaison et les ménages) : dossier commun réglé et présent seulement, après une attente
--     (DELAI_LANCEMENT), la comparaison (`--mises-a-jour --json`, sous l'alarme de perl comme
--     --analyser) ; si le SSD a plus récent, la proposition « Mettre à jour depuis le SSD »
--     (LrDialogs.confirm, éléments et versions), l'installation en arrière-plan, puis ce qu'il faut
--     relancer ; si ce Mac a plus récent, le dépôt en arrière-plan. Chacun dans une barre de
--     Lightroom (LrProgressScope) annulable : la croix arrête le connecteur (kill), qui reprend la
--     fois suivante (fichiers « .partiel »).
--   - Le Gestionnaire de modules externes (section « Mises à jour par le SSD ») : l'état et les
--     boutons Vérifier, Installer depuis le SSD, Déposer sur le SSD.
-- Une seule action à la fois depuis ce module (MisesAJour.enCours) ; le connecteur a aussi son
-- verrou. Jamais rien sans dossier commun réglé et présent. Les essais : essais-mises-a-jour.lua
-- (faux connecteur, jamais le vrai).

local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Json = require 'Json'
local Texte = require 'Texte'

local MisesAJour = {}

-- Attente après le lancement de Lightroom, avant la comparaison (secondes) : la liaison, le Suivi
-- et les ménages passent d'abord.
MisesAJour.DELAI_LANCEMENT = 45
-- Alarme de perl pour la comparaison (secondes) : le connecteur lit les versions et l'inventaire
-- des modèles (des milliers de fichiers lus sans être ouverts).
MisesAJour.ALARME = 120
-- Entre deux lectures de l'avancement d'un dépôt ou d'une installation (secondes).
MisesAJour.PAUSE = 1
MisesAJour.enCours = false
-- La dernière comparaison lue (le Gestionnaire la montre).
MisesAJour.derniere = false

local function q(s) return Texte.shell(s) end

local function dossier()
    local d = LrPathUtils.child(Chemins.temporaire(), 'Mises a jour')
    Fichiers.creerDossier(d)
    return d
end

function MisesAJour.connecteur()
    return Chemins.prefs().cheminConnecteur
end

-- Le refus (texte) quand les mises à jour ne peuvent pas passer par le SSD, sinon nil.
function MisesAJour.refus()
    local commun = Chemins.dossierCommun()
    if not commun.regle then
        return "Aucun dossier commun n'est réglé : les mises à jour par le SSD passent par lui (section Dossier commun, ci-dessus)."
    elseif not commun.present then
        return Chemins.messageAbsent(commun.chemin)
    end
    local connecteur = MisesAJour.connecteur()
    if not Fichiers.existe(connecteur) then
        return "Le connecteur MCP-Développeur est introuvable (" .. tostring(connecteur) .. ")."
    end
    return nil
end

-- La comparaison : la réponse du connecteur décodée, ou nil et la raison.
function MisesAJour.verifier()
    local refus = MisesAJour.refus()
    if refus then
        return nil, refus
    end
    local reponse = LrPathUtils.child(dossier(), string.format('comparaison-%d.json', os.time()))
    LrTasks.execute(string.format("/usr/bin/perl -e 'alarm %d; exec @ARGV' %s --mises-a-jour --json > %s 2>/dev/null",
        MisesAJour.ALARME, q(MisesAJour.connecteur()), q(reponse)))
    local texte = Fichiers.lire(reponse) or ''
    Fichiers.supprimer(reponse)
    local ok, r = pcall(Json.decode, texte)
    if not ok or type(r) ~= 'table' then
        return nil, "Le connecteur n'a pas répondu à temps (mises à jour par le SSD)."
    end
    if r.ok == false and type(r.erreur) == 'string' then
        return nil, r.erreur
    end
    MisesAJour.derniere = r
    return r
end

local function elements(r, cle)
    local liste = {}
    for _, e in ipairs(type(r) == 'table' and type(r.elements) == 'table' and r.elements or {}) do
        if type(e) == 'table' and e[cle] == true and type(e.element) == 'string' then
            liste[#liste + 1] = e
        end
    end
    return liste
end

-- Ce que ce Mac a de plus récent (ou que le SSD n'a pas). Développeur seulement s'il a son archive
-- (gardée par install.sh) : sans elle, le connecteur ne peut pas le déposer.
function MisesAJour.aDeposer(r)
    local archive = LrPathUtils.child(LrPathUtils.child(Chemins.locale(), 'Archive'), 'Developpeur.zip')
    local liste = {}
    for _, e in ipairs(elements(r, 'a_deposer')) do
        if type(e.mac) == 'table' and (e.element ~= 'developpeur' or Fichiers.existe(archive)) then
            liste[#liste + 1] = e
        end
    end
    return liste
end

-- Ce que le SSD a de plus récent (ou que ce Mac n'a pas).
function MisesAJour.aInstaller(r)
    local liste = {}
    for _, e in ipairs(elements(r, 'a_installer')) do
        if type(e.ssd) == 'table' then
            liste[#liste + 1] = e
        end
    end
    return liste
end

local function version(cote)
    return type(cote) == 'table' and type(cote.version) == 'string' and cote.version or nil
end

-- « Fibo 2 Studio : 2.8.1 sur le SSD (ce Mac : 2.7) », une ligne par élément.
function MisesAJour.texteListe(liste, sens)
    local lignes = {}
    for _, e in ipairs(liste) do
        local ssd, mac = version(e.ssd), version(e.mac)
        if sens == 'installer' then
            lignes[#lignes + 1] = string.format("• %s : %s sur le SSD (%s)", e.nom or e.element, ssd or '?',
                mac and ("ce Mac : " .. mac) or "absent de ce Mac")
        else
            lignes[#lignes + 1] = string.format("• %s : %s sur ce Mac (%s)", e.nom or e.element, mac or '?',
                ssd and ("SSD : " .. ssd) or "absent du SSD")
        end
    end
    return table.concat(lignes, "\n")
end

-- L'état en une phrase pour le Gestionnaire.
function MisesAJour.texteEtat(r, erreur)
    if not r then
        return erreur or "pas encore vérifié"
    end
    local installer, deposer = #MisesAJour.aInstaller(r), #MisesAJour.aDeposer(r)
    if installer == 0 and deposer == 0 then
        return "tout est à jour (ce Mac et le SSD)"
    end
    local morceaux = {}
    if installer > 0 then
        morceaux[#morceaux + 1] = string.format("%d élément%s plus récent%s sur le SSD", installer, installer > 1 and "s" or "", installer > 1 and "s" or "")
    end
    if deposer > 0 then
        morceaux[#morceaux + 1] = string.format("%d à déposer sur le SSD", deposer)
    end
    return table.concat(morceaux, " ; ")
end

-- La dernière ligne d'avancement écrite par le connecteur (stderr en JSON), ou nil.
local function derniereAvance(fichier)
    local texte = Fichiers.lire(fichier) or ''
    local derniere
    for ligne in texte:gmatch('[^\n]+') do
        if ligne:find('"avancement"', 1, true) then
            derniere = ligne
        end
    end
    if not derniere then
        return nil
    end
    local ok, j = pcall(Json.decode, derniere)
    return ok and type(j) == 'table' and type(j.avancement) == 'table' and j.avancement or nil
end

-- Dépose ou installe (action 'deposer' ou 'installer') ces éléments : le connecteur lancé à part,
-- son avancement dans la barre, la croix l'arrête. Rend la réponse décodée (nil : arrêté ou muet)
-- et vrai si Dany a annulé.
function MisesAJour.executer(action, liste, barre)
    local noms = {}
    for _, e in ipairs(liste) do
        noms[#noms + 1] = q(e.element)
    end
    local d = dossier()
    local base = string.format('%s-%d', action, os.time())
    local reponse = LrPathUtils.child(d, base .. '.json')
    local avancement = LrPathUtils.child(d, base .. '.avancement')
    local pid = LrPathUtils.child(d, base .. '.pid')
    LrTasks.execute(string.format("%s --mises-a-jour --json --%s %s > %s 2> %s < /dev/null & echo $! > %s",
        q(MisesAJour.connecteur()), action, table.concat(noms, ' '), q(reponse), q(avancement), q(pid)))
    local numero = tonumber((Fichiers.lire(pid) or ''):match('%d+'))
    local annule = false
    while numero and LrTasks.execute('kill -0 ' .. numero .. ' 2>/dev/null') == 0 do
        if barre then
            local a = derniereAvance(avancement)
            if a then
                if type(a.texte) == 'string' then barre:setCaption(a.texte) end
                if type(a.fait) == 'number' and type(a.total) == 'number' and a.total > 0 then
                    barre:setPortionComplete(math.min(a.fait, a.total), a.total)
                end
            end
            if barre:isCanceled() then
                annule = true
                LrTasks.execute('kill ' .. numero .. ' 2>/dev/null')
                break
            end
        end
        LrTasks.sleep(MisesAJour.PAUSE)
    end
    local ok, r = pcall(Json.decode, Fichiers.lire(reponse) or '')
    for _, f in ipairs({ reponse, avancement, pid }) do
        Fichiers.supprimer(f)
    end
    return ok and type(r) == 'table' and r or nil, annule
end

-- Le compte rendu d'une action pour Dany : chaque fait, puis ce qu'il faut relancer.
function MisesAJour.texteFin(r, annule)
    if annule then
        return "Arrêté : ce qui était à moitié copié reprendra à la prochaine mise à jour."
    end
    if type(r) ~= 'table' then
        return "Le connecteur n'a rien rendu : relancer la vérification depuis le Gestionnaire de modules externes."
    end
    local lignes = {}
    local faits = type(r.faits) == 'table' and r.faits or {}
    -- Un refus de tout le bloc (verrou pris, dossier commun disparu) : sans faits, avec son erreur.
    if #faits == 0 and type(r.erreur) == 'string' and r.erreur ~= '' then
        return r.erreur
    end
    for _, f in ipairs(faits) do
        if type(f) == 'table' and type(f.texte) == 'string' then
            lignes[#lignes + 1] = "• " .. f.texte
            -- Les notes (avertissements et prochaines étapes d'install.sh) sous leur fait ; la sortie
            -- complète est dans mises-a-jour.journal de ce Mac.
            for _, n in ipairs(type(f.notes) == 'table' and f.notes or {}) do
                if type(n) == 'string' and n ~= '' then
                    lignes[#lignes + 1] = "   – " .. n
                end
            end
        end
    end
    if #lignes == 0 then
        lignes[#lignes + 1] = "Rien n'a changé."
    end
    if type(r.relancer) == 'table' and #r.relancer > 0 then
        lignes[#lignes + 1] = "\nÀ relancer :"
        for _, t in ipairs(r.relancer) do
            lignes[#lignes + 1] = "• " .. tostring(t)
        end
    end
    return table.concat(lignes, "\n")
end

-- Une action dans sa barre ; rend la réponse et l'annulation.
local function avecBarre(titre, action, liste)
    local r, annule
    LrFunctionContext.callWithContext('Développeur · mises à jour par le SSD', function(context)
        local barre = LrProgressScope { title = titre, functionContext = context }
        barre:setCancelable(true)
        r, annule = MisesAJour.executer(action, liste, barre)
        barre:done()
    end)
    return r, annule
end

-- Le refus du verrou du connecteur (une autre mise à jour tourne déjà sur ce Mac : un connecteur resté
-- après un rechargement du module, build.sh --install) : au lancement, rien à dire.
MisesAJour.TEXTE_VERROU = "Une autre mise à jour par le SSD est déjà en cours"

local function refusDuVerrou(r)
    return type(r) == 'table' and r.ok == false and type(r.erreur) == 'string'
        and r.erreur:find(MisesAJour.TEXTE_VERROU, 1, true) ~= nil
end

-- Les refus retenus (préférence `misesAJourRefus`, JSON) : { [« action|élément|Mac|SSD »] = texte }.
-- Un élément refusé (place, réseau…) n'est plus retenté au lancement tant que ni ce Mac ni le SSD ne
-- changent de version : le Gestionnaire le relance, et sa réussite l'oublie.
local function signature(action, e)
    return table.concat({ action, tostring(e.element), version(e.mac) or '', version(e.ssd) or '' }, '|')
end

function MisesAJour.refusRetenus()
    local ok, t = pcall(Json.decode, Chemins.prefs().misesAJourRefus or '')
    return ok and type(t) == 'table' and t or {}
end

local function retenirRefus(action, liste, r)
    if type(r) ~= 'table' or type(r.faits) ~= 'table' then
        return
    end
    local retenus = MisesAJour.refusRetenus()
    local neuf = {}
    for cle, texte in pairs(retenus) do
        if type(cle) == 'string' and type(texte) == 'string' then neuf[cle] = texte end
    end
    for _, e in ipairs(liste) do
        -- L'ancien refus de cet élément pour cette action s'oublie, quelle que soit la version.
        local prefixe = action .. '|' .. tostring(e.element) .. '|'
        for cle in pairs(retenus) do
            if type(cle) == 'string' and cle:sub(1, #prefixe) == prefixe then neuf[cle] = nil end
        end
        for _, f in ipairs(r.faits) do
            if type(f) == 'table' and f.element == e.element and (f.action == 'refuse' or f.action == 'echec') then
                neuf[signature(action, e)] = type(f.texte) == 'string' and f.texte or ''
            end
        end
    end
    Chemins.prefs().misesAJourRefus = Json.encode(neuf)
end

-- Ce qui reste à faire au lancement : sans les refus retenus, et Claude Code seulement s'il manque
-- de l'autre côté ou s'il a une version mineure d'écart (il se met à jour seul en ligne, plusieurs
-- fois par semaine : sinon une question et un dépôt à presque chaque lancement).
local function majeureMineure(v)
    local a, b = tostring(v or ''):match('^(%d+)%.(%d+)')
    return a and (a .. '.' .. b) or nil
end

function MisesAJour.pourLeLancement(action, liste)
    local retenus = MisesAJour.refusRetenus()
    local garde = {}
    for _, e in ipairs(liste) do
        local claude = e.element == 'claude_code'
        local ecart = not claude or not version(e.mac) or not version(e.ssd)
            or majeureMineure(version(e.mac)) ~= majeureMineure(version(e.ssd))
        if ecart and not retenus[signature(action, e)] then
            garde[#garde + 1] = e
        end
    end
    return garde
end

-- Installer depuis le SSD : la question d'abord (sauf `sansQuestion`), puis l'installation et ce
-- qu'il faut relancer. Rend vrai si quelque chose a été installé. `auLancement` : rien à dire pour
-- le refus du verrou.
function MisesAJour.installer(liste, sansQuestion, auLancement)
    if #liste == 0 then
        return false
    end
    if not sansQuestion then
        local reponse = LrDialogs.confirm("Mettre à jour depuis le SSD",
            "Le SSD a plus récent que ce Mac :\n\n" .. MisesAJour.texteListe(liste, 'installer')
                .. "\n\nL'installation se fait depuis le SSD, sans téléchargement. Fibo 2 Studio, s'il est ouvert, n'est jamais quitté à votre place.",
            "Mettre à jour", "Plus tard")
        if reponse ~= 'ok' then
            return false
        end
    end
    local r, annule = avecBarre("Mises à jour depuis le SSD", 'installer', liste)
    retenirRefus('installer', liste, r)
    if not (auLancement and refusDuVerrou(r)) then
        LrDialogs.message("Mises à jour depuis le SSD", MisesAJour.texteFin(r, annule), r and r.ok ~= false and 'info' or 'warning')
    end
    return not annule and type(r) == 'table'
end

-- Déposer sur le SSD : sans question (Dany l'a demandé : « à chaque mise à jour… tu places sur le
-- SSD la dernière version »), en arrière-plan ; un message seulement en cas d'échec (jamais pour le
-- refus du verrou au lancement), ou depuis le Gestionnaire (`dire`). Un refus retenu n'est plus
-- retenté au lancement (`pourLeLancement`) : le message le dit une fois.
function MisesAJour.deposer(liste, dire)
    if #liste == 0 then
        return false
    end
    local r, annule = avecBarre("Dépôt sur le SSD : " .. #liste .. " élément" .. (#liste > 1 and "s" or ""), 'deposer', liste)
    retenirRefus('deposer', liste, r)
    if not dire and refusDuVerrou(r) then
        return false
    end
    if dire or annule or type(r) ~= 'table' or r.ok == false then
        local texte = MisesAJour.texteFin(r, annule)
        if not dire and type(r) == 'table' and r.ok == false and #(type(r.faits) == 'table' and r.faits or {}) > 0 then
            texte = texte .. "\n\nCe qui a été refusé ne sera plus retenté au lancement de Lightroom tant que rien ne change : "
                .. "Fichier › Gestionnaire de modules externes › Mises à jour par le SSD › Déposer sur le SSD le relance."
        end
        LrDialogs.message("Dépôt sur le SSD", texte, r and r.ok ~= false and 'info' or 'warning')
    end
    return not annule and type(r) == 'table'
end

-- La vérification du lancement : comparer, proposer l'installation de ce que le SSD a de plus
-- récent, puis déposer ce que ce Mac a de plus récent, sans les refus retenus ni les petits écarts de
-- Claude Code (`pourLeLancement`). Rend la comparaison (ou nil et la raison).
function MisesAJour.verifierEtMettreAJour()
    if MisesAJour.enCours then
        return nil, "Une mise à jour par le SSD est déjà en cours."
    end
    MisesAJour.enCours = true
    local ok, r, raison = LrTasks.pcall(function()
        local r, raison = MisesAJour.verifier()
        if not r then
            return nil, raison
        end
        MisesAJour.installer(MisesAJour.pourLeLancement('installer', MisesAJour.aInstaller(r)), false, true)
        local deposer = MisesAJour.pourLeLancement('deposer', MisesAJour.aDeposer(r))
        if #deposer > 0 then
            MisesAJour.deposer(deposer)
        end
        return MisesAJour.verifier()
    end)
    MisesAJour.enCours = false
    if not ok then
        return nil, tostring(r)
    end
    return r, raison
end

-- Au lancement de Lightroom (Init.lua, dans sa tâche) : rien sans dossier commun réglé et présent
-- (aucune attente non plus), sinon l'attente puis la vérification.
function MisesAJour.auLancement()
    local commun = Chemins.dossierCommun()
    if not commun.regle or not commun.present or not Fichiers.existe(MisesAJour.connecteur()) then
        return false
    end
    LrTasks.sleep(MisesAJour.DELAI_LANCEMENT)
    MisesAJour.verifierEtMettreAJour()
    return true
end

return MisesAJour
