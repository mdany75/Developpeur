-- Session.lua : un processus Claude Code gardé ouvert pour une conversation, par relais.sh.
-- Un message par demande ; les événements se relisent au fil de l'eau (Session:lire). Si le
-- processus s'est arrêté (inactivité, changement de modèle, erreur), la demande suivante le
-- relance avec `--resume` : la conversation continue.
-- Les méthodes qui lancent un processus s'appellent depuis une tâche (LrTasks.startAsyncTask).

local LrDate = import 'LrDate'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Evenements = require 'Evenements'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'
local Texte = require 'Texte'

local Session = {}
Session.__index = Session

-- Le nom du connecteur dans la configuration MCP passée à Claude Code : ses outils s'appellent
-- mcp__developpeur__* (relais.sh les autorise, Conversation.PREFIXE_OUTILS les reconnaît).
Session.SERVEUR = 'developpeur'

local numero = 0

-- options : idConversation, claude, connecteur, modele, effort, reprise (sessionID), travail
-- (dossier de travail de Claude Code), consignes (texte : Consignes.texte).
function Session.nouvelle(options)
    local s = setmetatable({}, Session)
    for cle, valeur in pairs(options) do
        s[cle] = valeur
    end
    s.position = 0
    s.reste = ''
    s.interruptions = 0
    return s
end

local function fichier(s, nom)
    return LrPathUtils.child(s.dossier, nom)
end

-- Vrai tant que le processus lancé n'a pas écrit son code de sortie.
function Session:actif()
    return self.dossier ~= nil and not self.termine and not Fichiers.existe(fichier(self, 'fin.code'))
end

-- La configuration MCP : le connecteur seul, par son chemin absolu.
function Session.configMCP(connecteur)
    return Json.encode({ mcpServers = { [Session.SERVEUR] = { command = connecteur } } })
end

-- Lance relais.sh dans un nouveau dossier de session. `premiereLigne` est écrite avant le
-- lancement (relais.sh relit entree.jsonl depuis le début).
function Session:lancer(premiereLigne)
    if not Fichiers.existe(self.claude) then
        error("Claude Code est introuvable (" .. tostring(self.claude) .. "). Réglez son chemin dans Fichier › Gestionnaire de modules externes › Développeur, section Fenêtre Claude.", 0)
    end
    if not Fichiers.existe(self.connecteur) then
        error("Le connecteur MCP-Développeur est introuvable (" .. tostring(self.connecteur) .. "). Réinstallez Développeur, ou réglez son chemin dans Fichier › Gestionnaire de modules externes › Développeur, section Fenêtre Claude.", 0)
    end
    numero = numero + 1
    self.dossier = LrPathUtils.child(Chemins.sessions(), string.format('%s-%d-%d', self.idConversation, os.time(), numero))
    Fichiers.creerDossier(self.dossier)
    Fichiers.creerDossier(self.travail)
    Fichiers.ecrire(Chemins.configMCP(), Session.configMCP(self.connecteur))
    -- Les consignes dans le dossier de la session : Claude Code les lit à son démarrage, un peu
    -- après ce lancement en arrière-plan ; un fichier commun pourrait être réécrit entre-temps.
    local consignes = fichier(self, 'consignes.md')
    Fichiers.ecrire(consignes, self.consignes or '')
    Fichiers.ecrire(fichier(self, 'entree.jsonl'), premiereLigne .. '\n')
    self.position = 0
    self.reste = ''
    self.termine = false
    self.arretDemande = false
    self.lanceLe = os.time()
    local q = Texte.shell
    -- « $PPID » : le parent du shell lancé par LrTasks.execute, c'est-à-dire Lightroom.
    local commande = table.concat({ '/bin/sh', q(Chemins.relais()), q(self.dossier), q(self.claude), q(self.modele),
        q(self.effort or ''), q(self.reprise or ''), q(self.travail), q(Chemins.configMCP()), q(consignes), '"$PPID"',
        '> /dev/null 2>&1 &' }, ' ')
    Journal.noter("Lancement de Claude Code :", self.modele, "effort " .. tostring(self.effort or 'par défaut'),
        self.reprise and ("reprise " .. self.reprise) or "nouvelle session", self.dossier)
    LrTasks.execute(commande)
