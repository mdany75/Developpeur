-- essais-masques-relus.lua : les masques relus après l'écriture (1.6, chantier « masques »), côté
-- module, hors de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua). Après add_mask
-- (commande masquer), les seules formes sans IA (dégradé linéaire, radial, pinceau, plages de
-- couleurs, de luminance ou de profondeur) sont relues et comparées à l'écrit
-- (Locaux.comparerFormes, tolérances provisoires Locaux.TOLERANCES_FORMES) ; verdicts « gardé »,
-- « écart », « absent », « à relire » dans masques_relus ; écarts et absents dits en remarques.
-- Depuis la 1.6.3, un masque en « écart » est retiré (verdict « retiré »), en une écriture
-- « Claude · masque retiré » dans l'étape de Claude, et dit ; ni un absent, ni un « à relire », ni
-- un masque déjà sur la photo. Les masques IA (sujet, ciel, personne, objet) ne se comparent pas.
-- Les écarts viennent de la « version future » de la simulation (S.formesIgnorees,
-- S.arrondiFormes, S.angleFormes), qui n'est pas un constat. Lancé par scripts/tester-module.sh.

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, proche, echoue, contient = A.test, A.egal, A.proche, A.echoue, A.contient

local Json = require 'Json'
local Commandes = require 'Commandes'
local Locaux = require 'Locaux'

-- Un RAW X-H2S de 6240 × 4160, photo active.
local function fuji(id)
    local photo = A.photoFuji()
    if id and id ~= 4 then
        photo = S.Photo(id, photo.reglages, photo.meta, photo.brut)
    end
    S.active, S.selection = photo, { photo }
    return photo
end

-- Des formes « riches » (valeurs à six décimales), sans masque IA : le chemin d'applyDevelopSettings.
local function formes()
    return Json.tableau({
        { type = 'lineaire', de_x = 0.123457, de_y = 0.111111, a_x = 0.876543, a_y = 0.432109, nom = 'Claude · Dégradé',
          locaux = { LocalExposure2012 = -0.2 } },
        { type = 'radial', centre_x = 0.456789, centre_y = 0.512345, rayon_x = 0.123457, angle = -160, fondu = 50,
          nom = 'Claude · Rond', locaux = { LocalExposure2012 = 0.1 } },
        { type = 'pinceau', nom = 'Claude · Pinceau', locaux = { LocalExposure2012 = 0.15 },
          traits = { { points = { { 0.2, 0.3 }, { 0.25, 0.35 } }, rayon = 0.02, flux = 0.7, durete = 30 },
                     { points = { { 0.6, 0.6 }, { 0.62, 0.64 } }, rayon = 0.035 } } },
        { type = 'luminance', min = 0.7, max = 1, fondu = 0.1, nom = 'Claude · Plage', locaux = { LocalHighlights2012 = -0.3 } },
    })
end

local function verdicts(resultat, i)
    local liste = {}
    for _, v in ipairs(resultat.resultats[i or 1].masques_relus or {}) do
        liste[v.nom] = v
    end
    return liste
end

local function remarque(resultat, morceau)
    return contient(resultat.resultats[1].remarques, morceau)
end

