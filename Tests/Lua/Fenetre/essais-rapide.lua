-- essais-rapide.lua : la fenêtre Demande rapide (FenetreRapide.lua) hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua) : ses boutons à icône à gauche du champ, sans ♻, et la
-- réponse effacée quand Dany choisit une autre photo ou une autre sélection (demandé par Dany le
-- 24 octobre 2026), mais pas quand la sélection change pendant le travail de Claude ou juste
-- après. Ni Claude, ni quota.
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

-- Toutes les vues d'un arbre, avec la marge gauche de la pièce qui les porte.
local function vues(contenu)
    local liste = {}
    local function parcourir(v, marge)
        marge = (v.args and v.args.margin_left) or marge
        liste[#liste + 1] = { vue = v, marge = marge }
        for _, enfant in ipairs(v.args or {}) do
            if type(enfant) == 'table' and enfant.genre then
                parcourir(enfant, marge)
            end
        end
    end
    parcourir(contenu, 0)
    return liste
end

local Moteur = require 'Moteur'
local FenetreRapide = require 'FenetreRapide'

essai("Les boutons à icône à gauche du champ, sans ♻", function()
    local contenu
    S.pendantFenetre = function(args) contenu = args.contents end
    FenetreRapide.afficher()
    S.pendantFenetre = nil
    vrai(contenu, 'fenêtre ouverte')
    local icones, champ = {}, nil
    for _, v in ipairs(vues(contenu)) do
        local a = v.vue.args or {}
        vrai(a.title ~= "♻", 'plus de bouton ♻')
        if v.vue.genre == 'square_button' and a.image_name then
            icones[#icones + 1] = v.marge or 0
            egal(FenetreRapide.CARRE, a.width, 'carré')
        elseif v.vue.genre == 'edit_field' then
            champ = v.marge
        end
    end
    egal(#FenetreRapide.ACTIONS, #icones, 'un carré par action')
    local pas = FenetreRapide.CARRE + FenetreRapide.ESPACE
    for i, marge in ipairs(icones) do
        egal((i - 1) * pas, marge, 'marge du carré ' .. i)
    end
    egal(#FenetreRapide.ACTIONS * pas - FenetreRapide.ESPACE + FenetreRapide.ECART, champ, 'le champ après les carrés')
    vrai(FenetreRapide.reinitialiser == nil, 'plus de reinitialiser')
end)

-- Une demande rapide finie, montrée dans la fenêtre.
local function reponse()
    Moteur.rapide = { id = 'r', elements = {} }
    Moteur.travaille, Moteur.enCours, Moteur.session = false, nil, nil
end

essai("Une autre photo ou une autre sélection efface la réponse ; le champ reste", function()
    FenetreRapide.cleVue, FenetreRapide.cleVueLe, FenetreRapide.message = nil, nil, nil
    Moteur.finTravail = os.time() - 60
    reponse()
    FenetreRapide.suivreSelection({ cle = '1:1:1' })
    vrai(Moteur.rapide, 'première sélection vue : rien ne change')
    FenetreRapide.suivreSelection({ cle = '1:1:1' })
    vrai(Moteur.rapide, 'même sélection : la réponse reste')
    FenetreRapide.p = { demande = 'Rends le ciel plus doux' }
    FenetreRapide.suivreSelection({ cle = '2:1:2' })
    egal(nil, Moteur.rapide, 'autre photo : demande oubliée')
    egal('Rends le ciel plus doux', FenetreRapide.p.demande, 'ce qui est tapé reste')
    FenetreRapide.p = nil
    egal(FenetreRapide.VIDE, FenetreRapide.texte(0), 'la réponse effacée')
    -- Un message seul (un refus, une erreur) s'efface de même.
    FenetreRapide.message = "Claude travaille déjà"
    FenetreRapide.suivreSelection({ cle = '2:3:2:4:5' })
    egal(nil, FenetreRapide.message, 'autre sélection : message effacé')
    -- Sans photo active (rien de sélectionné), rien ne change.
    reponse()
    FenetreRapide.suivreSelection({})
    vrai(Moteur.rapide, 'sans clé : la réponse reste')
    egal('2:3:2:4:5', FenetreRapide.cleVue)
end)

essai("La sélection changée par Claude, pendant son travail ou juste après, garde la réponse", function()
    FenetreRapide.cleVue, FenetreRapide.cleVueLe, FenetreRapide.message = '1:1:1', os.time(), nil
    reponse()
    Moteur.travaille = true
    FenetreRapide.suivreSelection({ cle = '9:1:9' })
    vrai(Moteur.rapide, 'pendant le travail (show_photo) : la réponse reste')
    Moteur.travaille, Moteur.finTravail = false, os.time()
    FenetreRapide.suivreSelection({ cle = '9:2:9:8' })
    vrai(Moteur.rapide, 'juste après le travail : la réponse reste')
    -- Plus tard, c'est Dany qui choisit.
    FenetreRapide.cleVueLe = os.time() - 10
    Moteur.finTravail = os.time() - 20
    FenetreRapide.suivreSelection({ cle = '3:1:3' })
    egal(nil, Moteur.rapide, 'choisie par Dany : demande oubliée')
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
