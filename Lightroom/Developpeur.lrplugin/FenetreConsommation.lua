-- FenetreConsommation.lua : la fenêtre « Claude · Consommation » : les économies actives, les
-- jetons comptés cette semaine et le budget (alerte à 80 %, arrêt à 100 %), le dernier relevé du
-- forfait, les jetons par jour et les dernières demandes. Les barres sont des caractères (le SDK
-- ne dessine pas) : un fond « ░ » et, superposée, la part pleine « █ ».

local LrBinding = import 'LrBinding'
local LrColor = import 'LrColor'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Consommation = require 'Consommation'
local Journal = require 'Journal'
local Moteur = require 'Moteur'
local Texte = require 'Texte'

local FenetreConsommation = { ouverte = false }

FenetreConsommation.LARGEUR = 540
FenetreConsommation.DEMANDES = 12
-- Caractères d'une barre (Menlo 11 : 6,6 points chacun).
FenetreConsommation.BARRE_SEMAINE = 72
FenetreConsommation.BARRE_JOUR = 58

local COULEURS = {
    texte = LrColor(0.11, 0.11, 0.12),
    gris = LrColor(0.45, 0.45, 0.48),
    fond = LrColor(0.80, 0.80, 0.82),
    bleu = LrColor(0.10, 0.42, 0.85),
    vert = LrColor(0.18, 0.62, 0.28),
    orange = LrColor(0.88, 0.50, 0.05),
    rouge = LrColor(0.82, 0.18, 0.18),
}
local POLICES = {
    texte = { name = 'Helvetica Neue', size = 13 },
    gras = { name = 'Helvetica Neue Bold', size = 13 },
    petit = { name = 'Helvetica Neue', size = 11 },
    mono = { name = 'Menlo', size = 11 },
}

FenetreConsommation.ECONOMIES = {
    "Seulement le connecteur MCP-Développeur (--strict-mcp-config)",
    "Aucun outil intégré ni compétence (--tools \"\", --disable-slash-commands)",
    "Dossier de travail à part : ni CLAUDE.md de projet, ni vos réglages",
    "Publication sans Claude : Lightroom exporte directement",
    "Claude Code gardé ouvert entre deux demandes (cache réutilisé)",
}