-- Les noms des masques de la photo, dans l'ordre.
local function noms(photo)
    local liste = {}
    for _, correction in ipairs(photo.reglages.MaskGroupBasedCorrections or {}) do
        liste[#liste + 1] = correction.CorrectionName
    end
    return table.concat(liste, ', ')
end

test("masques relus : quatre formes gardées telles qu'écrites, sans remarque ni écriture de plus", function()
    local photo = fuji()
    local resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    local relus = resultat.resultats[1].masques_relus
    egal(type(relus), 'table', "masques_relus dans la réponse")
    egal(#relus, 4)
    for _, nom in ipairs({ 'Claude · Dégradé', 'Claude · Rond', 'Claude · Pinceau', 'Claude · Plage' }) do
        egal(verdicts(resultat)[nom].verdict, 'gardé', nom)
        egal(verdicts(resultat)[nom].ecarts, nil, nom .. " : pas d'écarts sur un masque gardé")
    end
    egal(remarque(resultat, "pas gardé tel qu'écrit"), false)
    egal(#S.ecritures, 1, "une seule écriture : celle de l'étape")
    egal(#photo.reglages.MaskGroupBasedCorrections, 4)
    egal(resultat.resultats[1].releve_formes, nil, "le relevé seulement avec releve_formes")
end)

test("masques relus : un arrondi sous la tolérance reste « gardé », au-delà le masque est retiré et dit (1.6.3)", function()
    fuji()
    S.arrondiFormes = 5
    local resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    egal(verdicts(resultat)['Claude · Dégradé'].verdict, 'gardé', "arrondi à 1e-5 : sous la tolérance provisoire")
    egal(verdicts(resultat)['Claude · Pinceau'].verdict, 'gardé')

    local photo = fuji()
    local ecritures = #S.ecritures
    S.arrondiFormes = 2
    resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    local degrade = verdicts(resultat)['Claude · Dégradé']
    egal(degrade.verdict, 'retiré')
    egal(degrade.ecarts[1].genre, 'position', "les écarts restent dans la réponse")
    egal(degrade.ecarts[1].cle, 'ZeroX')
    egal(remarque(resultat, "Masque « Claude · Dégradé » : Lightroom ne l'a pas gardé tel qu'écrit (ZeroX : 0,876543 écrit, 0,88 relu"), true)
    egal(remarque(resultat, "il est retiré, le reste de la retouche est gardé. Le reposer autrement"), true)
    egal(remarque(resultat, "rien n'est retiré"), false)
    egal(verdicts(resultat)['Claude · Plage'].verdict, 'gardé', "la plage n'a rien d'arrondi")
    egal(noms(photo), 'Claude · Plage', "seuls les masques en écart sont retirés")
    egal(#S.ecritures, ecritures + 2, "l'étape, puis une seule écriture de retrait pour la commande")
    egal(S.ecritures[#S.ecritures], 'Claude · masque retiré')
end)

test("masques relus : touches d'un pinceau perdues : « écart » de structure, le pinceau seul est retiré", function()
    local photo = fuji()
    S.formesIgnorees = { 'Dabs' }
    local resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    local pinceau = verdicts(resultat)['Claude · Pinceau']
    egal(pinceau.verdict, 'retiré')
    egal(pinceau.ecarts[1].genre, 'structure')
    egal(pinceau.ecarts[1].cle, 'Dabs')
    egal(pinceau.ecarts[1].relu, 'absent')
    egal(verdicts(resultat)['Claude · Dégradé'].verdict, 'gardé', "les autres formes, gardées")
    egal(remarque(resultat, "Dabs : "), true)
    egal(noms(photo), 'Claude · Dégradé, Claude · Rond, Claude · Plage', "le reste de la retouche reste")
end)

test("masques relus : après un retrait, changements, journal (export_journal) et fenêtre de la liaison disent ce qui reste", function()
    local photo = fuji()
    S.formesIgnorees = { 'Dabs' }
    local resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    egal(verdicts(resultat)['Claude · Pinceau'].verdict, 'retiré')
    local attendu = "3 masques (+ Claude · Dégradé, Claude · Rond, Claude · Plage)"
    local changements = resultat.resultats[1].changements
    egal(#changements, 1)
    egal(changements[1].cle, 'MaskGroupBasedCorrections')
    egal(changements[1].avant, "0 masque")
    egal(changements[1].apres, attendu, "la réponse ne cite plus le masque retiré")
    local journal = Json.decode(photo.proprietes.journalClaude)
    local entree = journal[#journal]
    egal(entree.changements[1].apres, attendu, "le journal ne cite plus le masque retiré")
    egal(entree.note, "Masque retiré après l'écriture (Lightroom ne l'a pas gardé tel qu'écrit) : « Claude · Pinceau ».",
        "le journal dit le retrait")
    egal(tostring(require('Liaison').derniersReglages):find("Claude · Pinceau", 1, true), nil, "fenêtre de la liaison")

    -- Tous les masques ajoutés retirés : plus de changement des masques, le journal le dit.
    photo = fuji()
    S.formesIgnorees = { 'ZeroX' }
    resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.3, nom = 'Claude · Haut', locaux = { LocalExposure2012 = -0.2 } },
    }), etape = 'formes' })
    egal(verdicts(resultat)['Claude · Haut'].verdict, 'retiré')
    egal(#resultat.resultats[1].changements, 0, "aucun masque ajouté ne reste")
    journal = Json.decode(photo.proprietes.journalClaude)
    egal(#journal[#journal].changements, 0)
    egal(contient({ journal[#journal].note }, "« Claude · Haut »"), true)
end)

test("masques relus : retiré dans l'étape de Claude : une seule étape en mémoire, undo_last défait le tout, l'état laissé est sans le masque", function()
    local photo = fuji()
    photo.reglages.Exposure2012 = 0.3
    S.formesIgnorees = { 'Dabs' }
    local resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    local id = resultat.resultats[1].etape_id
    egal(verdicts(resultat)['Claude · Pinceau'].verdict, 'retiré')
    local etapes = Json.decode(photo.proprietes.etapesClaude)
    egal(#etapes, 1, "pas d'étape de mémoire pour le retrait")
    egal(etapes[1].id, id)
    local apres = Json.decode(photo.proprietes.apresClaude)
    egal(apres.reglages['#MaskGroupBasedCorrections'], 3, "l'état laissé par Claude est relu après le retrait")
    local annulation = Commandes.executer('annuler', {})
    egal(annulation.resultats[1].annulee, true)
    egal(annulation.resultats[1].etape_id, id, "undo_last défait l'étape de l'écriture et du retrait")
    egal(#(photo.reglages.MaskGroupBasedCorrections or {}), 0, "aucun masque de l'étape ne reste")
    egal(photo.reglages.Exposure2012, 0.3, "le reste de la photo, intact")
end)

test("masques relus : un masque combiné en écart est retiré avec ses composants ; un masque déjà sur la photo reste", function()
    local photo = fuji()
    Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.3, nom = 'Claude · Haut de Dany', locaux = {} },
    }), etape = 'avant' })
    S.formesIgnorees = { 'ZeroX' }
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'ia', soustype = 2, nom = 'Claude · Ciel sans le bas', locaux = { LocalExposure2012 = -0.1 },
          composants = { { mode = 'soustraire', type = 'lineaire', de_x = 0.5, de_y = 1, a_x = 0.5, a_y = 0.7, nom = 'Bas' } } },
        { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } },
    }), etape = 'masques' })
    egal(verdicts(resultat)['Claude · Ciel sans le bas'].verdict, 'retiré')
    egal(verdicts(resultat)['Claude · Ciel'], nil, "un masque IA seul n'est pas relu")
    egal(remarque(resultat, "il est retiré avec ses composants"), true)
    egal(noms(photo), 'Claude · Haut de Dany, Claude · Ciel', "le masque déjà là (même perdu par la version future) et le ciel restent")
end)

test("masques relus : retrait refusé par Lightroom : verdict « écart », retrait « échoué », dit, rien d'autre ne casse", function()
    local photo = fuji()
    S.formesIgnorees, S.retraitMasques = { 'Dabs' }, 'erreur'
    local resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    local pinceau = verdicts(resultat)['Claude · Pinceau']
    egal(pinceau.verdict, 'écart')
    egal(pinceau.retrait, 'échoué')
    egal(remarque(resultat, "et ne l'a pas laissé retirer (Lightroom refuse cette liste de masques"), true)
    egal(remarque(resultat, "undo_last défait toute l'étape"), true)
    egal(#photo.reglages.MaskGroupBasedCorrections, 4, "l'étape reste entière")
    egal(type(resultat.resultats[1].etape_id), 'string', "la réponse de l'étape est rendue")

    photo = fuji()
    S.retraitMasques = 'ignore'
    resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    egal(verdicts(resultat)['Claude · Pinceau'].retrait, 'échoué', "un masque encore là après le retrait : relu, et dit")
    egal(remarque(resultat, "et ne l'a pas laissé retirer ;"), true)
    egal(#photo.reglages.MaskGroupBasedCorrections, 4)
end)

test("masques relus : l'angle d'un radial se compare modulo 180 (−160° rangé 20° : gardé)", function()
    fuji()
    S.angleFormes = true
    local resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    egal(verdicts(resultat)['Claude · Rond'].verdict, 'gardé')
end)

test("masques relus : un radial à 170° sur une photo recadrée de 20° s'écrit 190°, rangé 10° : gardé", function()
    -- Le seul chemin vers un angle hors de ±180 : l'angle du recadrage ajouté (Plans.lua), le
    -- serveur refusant tout angle hors de −180…180.
    local photo = fuji()
    photo.reglages.CropAngle = 20
    S.angleFormes = true
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'radial', centre_x = 0.5, centre_y = 0.5, rayon_x = 0.2, angle = 170, nom = 'Claude · Rond penché',
          locaux = { LocalExposure2012 = 0.1 } },
    }), etape = 'formes' })
    local masque = photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1]
    proche(masque.Angle, 10, "190° rangé modulo 180 par la version future simulée")
    egal(verdicts(resultat)['Claude · Rond penché'].verdict, 'gardé')
