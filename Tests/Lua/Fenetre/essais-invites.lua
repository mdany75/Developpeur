-- essais-invites.lua : les invites réglables (après la 1.8, demandé par Dany le 10 novembre 2026 :
-- « un menu dans la config, qui me dirait tout ce que tu fais dans un preset […] et un bouton oui
-- ou non », pour « pouvoir configurer ces presets, et qu'ils utilisent les presets bâtis »), hors de
-- Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : la forme des données (Consignes.lua),
-- le message tout à Oui identique à celui de la 1.8, une étape à Non dite à Claude, le fichier
-- invites.json (absent, illisible, aller-retour, dossier commun introuvable), la même configuration
-- pour la fenêtre Claude et la Demande rapide, et la section Invites du Gestionnaire de modules
-- externes. Ni Claude, ni quota.
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
    if not tostring(texte or ''):find(morceau, 1, true) then
        error(string.format('%s : %q ne contient pas %q', quoi or 'texte', tostring(texte), morceau), 2)
    end
end

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Fichiers = require 'Fichiers'
local Json = require 'Json'

local fichier = Chemins.donnee('invites.json')
local function remettre()
    Fichiers.supprimer(fichier)
    vrai(not Fichiers.existe(fichier), 'invites.json retiré')
end

-- Les messages de la 1.8, recopiés tels qu'ils partaient : tout à Oui, rien ne change.
local AVANT = {
    retouche_pro = "Retouche la photo active comme un professionnel : diagnostic chiffré, deux passes vérifiées, puis au plus deux passes correctives si un défaut reste. Avant tout, lis mon guide de style (remember_style avec read = true) et suis ses préférences.",
    portrait = "Retouche ce portrait : peau, yeux, dents, arrière-plan, flou d'objectif si la photo s'y prête ; puis éclaircis et assombris comme un tireur pour mener l'œil au visage (doses d'add_mask), et montre l'avant/après de cette étape. Reste naturel. Avant tout, lis mon guide de style (remember_style avec read = true) et suis ses préférences.",
    paysage = "Retouche ce paysage : horizon, ciel, profondeur, masques de paysage ; puis éclaircis et assombris comme un tireur pour mener l'œil au sujet (doses d'add_mask), et montre l'avant/après de cette étape. Avant tout, lis mon guide de style (remember_style avec read = true) et suis ses préférences.",
    noir_et_blanc = "Passe la photo active en noir et blanc : profil, mélangeur, contraste local, puis éclaircis et assombris comme un tireur (doses d'add_mask) avec l'avant/après de cette étape, et grain. Avant tout, lis mon guide de style (remember_style avec read = true) et suis ses préférences.",
    iso_eleve = "Retouche cette photo prise à ISO élevé : le bruit d'abord (débruitage IA s'il est fort), puis les ombres, les couleurs et la netteté, sans lisser les détails. Avant tout, lis mon guide de style (remember_style avec read = true) et suis ses préférences.",
    composition = "Lis la composition de la photo active (horizon, tiers, espace devant le sujet) et propose un recadrage, sans l'appliquer ; dis la règle en une phrase.",
    sports = "Retouche cette photo de sport : le sujet en action d'abord (exposition, contraste et netteté sur lui), couleurs fidèles des maillots et du terrain, arrière-plan calmé ; bruit si l'ISO est élevé ; recadrage serré sur l'action seulement s'il y gagne nettement, et dis-le. Avant tout, lis mon guide de style (remember_style avec read = true) et suis ses préférences.",
    classer = "Classe la photo active, sans rien écrire d'abord : regarde-la (view_photo) et lis son classement (get_settings : mots-clés, légende, lieu et position GPS déjà posés), puis propose des mots-clés, en reprenant ceux du catalogue (list_keywords), un lieu seulement s'il est sûr (repris d'un champ de lieu ou d'un mot-clé de lieu déjà posé ; la position GPS seule ne nomme pas le lieu : donne-la et laisse-moi le nommer, jamais deviné) et une légende courte, sans remplacer celle que j'ai déjà écrite. Montre ta proposition et attends mon accord avant set_metadata, même en mode Appliquer.",
    noter = "Note chaque photo sélectionnée selon le standard de notation, même déjà évaluée : cull_photos avec selection = true, view_photo avec af_point = true sur chacune (plus de 30 photos : planche par planche, puce Notes de tes consignes), puis propose_ratings avec apply = true pour poser les notes. Dis chaque note posée et sa raison en une phrase.",
    classerRapide = "Pour toutes les photos sélectionnées dans Lightroom, une à une : Classe chaque photo, sans rien écrire d'abord : regarde-la (view_photo) et lis son classement (get_settings : mots-clés, légende, lieu et position GPS déjà posés), puis propose des mots-clés, en reprenant ceux du catalogue (list_keywords), un lieu seulement s'il est sûr (repris d'un champ de lieu ou d'un mot-clé de lieu déjà posé ; la position GPS seule ne nomme pas le lieu : donne-la et laisse-moi le nommer, jamais deviné) et une légende courte, sans remplacer celle que j'ai déjà écrite. Dans cette Demande rapide, la demande entière est ta proposition, photo par photo (mots-clés, lieu, légende) : n'appelle pas set_metadata, même en mode Appliquer. Finis en disant comment l'écrire : si cette conversation est gardée (la fenêtre Claude la reprend), en répondant dans la fenêtre Claude ; sinon, elle sera perdue : par l'invite Classer de la fenêtre Claude, photo par photo, ou par une nouvelle demande qui nomme ce qu'il faut écrire.",
    proposition = "comme une Retouche pro, mais sans rien appliquer : view_photo (mesures, bilan, intention_boitier) pour le diagnostic ; puis, dans un seul preview_settings, tous les panneaux que la photo demande, pas tout par principe (profil, corrections d'objectif et Upright si utile, balance des blancs, tonalité, présence, TSL, étalonnage, courbe, détail et bruit, vignetage ou radial inversé, jamais les deux) ; les retouches locales utiles (ciel, sujet, peau…) par add_mask avec preview = true ; un recadrage seulement s'il y gagne nettement. Donne chaque changement avec sa raison courte.",
    retouche = "comme une Retouche pro, appliquée dans ce même tour (c'est la demande) : view_photo (mesures, bilan, intention_boitier) pour le diagnostic ; puis, dans un seul apply_settings avec confirm = true, tous les panneaux que la photo demande, pas tout par principe (profil, corrections d'objectif et Upright si utile, balance des blancs, tonalité, présence, TSL, étalonnage, courbe, détail et bruit, vignetage ou radial inversé, jamais les deux) ; les retouches locales utiles (ciel, sujet, peau…) par add_mask avec confirm = true, sans preview ; un recadrage seulement s'il y gagne nettement ; puis view_photo pour vérifier, et une passe corrective seulement si un défaut est constaté.",
    obtenir = "Prépare la proposition de retouche la plus complète possible de la photo active : note-la d'abord si elle n'est pas encore évaluée, puis fais-la comme une Retouche pro, mais sans rien appliquer : view_photo (mesures, bilan, intention_boitier) pour le diagnostic ; puis, dans un seul preview_settings, tous les panneaux que la photo demande, pas tout par principe (profil, corrections d'objectif et Upright si utile, balance des blancs, tonalité, présence, TSL, étalonnage, courbe, détail et bruit, vignetage ou radial inversé, jamais les deux) ; les retouches locales utiles (ciel, sujet, peau…) par add_mask avec preview = true ; un recadrage seulement s'il y gagne nettement. Donne chaque changement avec sa raison courte. J'accepterai, refuserai ou ajusterai dans l'onglet Proposition. Avant tout, lis mon guide de style (remember_style avec read = true) et suis ses préférences.",
}

-- Les traces d'une liste mal recollée.
local function propre(message, quoi)
    for _, motif in ipairs({ ' ,', ', ,', ': ,', ': ;', ': %.', ' ;;', '%(%)', '%( ', ' %)', '  ', ',%.', ';%.', ' %.', 'et puis', ': puis' }) do
        vrai(not message:find(motif), string.format('%s : « %s » dans %q', quoi, motif, message))
    end
end

-- Forme des données -------------------------------------------------------------------------------

essai('Forme : chaque invite a des étapes nommées, à id stable et unique, titre, ce qui est refusé, Oui par défaut ; sa forme ne nomme que ses étapes', function()
    local liste = Consignes.configurables()
    egal(10, #liste, 'les huit invites de la fenêtre, Noter et Proposer et appliquer')
    local ids = {}
    for i, invite in ipairs(Consignes.invites) do
        egal(invite, liste[i], 'les invites de la fenêtre d\'abord, dans leur ordre')
    end
    egal('noter', liste[9].id)
    egal('proposer_appliquer', liste[10].id)
    local plus = 0
    for _, invite in ipairs(liste) do
        vrai(not ids[invite.id], 'invite en double : ' .. invite.id)
        ids[invite.id] = true
        vrai(type(invite.titre) == 'string' and invite.titre ~= '', invite.id .. ' : titre')
        vrai(type(invite.sert) == 'string' and invite.sert ~= '', invite.id .. ' : à quoi elle sert')
        vrai(#invite.etapes >= 3, invite.id .. ' : ses étapes')
        plus = math.max(plus, #invite.etapes)
        local etapes = {}
        for _, e in ipairs(invite.etapes) do
            vrai(type(e.id) == 'string' and e.id:match('^[a-z_]+$'), invite.id .. ' : id ' .. tostring(e.id))
            vrai(not etapes[e.id], invite.id .. ' : étape en double ' .. e.id)
            etapes[e.id] = { e = e, vue = false }
            egal(true, e.defaut, invite.id .. '.' .. e.id .. ' : Oui par défaut')
            vrai(type(e.titre) == 'string' and #e.titre > 3 and #e.titre <= 70, invite.id .. '.' .. e.id .. ' : titre court')
            vrai(type(e.non) == 'string' and e.non ~= '', invite.id .. '.' .. e.id .. ' : ce qui est refusé')
            -- Aucun chiffre (les doses restent dans les descriptions des outils).
            vrai(not e.titre:find('%d') and not e.non:find('%d'), invite.id .. '.' .. e.id .. ' : sans chiffre')
        end
        -- Chaque étape d'une forme est une étape de l'invite ; chaque étape qui a un texte paraît
        -- dans une forme ; une étape sans texte (faite par la méthode du connecteur) dans aucune.
        local formes = invite.formes or { invite.forme }
        for _, forme in pairs(formes) do
            for _, morceau in ipairs(forme) do
                if type(morceau) == 'table' then
                    for _, x in ipairs(morceau) do
                        local id = type(x) == 'table' and x[1] or x
                        vrai(etapes[id], invite.id .. ' : la forme nomme une étape inconnue ' .. tostring(id))
                        etapes[id].vue = true
                    end
                end
            end
        end
        for id, t in pairs(etapes) do
            egal(t.e.texte ~= nil, t.vue, invite.id .. '.' .. id .. ' : dans la forme si et seulement si elle a un texte')
        end
    end
    egal(plus, Consignes.maxEtapes())
    egal(13, Consignes.maxEtapes(), 'Proposer et appliquer, la plus longue')
end)

essai("Tout à Oui : le message de chaque invite est celui de la 1.8, mot pour mot (fenêtre Claude et Demande rapide)", function()
    remettre()
    for _, invite in ipairs(Consignes.invites) do
        egal(AVANT[invite.id], invite.message, invite.id .. ' : message tout à Oui')
        egal(AVANT[invite.id], Consignes.message(invite.id), invite.id .. ' : sans fichier')
        egal(AVANT[invite.id], Consignes.message(invite.id, {}), invite.id .. ' : choix vides')
        local oui = {}
        for _, e in ipairs(invite.etapes) do
            oui[e.id] = true
        end
        egal(AVANT[invite.id], Consignes.message(invite.id, oui), invite.id .. ' : chaque étape à Oui')
    end
    egal(AVANT.noter, Consignes.noterRapide)
    egal(AVANT.noter, Consignes.message('noter'))
    egal(AVANT.classerRapide, Consignes.classerRapide)
    egal(AVANT.classerRapide, Consignes.classerRapideMessage())
    egal(AVANT.proposition, Consignes.PROPOSITION_COMPLETE)
    egal(AVANT.proposition, Consignes.propositionComplete())
    egal(AVANT.retouche, Consignes.RETOUCHE_COMPLETE)
    egal(AVANT.retouche, Consignes.retoucheComplete())
    egal(AVANT.obtenir, Consignes.obtenir.demande)
    egal(AVANT.obtenir, Consignes.demandeObtenir())
    -- Proposer et appliquer, dans les deux modes : comme la 1.8 les faisait.
    contient(Consignes.proposerAppliquerRapide('appliquer', false), AVANT.retouche, 'mode Appliquer')
    contient(Consignes.proposerAppliquerRapide('proposer', true), AVANT.proposition, 'Proposer d\'abord')
    vrai(not Consignes.proposerAppliquerRapide('appliquer', false):find(Consignes.NE_PAS_FAIRE, 1, true), 'rien à ne pas faire')
end)

-- Étapes à Non --------------------------------------------------------------------------------------

essai('Une étape à Non : son texte retiré, et dite à Claude (« Ne fais pas ceci… »), avant la phrase du guide ; liste toujours bien recollée', function()
    -- Le flou d'objectif du portrait.
    local m = Consignes.message('portrait', { flou = false })
    egal("Retouche ce portrait : peau, yeux, dents, arrière-plan ; " .. Consignes.invite('portrait').etapes[6].texte .. ". Reste naturel. "
        .. Consignes.NE_PAS_FAIRE .. "ajouter du flou d'objectif (lens_blur). " .. Consignes.LIRE_GUIDE, m)
    -- Une étape faite par la méthode du connecteur (le recadrage de la Retouche pro), sans mot dans
    -- le message à Oui : à Non, elle est dite.
    egal("Retouche la photo active comme un professionnel : diagnostic chiffré, deux passes vérifiées, puis au plus deux passes correctives si un défaut reste. "
        .. Consignes.NE_PAS_FAIRE .. "recadrer. " .. Consignes.LIRE_GUIDE, Consignes.message('retouche_pro', { recadrer = false }))
    -- La poussière du capteur (10 novembre 2026) : une étape de la Retouche pro, faite par la méthode
    -- du connecteur (remove_distractions avec dust) ; à Non, dite. Les imperfections du portrait, à
    -- Non, refusent aussi remove_distractions avec imperfections.
    egal("Retouche la photo active comme un professionnel : diagnostic chiffré, deux passes vérifiées, puis au plus deux passes correctives si un défaut reste. "
        .. Consignes.NE_PAS_FAIRE .. "retirer la poussière du capteur (remove_distractions avec dust). " .. Consignes.LIRE_GUIDE,
        Consignes.message('retouche_pro', { poussiere = false }))
    contient(Consignes.message('portrait', { imperfections = false }),
        "retirer des imperfections (ni remove_distractions avec imperfections, ni retouch_spots)")
    -- Le grain du noir et blanc : la liste se finit sans lui, sans « et puis » (le tireur porte déjà
    -- son « puis »).
    egal("Passe la photo active en noir et blanc : profil, mélangeur, contraste local, puis éclaircis et assombris comme un tireur (doses d'add_mask) avec l'avant/après de cette étape. "
        .. Consignes.NE_PAS_FAIRE .. "ajouter du grain. " .. Consignes.LIRE_GUIDE, Consignes.message('noir_et_blanc', { grain = false }))
    -- Le tireur seul (toutes les autres étapes à Non) : il ouvre la liste, sans « puis ».
    contient(Consignes.message('portrait', { peau = false, yeux = false, dents = false, arriere_plan = false, flou = false }),
        "Retouche ce portrait : éclaircis et assombris comme un tireur pour mener l'œil au visage")
    contient(Consignes.message('paysage', { horizon = false, ciel = false, profondeur = false, masques = false }),
        "Retouche ce paysage : éclaircis et assombris")
    contient(Consignes.message('noir_et_blanc', { profil = false, melangeur = false, contraste_local = false, grain = false }),
        "Passe la photo active en noir et blanc : éclaircis et assombris")
    contient(Consignes.message('retouche_pro', { diagnostic = false, deux_passes = false }),
        "comme un professionnel : au plus deux passes correctives")
    -- Le style choisi (menu Style) est nommé : sa recette ne l'emporte pas sur une étape à Non
    -- (« Or et peau douce » adoucit la peau, Portrait › peau à Non).
    contient(Consignes.NE_PAS_FAIRE, "le style choisi", 'le style choisi ne passe pas outre')
    contient(Consignes.message('portrait', { peau = false }), "mon guide de style ou le style choisi le prévoit : toucher à la peau")
    -- Deux étapes à Non : dites dans l'ordre des étapes.
    contient(Consignes.message('iso_eleve', { nettete = false, bruit = false }),
        "Retouche cette photo prise à ISO élevé : les ombres et les couleurs, sans lisser les détails. " .. Consignes.NE_PAS_FAIRE .. "débruiter (enhance_photo) ; toucher à la netteté.")
    -- Chaque étape de chaque invite, seule à Non, puis toutes à Non.
    for _, invite in ipairs(Consignes.configurables()) do
        local tout = {}
        for _, e in ipairs(invite.etapes) do
            tout[e.id] = false
            local choix = { [e.id] = false }
            local message = Consignes.message(invite.id, choix)
            vrai(message ~= Consignes.message(invite.id, {}), invite.id .. '.' .. e.id .. ' : le message change')
            contient(message, Consignes.NE_PAS_FAIRE .. e.non .. ".", invite.id .. '.' .. e.id)
            propre(message, invite.id .. '.' .. e.id)
            if invite.retouche then
                egal(#message - #Consignes.LIRE_GUIDE + 1, message:find(Consignes.LIRE_GUIDE, 1, true), invite.id .. ' : le guide en dernier')
            end
            egal(invite.titre == 'Classer' and 1 or 0, select(2, message:gsub('set_metadata', '')) > 0 and 1 or 0, 'l\'accord de Classer gardé')
        end
        local message = Consignes.message(invite.id, tout)
        propre(message, invite.id .. ' : tout à Non')
        local _, n = message:gsub(' ; ', ' ; ')
        vrai(n >= #invite.etapes - 1, invite.id .. ' : toutes les étapes dites')
    end
    -- Les deux formes de Proposer et appliquer, et Obtenir qui la reprend.
    local choix = { recadrage = false, vignetage = false }
    for _, m in ipairs({ Consignes.propositionComplete(choix), Consignes.retoucheComplete(choix), Consignes.demandeObtenir(choix),
        Consignes.proposerAppliquerRapide('appliquer', false, choix), Consignes.proposerAppliquerRapide('proposer', true, choix) }) do
        vrai(not m:find("un recadrage seulement", 1, true), 'recadrage retiré')
        vrai(not m:find("vignetage ou radial", 1, true), 'vignetage retiré')
        contient(m, Consignes.NE_PAS_FAIRE .. "assombrir les bords (ni vignetage ni radial inversé) ; recadrer.")
        propre(m, 'proposer et appliquer')
    end
    -- La Retouche pro sur la sélection (Demande rapide) garde ce qui est refusé, le guide en tête.
    local selection = Consignes.retoucheProSurLaSelection(Consignes.message('retouche_pro', { debruitage = false }))
    contient(selection, Consignes.NE_PAS_FAIRE .. "débruiter (enhance_photo).")
    egal(1, selection:find(Consignes.LIRE_GUIDE, 1, true), 'le guide en tête')
end)

essai("Le résumé dit à quoi sert l'invite, ce qu'elle fera et ce qu'elle ne fera pas", function()
    local r = Consignes.resume('portrait', { flou = false })
    contient(r, 'Sert à : le bouton Portrait de la fenêtre Claude et celui de la Demande rapide.')
    contient(r, "Fera : Peau")
    contient(r, "Ne fera pas : Flou d'objectif, si la photo s'y prête.")
    contient(r, 'guide de style')
    vrai(not Consignes.resume('portrait', {}):find('Ne fera pas', 1, true), 'tout à Oui : rien à ne pas faire')
    vrai(not Consignes.resume('composition', {}):find('guide de style', 1, true), 'Composition ne lit pas le guide')
    -- Proposer et appliquer fait lire le guide (Obtenir et les deux messages de la Demande rapide) :
    -- son résumé le dit.
    for _, m in ipairs({ Consignes.demandeObtenir({}), Consignes.proposerAppliquerRapide('appliquer', false, {}),
        Consignes.proposerAppliquerRapide('proposer', true, {}) }) do
        contient(m, Consignes.LIRE_GUIDE, 'Proposer et appliquer lit le guide')
    end
    contient(Consignes.resume('proposer_appliquer', {}), "Lit d'abord votre guide de style.", 'le résumé de Proposer et appliquer')
    -- Et chaque invite dont un message lit le guide le dit, les autres non.
    for _, invite in ipairs(Consignes.configurables()) do
        local lit = false
        for _, v in ipairs(Consignes.variantes(invite.id, {})) do
            lit = lit or v.message:find(Consignes.LIRE_GUIDE, 1, true) ~= nil
        end
        egal(lit, Consignes.resume(invite.id, {}):find('guide de style', 1, true) ~= nil, invite.id .. ' : le guide dit au résumé')
    end
end)

-- Fichier invites.json --------------------------------------------------------------------------------

essai('Fichier : absent ou illisible, tout à Oui sans erreur ; une valeur qui n\'est pas un booléen, une étape ou une invite inconnue, ignorées', function()
    remettre()
    local function toutOui(quoi)
        for _, invite in ipairs(Consignes.configurables()) do
            for id, v in pairs(Consignes.choix(invite.id)) do
                egal(true, v, quoi .. ' : ' .. invite.id .. '.' .. id)
            end
            egal(Consignes.message(invite.id, {}), Consignes.message(invite.id), quoi .. ' : ' .. invite.id)
        end
    end
    toutOui('absent')
    -- Un format inconnu (un module plus récent) n'est pas lu comme le format 1.
    for _, texte in ipairs({ '{"format":1,"invites":{"portrait":', 'pas du JSON', '[]', '{"format":1}', '{"format":1,"invites":"non"}', '',
        '{"format":2,"invites":{"portrait":{"flou":false}}}', '{"invites":{"portrait":{"flou":false}}}' }) do
        Fichiers.ecrire(fichier, texte)
        toutOui('illisible ' .. texte)
        egal(texte, Fichiers.lire(fichier), 'le fichier n\'est pas réécrit à la lecture')
    end
    Fichiers.ecrire(fichier, '{"format":1,"invites":{"portrait":{"flou":"non","peau":0,"inconnue":false},"inconnue":{"x":false}}}')
    toutOui('valeurs ignorées')
    remettre()
end)

essai("Aller-retour : un choix gardé dans invites.json (racine des données), relu à chaque lancement ; « comme à l'origine » le retire", function()
    remettre()
    vrai(Chemins.estDonnee('invites.json'), 'une donnée du dossier commun (elle suit l\'autre Mac)')
    egal(true, Consignes.poserChoix('portrait', { flou = false, peau = true }))
    vrai(Fichiers.existe(fichier), 'invites.json écrit')
    local lu = Json.decode(Fichiers.lire(fichier))
    egal(1, lu.format)
    egal(false, lu.invites.portrait.flou)
    egal(true, lu.invites.portrait.peau)
    egal(true, lu.invites.portrait.tireur, 'chaque étape écrite')
    egal(nil, lu.invites.paysage, 'une invite non réglée n\'y est pas')
    egal(false, Consignes.choix('portrait').flou)
    egal(true, Consignes.choix('portrait').yeux)
    egal(Consignes.message('portrait', { flou = false }), Consignes.message('portrait'), 'relu au lancement')
    -- Une autre invite à côté : la première reste.
    egal(true, Consignes.poserChoix('classer', { lieu = false }))
    egal(false, Consignes.choix('portrait').flou)
    egal(false, Consignes.choix('classer').lieu)
    -- Rien à Non : l'invite redevient « comme à l'origine », retirée du fichier.
    egal(true, Consignes.poserChoix('classer', { lieu = true }))
    egal(nil, Json.decode(Fichiers.lire(fichier)).invites.classer)
    egal(true, Consignes.poserChoix('portrait', nil))
    egal(Consignes.message('portrait', {}), Consignes.message('portrait'))
    egal(nil, Json.decode(Fichiers.lire(fichier)).invites.portrait)
    -- Une invite inconnue est une erreur de programme, pas un choix.
    vrai(not pcall(Consignes.poserChoix, 'inconnue', {}), 'invite inconnue refusée')
    remettre()
end)

essai('Dossier commun introuvable : tout à Oui à la lecture, sans erreur ; le choix n\'est pas gardé, et la raison est dite', function()
    remettre()
    local absent = S.home .. '/Volumes/Photos débranché/Développeur IA'
    Fichiers.ecrire(Chemins.pointeur(), Json.encode({ format = 1, dossier = absent }))
    local ok, refus = Consignes.poserChoix('portrait', { flou = false })
    egal(false, ok)
    contient(refus, 'introuvable', 'la raison')
    egal(true, Consignes.choix('portrait').flou, 'tout à Oui')
    egal(Consignes.invite('portrait').message, Consignes.message('portrait'))
    vrai(not Fichiers.existe(absent), 'rien créé là où le SSD n\'est pas')
    vrai(not Fichiers.existe(fichier), 'aucun repli sur la racine locale')
    Fichiers.supprimer(Chemins.pointeur())
end)

-- Les entrées du journal pendant `fn` (Journal.noter, que Consignes appelle à chaque fois).
local function journal(fn)
    local Journal = require 'Journal'
    local avant, lignes = Journal.noter, {}
    Journal.noter = function(...)
        local morceaux = {}
        for i = 1, select('#', ...) do
            morceaux[#morceaux + 1] = tostring((select(i, ...)))
        end
        lignes[#lignes + 1] = table.concat(morceaux, ' ')
    end
    local ok, erreur = pcall(fn)
    Journal.noter = avant
    assert(ok, erreur)
    return lignes
end

-- Les copies mises de côté (invites-illisible-*.json), avec leur contenu.
local function misesDeCote()
    local liste = {}
    for _, nom in ipairs(Fichiers.entrees(Chemins.donnees())) do
        local chemin = Chemins.donnee(nom)
        if nom:find('^invites%-illisible%-') then
            liste[#liste + 1] = { nom = nom, contenu = Fichiers.lire(chemin), chemin = chemin }
        end
    end
    return liste
end

local function retirerMisesDeCote()
    for _, m in ipairs(misesDeCote()) do
        Fichiers.supprimer(m.chemin)
    end
end

essai("Fichier illisible ou d'un format inconnu : mis de côté (invites-illisible-<date>.json, dans les données) avant la première écriture, jamais écrasé ; rien d'effacé", function()
    remettre()
    retirerMisesDeCote()
    vrai(Chemins.estDonnee('invites-illisible-1700000000.json'), 'la copie suit le dossier commun, comme celles du carnet et du Suivi')
    -- Coupé (copie du SSD interrompue) : le premier Oui ou Non le met de côté, puis écrit le choix.
    local coupe = '{"format":1,"invites":{"portrait":{"flou":false},"classer":{"lie'
    Fichiers.ecrire(fichier, coupe)
    egal(true, Consignes.poserChoix('paysage', { ciel = false }))
    local copies = misesDeCote()
    egal(1, #copies, 'une copie mise de côté')
    egal(coupe, copies[1].contenu, 'son contenu gardé tel quel')
    egal(false, Consignes.choix('paysage').ciel, 'le nouveau choix écrit')
    egal(1, Json.decode(Fichiers.lire(fichier)).format)
    -- Un format inconnu (un module plus récent) : ni lu comme le format 1, ni écrasé.
    local futur = '{"format":2,"invites":{"portrait":{"flou":false}},"autre":true}'
    Fichiers.ecrire(fichier, futur)
    egal(true, Consignes.choix('portrait').flou, 'format inconnu : tout à Oui')
    egal(true, Consignes.choix('paysage').ciel, 'format inconnu : rien n\'en est lu')
    egal(true, Consignes.poserChoix('classer', { lieu = false }))
    copies = misesDeCote()
    egal(2, #copies, 'une deuxième copie, sous un autre nom')
    vrai(copies[1].nom ~= copies[2].nom, 'jamais le nom d\'une copie qui existe')
    vrai(copies[1].contenu == futur or copies[2].contenu == futur, 'le format inconnu gardé tel quel')
    egal(false, Consignes.choix('classer').lieu)
    -- Lisible : rien de plus n'est mis de côté.
    egal(true, Consignes.poserChoix('classer', { lieu = true }))
    egal(2, #misesDeCote(), 'un fichier lisible n\'est pas mis de côté')
    -- Vide : rien à garder, il est remplacé.
    Fichiers.ecrire(fichier, '')
    egal(true, Consignes.poserChoix('portrait', { dents = false }))
    egal(2, #misesDeCote(), 'un fichier vide n\'a rien à garder')
    egal(false, Consignes.choix('portrait').dents)
    -- Qui ne se laisse pas mettre de côté : rien n'est écrit, il reste tel quel, et la raison est dite.
    Fichiers.ecrire(fichier, coupe)
    local renommer, deplacer = os.rename, S.modules.LrFileUtils.move
    os.rename = function() return nil end
    S.modules.LrFileUtils.move = function() return false end
    local ok, pose, pourquoi = pcall(Consignes.poserChoix, 'portrait', { flou = false })
    os.rename, S.modules.LrFileUtils.move = renommer, deplacer
    vrai(ok, 'sans erreur : ' .. tostring(pose))
    egal(false, pose, 'non gardé')
    contient(pourquoi, 'illisible', 'la raison')
    egal(coupe, Fichiers.lire(fichier), 'laissé tel quel')
    egal(2, #misesDeCote(), 'rien de mis de côté')
    remettre()
    retirerMisesDeCote()
end)

essai("Journal : chaque cause dite une fois (la fenêtre lit le réglage à chaque infobulle et à chaque clic) ; le dossier commun introuvable est dit comme tel", function()
    remettre()
    Consignes.lireReglages() -- absent : les causes déjà dites sont oubliées
    Fichiers.ecrire(fichier, 'pas du JSON')
    local lignes = journal(function()
        for _ = 1, 7 do
            Consignes.lireReglages()
            Consignes.message('portrait')
        end
    end)
    egal(1, #lignes, 'une seule entrée pour sept lectures : ' .. table.concat(lignes, ' | '))
    contient(lignes[1], 'illisible')
    -- Une autre cause : dite à son tour, une fois.
    Fichiers.ecrire(fichier, '{"format":9,"invites":{}}')
    lignes = journal(function()
        for _ = 1, 3 do
            Consignes.lireReglages()
        end
    end)
    egal(1, #lignes)
    contient(lignes[1], 'format inconnu')
    -- Lu de nouveau : la même panne, plus tard, est dite de nouveau.
    remettre()
    Consignes.lireReglages()
    Fichiers.ecrire(fichier, 'pas du JSON')
    egal(1, #journal(function() Consignes.lireReglages() end), 'dite de nouveau après une lecture réussie')
    remettre()
    -- Le dossier commun introuvable : ni « illisible », ni plusieurs fois.
    local absent = S.home .. '/Volumes/Photos débranché/Développeur IA'
    Fichiers.ecrire(Chemins.pointeur(), Json.encode({ format = 1, dossier = absent }))
    lignes = journal(function()
        for _ = 1, 5 do
            Consignes.lireReglages()
            Consignes.message('classer')
        end
    end)
    Fichiers.supprimer(Chemins.pointeur())
    egal(1, #lignes, 'une fois : ' .. table.concat(lignes, ' | '))
    contient(lignes[1], 'dossier commun introuvable')
    vrai(not lignes[1]:find('illisible', 1, true), 'pas « illisible »')
    remettre()
end)

-- Une seule configuration pour la fenêtre Claude et la Demande rapide ------------------------------

essai("La même configuration pour la fenêtre Claude et la Demande rapide : Retouche pro, Portrait, Classer, Noter, Proposer et appliquer, relus au clic", function()
    remettre()
    local FenetreRapide = require 'FenetreRapide'
    local A = FenetreRapide.ACTIONS
    for i = 1, 4 do
        egal('function', type(A[i].message), 'bouton ' .. i .. ' : fait au clic')
    end
    egal(AVANT.noter, A[1].message())
    egal(Consignes.retoucheProSurLaSelection(AVANT.retouche_pro), A[2].message())
    egal(Consignes.surLaSelection(AVANT.portrait), A[3].message())
    egal(AVANT.classerRapide, A[4].message())
    Consignes.poserChoix('retouche_pro', { recadrer = false })
    Consignes.poserChoix('portrait', { dents = false })
    Consignes.poserChoix('classer', { lieu = false })
    Consignes.poserChoix('noter', { deja = false })
    Consignes.poserChoix('proposer_appliquer', { tsl = false })
    contient(A[2].message(), Consignes.NE_PAS_FAIRE .. 'recadrer.')
    egal(Consignes.retoucheProSurLaSelection(Consignes.message('retouche_pro')), A[2].message())
    egal(Consignes.surLaSelection(Consignes.message('portrait')), A[3].message())
    contient(A[3].message(), 'blanchir les dents')
    local classer = A[4].message()
    contient(classer, Consignes.NE_PAS_FAIRE .. 'proposer un lieu.')
    vrai(not classer:find("un lieu seulement s'il est sûr", 1, true), 'le lieu retiré dans la Demande rapide')
    vrai(not Consignes.message('classer'):find("un lieu seulement s'il est sûr", 1, true), 'et dans la fenêtre Claude')
    contient(Consignes.message('classer'), 'attends mon accord', 'la fin de Classer gardée')
    vrai(not A[1].message():find('même déjà évaluée', 1, true), 'Noter')
    contient(A[1].message(), "changer la note d'une photo déjà évaluée")
    vrai(not Consignes.demandeObtenir():find(', TSL,', 1, true), 'Obtenir suit Proposer et appliquer')
    vrai(not Consignes.proposerAppliquerRapide('appliquer', false):find(', TSL,', 1, true), 'Proposer et appliquer, mode Appliquer')
    vrai(not Consignes.proposerAppliquerRapide('proposer', true):find(', TSL,', 1, true), "Proposer et appliquer, « Proposer d'abord »")
    -- Les infobulles des cinq boutons, faites à l'ouverture de la fenêtre (FenetreRapide.infobulle),
    -- montrent le réglage : le message de Retouche pro et de Portrait, ce que les autres ne feront pas.
    contient(FenetreRapide.infobulle(A[2]), Consignes.message('retouche_pro'), 'infobulle de Retouche pro')
    contient(FenetreRapide.infobulle(A[2]), Consignes.NE_PAS_FAIRE .. 'recadrer.')
    contient(FenetreRapide.infobulle(A[3]), Consignes.message('portrait'), 'infobulle de Portrait')
    contient(FenetreRapide.infobulle(A[3]), 'blanchir les dents')
    contient(FenetreRapide.infobulle(A[1]), 'ne fera pas : Noter aussi les photos déjà évaluées.', 'infobulle de Noter')
    contient(FenetreRapide.infobulle(A[4]), "ne fera pas : Lieu, seulement s'il est sûr (jamais deviné).", 'infobulle de Classer')
    contient(FenetreRapide.infobulle(A[5]), 'ne fera pas : Mélangeur TSL.', 'infobulle de Proposer et appliquer')
    remettre()
    egal(AVANT.classerRapide, A[4].message(), 'fichier retiré : de nouveau comme à l\'origine')
    -- Sans réglage : les infobulles d'origine, sans rien de plus.
    contient(FenetreRapide.infobulle(A[2]), AVANT.retouche_pro)
    contient(FenetreRapide.infobulle(A[3]), AVANT.portrait)
    for i = 1, 5 do
        vrai(not FenetreRapide.infobulle(A[i]):find('ne fera pas', 1, true), 'bouton ' .. i .. ' : rien à ne pas faire')
    end
end)

-- Section Invites du Gestionnaire de modules externes ------------------------------------------------

local function sectionInvites()
    local f = S.modules.LrView.osFactory()
    local proprietes = S.modules.LrBinding.makePropertyTable()
    local sections = require('PluginInfoProvider').sectionsForTopOfDialog(f, proprietes)
    local section = sections[#sections]
    egal('Invites', section.title)
    return section, proprietes, f
end

local function parGenre(racine, genre)
    local liste = {}
    for _, v in ipairs(S.vues(racine)) do
        if v.genre == genre then
            liste[#liste + 1] = v
        end
    end
    return liste
end

-- La section dans une fenêtre ouverte (pour cliquer et choisir comme Dany), puis fermée.
local function ouvrir(fn)
    local section, p, f = sectionInvites()
    local vuesSection = {}
    for i, v in ipairs(section) do
        vuesSection[i] = v
    end
    local contenu = f:column(vuesSection)
    S.pendantFenetre = function() fn(p, contenu, section) end
    S.modules.LrDialogs.presentFloatingDialog(_PLUGIN, { title = 'Gestionnaire de modules externes', contents = contenu })
    S.pendantFenetre = nil
end

essai("Gestionnaire, section Invites (la dernière) : menu des invites, un nombre fixe de lignes Oui / Non liées (titre, valeur, visible), le résumé, Remettre, le message", function()
    remettre()
    local section, p = sectionInvites()
    egal(5, select('#', unpack(require('PluginInfoProvider').sectionsForTopOfDialog(S.modules.LrView.osFactory(), S.modules.LrBinding.makePropertyTable()))))
    egal("toutes comme à l'origine", S.evaluer(section.synopsis, p), 'synopsis')
    local menus = {}
    for _, v in ipairs(section) do
        for _, x in ipairs(parGenre(v, 'popup_menu')) do
            menus[#menus + 1] = x
        end
        -- Chaque liaison a sa valeur avant l'ouverture (Lightroom l'exige).
        for _, x in ipairs(S.vues(v)) do
            for cle, valeur in pairs(x.args) do
                if type(cle) == 'string' and type(valeur) == 'table' and valeur.liaison then
                    S.verifierLiaison(valeur, p, x.genre .. '.' .. cle)
                end
            end
        end
    end
    egal(1, #menus, 'un menu')
    local items = menus[1].args.items
    S.neuve(items, 'éléments du menu des invites')
    egal(10, #items)
    for i, invite in ipairs(Consignes.configurables()) do
        egal(invite.titre, items[i].title)
        egal(invite.id, items[i].value)
    end
    egal('retouche_pro', p.inviteChoisie, 'la Retouche pro d\'abord')
    -- Les lignes : autant que d'étapes dans la plus longue invite, chacune Oui, Non et son titre.
    local lignes = 0
    for _, v in ipairs(section) do
        local radios = parGenre(v, 'radio_button')
        if #radios > 0 then
            lignes = lignes + 1
            egal(2, #radios, 'Oui et Non')
            egal('Oui', radios[1].args.title)
            egal(true, radios[1].args.checked_value)
            egal('Non', radios[2].args.title)
            egal(false, radios[2].args.checked_value)
            egal(radios[1].args.value.key, radios[2].args.value.key, 'la même valeur')
            egal('etapeOui' .. lignes, radios[1].args.value.key)
            -- visible sur les vues simples, jamais sur la rangée (Lightroom l'ignorerait).
            egal(nil, v.args.visible, 'pas de visible sur la rangée')
            egal('etapeVisible' .. lignes, radios[1].args.visible.key)
        end
    end
    egal(Consignes.maxEtapes(), lignes, 'un nombre fixe de lignes')
    local invite = Consignes.configurable('retouche_pro')
    for i = 1, lignes do
        egal(invite.etapes[i] ~= nil, p['etapeVisible' .. i], 'ligne ' .. i .. ' visible')
        egal(invite.etapes[i] and invite.etapes[i].titre or '', p['etapeTitre' .. i])
        egal(true, p['etapeOui' .. i])
    end
    contient(p.resumeInvite, 'Sert à : le bouton Retouche pro')
    egal(nil, Fichiers.existe(fichier) or nil, 'rien d\'écrit à l\'ouverture')
end)

-- Chaque combinaison de Oui et de Non d'une invite (2^n), donnée à `fn(choix)`.
local function combinaisons(invite, fn)
    local n = #invite.etapes
    for m = 0, 2 ^ n - 1 do
        local choix = {}
        for i, e in ipairs(invite.etapes) do
            if math.floor(m / 2 ^ (i - 1)) % 2 == 1 then
                choix[e.id] = false
            end
        end
        fn(choix)
    end
end

essai("Gestionnaire, section Invites : chaque texte tient dans sa place (largeur en caractères × lignes) : l'introduction, chaque titre d'étape sur sa ligne, le résumé de chaque invite, tout à Oui comme avec la pire combinaison de Non", function()
    remettre()
    local Texte = require 'Texte'
    local section, p = sectionInvites()
    local titres, resume, fixes = {}, nil, {}
    for _, v in ipairs(section) do
        for _, x in ipairs(parGenre(v, 'static_text')) do
            local t = x.args.title
            if type(t) == 'table' and t.liaison and t.key:find('^etapeTitre') then
                titres[#titres + 1] = x
            elseif type(t) == 'table' and t.liaison and t.key == 'resumeInvite' then
                resume = x
            elseif type(t) == 'string' and x.args.height_in_lines then
                fixes[#fixes + 1] = x
            end
        end
    end
    egal(Consignes.maxEtapes(), #titres, 'un titre par ligne')
    vrai(resume, 'le résumé')
    vrai(#fixes >= 1, "l'introduction")
    -- Les textes fixes (l'introduction) : leurs lignes suffisent.
    for _, x in ipairs(fixes) do
        local largeur, lignes = x.args.width_in_chars, x.args.height_in_lines
        vrai(largeur, 'largeur de ' .. x.args.title)
        vrai(Texte.nombreDeLignes(x.args.title, largeur) <= lignes,
            string.format('%d lignes à %d caractères pour %q, %d prévues', Texte.nombreDeLignes(x.args.title, largeur), largeur, x.args.title, lignes))
    end
    -- Chaque titre de chaque invite, sur la ligne d'un titre.
    local largeur, lignes = titres[1].args.width_in_chars, titres[1].args.height_in_lines or 1
    for _, x in ipairs(titres) do
        egal(largeur, x.args.width_in_chars, 'la même largeur pour chaque ligne')
    end
    for _, invite in ipairs(Consignes.configurables()) do
        for _, e in ipairs(invite.etapes) do
            vrai(Texte.nombreDeLignes(e.titre, largeur) <= lignes and Texte.longueur(e.titre) <= largeur,
                string.format('%s.%s : %q fait %d caractères, %d de place', invite.id, e.id, e.titre, Texte.longueur(e.titre), largeur))
        end
    end
    -- Le résumé : chaque invite, chaque combinaison ; la hauteur est celle du plus long, ni moins
    -- (coupé), ni plus (des lignes vides pour rien).
    largeur, lignes = resume.args.width_in_chars, resume.args.height_in_lines
    vrai(largeur and lignes, 'le résumé a sa largeur et ses lignes')
    local plus, pire = 0, nil
    for _, invite in ipairs(Consignes.configurables()) do
        combinaisons(invite, function(choix)
            local texte = Consignes.resume(invite.id, choix)
            local n = Texte.nombreDeLignes(texte, largeur)
            if n > plus then
                plus, pire = n, texte
            end
        end)
        egal(true, Texte.nombreDeLignes(Consignes.resume(invite.id, {}), largeur) <= lignes, invite.id .. ' : tout à Oui')
    end
    vrai(plus <= lignes, string.format('le plus long résumé fait %d lignes à %d caractères, %d prévues :\n%s', plus, largeur, lignes, tostring(pire)))
    egal(plus, lignes, 'la hauteur du résumé : celle du plus long (Consignes.LIGNES_RESUME)')
    -- La ligne « Ne fera pas », la plus utile, est dans le plus long.
    contient(pire, 'Ne fera pas', 'le plus long a des étapes à Non')
end)

essai("Gestionnaire, « Voir le message à Claude » : chaque message que l'invite envoie, un par bouton, tel qu'il part (Retouche pro par groupes de lumière, Classer qui propose seulement, les trois de Proposer et appliquer)", function()
    remettre()
    local FenetreRapide = require 'FenetreRapide'
    local A = FenetreRapide.ACTIONS
    egal(true, Consignes.poserChoix('proposer_appliquer', { tsl = false }))
    egal(true, Consignes.poserChoix('retouche_pro', { recadrer = false }))
    local attendus = {
        retouche_pro = { Consignes.message('retouche_pro'), A[2].message() },
        portrait = { Consignes.message('portrait'), A[3].message() },
        classer = { Consignes.message('classer'), A[4].message() },
        noter = { A[1].message() },
        proposer_appliquer = { Consignes.demandeObtenir(), Consignes.proposerAppliquerRapide('appliquer', false),
            (Consignes.proposerAppliquerRapide('proposer', true)) },
    }
    ouvrir(function(p, contenu)
        local menu = parGenre(contenu, 'popup_menu')[1]
        for _, invite in ipairs(Consignes.configurables()) do
            S.choisir(menu, invite.id)
            local dialogues = #S.dialogues
            S.cliquer(S.trouverBouton(contenu, 'Voir le message à Claude'))
            egal(dialogues + 1, #S.dialogues, invite.id .. ' : une fenêtre')
            local d = S.dialogues[#S.dialogues].contents
            local champs = parGenre(d, 'edit_field')
            local attendu = attendus[invite.id] or { Consignes.message(invite.id) }
            egal(#attendu, #champs, invite.id .. ' : un message par bouton')
            for i, m in ipairs(attendu) do
                egal(m, champs[i].args.value, invite.id .. ' : message ' .. i)
            end
            local variantes = Consignes.variantes(invite.id)
            egal(#attendu, #variantes)
            for _, x in ipairs(parGenre(d, 'static_text')) do
                vrai(not x.args.title:find("l'adresse à chaque photo", 1, true), invite.id .. ' : plus de phrase fausse')
            end
            -- Chaque message est nommé par son bouton.
            local textes = {}
            for _, x in ipairs(parGenre(d, 'static_text')) do
                textes[#textes + 1] = x.args.title
            end
            for _, v in ipairs(variantes) do
                contient(table.concat(textes, '\n'), v.titre, invite.id)
            end
        end
    end)
    contient(attendus.retouche_pro[2], 'par groupes de lumière', 'Retouche pro de la Demande rapide')
    contient(attendus.classer[2], "n'appelle pas set_metadata", 'Classer de la Demande rapide propose seulement')
    for _, m in ipairs(attendus.proposer_appliquer) do
        contient(m, Consignes.NE_PAS_FAIRE .. 'toucher au mélangeur TSL.', 'le réglage dans chaque message')
    end
    remettre()
end)

essai("Gestionnaire, section Invites : choisir Portrait, mettre une étape à Non (gardé tout de suite), changer d'invite et revenir, Remettre comme à l'origine, voir le message", function()
    remettre()
    ouvrir(function(p, contenu)
        local menu = parGenre(contenu, 'popup_menu')[1]
        S.choisir(menu, 'portrait')
        local portrait = Consignes.configurable('portrait')
        local radios = parGenre(contenu, 'radio_button')
        for i = 1, Consignes.maxEtapes() do
            local montree = S.montreeDansFenetre(radios[2 * i])
            egal(portrait.etapes[i] ~= nil, montree, 'ligne ' .. i .. ' montrée seulement si Portrait a une étape')
            egal(portrait.etapes[i] and portrait.etapes[i].titre or '', p['etapeTitre' .. i])
        end
        -- Une ligne masquée ne prend pas de clic.
        vrai(not pcall(S.cliquer, radios[2 * Consignes.maxEtapes()]), 'ligne masquée')
        -- Le flou d'objectif (5ᵉ étape) à Non : gardé, le résumé et le synopsis suivent.
        egal('flou', portrait.etapes[5].id)
        S.cliquer(radios[10])
        egal(false, p.etapeOui5)
        egal(false, Consignes.choix('portrait').flou, 'gardé dans invites.json')
        contient(Consignes.message('portrait'), Consignes.NE_PAS_FAIRE .. "ajouter du flou d'objectif (lens_blur).")
        contient(p.resumeInvite, "Ne fera pas : Flou d'objectif, si la photo s'y prête.")
        egal('1 invite réglée', p.synopsisInvites)
        -- Une autre invite : ses étapes, toutes à Oui ; rien n'est écrit en changeant d'invite.
        local avant = Fichiers.lire(fichier)
        S.choisir(menu, 'paysage')
        egal(Consignes.configurable('paysage').etapes[1].titre, p.etapeTitre1)
        for i = 1, #Consignes.configurable('paysage').etapes do
            egal(true, p['etapeOui' .. i], 'Paysage, ligne ' .. i)
        end
        egal(avant, Fichiers.lire(fichier), 'rien d\'écrit au changement d\'invite')
        -- Retour à Portrait : son Non relu.
        S.choisir(menu, 'portrait')
        egal(false, p.etapeOui5)
        egal(true, p.etapeOui4)
        -- Le message tel qu'il part, dans une fenêtre que l'on peut copier.
        local dialogues = #S.dialogues
        S.cliquer(S.trouverBouton(contenu, 'Voir le message à Claude'))
        egal(dialogues + 1, #S.dialogues)
        local champ = parGenre(S.dialogues[#S.dialogues].contents, 'edit_field')[1]
        egal(Consignes.message('portrait'), champ.args.value)
        -- Remettre comme à l'origine : tout à Oui, l'invite retirée du fichier.
        S.cliquer(S.trouverBouton(contenu, "Remettre comme à l'origine"))
        egal(true, p.etapeOui5)
        egal(true, Consignes.choix('portrait').flou)
        egal(nil, Json.decode(Fichiers.lire(fichier)).invites.portrait)
        egal("toutes comme à l'origine", p.synopsisInvites)
        vrai(not p.resumeInvite:find('Ne fera pas', 1, true))
        -- Oui de nouveau après un Non : comme à l'origine.
        S.cliquer(radios[2 * 3])
        egal(false, Consignes.choix('portrait').dents)
        S.cliquer(radios[2 * 3 - 1])
        egal(true, Consignes.choix('portrait').dents)
        egal(Consignes.message('portrait', {}), Consignes.message('portrait'))
    end)
    remettre()
end)

essai("Gestionnaire, section Invites : le dossier commun introuvable, le choix n'est pas gardé et la raison est dite", function()
    remettre()
    local absent = S.home .. '/Volumes/Photos débranché/Développeur IA'
    ouvrir(function(p, contenu)
        Fichiers.ecrire(Chemins.pointeur(), Json.encode({ format = 1, dossier = absent }))
        local messages = #S.messages
        S.cliquer(parGenre(contenu, 'radio_button')[2])
        egal(messages + 1, #S.messages, 'un message')
        contient(S.messages[#S.messages][2], 'Réglage non gardé')
        contient(S.messages[#S.messages][2], 'introuvable')
        egal(true, p.etapeOui1, 'la ligne revient à ce qui est gardé : Oui')
        Fichiers.supprimer(Chemins.pointeur())
    end)
    vrai(not Fichiers.existe(fichier))
end)

-- Essais repris de essais-mes-demandes.lua, retiré avec le menu (relevé de la revue du 10 novembre
-- 2026 : ils ne vérifiaient pas que Mes demandes) ---------------------------------------------------

local function refuse(fn, attendu, quoi)
    local ok, erreur = pcall(fn)
    vrai(not ok, (quoi or 'refus attendu') .. ' : accepté')
    vrai(tostring(erreur):find(attendu, 1, true), (quoi or 'refus') .. ' : ' .. tostring(erreur))
end

local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')

essai('Consignes : plus de section « Demande à garder », ni de ligne à écrire, ni dans la Demande rapide (« Pas de titre. » gardé) ; plus de section Leçon ; le texte sous 7 500', function()
    local Texte = require 'Texte'
    local texte = Consignes.texte
    egal(nil, texte:find('Demande à garder', 1, true), 'plus de section Demande à garder')
    egal(nil, texte:find('<ta demande>', 1, true), 'plus de gabarit')
    for _, quoi in ipairs({ 'rapide', 'rapidePhoto' }) do
        egal(nil, Consignes[quoi]:find('Demande à garder', 1, true), quoi)
        contient(Consignes[quoi], 'Pas de titre.', quoi)
    end
    egal(nil, texte:find('\n## Leçon de la photo\n', 1, true), 'plus de section Leçon')
    vrai(Texte.longueur(texte) <= 7500, string.format('plafond des consignes : %d', Texte.longueur(texte)))
    vrai(not texte:find('\\\n', 1, true), 'lignes recollées')
end)

essai('Simulation : un élément de menu sans titre refusé à la création ; S.choisir refuse un élément grisé, un séparateur, une valeur absente ; une liste liée refaite sans titre refusée', function()
    local f = S.modules.LrView.osFactory()
    local bind = S.modules.LrView.bind
    refuse(function() f:popup_menu { items = { { value = 1 } } } end, 'sans title ni separator')
    refuse(function() f:popup_menu { items = { { title = 'a', value = 1, enabled = 'non' } } } end, 'enabled doit être un booléen')
    local p = S.modules.LrBinding.makePropertyTable()
    p.choix = 'a'
    p.elements = { { title = 'A', value = 'a' }, { separator = true }, { title = 'Grisé', value = 'g', enabled = false }, 'texte' }
    local menu = f:popup_menu { value = bind { key = 'choix', bind_to_object = p }, items = bind { key = 'elements', bind_to_object = p } }
    local vu = false
    S.pendantFenetre = function()
        vu = true
        refuse(function() S.choisir(menu, 'g') end, 'grisé', 'un élément grisé ne se choisit pas')
        refuse(function() S.choisir(menu, nil) end, 'aucun élément', 'un séparateur ne se choisit pas')
        refuse(function() S.choisir(menu, 'absente') end, 'aucun élément', 'une valeur absente')
        egal('a', p.choix, 'rien de choisi')
        S.choisir(menu, 'texte')
        egal('texte', p.choix, 'un texte est sa propre valeur')
        -- Une liste refaite sans titre à un élément : refusée à la nouvelle valeur.
        refuse(function() p.elements = { { value = 'x' } } end, 'sans title ni separator')
        S.refusDeLaFenetre()
    end
    S.modules.LrDialogs.presentFloatingDialog(_PLUGIN, { title = 'Menu', contents = f:column { menu } })
    S.pendantFenetre = nil
    vrai(vu, 'la fenêtre ouverte')
end)

essai('uninstall.sh et README : invites.json et ses copies illisibles retirés par --tout (tout le dossier) ; sans --tout, ils restent et le script le dit ; le README les cite', function()
    local script = assert(Fichiers.lire(dossierTests .. '/../../../uninstall.sh'), 'uninstall.sh')
    local entete = script:match('^(.-)\nset %-euo pipefail')
    contient(entete, '(invites.json', 'en-tête')
    contient(entete, 'invites-illisible-', 'en-tête : les copies illisibles')
    local travail = script:match('TRAVAIL=%((.-)\n%)')
    vrai(not travail:find('invites', 1, true), "invites.json n'est pas un fichier de travail")
    contient(script, 'retirer "${DEST_DIR}"', '--tout retire tout le dossier')
    local gardes = script:match('GARDES%+=%("%${DEST_DIR} %((.-)%)"%)')
    vrai(gardes, 'la ligne « Gardé pour vous » du dossier')
    contient(gardes, 'réglage des invites', 'gardé et dit')
    local readme = assert(Fichiers.lire(dossierTests .. '/../../../README.md'), 'README.md')
    local reste = readme:match('\nCe qui reste sur le Mac :\n(.-)\n\n[^\n%-]')
    vrai(reste, 'la liste « Ce qui reste sur le Mac » du README')
    contient(reste, '`invites.json`', 'le README cite invites.json')
    local desinstaller = readme:match('Pour désinstaller : (.-)\n\n')
    contient(desinstaller, '`invites.json`', 'la désinstallation le garde')
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