local BUDGETS = { 500000, 1000000, 2000000, 3000000, 5000000, 10000000, 20000000 }
local MOIS = { 'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.' }
local JOURS = { 'dim.', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.' }

local bind = LrView.bind

local function poser(p, cle, valeur)
    if p[cle] ~= valeur then
        p[cle] = valeur
    end
end

-- « 19 oct. 2026 à 7:37 ».
function FenetreConsommation.date(t)
    local d = os.date('*t', t)
    return string.format("%d %s %d à %d:%02d", d.day, MOIS[d.month], d.year, d.hour, d.min)
end

function FenetreConsommation.jour(t)
    return JOURS[os.date('*t', t).wday]
end

-- Une barre de `longueur` caractères, pleine à `part` (de 0 à 1).
function FenetreConsommation.barre(part, longueur)
    local n = math.floor(math.max(0, math.min(1, part or 0)) * longueur + 0.5)
    if (part or 0) > 0 and n == 0 then
        n = 1
    end
    return string.rep('█', n)
end

function FenetreConsommation.elementsBudget(actuel)
    local items = {}
    local trouve = false
    for _, b in ipairs(BUDGETS) do
        items[#items + 1] = { title = Consommation.format(b) .. " jetons", value = b }
        trouve = trouve or b == actuel
    end
    if not trouve and actuel and actuel > 0 then
        table.insert(items, 1, { title = Consommation.format(actuel) .. " jetons", value = actuel })
    end
    items[#items + 1] = { title = "Sans budget", value = 0 }
    return items
end

function FenetreConsommation.rafraichir()
    local p = FenetreConsommation.p
    if not p then
        return
    end
    local r = Consommation.charger()
    local semaine = Consommation.jetonsSemaine()
    local budget = r.budgetSemaine or 0
    poser(p, 'semaine', budget > 0 and (Consommation.format(semaine) .. " sur " .. Consommation.format(budget)) or Consommation.format(semaine))
    poser(p, 'barreSemaine', FenetreConsommation.barre(budget > 0 and semaine / budget or 0, FenetreConsommation.BARRE_SEMAINE))
    local niveau = Consommation.niveau()
    poser(p, 'alerte', niveau == 'arret' and "Budget de la semaine atteint : les demandes sont arrêtées. Augmentez le budget pour continuer."
        or (niveau == 'alerte' and "Plus de 80 % du budget de la semaine." or ''))
    poser(p, 'releve', Consommation.texteReleve())
    local jours = Consommation.parJour()
    local maxi = 0
    for _, j in ipairs(jours) do
        maxi = math.max(maxi, j.jetons)
    end
    for i, j in ipairs(jours) do
        poser(p, 'jour' .. i, FenetreConsommation.jour(j.debut))
        poser(p, 'barre' .. i, FenetreConsommation.barre(maxi > 0 and j.jetons / maxi or 0, FenetreConsommation.BARRE_JOUR))
        poser(p, 'jetons' .. i, j.jetons > 0 and Consommation.format(j.jetons) or '')
    end
    local dernieres = Consommation.dernieres(FenetreConsommation.DEMANDES)
    poser(p, 'aucune', #dernieres == 0 and "Aucune demande encore." or '')
    for i = 1, FenetreConsommation.DEMANDES do
        local d = dernieres[i]
        poser(p, 'apercu' .. i, d and (Texte.nettoyer(d.apercu) ~= '' and Texte.lignes(d.apercu)[1] or "Demande") or '')
        poser(p, 'detail' .. i, d and (FenetreConsommation.date(d.date or 0) .. " · " .. tostring(d.modele or '')) or '')
        poser(p, 'total' .. i, d and Consommation.format(Consommation.total(d.usage)) or '')
    end
end

local function section(f, titre, contenu)
    contenu.title = titre
    contenu.width = FenetreConsommation.LARGEUR
    return f:group_box(contenu)
end

local function barre(f, cleTexte, longueur)
    return f:column {
        place = 'overlapping',
        f:static_text { title = string.rep('░', longueur), font = POLICES.mono, text_color = COULEURS.fond },
        f:static_text { title = bind(cleTexte), font = POLICES.mono, text_color = COULEURS.bleu, width_in_chars = longueur },
    }
end

function FenetreConsommation.construire(f, p)
    local L = FenetreConsommation.LARGEUR
    local economies = { spacing = 2 }
    for _, e in ipairs(FenetreConsommation.ECONOMIES) do
        economies[#economies + 1] = f:row {
            f:static_text { title = '✓', text_color = COULEURS.vert, font = POLICES.petit },
            f:static_text { title = e, font = POLICES.petit, width = L - 50 },
        }
    end

    local jours = { spacing = 1 }
    for i = 1, 7 do
        jours[#jours + 1] = f:row {
            f:static_text { title = bind('jour' .. i), font = POLICES.petit, width = 36 },
            barre(f, 'barre' .. i, FenetreConsommation.BARRE_JOUR),
            f:static_text { title = bind('jetons' .. i), font = POLICES.petit, text_color = COULEURS.gris, alignment = 'right', width = 60 },
        }
    end

    local demandes = { spacing = 4, f:static_text { title = bind 'aucune', font = POLICES.petit, text_color = COULEURS.gris } }
    for i = 1, FenetreConsommation.DEMANDES do
        demandes[#demandes + 1] = f:row {
            f:column {
                spacing = 0,
                f:static_text { title = bind('apercu' .. i), font = POLICES.texte, width = L - 110, truncation = 'tail' },
                f:static_text { title = bind('detail' .. i), font = POLICES.petit, text_color = COULEURS.gris, width = L - 110, truncation = 'tail' },
            },
            f:static_text { title = bind('total' .. i), alignment = 'right', width = 60 },
        }
    end

    return f:row {
        bind_to_object = p,
        margin = 14,
        spacing = 14,
        f:column {
            spacing = 10,
            section(f, "Économies actives", economies),
            section(f, "Cette semaine", {
                spacing = 6,
                f:row {
                    f:static_text { title = "Jetons comptés par la fenêtre", width = L - 200 },
                    f:static_text { title = bind 'semaine', alignment = 'right', width = 160, text_color = COULEURS.gris },
                },
                barre(f, 'barreSemaine', FenetreConsommation.BARRE_SEMAINE),
                f:static_text { title = bind 'alerte', text_color = COULEURS.orange, width = L - 30 },
                f:row {
                    f:static_text { title = "Budget de la semaine :" },
                    f:popup_menu { value = bind 'budget', items = FenetreConsommation.elementsBudget(Consommation.charger().budgetSemaine), width = 160 },
                },
                f:static_text { title = "Alerte à 80 %, arrêt à 100 %. Jetons : entrée, sortie et écriture du cache ; la lecture du cache compte pour un dixième.",
                    font = POLICES.petit, text_color = COULEURS.gris, width = L - 30, height_in_lines = 2 },
                f:row {
                    f:static_text { title = "Forfait, dernier relevé de Claude Code", width = L - 260 },
                    f:static_text { title = bind 'releve', alignment = 'right', width = 220, text_color = COULEURS.gris },
                },
                f:static_text { title = "Le pourcentage officiel du forfait ne se lit pas directement : la fenêtre montre le dernier relevé que Claude Code lui transmet à chaque demande (tous modèles confondus). Le menu Usage de Claude reste la référence.",
                    font = POLICES.petit, text_color = COULEURS.gris, width = L - 30, height_in_lines = 3 },
            }),
            section(f, "Par jour", jours),
        },
        section(f, "Dernières demandes", demandes),
    }
end

local function boucle()
    local tic = 0
    while FenetreConsommation.ouverte do
        if FenetreConsommation.aRafraichir or tic % 20 == 0 then
            FenetreConsommation.aRafraichir = false
            local ok, erreur = LrTasks.pcall(FenetreConsommation.rafraichir)
            if not ok then
                Journal.noter("Consommation :", tostring(erreur))
            end
        end
        tic = tic + 1
        LrTasks.sleep(0.25)
    end
end

function FenetreConsommation.afficher()
    if FenetreConsommation.ouverte then
        if FenetreConsommation.controle and FenetreConsommation.controle.toFront then
            FenetreConsommation.controle.toFront()
        end
        return
    end
    FenetreConsommation.ouverte = true
    LrFunctionContext.postAsyncTaskWithContext('Claude · consommation', function(context)
        context:addFailureHandler(function(_, erreur)
            FenetreConsommation.ouverte = false
            FenetreConsommation.p = nil
            Moteur.desabonner('consommation')
            Journal.noter("Fenêtre Consommation :", tostring(erreur))
            LrDialogs.message("La fenêtre Consommation n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)
        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
        local r = Consommation.charger()
        p.budget = r.budgetSemaine or 0
        p.semaine, p.barreSemaine, p.alerte, p.releve, p.aucune = '', '', '', '', ''
        for i = 1, 7 do
            p['jour' .. i], p['barre' .. i], p['jetons' .. i] = '', '', ''
        end
        for i = 1, FenetreConsommation.DEMANDES do
            p['apercu' .. i], p['detail' .. i], p['total' .. i] = '', '', ''
        end
        FenetreConsommation.p = p
        p:addObserver('budget', function(_, _, valeur)
            Consommation.changerBudget(valeur)
            FenetreConsommation.aRafraichir = true
            Moteur.signaler('consommation')
        end)
        local contenu = FenetreConsommation.construire(f, p)
        FenetreConsommation.rafraichir()
        Moteur.abonner('consommation', function() FenetreConsommation.aRafraichir = true end)
        LrTasks.startAsyncTask(boucle)
        LrDialogs.presentFloatingDialog(_PLUGIN, {
            title = "Claude · Consommation",
            contents = contenu,
            save_frame = 'DeveloppeurConsommation',
            blockTask = true,
            onShow = function(controle) FenetreConsommation.controle = controle end,
            windowWillClose = function()
                FenetreConsommation.ouverte = false
                FenetreConsommation.controle = nil
                Moteur.desabonner('consommation')
            end,
        })
        while FenetreConsommation.ouverte do
            LrTasks.sleep(0.5)
        end
        FenetreConsommation.p = nil
    end)
end

return FenetreConsommation