end)

test("masques relus : les masques IA (ciel, objet) ne se comparent pas ; un ciel combiné à un dégradé, si", function()
    local photo = fuji()
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } },
        { type = 'objet', nom = 'Claude · Objet', locaux = { LocalExposure2012 = 0.1 },
          traits = { { points = { { 0.3, 0.3 }, { 0.32, 0.31 } }, rayon = 0.008 } } },
        { type = 'ia', soustype = 2, nom = 'Claude · Ciel sans le bas', locaux = { LocalExposure2012 = -0.1 },
          composants = { { mode = 'soustraire', type = 'lineaire', de_x = 0.5, de_y = 1, a_x = 0.5, a_y = 0.7, nom = 'Bas' } } },
        { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.4, nom = 'Claude · Dégradé', locaux = {} },
    }), etape = 'masques' })
    local relus = verdicts(resultat)
    egal(relus['Claude · Ciel'], nil, "un masque IA seul n'est pas relu")
    egal(relus['Claude · Objet'], nil, "un objet (Mask/Image, ReferencePoint réécrit) n'est pas relu")
    egal(relus['Claude · Ciel sans le bas'].verdict, 'gardé', "son dégradé se relit")
    egal(relus['Claude · Dégradé'].verdict, 'gardé', "chemin du paramètre prédéfini")
    egal(#photo.reglages.MaskGroupBasedCorrections, 4)
end)