end

-- Envoie une ligne (message ou commande) ; lance le processus s'il ne tourne pas.
function Session:ecrire(ligne)
    if self:actif() then
        Fichiers.ajouterLigne(fichier(self, 'entree.jsonl'), ligne)
    else
        self:lancer(ligne)
    end
end

-- Envoie une demande : le texte et les images jointes ({ donnees, type }).
function Session:envoyer(texte, images)
    self:ecrire(Evenements.messageUtilisateur(texte, images))
end

-- Demande à Claude d'arrêter ce qu'il fait (le connecteur arrête une série proprement).
function Session:interrompre()
    if self:actif() then
        self.interruptions = self.interruptions + 1
        Fichiers.ajouterLigne(fichier(self, 'entree.jsonl'), Evenements.interruption('interruption-' .. self.interruptions))
    end
end

-- Ferme le processus (relais.sh termine son entrée, puis l'arrête s'il traîne).
function Session:arreter()
    if self:actif() and not self.arretDemande then
        self.arretDemande = true
        Fichiers.ecrire(fichier(self, 'arreter'), '')
    end
end

-- Les lignes complètes arrivées depuis la dernière lecture, puis, une seule fois après l'arrêt du
-- processus, `fini` = true avec son code de sortie et la fin de son journal d'erreurs.
function Session:lire()
    local lignes = {}
    if not self.dossier or self.termine then
        return lignes, false
    end
    local f = io.open(fichier(self, 'sortie.jsonl'), 'rb')
    if f then
        local morceau
        if f.seek then
            f:seek('set', self.position)
            morceau = f:read('*a')
        else
            morceau = (f:read('*a') or ''):sub(self.position + 1)
        end
        f:close()
        if morceau and #morceau > 0 then
            self.position = self.position + #morceau
            local texte = self.reste .. morceau
            local debut = 1
            while true do
                local fin = texte:find('\n', debut, true)
                if not fin then
                    break
                end
                lignes[#lignes + 1] = texte:sub(debut, fin - 1)
                debut = fin + 1
            end
            self.reste = texte:sub(debut)
        end
    end
    local code = Fichiers.lire(fichier(self, 'fin.code'))
    if code and #lignes == 0 then
        -- Le processus est fini et tout est lu : la dernière ligne sans saut de ligne aussi.
        if self.reste ~= '' then
            lignes[#lignes + 1] = self.reste
            self.reste = ''
            return lignes, false
        end
        self.termine = true
        local erreurs = Fichiers.lire(fichier(self, 'erreurs.log')) or ''
        erreurs = Texte.nettoyer(erreurs)
        if #erreurs > 600 then
            erreurs = erreurs:sub(-600)
        end
        Journal.noter("Claude Code arrêté, code " .. Texte.nettoyer(code), erreurs ~= '' and ("· " .. erreurs) or '')
        return lignes, true, tonumber(Texte.nettoyer(code)), erreurs
    end
    return lignes, false
end

-- Ménage au chargement du module : les sessions d'une séance précédente sont fermées (relais.sh
-- s'arrête seul avec Lightroom ; « arreter » au cas où), celles qui sont finies sont effacées.
function Session.menage()
    local maintenant = LrDate.currentTime()
    for _, nom in ipairs(Fichiers.entrees(Chemins.sessions())) do
        local dossier = LrPathUtils.child(Chemins.sessions(), nom)
        local date = Fichiers.date(dossier)
        if Fichiers.existe(LrPathUtils.child(dossier, 'fin.code')) or (date and maintenant - date > 86400) then
            Fichiers.supprimer(dossier)
        else
            pcall(Fichiers.ecrire, LrPathUtils.child(dossier, 'arreter'), '')
        end
    end
end

return Session
