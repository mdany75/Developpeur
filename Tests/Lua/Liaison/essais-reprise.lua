-- essais-reprise.lua : ne plus perdre une réponse (Liaison.lua), hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua) : la liaison garde la réponse des dernières commandes sous
-- leur `commande_id`, et la commande système `reprendre` la rend sans rien rejouer ; en cours,
-- inconnue, trop grosse, portant le jeton, trop vieille ou au-delà des 20 dernières ; jeton exigé
-- comme pour toute autre ligne. La réponse perdue passe par S.priseReponses et S.serveurParti
-- (Simulation.lua).
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, ligne, photoRaw = A.test, A.egal, A.ligne, A.photoRaw

local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'

local CLE = '6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F'

local function essai(nom, fonction)
    test(nom, function()
        Liaison.prise, Liaison.reponsesConnectee = S.priseReponses(), true
        local executer = Commandes.executer
        local ok, erreur = pcall(fonction)
        Commandes.executer = executer
        Liaison.prise, Liaison.reponsesConnectee = nil, false
        if not ok then
            error(erreur, 0)
        end
    end)
end

local function exposer(valeur)
    return { reglages = { Exposure2012 = valeur }, plages = { Exposure2012 = { -5, 5 } }, confirme = true, etape = 'passe 1',
        raison = "Photo trop sombre." }
end

local function reprendre(id, cle, jeton)
    Liaison.recevoir(ligne({ id = id, command = 'reprendre', params = { commande_id = cle } }, jeton))
    return Json.decode(S.envois[#S.envois])
end

essai("Reprise : la réponse perdue d'une écriture se reprend, sans la rejouer", function()
    local photo = photoRaw()
    S.active = photo
    S.serveurParti = true
    Liaison.recevoir(ligne({ id = 7, commande_id = CLE, command = 'appliquer', params = exposer(0.5) }))
    egal(#S.envois, 0, "le serveur est parti : rien ne lui arrive")
    egal(#S.perdues, 1, "la réponse s'est perdue")
    local ecritures = #S.ecritures
    egal(photo.reglages.Exposure2012, 0.5)

    S.serveurParti = false
    local reponse = reprendre(8, CLE)
    egal(reponse.id, 8)
    egal(reponse.result.trouve, true)
    egal(reponse.result.commande, 'appliquer')
    local perdue = Json.decode(S.perdues[1])
    egal(Json.encode(reponse.result.reponse.result), Json.encode(perdue.result), "la même réponse que celle perdue")
    egal(reponse.result.reponse.id, nil, "sans l'id de l'ancienne ligne")
    egal(#S.ecritures, ecritures, "rien n'est rejoué")
    egal(photo.reglages.Exposure2012, 0.5)
    for _, entree in ipairs(Liaison.resultatsGardes) do
        egal(tostring(entree.texte):find(A.JETON, 1, true), nil, "aucun jeton dans une réponse gardée")
    end

    -- Redemandée, elle est toujours là.
    egal(reprendre(9, CLE).result.trouve, true)
end)

essai("Reprise : une erreur se reprend avec son texte et son code", function()
    S.serveurParti = true
    Liaison.recevoir(ligne({ id = 3, commande_id = CLE, command = 'pivoter', params = {} }))
    S.serveurParti = false
    local reponse = reprendre(4, CLE)
    egal(reponse.result.trouve, true)
    egal(reponse.result.reponse.error, "Commande inconnue : pivoter")
end)

essai("Reprise : jeton exigé, comme pour toute autre ligne", function()
    S.serveurParti = true
    Liaison.recevoir(ligne({ id = 3, commande_id = CLE, command = 'ping', params = {} }))
    S.serveurParti = false
    local refus = reprendre(4, CLE, false)
    egal(refus.code, 'jeton', "sans jeton : refusée")
    egal(refus.result, nil)
    refus = reprendre(5, CLE, string.rep('cd', 32))
    egal(refus.code, 'jeton', "mauvais jeton : refusée")
end)

essai("Reprise : ni ping, ni ligne sans identifiant, ni identifiant invalide ne se gardent", function()
    Liaison.recevoir(ligne({ id = 1, commande_id = CLE, command = 'ping', params = {} }))
    Liaison.recevoir(ligne({ id = 2, command = 'pivoter', params = {} }))
    Liaison.recevoir(ligne({ id = 3, commande_id = 'x; rm', command = 'pivoter', params = {} }))
    egal(#Liaison.resultatsGardes, 0)
    local reponse = reprendre(4, CLE)
    egal(reponse.result.trouve, false)
    egal(reponse.result.en_cours, false, "jamais reçue")
    reponse = reprendre(5, 'x; rm')
    egal(reponse.error, "Reprise : identifiant de commande invalide.")
end)

essai("Reprise : une commande pas finie se dit en cours, et ne compte pas dans enCours", function()
    local vue
    Commandes.executer = function(nom)
        if nom == 'etat' then
            vue = reprendre(2, CLE)
            vue.enCours = Liaison.enCours
            return { ok = true }
        end
    end
    Liaison.recevoir(ligne({ id = 1, commande_id = CLE, command = 'etat', params = {} }))
    egal(vue.result.trouve, false)
    egal(vue.result.en_cours, true)
    egal(vue.result.commande, 'etat')
    egal(vue.enCours, 1, "seule la commande compte, pas la reprise")
    egal(Liaison.commandesEnCours[CLE], nil, "finie : plus en cours")
    egal(reprendre(3, CLE).result.trouve, true)
end)

essai("Reprise : une réponse trop grosse, ou qui porte le jeton, devient un marqueur", function()
    local gros = string.rep('a', Liaison.TAILLE_RESULTAT_GARDE + 10)
    Commandes.executer = function(nom)
        if nom == 'etat' then return { texte = gros } end
        return { fuite = A.JETON }
    end
    Liaison.recevoir(ligne({ id = 1, commande_id = CLE, command = 'etat', params = {} }))
    local reponse = reprendre(2, CLE)
    egal(reponse.result.trouve, true)
    egal(reponse.result.indisponible, 'taille')
    egal(reponse.result.reponse, nil, "rien de lourd gardé")
    egal(reponse.result.octets > Liaison.TAILLE_RESULTAT_GARDE, true)
    egal(Liaison.resultatsGardes[1].texte, nil)

    local autre = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
    Liaison.recevoir(ligne({ id = 3, commande_id = autre, command = 'selection', params = {} }))
    reponse = reprendre(4, autre)
    egal(reponse.result.indisponible, 'jeton')
    egal(S.envois[#S.envois]:find(A.JETON, 1, true), nil, "le jeton ne repart jamais")
end)

essai("Reprise : les 20 dernières réponses, pendant 10 minutes au plus", function()
    Commandes.executer = function() return { ok = true } end
    for i = 1, 25 do
        Liaison.recevoir(ligne({ id = i, commande_id = string.format('CLE-%04d', i), command = 'etat', params = {} }))
    end
    egal(#Liaison.resultatsGardes, Liaison.GARDER_RESULTATS)
    egal(reprendre(30, 'CLE-0005').result.trouve, false, "trop ancienne : oubliée")
    egal(reprendre(31, 'CLE-0006').result.trouve, true)
    egal(reprendre(32, 'CLE-0025').result.trouve, true)
    S.horloge = S.horloge + Liaison.DUREE_RESULTAT_GARDE + 1
    egal(reprendre(33, 'CLE-0025').result.trouve, false, "trop vieille : oubliée")
    egal(#Liaison.resultatsGardes, 0)
end)

A.bilan()