test("masques relus : masques IA pas encore calculés : « à relire », sans remarque", function()
    fuji()
    S.calculDiffere, S.jamaisCalcule, S.modelesIAAbsents = true, true, true
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } },
        { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.4, nom = 'Claude · Dégradé', locaux = {} },
    }), etape = 'masques' })
    egal(verdicts(resultat)['Claude · Dégradé'].verdict, 'à relire')
    egal(remarque(resultat, "pas gardé tel qu'écrit"), false)
end)

test("masques relus : une correction que Lightroom n'a pas gardée est « absent », et dite", function()
    local photo = fuji()
    S.pendantAttente = function()
        local liste = photo.reglages.MaskGroupBasedCorrections or {}
        for i = #liste, 1, -1 do
            if liste[i].CorrectionName == 'Claude · Dégradé' then
                table.remove(liste, i)
            end
        end
    end
    local resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    egal(verdicts(resultat)['Claude · Dégradé'].verdict, 'absent')
    egal(remarque(resultat, "Masque « Claude · Dégradé » : absent après l'écriture"), true)
    egal(verdicts(resultat)['Claude · Rond'].verdict, 'gardé')
    egal(#photo.reglages.MaskGroupBasedCorrections, 3, "rien de plus n'est retiré")
    egal(S.ecritures[#S.ecritures] ~= 'Claude · masque retiré', true, "aucune écriture de retrait")
end)

test("masques relus : une liste encore changeante après les relectures dit « à relire », en quatre lectures au plus", function()
    local photo = fuji()
    S.pendantAttente = function()
        for _, correction in ipairs(photo.reglages.MaskGroupBasedCorrections or {}) do
            local m = correction.CorrectionMasks[1]
            if m.What == 'Mask/Gradient' then
                m.ZeroX = m.ZeroX + 0.01
            end
        end
    end
    local avant = S.attentes
    local resultat = Commandes.executer('masquer', { masques = formes(), etape = 'formes' })
    egal(verdicts(resultat)['Claude · Dégradé'].verdict, 'à relire')
    egal(verdicts(resultat)['Claude · Dégradé'].ecarts[1].cle, 'ZeroX', "l'écart vu reste dit")
    egal(remarque(resultat, "pas retiré : Lightroom le calculait encore"), true)
    egal(#photo.reglages.MaskGroupBasedCorrections, 4, "un masque « à relire » n'est jamais retiré")
    egal(S.attentes - avant, 3, "trois attentes de 0,3 s au plus pour toute la commande")
end)

test("masques relus : deux photos, chacune ses verdicts, une seule attente pour la commande", function()
    local p5 = fuji(5)
    local p4 = fuji()
    local avant = S.attentes
    local resultat = Commandes.executer('masquer', { photos = { 4, 5 }, masques = formes(), etape = 'formes' })
    egal(#resultat.resultats, 2)
    egal(#resultat.resultats[1].masques_relus, 4)
    egal(#resultat.resultats[2].masques_relus, 4)
    egal(verdicts(resultat, 2)['Claude · Pinceau'].verdict, 'gardé')
    egal(S.attentes - avant, 1, "une lecture, une attente, une seconde lecture, pour les deux photos")
    egal(#p4.reglages.MaskGroupBasedCorrections, 4)
    egal(#p5.reglages.MaskGroupBasedCorrections, 4)
end)

test("masques relus : releve_formes (développement) rend l'écrit et le relu de chaque masque, IA compris", function()
    fuji()
    local resultat = Commandes.executer('masquer', { releve_formes = true, masques = Json.tableau({
        { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } },
        { type = 'lineaire', de_x = 0.123457, de_y = 0, a_x = 0.5, a_y = 0.4, nom = 'Claude · Dégradé', locaux = {} },
    }), etape = 'masques' })
    local releve = resultat.resultats[1].releve_formes
    egal(#releve, 2)
    egal(releve[1].nom, 'Claude · Ciel')
    egal(releve[1].compare, false, "un masque IA est relevé, pas comparé")
    egal(releve[1].relu[1].MaskDigest ~= nil, true, "le relu porte ce que Lightroom a calculé")
    egal(releve[2].compare, true)
    proche(releve[2].ecrit[1].FullX, 0.123457 * 1)
    egal(type(releve[2].correction_id), 'string')
    egal(Json.decode(Json.encode(resultat)) ~= nil, true, "le relevé passe en JSON")
end)

test("Locaux.comparerFormes : IA ignorée, angle modulo 180, booléens 0/1, touches, couleurs, plages, tolérances", function()
    local tol = Locaux.TOLERANCES_FORMES
    egal(tol.provisoires, false, "tolérances constatées le 2 novembre 2026")
    proche(tol.position, 4e-5, "10 fois l'écart maximal relevé (4e-6 : six chiffres significatifs)")
    -- Un objet dont Lightroom a déplacé ReferencePoint et retiré le geste : pas comparé.
    local objet = { What = 'Mask/Image', ReferencePoint = '0.200000 0.300000', Gesture = { { What = 'Mask/Paint' } } }
    egal(#Locaux.comparerFormes({ objet }, { { What = 'Mask/Image', ReferencePoint = '0.500000 0.500000' } }), 0)
    -- Radial : 200° (possible par l'angle du recadrage ajouté) rangé 20° ou −160°, gardé ; 110°, écart d'angle.
    local radial = { What = 'Mask/CircularGradient', Left = 0.1, Top = 0.2, Right = 0.3, Bottom = 0.4, Angle = 200, Feather = 50,
        Midpoint = 50, Roundness = 0, Flipped = true, MaskInverted = false }
    local function avec(base, changes)
        local copie = {}
        for k, v in pairs(base) do copie[k] = v end
        for k, v in pairs(changes) do copie[k] = v end
        return copie
    end
    egal(#Locaux.comparerFormes({ radial }, { avec(radial, { Angle = 20 }) }), 0)
    egal(#Locaux.comparerFormes({ radial }, { avec(radial, { Angle = -160 }) }), 0)
    local e = Locaux.comparerFormes({ radial }, { avec(radial, { Angle = 110 }) })
    egal(#e, 1) egal(e[1].genre, 'angle') proche(e[1].ecart, 90)
    -- Booléens rangés 1 ou 0 : pareils ; Flipped perdu : structure.
    egal(#Locaux.comparerFormes({ radial }, { avec(radial, { Flipped = 1, MaskInverted = 0 }) }), 0)
    egal(Locaux.comparerFormes({ radial }, { avec(radial, { MaskInverted = true }) })[1].cle, 'MaskInverted')
    -- Position : sous la tolérance, rien ; au-delà, écart.
    egal(#Locaux.comparerFormes({ radial }, { avec(radial, { Left = 0.1 + tol.position / 2 }) }), 0)
    egal(Locaux.comparerFormes({ radial }, { avec(radial, { Left = 0.1 + tol.position * 2 }) })[1].cle, 'Left')
    -- Fondu : écart relatif.
    egal(#Locaux.comparerFormes({ radial }, { avec(radial, { Feather = 50.01 }) }), 0)
    egal(Locaux.comparerFormes({ radial }, { avec(radial, { Feather = 51 }) })[1].genre, 'valeur')
    -- Une valeur sous 1 se compare aussi en relatif : flux 0,7 relu 0,7008 (0,11 %), écart.
    local flux = { What = 'Mask/Paint', Flow = 0.7 }
    egal(Locaux.comparerFormes({ flux }, { avec(flux, { Flow = 0.7008 }) })[1].genre, 'valeur')
    egal(#Locaux.comparerFormes({ flux }, { avec(flux, { Flow = 0.7004 }) }), 0, "0,06 % : gardé")
    -- Pinceau : traits et touches.
    local trait = { What = 'Mask/Paint', Radius = 0.02, Flow = 0.7, CenterWeight = 0.3,
        Dabs = { 'r 0.020000', 'f 0.7000', 'h 0.3000', 'd 0.200000 0.300000', 'd 0.210000 0.310000' } }
    local pinceau = { What = 'Mask/Aggregate', MaskInverted = false, Masks = { trait } }
    egal(#Locaux.comparerFormes({ pinceau }, { pinceau }), 0)
    local moins = avec(trait, { Dabs = { 'r 0.020000', 'f 0.7000', 'h 0.3000', 'd 0.200000 0.300000' } })
    e = Locaux.comparerFormes({ pinceau }, { avec(pinceau, { Masks = { moins } }) })
    egal(e[1].cle, 'Dabs') egal(e[1].genre, 'structure') egal(e[1].composant, '1.1')
    local deplace = avec(trait, { Dabs = { 'r 0.020000', 'f 0.7000', 'h 0.3000', 'd 0.200000 0.300000', 'd 0.215000 0.310000' } })
    e = Locaux.comparerFormes({ pinceau }, { avec(pinceau, { Masks = { deplace } }) })
    egal(e[1].cle, 'Dabs[5]') egal(e[1].genre, 'position')
    -- Rayon d'un pinceau fin (part du grand côté) : 0,005 relu 0,0059 (18 % plus large), écart de
    -- position sur Radius ; la touche « r » ne se compare pas (Lightroom la retire au calcul).
    local fin = avec(trait, { Radius = 0.005, Dabs = { 'r 0.005000', 'f 0.7000', 'h 0.3000', 'd 0.200000 0.300000', 'd 0.210000 0.310000' } })
    local large = avec(fin, { Radius = 0.0059, Dabs = { 'r 0.005900', 'f 0.7000', 'h 0.3000', 'd 0.200000 0.300000', 'd 0.210000 0.310000' } })
    e = Locaux.comparerFormes({ avec(pinceau, { Masks = { fin } }) }, { avec(pinceau, { Masks = { large } }) })
    egal(#e, 1) egal(e[1].cle, 'Radius') egal(e[1].genre, 'position')
    egal(#Locaux.comparerFormes({ avec(pinceau, { Masks = { fin } }) }, { avec(pinceau, { Masks = { avec(fin, { Radius = 0.005004 }) } }) }), 0,
        "0,02 px sur 6240 : gardé")
    e = Locaux.comparerFormes({ pinceau }, { avec(pinceau, { Masks = {} }) })
    egal(e[1].cle, 'Masks')
    local auto = avec(trait, { Dabs = { 'r 0.020000', 'f 0.7000', 'h 0.3000', 'M 0.200000 0.300000', 'd 0.210000 0.310000' } })
    egal(Locaux.comparerFormes({ pinceau }, { avec(pinceau, { Masks = { auto } }) })[1].genre, 'structure', "une autre lettre de touche")
    -- Plage de couleurs : position du prélèvement, modèle ; plage de luminance.
    local couleur = { What = 'Mask/RangeMask', CorrectionReferenceX = 0.3, CorrectionReferenceY = 0.4,
        CorrectionRangeMask = { Type = 1, ColorAmount = 0.5, PointModels = { '0.100000 0.200000 0.300000 0.300000 0.400000 0' } } }
    egal(#Locaux.comparerFormes({ couleur }, { couleur }), 0)
    local autre = avec(couleur, { CorrectionRangeMask = { Type = 1, ColorAmount = 0.5, PointModels = { '0.100000 0.200000 0.300000 0.350000 0.400000 0' } } })
    e = Locaux.comparerFormes({ couleur }, { autre })
    egal(e[1].cle, 'PointModels[1][4]') egal(e[1].genre, 'position')
    egal(Locaux.comparerFormes({ couleur }, { avec(couleur, { CorrectionRangeMask = { Type = 2 } }) })[1].cle, 'CorrectionRangeMask.Type')
    local lum = { What = 'Mask/RangeMask', CorrectionRangeMask = { Type = 2, LumRange = '0.600000 0.700000 1.000000 1.000000' } }
    egal(#Locaux.comparerFormes({ lum }, { lum }), 0)
    egal(Locaux.comparerFormes({ lum }, { avec(lum, { CorrectionRangeMask = { Type = 2, LumRange = '0.6 0.7 1' } }) })[1].genre, 'structure')
    -- Autre nombre de composants, autre forme.
    egal(Locaux.comparerFormes({ radial, lum }, { radial })[1].cle, 'CorrectionMasks')
    egal(Locaux.comparerFormes({ radial }, { lum })[1].cle, 'What')
    -- Clé de position perdue.
    local lineaire = { What = 'Mask/Gradient', ZeroX = 0.5, ZeroY = 0.4, FullX = 0.5, FullY = 0 }
    e = Locaux.comparerFormes({ lineaire }, { avec(lineaire, { ZeroX = false }) })
    egal(e[1].cle, 'ZeroX') egal(e[1].genre, 'structure')
end)

-- Constats du 2 novembre 2026 (Lightroom Classic 15.6, relevé DEVELOPPEUR_RELEVE_FORMES sur des
-- copies d'Essais) : au calcul du masque, Lightroom retire les touches « r » et « h », range Flipped
-- faux sur un radial inversé, retire CorrectionReferenceX/Y d'une plage de couleurs, range un long
-- pinceau en table compressée, garde six chiffres significatifs ; rien n'est borné ; l'angle reste
-- tel qu'écrit. Aucune de ces formes calculées n'est un écart.
local function formesConstat()
    return Json.tableau({
        { type = 'radial', centre_x = 0.543211, centre_y = 0.487655, rayon_x = 0.234567, angle = -30, fondu = 37,
          inverser = true, nom = 'Claude · Rond inversé', locaux = { LocalExposure2012 = -0.1 } },
        { type = 'pinceau', nom = 'Claude · Pinceau', locaux = { LocalExposure2012 = 0.15 },
          traits = { { points = { { 0.2, 0.3 }, { 0.234567, 0.345678 } }, rayon = 0.02, flux = 0.7, durete = 30 },
                     { points = { { 0.6, 0.6 }, { 0.62, 0.64 } }, rayon = 0.035, flux = 0.7, durete = 30 } } },
        { type = 'pinceau', nom = 'Claude · Pinceau auto', locaux = { LocalExposure2012 = 0.1 }, auto = true,
          traits = { { points = { { 0.41, 0.62 }, { 0.456789, 0.654321 } }, rayon = 0.015, flux = 0.55, durete = 80 } } },
        { type = 'luminance', min = 0.7, max = 1, fondu = 0.1, nom = 'Claude · Plage', locaux = { LocalHighlights2012 = -0.3 } },
        { type = 'lineaire', de_x = -0.05, de_y = -0.05, a_x = 1.000646, a_y = 1.05, nom = 'Claude · Hors image', locaux = {} },
    })
end

-- Recette de la 1.6.6 (2 novembre 2026 au soir, DSCF2402, relevé DEVELOPPEUR_RELEVE_FORMES) : un trait
-- dur au flux 1 revenait sans sa touche « f 1.0000 », 98 touches pour 99, et le pinceau était retiré
-- à tort comme mal gardé.
test("masques relus (constat 15.6) : un pinceau au flux 1 perd sa touche « f » au calcul : gardé", function()
    local photo = fuji()
    S.negatifCharge = true
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'pinceau', nom = 'Claude · Trait dur', locaux = { LocalExposure2012 = -2 },
          traits = { { points = { { 0.3, 0.5 }, { 0.7, 0.5 } }, rayon = 0.02, flux = 1, durete = 100 } } },
    }), etape = 'trait dur' })
    local trait = photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].Masks[1]
    egal(tostring(trait.Dabs[1]):sub(1, 1), 'd', "simulation : « f 1.0000 » retiré aussi")
    egal(verdicts(resultat)['Claude · Trait dur'].verdict, 'gardé')
    egal(#photo.reglages.MaskGroupBasedCorrections, 1, "le pinceau reste")
end)

test("masques relus (constat 15.6) : formes calculées dès l'écriture (négatif chargé) : toutes gardées", function()
    local photo = fuji()
    S.negatifCharge = true
    local resultat = Commandes.executer('masquer', { masques = formesConstat(), etape = 'formes' })
    local corrections = photo.reglages.MaskGroupBasedCorrections
    local inverse = corrections[1].CorrectionMasks[1]
    egal(inverse.Flipped, false, "simulation : Flipped rangé faux sur le radial inversé")
    egal(inverse.MaskInverted, true)
    local trait = corrections[2].CorrectionMasks[1].Masks[1]
    egal(tostring(trait.Dabs[1]):sub(1, 1), 'f', "simulation : touches « r » et « h » retirées")
    egal(corrections[4].CorrectionMasks[1].CorrectionRangeMask.LuminanceDepthSampleInfo ~= nil, true)
    proche(corrections[5].CorrectionMasks[1].ZeroX, 1.00065, "six chiffres significatifs, pas de bornage")
    for _, nom in ipairs({ 'Claude · Rond inversé', 'Claude · Pinceau', 'Claude · Pinceau auto', 'Claude · Plage', 'Claude · Hors image' }) do
        egal(verdicts(resultat)[nom].verdict, 'gardé', nom)
    end
    egal(remarque(resultat, "pas gardé tel qu'écrit"), false)
end)

test("masques relus (constat 15.6) : sans calcul à l'écriture, les mêmes formes restent gardées telles qu'écrites", function()
    local photo = fuji()
    local resultat = Commandes.executer('masquer', { masques = formesConstat(), etape = 'formes' })
    egal(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].Flipped, true, "rangé tel qu'écrit")
    for _, v in ipairs(resultat.resultats[1].masques_relus) do
        egal(v.verdict, 'gardé', v.nom)
    end
end)

test("masques relus (constat 15.6) : chemin du paramètre prédéfini, plage de couleurs sans CorrectionReferenceX/Y : gardée", function()
    local photo = fuji()
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } },
        { type = 'couleur', prelevements = { { x = 0.4997944, y = 0.2099602, modele = { 0.67433, 0.457151, 0.427596 } } }, etendue = 0.37, nom = 'Claude · Couleur',
          locaux = { LocalSaturation = -0.05 } },
        { type = 'pinceau', nom = 'Claude · Pinceau', locaux = { LocalExposure2012 = 0.15 },
          traits = { { points = { { 0.2, 0.3 }, { 0.25, 0.35 } }, rayon = 0.02, flux = 0.7, durete = 30 } } },
    }), etape = 'masques' })
    local couleur
    for _, c in ipairs(photo.reglages.MaskGroupBasedCorrections) do
        if c.CorrectionName == 'Claude · Couleur' then couleur = c.CorrectionMasks[1] end
    end
    egal(couleur.CorrectionReferenceX, nil, "simulation : retiré au calcul")
    egal(verdicts(resultat)['Claude · Couleur'].verdict, 'gardé')
    egal(verdicts(resultat)['Claude · Pinceau'].verdict, 'gardé')
end)

test("masques relus (constat 15.6) : un long trait rangé en table compressée (MaskBrushTable) : gardé, traits non relus", function()
    local photo = fuji()
    S.negatifCharge, S.seuilTableBrosse = true, 20
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'pinceau', nom = 'Claude · Bord', locaux = { LocalExposure2012 = 0.1 },
          traits = { { points = { { 0.02, 0.02 }, { 0.98, 0.02 }, { 0.98, 0.98 } }, rayon = 0.02, flux = 0.7, durete = 30 } } },
    }), etape = 'formes' })
    local agregat = photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1]
    egal(agregat.Masks, nil, "simulation : traits compressés")
    egal(agregat.MaskBrushTable ~= nil, true)
    egal(verdicts(resultat)['Claude · Bord'].verdict, 'gardé')
end)

test("masques relus (constat 15.6) : un radial à 170° sur une photo recadrée de 20° s'écrit et se range 190°", function()
    local photo = fuji()
    photo.reglages.CropAngle = 20
    S.negatifCharge = true
    local resultat = Commandes.executer('masquer', { masques = Json.tableau({
        { type = 'radial', centre_x = 0.5, centre_y = 0.5, rayon_x = 0.2, angle = 170, nom = 'Claude · Rond penché',
          locaux = { LocalExposure2012 = 0.1 } },
    }), etape = 'formes' })
    proche(photo.reglages.MaskGroupBasedCorrections[1].CorrectionMasks[1].Angle, 190, "angle gardé tel qu'écrit")
    egal(verdicts(resultat)['Claude · Rond penché'].verdict, 'gardé')
end)

A.bilan()
