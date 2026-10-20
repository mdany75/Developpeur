-- Fenetre.lua : la fenêtre « Claude » du module Développeur (fenêtre flottante, non bloquante) :
-- les conversations à gauche, le fil au centre avec les appels d'outils, les invites en raccourcis
-- et la demande ; à droite, ce que Claude regarde, sa proposition à accepter, refuser ou ajuster,
-- et en bas les versions du module et du connecteur MCP-Développeur.
--
-- Le SDK ne sait ni ajouter de vues à une fenêtre ouverte ni la faire défiler par programme, et
-- une vue masquée garde sa place : le fil est une grille de lignes fixes (Fil.lua), remplie à
-- chaque changement et parcourue par les boutons ▲ ▼ ; chaque ligne superpose une variante par
-- genre (police, couleur), dont une seule est visible.

local LrBinding = import 'LrBinding'
local LrColor = import 'LrColor'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Fil = require 'Fil'
local Images = require 'Images'
local Journal = require 'Journal'
local Json = require 'Json'
local Lightroom = require 'Lightroom'
local Metriques = require 'Metriques'
local Moteur = require 'Moteur'
local Stockage = require 'Stockage'
local Texte = require 'Texte'
local Composants = require 'Composants'

local Fenetre = { ouverte = false, defilement = 0, jointes = {}, cache = {}, vignettes = {} }

-- lignes : lignes du fil montrées ; fil : largeur de la colonne centrale ; liste : colonne des
-- conversations ; droite : colonne des aperçus ; apercu : côté de l'aperçu (et de son image vide).
Fenetre.TAILLES = {
    petite = { lignes = 22, fil = 560, liste = 190, droite = 250, apercu = 230 },
    moyenne = { lignes = 30, fil = 760, liste = 220, droite = 290, apercu = 270 },
    grande = { lignes = 40, fil = 900, liste = 250, droite = 340, apercu = 320 },
}

local COULEURS = {
    texte = LrColor(0.11, 0.11, 0.12),
    dany = LrColor(0.04, 0.32, 0.72),
    gris = LrColor(0.45, 0.45, 0.48),
    mono = LrColor(0.24, 0.24, 0.27),
    vert = LrColor(0.18, 0.62, 0.28),
    orange = LrColor(0.88, 0.50, 0.05),
    rouge = LrColor(0.82, 0.18, 0.18),
    bleu = LrColor(0.10, 0.42, 0.85),
}

local function police(cle, taille)
    local m = Metriques[cle]
    return { name = m.nom, size = taille or m.taille }
end

local POLICES = {
    texte = police('texte'),
    gras = police('gras'),
    mono = police('mono'),
    titre = police('gras', 15),
    petit = police('texte', 11),
}

-- Icônes de la colonne de gauche du fil.
local ICONES = {
    { cle = 'dany', glyphe = '›', couleur = 'dany' },
    { cle = 'ok', glyphe = '✓', couleur = 'vert' },
    { cle = 'cours', glyphe = '●', couleur = 'orange' },
    { cle = 'erreur', glyphe = '✕', couleur = 'rouge' },
    { cle = 'apercu', glyphe = '▣', couleur = 'bleu' },
    { cle = 'proposition', glyphe = '●', couleur = 'orange' },
    { cle = 'note', glyphe = 'ⓘ', couleur = 'gris' },
}

-- Variantes de texte d'une ligne, selon son genre.
local STYLES = {
    { genres = { claude = true, vide = true }, police = 'texte', couleur = 'texte' },
    { genres = { titre = true }, police = 'gras', couleur = 'texte' },
    { genres = { dany = true }, police = 'texte', couleur = 'dany' },
    { genres = { outil = true }, police = 'mono', couleur = 'mono' },
    { genres = { apercu = true }, police = 'texte', couleur = 'bleu' },
    { genres = { proposition = true }, police = 'gras', couleur = 'orange' },
    { genres = { note = true }, police = 'texte', couleur = 'gris' },
}

-- Pastilles des voyants (Claude Code, Lightroom, mode).
local PASTILLES = { ok = 'vert', attention = 'orange', erreur = 'rouge', neutre = 'gris', bleu = 'bleu' }

local bind = LrView.bind

local function egal(cle, valeur)
    return bind { key = cle, transform = function(v) return v == valeur end }
end

-- Les fenêtres modales et le choix de fichiers s'ouvrent depuis une tâche, pas depuis l'action
-- d'un bouton.
local function enTache(fn, ...)
    local arguments = { ... }
    LrTasks.startAsyncTask(function()
        local ok, erreur = LrTasks.pcall(fn, unpack(arguments))
        if not ok then
            Journal.noter("Fenêtre :", tostring(erreur))
        end
    end)
end

-- Change une propriété seulement si sa valeur change (moins de travail pour Lightroom).
local function poser(p, cle, valeur)
    if p[cle] ~= valeur then
        p[cle] = valeur
    end
end

-- Texte JSON rendu lisible (indenté), ou tel quel s'il n'est pas du JSON.
function Fenetre.lisible(texte)
    local ok, valeur = pcall(Json.decode, texte)
    if not ok or type(valeur) ~= 'table' then
        return texte
    end
    local function ecrire(v, retrait)
        if type(v) ~= 'table' or v == Json.null then
            return Json.encode(v)
        end
        local suivant = retrait .. '  '
        local morceaux = {}
        if #v > 0 or getmetatable(v) ~= nil then
            for _, x in ipairs(v) do
                morceaux[#morceaux + 1] = suivant .. ecrire(x, suivant)
            end
            return #morceaux == 0 and '[]' or ('[\n' .. table.concat(morceaux, ',\n') .. '\n' .. retrait .. ']')
        end
        local cles = {}
        for k in pairs(v) do
            cles[#cles + 1] = tostring(k)
        end
        table.sort(cles)
        for _, k in ipairs(cles) do
            morceaux[#morceaux + 1] = suivant .. Json.encode(k) .. ': ' .. ecrire(v[k], suivant)
        end
        return #morceaux == 0 and '{}' or ('{\n' .. table.concat(morceaux, ',\n') .. '\n' .. retrait .. '}')
    end
    return ecrire(valeur, '')
end

-- Liste des conversations ---------------------------------------------------------------------

local function periode(t, maintenant)
    maintenant = maintenant or os.time()
    if os.date('%Y%m%d', t) == os.date('%Y%m%d', maintenant) then
        return "Aujourd'hui"
    end
    local debut = os.date('*t', maintenant)
    debut.hour, debut.min, debut.sec = 0, 0, 0
    if t >= os.time(debut) - 7 * 86400 then
        return "Cette semaine"
    end
    return "Plus ancien"
end

-- Éléments de la liste : en-têtes de période et conversations trouvées (tables neuves, sans
-- métatable : Lightroom bloque sur une table relue par Json.decode).
function Fenetre.elementsListe(recherche)
    local items = {}
    local courante = Moteur.courante
    local dejaVue = false
    local derniere
    for _, c in ipairs(Moteur.conversations) do
        if c == courante then
            dejaVue = true
        end
        if Conversation.correspond(c, recherche or '') then
            local p = periode(c.modifiee or c.creee or os.time())
            if p ~= derniere then
                items[#items + 1] = { title = p, value = '§' .. p }
                derniere = p
            end
            items[#items + 1] = { title = "   " .. tostring(c.titre or ''), value = c.id }
        end
    end
    if courante and not dejaVue then
        table.insert(items, 1, { title = "   " .. tostring(courante.titre or Conversation.TITRE_PAR_DEFAUT), value = courante.id })
    end
    return items
end

function Fenetre.rafraichirListe()
    local p = Fenetre.p
    if not p then
        return
    end
    local items = Fenetre.elementsListe(p.recherche)
    local morceaux = {}
    for _, item in ipairs(items) do
        morceaux[#morceaux + 1] = tostring(item.value) .. '\1' .. item.title
    end
    morceaux[#morceaux + 1] = Moteur.courante and Moteur.courante.id or ''
    local signature = table.concat(morceaux, '\2')
    -- Remplacer la liste à chaque rafraîchissement la ferait sauter : seulement si elle change.
    if signature == Fenetre.signatureListe then
        return
    end
    Fenetre.signatureListe = signature
    Fenetre.majListe = true
    p.listeConversations = items
    if Moteur.courante then
        p.selectionListe = { Moteur.courante.id }
    end
    Fenetre.majListe = false
end

-- Choix dans la liste : ouvre la conversation (un en-tête, ou un refus, remet la sélection).
function Fenetre.choisirDansListe(valeur)
    if Fenetre.majListe then
        return
    end
    local id = type(valeur) == 'table' and valeur[1] or valeur
    if id == nil or (Moteur.courante and id == Moteur.courante.id) then
        return
    end
    if type(id) == 'string' and id:sub(1, 1) == '§' then
        Fenetre.signatureListe = nil
        Fenetre.rafraichirListe()
        return
    end
    local ok, raison = Moteur.ouvrir(id)
    if not ok then
        Fenetre.p.message = raison or ''
        Fenetre.signatureListe = nil
        Fenetre.rafraichirListe()
        return
    end
    Fenetre.defilement = 0
    Fenetre.indiceImage = nil
    Fenetre.p.message = ''
end

-- Fil -----------------------------------------------------------------------------------------

function Fenetre.largeurTexte()
    return Fenetre.T.fil - 20
end

function Fenetre.rafraichirFil()
    local p, T = Fenetre.p, Fenetre.T
    if not p then
        return
    end
    local c = Moteur.courante
    if Fenetre.conversationAffichee ~= c then
        Fenetre.defilement = 0
        Fenetre.cache = {}
        Fenetre.total = nil
    end
    local lignes = c and Fil.lignes(c, Fenetre.largeurTexte(), Fenetre.cache) or {}
    -- Lecteur remonté dans le fil : ce qui arrive ne déplace pas ce qu'il lit.
    if Fenetre.defilement > 0 and Fenetre.total and #lignes > Fenetre.total then
        Fenetre.defilement = Fenetre.defilement + (#lignes - Fenetre.total)
    end
    Fenetre.conversationAffichee = c
    Fenetre.total = #lignes
    Fenetre.lignes = lignes
    local premiere, defilement = Fil.fenetre(#lignes, T.lignes, Fenetre.defilement)
    Fenetre.defilement = defilement
    Fenetre.premiere = premiere
    for i = 1, T.lignes do
        local l = lignes[premiere + i - 1]
        poser(p, 't' .. i, l and l.texte or '')
        poser(p, 'g' .. i, l and l.genre or 'vide')
        poser(p, 'i' .. i, l and l.icone or '')
    end
    if #lignes == 0 then
        poser(p, 't2', "Demandez à Claude.")
        poser(p, 'g2', 'titre')
        poser(p, 't3', "Claude voit la photo active et la sélection de Lightroom, et retouche avec le connecteur MCP-Développeur.")
        poser(p, 'g3', 'note')
    end
    local derniere = math.min(premiere + T.lignes - 1, #lignes)
    poser(p, 'positionFil', #lignes > T.lignes and string.format("Lignes %d à %d sur %d", premiere, derniere, #lignes) or '')
    poser(p, 'peutMonter', premiere > 1)
    poser(p, 'peutDescendre', defilement > 0)
end

function Fenetre.defiler(pas)
    if pas == 'fin' then
        Fenetre.defilement = 0
    else
        Fenetre.defilement = math.max(0, Fenetre.defilement + pas)
    end
    Fenetre.rafraichirFil()
end

-- Clic sur une ligne : une image s'affiche à droite, un outil montre son détail.
function Fenetre.cliquerLigne(i)
    Fenetre.annulerEnvoiAuto()
    local l = Fenetre.lignes and Fenetre.lignes[(Fenetre.premiere or 1) + i - 1]
    if not l then
        return
    end
    if l.image then
        for n, image in ipairs(Fenetre.images or {}) do
            if image.chemin == l.image then
                Fenetre.indiceImage = n
            end
        end
        Fenetre.rafraichirApercu()
        return
    end
    local c = Moteur.courante
    local e = c and l.element and c.elements[l.element]
    if e and e.genre == 'outil' then
        enTache(Fenetre.montrerDetail, e)
    end
end

function Fenetre.montrerDetail(e)
    local detail = e.detail or ''
    local entree, reponse = detail:match('^(.-)\n\n— Réponse —\n(.*)$')
    local texte = entree and (Fenetre.lisible(entree) .. "\n\n— Réponse —\n" .. Fenetre.lisible(reponse)) or Fenetre.lisible(detail)
    local f = LrView.osFactory()
    LrDialogs.presentModalDialog {
        title = "Claude · " .. tostring(e.texte or e.outil or 'outil'),
        contents = f:column {
            spacing = f:control_spacing(),
            f:static_text { title = "Ce que Claude a demandé au connecteur, puis sa réponse (sélectionnable, ⌘A puis ⌘C pour copier)." },
            f:edit_field { value = texte, width_in_chars = 90, height_in_lines = 24, font = POLICES.mono },
        },
        actionVerb = "Fermer",
        cancelVerb = '< exclude >',
    }
end

-- Aperçus -------------------------------------------------------------------------------------

function Fenetre.imageVide()
    return Chemins.ressource('vide-' .. Fenetre.T.apercu .. '.png')
end

function Fenetre.rafraichirApercu()
    local p, T = Fenetre.p, Fenetre.T
    if not p then
        return
    end
    local c = Moteur.courante
    Fenetre.images = c and Conversation.images(c) or {}
    local n = #Fenetre.images
    if Fenetre.indiceImage and Fenetre.indiceImage > n then
        Fenetre.indiceImage = nil
    end
    local indice = Fenetre.indiceImage or n
    poser(p, 'aImage', n > 0)
    poser(p, 'peutPrecedente', indice > 1)
    poser(p, 'peutSuivante', indice < n)
    if n == 0 then
        poser(p, 'legendeApercu', "Aucun aperçu pour l'instant")
        poser(p, 'imageApercu', Fenetre.imageVide())
        return
    end
    local image = Fenetre.images[indice]
    local nature = image.outil == 'jointe' and "photo jointe" or (image.outil or "aperçu")
    poser(p, 'legendeApercu', string.format("%d sur %d · %s", indice, n, nature))
    local cle = c.id .. '/' .. image.chemin .. '/' .. T.apercu
    local deja = Fenetre.vignettes[cle]
    if deja then
        poser(p, 'imageApercu', deja)
        return
    end
    LrTasks.startAsyncTask(function()
        local chemin = Images.vignette(Stockage.dossier(c.id), image.chemin, T.apercu)
        if chemin then
            Fenetre.vignettes[cle] = chemin
            if Fenetre.p and Moteur.courante == c then
                Fenetre.p.imageApercu = chemin
            end
        end
    end)
end

function Fenetre.changerImage(pas)
    local n = #(Fenetre.images or {})
    if n == 0 then
        return
    end
    Fenetre.indiceImage = math.max(1, math.min(n, (Fenetre.indiceImage or n) + pas))
    if Fenetre.indiceImage == n then
        Fenetre.indiceImage = nil
    end
    Fenetre.rafraichirApercu()
end

-- L'aperçu en grand, dans une fenêtre à part.
function Fenetre.agrandir()
    local c = Moteur.courante
    local n = #(Fenetre.images or {})
    if not c or n == 0 then
        return
    end
    local image = Fenetre.images[Fenetre.indiceImage or n]
    LrTasks.startAsyncTask(function()
        local chemin, l, h = Images.grande(Stockage.dossier(c.id), image.chemin, 1100, 740)
        if not chemin then
            LrDialogs.message("Aperçu illisible", image.chemin, 'warning')
            return
        end
        local f = LrView.osFactory()
        LrDialogs.presentModalDialog {
            title = "Claude · " .. (Fenetre.p and Fenetre.p.legendeApercu or "aperçu"),
            contents = f:picture { value = chemin, width = l, height = h },
            actionVerb = "Fermer",
            cancelVerb = '< exclude >',
        }
    end)
end

-- Proposition ---------------------------------------------------------------------------------

function Fenetre.rafraichirProposition()
    local p = Fenetre.p
    if not p then
        return
    end
    local c = Moteur.courante
    local prop = c and Conversation.propositionEnAttente(c)
    poser(p, 'enAttente', prop ~= nil and not Moteur.travaille)
    if not prop then
        poser(p, 'propositionTexte', "Aucune proposition en attente.\n\nEn mode « Proposer d'abord », Claude montre ici ce qu'il compte changer et attend votre accord.")
        return
    end
    local lignes = { Texte.nettoyer(prop.texte) ~= '' and prop.texte or "Claude propose :" , '' }
    for _, ch in ipairs(prop.changements or {}) do
        lignes[#lignes + 1] = string.format("%s : %s → %s", ch.libelle or '?', ch.avant or '—', ch.apres or '—')
    end
    poser(p, 'propositionTexte', table.concat(lignes, '\n'))
end

function Fenetre.ajuster()
    local f = LrView.osFactory()
    local texte = ''
    LrFunctionContext.callWithContext('Claude · ajuster', function(context)
        local q = LrBinding.makePropertyTable(context)
        q.texte = ''
        local rapides = { spacing = 6 }
        for _, a in ipairs(Consignes.ajustementsRapides) do
            rapides[#rapides + 1] = f:push_button { title = a, action = function()
                q.texte = Texte.nettoyer(q.texte) == '' and a or (Texte.nettoyer(q.texte) .. ", " .. a:lower())
            end }
        end
        local reponse = LrDialogs.presentModalDialog {
            title = "Ajuster la proposition",
            contents = f:column {
                bind_to_object = q,
                spacing = f:control_spacing(),
                f:static_text { title = "Ce qu'il faut changer avant d'appliquer :" },
                f:edit_field { value = bind 'texte', width_in_chars = 60, height_in_lines = 3, immediate = true },
                f:row(rapides),
            },
            actionVerb = "Envoyer à Claude",
        }
        if reponse == 'ok' then
            texte = q.texte
        end
    end)
    if Texte.nettoyer(texte) ~= '' then
        LrTasks.startAsyncTask(function()
            Moteur.ajuster(texte)
        end)
    end
end

-- Voyants -------------------------------------------------------------------------------------

function Fenetre.rafraichirMode()
    local p = Fenetre.p
    if not p then
        return
    end
    local mode = Lightroom.mode()
    poser(p, 'texteMode', mode == 'proposer' and "Proposer d'abord" or "Appliquer directement")
    poser(p, 'etatMode', mode == 'proposer' and 'bleu' or 'neutre')
end

-- Claude Code (commandes du système : dans une tâche) et la liaison avec le serveur, lue
-- directement dans ce module.
function Fenetre.verifier(avecClaude)
    local p = Fenetre.p
    if not p then
        return
    end
    local prefs = Chemins.prefs()
    if avecClaude then
        local etat = Lightroom.etatClaude(prefs.cheminClaude)
        p.texteClaude = etat.texte
        p.etatClaude = etat.connecte == true and (etat.forfait and 'ok' or 'attention') or (etat.connecte == nil and 'neutre' or 'erreur')
        Fenetre.aideClaude = etat.connecte == false and (etat.installe and
            "Claude Code n'est pas connecté : ouvrez le Terminal et lancez « claude », puis /login avec votre compte claude.ai."
            or "Claude Code est introuvable : installez-le, ou réglez son chemin dans le Gestionnaire de modules externes.") or nil
    end
    if avecClaude then
        Fenetre.rafraichirVersions(Composants.lire())
    end
    local liaison, erreur = Lightroom.liaison()
    poser(p, 'texteLightroom', liaison == 'active' and "Lightroom"
        or (liaison == 'erreur' and "Lightroom · liaison en erreur" or "Lightroom · liaison arrêtée"))
    poser(p, 'etatLightroom', liaison == 'active' and 'ok' or 'erreur')
    if liaison == 'erreur' then
        Fenetre.aideLiaison = "La liaison avec Claude est en erreur (" .. tostring(erreur)
            .. ") : un autre Lightroom ouvert tient peut-être ses ports. Fermez-le, puis cliquez le voyant Lightroom."
    elseif liaison == 'arretee' then
        Fenetre.aideLiaison = "La liaison avec Claude est arrêtée : cliquez le voyant Lightroom pour la démarrer "
            .. "(ou Fichier › Module externe - Extras › Démarrer la liaison avec Claude)."
    else
        Fenetre.aideLiaison = nil
    end
    Fenetre.rafraichirMode()
    Fenetre.rafraichirAide()
end

-- Clic sur le voyant Lightroom : démarre la liaison si elle est arrêtée (ou la relance après une
-- erreur), puis le voyant se relit.
function Fenetre.demarrerLiaison()
    Lightroom.demarrerLiaison()
    Fenetre.verifier(false)
end

-- Les deux versions en bas à droite (Composants.lignes).
function Fenetre.rafraichirVersions(lignes)
    local p = Fenetre.p
    if not p then
        return
    end
    for i, l in ipairs(lignes) do
        poser(p, 'versionNom' .. i, l.nom)
        poser(p, 'version' .. i, l.version)
        poser(p, 'versionAlerte' .. i, l.alerte == true)
    end
end

function Fenetre.rafraichirAide()
    local p = Fenetre.p
    if not p then
        return
    end
    local aides = {}
    if Fenetre.aideClaude then
        aides[#aides + 1] = Fenetre.aideClaude
    end
    if Fenetre.aideLiaison then
        aides[#aides + 1] = Fenetre.aideLiaison
    end
    Fenetre.aides = aides
    poser(p, 'aide', table.concat(aides, "  ·  "))
end

-- Clic sur l'aide du bandeau : le texte entier.
function Fenetre.montrerAide()
    if Fenetre.aides and #Fenetre.aides > 0 then
        LrDialogs.message("Claude · aide", table.concat(Fenetre.aides, "\n\n"), 'info')
    end
end

-- Ce que montre le bandeau de la ligne du Style : un message, sinon l'aide d'un voyant rouge,
-- sinon les photos jointes, sinon le rappel du style.
function Fenetre.etatBandeau(p)
    if (p.message or '') ~= '' then
        return 'message'
    elseif (p.aide or '') ~= '' then
        return 'aide'
    elseif (p.jointes or '') ~= '' then
        return 'jointes'
    end
    return 'rappel'
end

function Fenetre.majPhoto()
    local p = Fenetre.p
    if not p then
        return
    end
    local info = Lightroom.photos()
    if info.active then
        p.infoPhoto = string.format("Active : %s     Sélection : %d", Lightroom.nomCourt(info.active.nom), info.selection)
    else
        p.infoPhoto = "Aucune photo active"
    end
end

-- Tout ce qui dépend du moteur.
function Fenetre.rafraichir()
    local p = Fenetre.p
    if not p then
        return
    end
    local c = Moteur.courante
    poser(p, 'titre', c and c.titre or Conversation.TITRE_PAR_DEFAUT)
    poser(p, 'libre', not Moteur.travaille)
    poser(p, 'travaille', Moteur.travaille)
    poser(p, 'titreEnvoyer', Moteur.travaille and "Arrêter" or "Envoyer")
    poser(p, 'forfait', Moteur.texteForfait())
    Fenetre.rafraichirFil()
    Fenetre.rafraichirApercu()
    Fenetre.rafraichirProposition()
    Fenetre.rafraichirListe()
end

-- Demandes ------------------------------------------------------------------------------------

function Fenetre.texteJointes()
    local n = #Fenetre.jointes
    if n == 0 then
        return ''
    end
    local noms = {}
    for _, chemin in ipairs(Fenetre.jointes) do
        local nom = LrPathUtils.leafName(chemin)
        noms[#noms + 1] = nom:sub(1, 7) == 'collee-' and "image collée" or nom
    end
    return (n == 1 and "1 photo jointe : " or (n .. " photos jointes : ")) .. table.concat(noms, ", ")
end

function Fenetre.envoyer(texte, modele)
    local p = Fenetre.p
    if Moteur.travaille then
        return
    end
    local jointes = Fenetre.jointes
    texte = Texte.nettoyer(texte)
    if texte == '' and #jointes == 0 then
        p.message = "Écrivez une demande avant d'envoyer."
        return
    end
    Fenetre.jointes = {}
    p.jointes = ''
    p.message = ''
    p.libre = false
    Fenetre.defilement = 0
    LrTasks.startAsyncTask(function()
        local ok, raison = Moteur.envoyer(texte, { modele = modele or p.modele, jointes = jointes, style = p.style })
        if not ok and Fenetre.p then
            Fenetre.p.message = raison or ''
            if not Moteur.travaille then
                Fenetre.jointes = jointes
                Fenetre.p.jointes = Fenetre.texteJointes()
            end
        end
        Fenetre.aRafraichir = true
    end)
end

-- Champ de demande. Sur Mac, Lightroom ne reprend le texte d'un champ (immediate = false) qu'à
-- Retour, et au clic d'un bouton, juste avant l'action du bouton (constaté dans Lightroom 15.6 ;
-- avec immediate = true, Retour ne se voit pas du tout). Un texte reçu part donc tout seul après un
-- court délai, sauf si un clic de bouton le suit : le bouton décide (Envoyer l'envoie, les autres
-- le laissent dans le champ, pour une photo jointe par exemple).
Fenetre.DELAI_RETOUR = 0.3

function Fenetre.saisieValidee(valeur)
    if Fenetre.ignorerSaisie or type(valeur) ~= 'string' or Texte.nettoyer(valeur) == '' then
        return
    end
    local jeton = {}
    Fenetre.envoiAuto = jeton
    LrTasks.startAsyncTask(function()
        LrTasks.sleep(Fenetre.DELAI_RETOUR)
        if Fenetre.envoiAuto ~= jeton or not Fenetre.ouverte or not Fenetre.p then
            return
        end
        Fenetre.envoiAuto = nil
        Fenetre.envoyerSaisie()
    end)
end

-- Un clic de bouton, un choix dans la liste ou le menu : pas d'envoi automatique.
function Fenetre.annulerEnvoiAuto()
    Fenetre.envoiAuto = nil
end

-- Envoie la demande du champ et le vide.
function Fenetre.envoyerSaisie()
    local p = Fenetre.p
    if Moteur.travaille then
        p.message = "Claude travaille : attendez la fin, ou cliquez Arrêter."
        return
    end
    local texte = p.saisie
    Fenetre.ignorerSaisie = true
    p.saisie = ''
    Fenetre.ignorerSaisie = false
    Fenetre.envoyer(texte)
end

-- Bouton Envoyer / Arrêter.
function Fenetre.boutonPrincipal()
    Fenetre.annulerEnvoiAuto()
    if Moteur.travaille then
        Moteur.interrompre()
        return
    end
    Fenetre.envoyerSaisie()
end

function Fenetre.joindre()
    local chemins = LrDialogs.runOpenPanel {
        title = "Joindre une photo à la demande",
        prompt = "Joindre",
        canChooseFiles = true,
        canChooseDirectories = false,
        allowsMultipleSelection = true,
        fileTypes = { 'jpg', 'jpeg', 'png', 'heic', 'tif', 'tiff', 'webp' },
    }
    if chemins then
        for _, chemin in ipairs(chemins) do
            Fenetre.jointes[#Fenetre.jointes + 1] = chemin
        end
        Fenetre.p.jointes = Fenetre.texteJointes()
    end
end

-- Bouton 📋 : l'image du presse-papiers (capture d'écran, image copiée, fichier copié dans le
-- Finder) jointe à la demande. Le SDK ne lit pas le presse-papiers, et ⌘V dans le champ n'y colle
-- que du texte.
function Fenetre.coller()
    local chemins = Images.coller()
    if #chemins == 0 then
        Fenetre.p.message = "Pas d'image dans le presse-papiers : copiez une image (⌘C), une capture d'écran (⌃⇧⌘4) ou une photo dans le Finder, puis cliquez 📋."
        return
    end
    for _, chemin in ipairs(chemins) do
        Fenetre.jointes[#Fenetre.jointes + 1] = chemin
    end
    Fenetre.p.message = ''
    Fenetre.p.jointes = Fenetre.texteJointes()
end

function Fenetre.retirerJointes()
    Fenetre.jointes = {}
    Fenetre.p.jointes = ''
end

function Fenetre.renommer()
    local c = Moteur.courante
    if not c then
        return
    end
    local f = LrView.osFactory()
    LrFunctionContext.callWithContext('Claude · renommer', function(context)
        local q = LrBinding.makePropertyTable(context)
        q.titre = c.titre or ''
        local reponse = LrDialogs.presentModalDialog {
            title = "Renommer la conversation",
            contents = f:column {
                bind_to_object = q,
                f:edit_field { value = bind 'titre', width_in_chars = 40, immediate = true },
            },
            actionVerb = "Renommer",
        }
        if reponse == 'ok' then
            Moteur.renommer(c.id, q.titre)
            Fenetre.aRafraichir = true
        end
    end)
end

function Fenetre.supprimer()
    local c = Moteur.courante
    if not c or #c.elements == 0 then
        return
    end
    local reponse = LrDialogs.confirm("Supprimer la conversation « " .. tostring(c.titre) .. " » ?",
        "Elle va à la corbeille du Finder, avec ses images. Les retouches faites dans Lightroom restent.", "Supprimer", "Annuler")
    if reponse == 'ok' then
        local ok, raison = Moteur.supprimer(c.id)
        if not ok and raison then
            Fenetre.p.message = raison
        end
        Fenetre.aRafraichir = true
    end
end

-- Construction --------------------------------------------------------------------------------

local function ligneFil(f, i, largeur)
    local icones = { place = 'overlapping', width = 16 }
    for _, ic in ipairs(ICONES) do
        icones[#icones + 1] = f:static_text { title = ic.glyphe, font = POLICES.texte, text_color = COULEURS[ic.couleur],
            visible = egal('i' .. i, ic.cle) }
    end
    local textes = { place = 'overlapping' }
    for _, st in ipairs(STYLES) do
        local genres = st.genres
        textes[#textes + 1] = f:static_text {
            title = bind('t' .. i),
            width = largeur,
            font = POLICES[st.police],
            text_color = COULEURS[st.couleur],
            truncation = 'tail',
            visible = bind { key = 'g' .. i, transform = function(v) return genres[v] == true end },
            mouse_down = function() Fenetre.cliquerLigne(i) end,
        }
    end
    return f:row { spacing = 4, f:column(icones), f:column(textes) }
end

-- Une ligne de version : le nom à gauche, le numéro à droite, en gris ou en orange (alerte).
local function ligneVersion(f, i, largeur)
    local alerte = bind('versionAlerte' .. i)
    local normal = bind { key = 'versionAlerte' .. i, transform = function(v) return not v end }
    return f:row {
        spacing = 0,
        f:column {
            place = 'overlapping',
            f:static_text { title = bind('versionNom' .. i), font = POLICES.petit, text_color = COULEURS.gris, width = largeur - 46, truncation = 'tail', visible = normal },
            f:static_text { title = bind('versionNom' .. i), font = POLICES.petit, text_color = COULEURS.orange, width = largeur - 46, truncation = 'tail', visible = alerte },
        },
        f:column {
            place = 'overlapping',
            f:static_text { title = bind('version' .. i), font = POLICES.petit, text_color = COULEURS.gris, alignment = 'right', width = 46, visible = normal },
            f:static_text { title = bind('version' .. i), font = POLICES.petit, text_color = COULEURS.orange, alignment = 'right', width = 46, visible = alerte },
        },
    }
end

local function voyant(f, cleEtat, cleTexte, action, infobulle)
    local pastilles = { place = 'overlapping' }
    for etat, couleur in pairs(PASTILLES) do
        pastilles[#pastilles + 1] = f:static_text { title = '●', font = POLICES.petit, text_color = COULEURS[couleur], visible = egal(cleEtat, etat) }
    end
    return f:row {
        spacing = 3,
        f:column(pastilles),
        f:static_text { title = bind(cleTexte), font = POLICES.petit, mouse_down = action, tooltip = infobulle, width = 150, truncation = 'tail' },
    }
end

-- Le bandeau de la ligne du Style, une seule ligne : il remplace la rangée « photos jointes,
-- Retirer » et la ligne de message qui suivaient le champ de demande, pour que le champ finisse au
-- niveau des colonnes voisines. Un clic sur les photos jointes les retire ; sur l'aide, l'affiche
-- en entier.
local function bandeau(f, largeur)
    return f:column {
        place = 'overlapping',
        f:static_text { title = "ajouté à chaque demande, invites comprises", font = POLICES.petit, text_color = COULEURS.gris,
            width = largeur, visible = egal('bandeau', 'rappel') },
        f:static_text { title = bind { key = 'jointes', transform = function(v) return tostring(v or '') .. "  ·  cliquer pour retirer" end },
            font = POLICES.petit, text_color = COULEURS.gris, width = largeur, truncation = 'middle', visible = egal('bandeau', 'jointes'),
            tooltip = "Cliquer pour retirer les photos jointes",
            mouse_down = function()
                Fenetre.annulerEnvoiAuto()
                Fenetre.retirerJointes()
            end },
        f:static_text { title = bind 'message', font = POLICES.petit, text_color = COULEURS.orange, width = largeur, truncation = 'tail',
            visible = egal('bandeau', 'message') },
        f:static_text { title = bind 'aide', font = POLICES.petit, text_color = COULEURS.rouge, width = largeur, truncation = 'tail',
            visible = egal('bandeau', 'aide'), tooltip = "Cliquer pour lire l'aide en entier",
            mouse_down = function()
                Fenetre.annulerEnvoiAuto()
                enTache(Fenetre.montrerAide)
            end },
    }
end

function Fenetre.construire(f, p, T)
    local hauteurFil = T.lignes * 17
    -- Le clic d'un bouton valide aussi le champ de demande : il ne doit pas l'envoyer.
    local function bouton(args)
        local action = args.action
        args.action = function(...)
            Fenetre.annulerEnvoiAuto()
            return action(...)
        end
        return f:push_button(args)
    end

    -- Colonne des conversations.
    local gauche = f:column {
        spacing = 8,
        width = T.liste,
        fill_vertical = 1,
        bouton { title = "Nouvelle conversation", width = T.liste, enabled = bind 'libre',
            action = function()
                Moteur.nouvelle()
                Fenetre.defilement = 0
                Fenetre.indiceImage = nil
                Fenetre.aRafraichir = true
            end },
        f:edit_field { value = bind 'recherche', immediate = true, width = T.liste, placeholder_string = "Rechercher" },
        f:simple_list { items = bind 'listeConversations', value = bind 'selectionListe', allows_multiple_selection = false,
            width = T.liste, height = hauteurFil + 93, enabled = bind 'libre' },
        f:row {
            bouton { title = "Renommer…", size = 'small', action = function() enTache(Fenetre.renommer) end },
            bouton { title = "Supprimer…", size = 'small', enabled = bind 'libre', action = function() enTache(Fenetre.supprimer) end },
        },
    }

    -- Grille du fil.
    local grille = { spacing = 0 }
    for i = 1, T.lignes do
        grille[#grille + 1] = ligneFil(f, i, Fenetre.largeurTexte())
    end

    local invites = { spacing = 6 }
    for _, invite in ipairs(Consignes.invites) do
        invites[#invites + 1] = bouton {
            title = invite.titre,
            tooltip = invite.message,
            enabled = bind 'libre',
            action = function() Fenetre.envoyer(invite.message, invite.modele) end,
        }
    end

    local modeles = {}
    for _, m in ipairs(Consignes.modeles) do
        modeles[#modeles + 1] = { title = m.title, value = m.value }
    end
    local styles = {}
    for _, st in ipairs(Consignes.styles) do
        styles[#styles + 1] = { title = st.title, value = st.value }
    end

    local centre = f:column {
        spacing = 6,
        width = T.fil,
        fill_vertical = 1,
        f:row {
            f:static_text { title = bind 'titre', font = POLICES.titre, width = T.fil - 280, truncation = 'tail' },
            bouton { title = "✎", size = 'small', tooltip = "Renommer la conversation", action = function() enTache(Fenetre.renommer) end },
            f:spacer { fill_horizontal = 1 },
            f:static_text { title = bind 'infoPhoto', text_color = COULEURS.gris, alignment = 'right', width = 210, truncation = 'middle' },
        },
        f:row {
            spacing = 12,
            voyant(f, 'etatClaude', 'texteClaude', nil, "Claude Code, avec votre forfait claude.ai (pas de clé d'API)"),
            voyant(f, 'etatLightroom', 'texteLightroom', function()
                Fenetre.annulerEnvoiAuto()
                Fenetre.demarrerLiaison()
            end, "Liaison de ce module avec le connecteur MCP-Développeur ; arrêtée, un clic la démarre"),
            voyant(f, 'etatMode', 'texteMode', function()
                Fenetre.annulerEnvoiAuto()
                Lightroom.basculerMode()
                Fenetre.rafraichirMode()
            end, "Mode du connecteur ; un clic bascule entre « Proposer d'abord » et « Appliquer directement »"),
        },
        f:separator { fill_horizontal = 1 },
        f:column(grille),
        f:row {
            spacing = 4,
            bouton { title = "▲", size = 'small', tooltip = "Remonter dans le fil", enabled = bind 'peutMonter',
                action = function() Fenetre.defiler(math.floor(T.lignes * 0.8)) end },
            bouton { title = "▼", size = 'small', tooltip = "Redescendre", enabled = bind 'peutDescendre',
                action = function() Fenetre.defiler(-math.floor(T.lignes * 0.8)) end },
            bouton { title = "Fin", size = 'small', tooltip = "Aller au dernier message", enabled = bind 'peutDescendre',
                action = function() Fenetre.defiler('fin') end },
            f:static_text { title = bind 'positionFil', font = POLICES.petit, text_color = COULEURS.gris, width = 150 },
            f:spacer { fill_horizontal = 1 },
            f:column {
                place = 'overlapping',
                f:static_text { title = bind 'activite', text_color = COULEURS.orange, alignment = 'right', width = 300, visible = bind 'travaille' },
                f:static_text { title = bind 'forfait', font = POLICES.petit, text_color = COULEURS.gris, alignment = 'right', width = 300,
                    visible = bind { key = 'travaille', transform = function(v) return not v end } },
            },
        },
        -- Ne grandit que si une autre colonne est plus haute (petite taille). La liste des
        -- conversations (hauteurFil + 93) finit au niveau du champ de demande.
        f:spacer { fill_vertical = 1 },
        f:separator { fill_horizontal = 1 },
        f:row(invites),
        f:row {
            spacing = 8,
            f:static_text { title = "Style" },
            f:popup_menu { items = styles, value = bind 'style', width = 220, enabled = bind 'libre',
                tooltip = "Style de retouche joint à chaque demande (Standard : rien d'ajouté)" },
            bandeau(f, T.fil - 300),
        },
        f:row {
            spacing = 6,
            f:column {
                spacing = 2,
                bouton { title = "📎", tooltip = "Joindre une photo du disque à la demande", enabled = bind 'libre', action = function() enTache(Fenetre.joindre) end },
                bouton { title = "📋", tooltip = "Coller l'image du presse-papiers (capture d'écran, image copiée, photo copiée dans le Finder)", enabled = bind 'libre',
                    action = function() enTache(Fenetre.coller) end },
            },
            f:edit_field { value = bind 'saisie', immediate = false, height_in_lines = 3, width = T.fil - 250, enabled = bind 'libre',
                placeholder_string = "Demander à Claude… (par exemple : « Retouche la photo active, rendu naturel »)",
                tooltip = "Retour envoie la demande. Dictée : touche 🌐 deux fois." },
            f:column {
                spacing = 6,
                f:popup_menu { items = modeles, value = bind 'modele', width = 170, enabled = bind 'libre' },
                bouton { title = bind 'titreEnvoyer', width = 170, action = function() Fenetre.boutonPrincipal() end },
            },
        },
    }

    -- Colonne des aperçus et de la proposition.
    local droite = f:column {
        spacing = 8,
        width = T.droite,
        fill_vertical = 1,
        f:static_text { title = "Ce que Claude voit", font = POLICES.gras },
        f:picture { value = bind 'imageApercu', width = T.apercu, height = T.apercu },
        f:row {
            spacing = 4,
            bouton { title = "◀", size = 'small', enabled = bind 'peutPrecedente', action = function() Fenetre.changerImage(-1) end },
            f:static_text { title = bind 'legendeApercu', font = POLICES.petit, alignment = 'center', width = T.apercu - 80, truncation = 'middle' },
            bouton { title = "▶", size = 'small', enabled = bind 'peutSuivante', action = function() Fenetre.changerImage(1) end },
        },
        bouton { title = "Agrandir", enabled = bind 'aImage', action = function() Fenetre.agrandir() end },
        f:group_box {
            title = "Proposition de Claude",
            width = T.droite,
            f:static_text { title = bind 'propositionTexte', width = T.droite - 24, height_in_lines = 10 },
            f:row {
                spacing = 4,
                bouton { title = "Accepter", enabled = bind 'enAttente', action = function()
                    LrTasks.startAsyncTask(function() Moteur.repondre(true) end)
                end },
                bouton { title = "Refuser", enabled = bind 'enAttente', action = function()
                    LrTasks.startAsyncTask(function() Moteur.repondre(false) end)
                end },
                bouton { title = "Ajuster…", enabled = bind 'enAttente', action = function() enTache(Fenetre.ajuster) end },
            },
        },
        f:row {
            spacing = 6,
            bouton { title = "Publication…", tooltip = "Publier des photos en fichiers, sans Claude ni quota",
                action = function() require('FenetrePublication').afficher() end },
            bouton { title = "Consommation…", tooltip = "Jetons de la semaine, budget, relevé du forfait",
                action = function() require('FenetreConsommation').afficher() end },
        },
        -- Les versions en bas, au niveau du champ de demande.
        f:spacer { fill_vertical = 1 },
        f:separator { fill_horizontal = 1 },
        ligneVersion(f, 1, T.droite),
        ligneVersion(f, 2, T.droite),
    }

    return f:row {
        bind_to_object = p,
        margin = 12,
        spacing = 12,
        gauche,
        f:separator { fill_vertical = 1 },
        centre,
        f:separator { fill_vertical = 1 },
        droite,
    }
end

-- Ouverture -----------------------------------------------------------------------------------

-- Le nom du cadre enregistré de la fenêtre. Lightroom rend sa taille enregistrée à la fenêtre et
-- ne la rapetisse pas quand le contenu devient plus petit (bande vide en bas, constaté) : une
-- taille de fenêtre a son propre cadre, et FORME augmente quand le contenu rapetisse.
Fenetre.FORME = 1

function Fenetre.cadre(taille)
    return 'DeveloppeurClaude-' .. tostring(taille or 'moyenne') .. '-' .. Fenetre.FORME
end

-- Boucle de la fenêtre : rafraîchit ce que le moteur a changé, l'activité, et les voyants.
local function boucle()
    local tic = 0
    while Fenetre.ouverte do
        tic = tic + 1
        local p = Fenetre.p
        if p then
            if Fenetre.aRafraichir then
                Fenetre.aRafraichir = false
                local ok, erreur = LrTasks.pcall(Fenetre.rafraichir)
                if not ok then
                    Journal.noter("Rafraîchissement :", tostring(erreur))
                end
            end
            if Fenetre.photoChangee then
                Fenetre.photoChangee = false
                LrTasks.pcall(Fenetre.majPhoto)
            end
            poser(p, 'activite', Moteur.texteTravail(math.floor(tic / 2)))
            poser(p, 'travaille', Moteur.travaille)
            -- Voyants et photo active toutes les 2 s (la liaison, lue dans ce module sans commande
            -- du système, peut démarrer ou s'arrêter par le menu).
            if tic % 8 == 0 then
                LrTasks.pcall(Fenetre.verifier, false)
                LrTasks.pcall(Fenetre.majPhoto)
            end
        end
        LrTasks.sleep(0.25)
    end
end

function Fenetre.afficher()
    if Fenetre.ouverte then
        if Fenetre.controle and Fenetre.controle.toFront then
            Fenetre.controle.toFront()
        end
        return
    end
    Fenetre.ouverte = true

    LrFunctionContext.postAsyncTaskWithContext('Claude · fenêtre', function(context)
        context:addFailureHandler(function(_, erreur)
            Fenetre.ouverte = false
            Fenetre.p = nil
            Moteur.desabonner('fenetre')
            Journal.noter("Fenêtre :", tostring(erreur))
            LrDialogs.message("La fenêtre Claude n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)

        Moteur.charger()
        local prefs = Chemins.prefs()
        local T = Fenetre.TAILLES[prefs.taille] or Fenetre.TAILLES.moyenne
        Fenetre.T = T
        Fenetre.cache = {}
        Fenetre.vignettes = {}
        Fenetre.conversationAffichee = nil
        Fenetre.signatureListe = nil
        Fenetre.defilement = 0

        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
        p.recherche = ''
        p.saisie = ''
        p.message = ''
        p.jointes = Fenetre.texteJointes()
        p.modele = prefs.modele
        p.style = Consignes.style(prefs.styleChoisi) and prefs.styleChoisi or 'standard'
        p.libre = not Moteur.travaille
        p.travaille = Moteur.travaille
        p.forfait = Moteur.texteForfait()
        p.texteClaude = "Claude Code"
        p.etatClaude = 'neutre'
        p.texteLightroom = "Lightroom"
        p.etatLightroom = 'neutre'
        p.texteMode = ''
        p.etatMode = 'neutre'
        p.infoPhoto = ''
        p.imageApercu = Fenetre.imageVide()
        p.legendeApercu = ''
        p.aide = ''
        p.bandeau = Fenetre.etatBandeau(p)
        for i, l in ipairs(Composants.lignes(Composants.module(), '…')) do
            p['versionNom' .. i], p['version' .. i], p['versionAlerte' .. i] = l.nom, l.version, false
        end
        p.activite = Moteur.texteTravail(0)
        p.listeConversations = {}
        p.selectionListe = {}
        for i = 1, T.lignes do
            p['t' .. i] = ''
            p['g' .. i] = 'vide'
            p['i' .. i] = ''
        end
        Fenetre.p = p

        p:addObserver('selectionListe', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Fenetre.choisirDansListe(valeur)
        end)
        p:addObserver('recherche', function()
            Fenetre.annulerEnvoiAuto()
            Fenetre.rafraichirListe()
        end)
        p:addObserver('modele', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Moteur.changerModele(valeur)
        end)
        p:addObserver('style', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Chemins.prefs().styleChoisi = valeur
        end)
        p:addObserver('saisie', function(_, _, valeur) Fenetre.saisieValidee(valeur) end)
        for _, cle in ipairs({ 'message', 'aide', 'jointes' }) do
            p:addObserver(cle, function(proprietes) poser(proprietes, 'bandeau', Fenetre.etatBandeau(proprietes)) end)
        end

        local contenu = Fenetre.construire(f, p, T)
        Fenetre.rafraichir()
        Fenetre.majPhoto()
        Fenetre.rafraichirMode()
        Moteur.abonner('fenetre', function() Fenetre.aRafraichir = true end)

        LrTasks.startAsyncTask(boucle)
        LrTasks.startAsyncTask(function() LrTasks.pcall(Fenetre.verifier, true) end)

        LrDialogs.presentFloatingDialog(_PLUGIN, {
            title = "Claude",
            contents = contenu,
            save_frame = Fenetre.cadre(prefs.taille),
            blockTask = true,
            onShow = function(controle) Fenetre.controle = controle end,
            selectionChangeObserver = function() Fenetre.photoChangee = true end,
            windowWillClose = function()
                Fenetre.ouverte = false
                Fenetre.annulerEnvoiAuto()
                Fenetre.controle = nil
                Moteur.desabonner('fenetre')
            end,
        })

        -- Au cas où blockTask ne bloquerait pas : garder le contexte (et la table) en vie.
        while Fenetre.ouverte do
            LrTasks.sleep(0.5)
        end
        Fenetre.p = nil
    end)
end

return Fenetre
