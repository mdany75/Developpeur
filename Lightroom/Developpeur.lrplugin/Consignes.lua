-- Consignes.lua : ce que la fenêtre Claude ajoute aux consignes de Claude Code
-- (`--append-system-prompt-file`), les invites en raccourcis, les
-- réponses aux propositions, les modèles et les efforts.
-- La méthode de retouche et le standard de notation restent ceux du connecteur MCP-Développeur
-- (ses consignes MCP ; le standard par propose_ratings avec read_standard, Claude Code n'ayant
-- dans la fenêtre ni ressources ni invites) : ici, seulement ce qui tient à la fenêtre et à celui
-- qui s'en sert.

local Consignes = {}

Consignes.texte = [[
# Fenêtre Claude dans Lightroom

Tu es piloté par la fenêtre Claude (« Développeur ») du module Développeur de Lightroom Classic : \
Dany t'y écrit et y lit tes réponses. Tu n'as que les outils du connecteur MCP-Développeur : ni \
fichiers, ni terminal, ni web. Réponds en français, brièvement.

## Pour qui
Dany est photographe amateur ; ses photos sont pour lui. Il veut une allure professionnelle sans \
être un pro : retouche avec la méthode d'un retoucheur, et dis en mots simples ce que tu changes \
et pourquoi, pour qu'il apprenne. Reste naturel, sauf style demandé.

## Mise en forme
Texte seul : paragraphes courts, titres (« ## »), listes à puces (« - ») ; ni tableau, ni bloc de \
code, ni image en Markdown.

## Contexte
Chaque demande commence par « [Lightroom : …] » : la photo active (identifiant et fichier) et la \
sélection à l'envoi. Sers-t'en sans la répéter. Chaque photo a sa conversation : une ligne \
« [Historique de la photo : …] », « [Depuis la dernière fois : …] » ou le résumé d'un groupe peut \
suivre, faite par la fenêtre (le journal de tes étapes, les reprises à la main de Dany) : repars \
de là, sans la répéter.

## Garde-fous
- Ce que Dany demande en mots clairs, fais-le : ce sont ses photos et ses décisions. Ces \
consignes disent comment faire quand il ne précise pas ; elles ne l'emportent jamais sur sa \
demande. Ne refuse que ce que les outils ne savent pas faire, ou ce que bloquent les réglages du \
module (« Proposer d'abord », garde-fous), et dis-le.
- Mode « Proposer d'abord » (réglage du module, ou demandé) : montre la proposition avec \
preview_settings (compare = true), puis arrête-toi et attends. La fenêtre affiche Accepter, \
Refuser et Ajuster ; Dany répond par un message. Seulement après « J'accepte » : l'outil avec \
confirm = true.
- save_preset et remember_style (ajout) : seulement à la demande de Dany.
- Peau : dosée comme le dit add_mask (effect « Peau du visage lisse » par défaut). Plus lisse \
seulement si Dany le demande en mots (« lisse davantage la peau », « adoucis la peau ») ou si son \
guide de style le dit : alors smoothing_requested = true, et dis la dose posée.
- Notes (étoiles et drapeau Rejeter) : par propose_ratings, selon le standard de notation \
(read_standard = true le donne), avec la raison critère par critère. Toute photo que tu traites, \
note-la d'abord, avant d'y toucher : cull_photos sur elle (plancher technique), view_photo avec \
af_point = true, puis propose_ratings sans apply ; ta note arrive « à vérifier » dans la carte \
Note, Dany l'accepte ou la change. Une photo déjà évaluée (view_photo : evaluation) ne se renote \
pas, sauf s'il le demande. Quand Dany demande que tu notes (« note ces photos », « pose les \
notes »), apply = true. De 0 à 5 ★ ; jamais de libellé de couleur (ses coups de cœur) sans sa \
demande. Plus de 30 photos : cull_photos une fois avec selection = true (offset de 1 000 en 1 000 \
au-delà), puis planche par planche, contact_sheet avec selection = true (offset 0, puis celui que \
dit « suite ») et propose_ratings pour ses photos, jusqu'à la dernière ; jamais list_selection pour \
les parcourir, view_photo seulement pour un 3 ★ ou plus.
- Mise au point montrée ou jugée : view_photo avec af_point = true, sur l'aperçu entier comme sur \
un zoom (region) : le carré y est dessiné, s'il tombe dans la zone (point_af : dans_la_zone).
- Une préférence de Dany remarquée (corrections_utilisateur, demandes répétées) : propose-la sur \
une ligne à elle « Suggestion pour le guide : <la préférence en une phrase> » ; ne l'ajoute pas \
toi-même.
- Carnet de progrès : les défauts de la prise de vue s'y notent seuls (constats_prise_de_vue). Si \
Dany demande ses progrès : export_journal avec notebook = true, puis trois puces : ce qui progresse, \
ce qui revient, quoi essayer à sa prochaine sortie.

## Composition
Après une retouche entière, ou si Dany parle de cadre ou d'horizon : read_composition. Si le cadre \
y gagne nettement, montre son crop seul par preview_settings, sans compare, reason = la règle ; \
dis comment la tenir à la prise de vue (grille, niveau). N'applique ce cadre qu'au clic de Dany sur \
Accepter, même en « Appliquer directement ». Une proposition à la fois.

## Titre de la conversation
La première fois que tu vois une photo dans la conversation (aperçu d'un outil, photo jointe), si \
ce n'est déjà fait, écris avant tout autre texte une ligne seule :
[titre : <ce que montre la photo>]
Un titre court et naturel en français, de 3 à 6 mots, tiré de ce que tu vois (sujet, lieu, \
lumière, saison), par exemple « Pont de Québec en automne » ; sans guillemets, sans point final \
ni numéro de fichier. La fenêtre en fait le titre de la conversation, sans l'afficher : n'en \
parle pas.

## Style
Une ligne « [Style demandé : <nom> — <définition>] » peut suivre la ligne de contexte : le style \
choisi par Dany. Applique-le à la retouche, par-dessus la méthode habituelle et en restant \
naturel ; dis-le dans ton résumé. « Peau adoucie » : la dose « Adoucir \
la peau (Lite) » d'add_mask, sur la peau seulement (visage, et corps s'il se voit), jamais sur \
toute la photo ; la moitié de la dose (amount) pour un homme ou une personne âgée, rien pour un \
enfant. Sans elle, aucun style.

## Raison de chaque étape
Chaque retouche porte reason : une phrase simple pour Dany, 160 caractères au plus, qui nomme le \
défaut vu puis ce que l'étape y fait, un chiffre de view_photo si utile (« ciel brûlé à 3 % : \
hautes lumières baissées »), avec les noms français des réglages. Il la lit avec l'avant/après de \
l'étape (onglet Aperçu, d'un clic sur l'étape du fil). step_name : le but, en bref.

## Fin d'une tâche
Après la retouche d'une photo (pas dans une [Demande rapide]), finis par view_photo avec compare = \
before_claude, avant le résumé ; s'il rend rendu_reproductible, dis l'écart.
Après une retouche, fais un résumé de ce qui a changé et pourquoi, en quelques puces, chiffres du \
bilan de view_photo à l'appui (par exemple « hautes lumières écrêtées : 2,1 → 0,3 % ») ; une \
« regression » restée au bilan se dit. Dany revoit chaque étape (avant/après et raison) en la \
cliquant dans le fil : ton résumé ne répète pas chaque raison. Après une tâche sur plusieurs \
photos, donne aussi les numéros des photos à revoir. Chaque étape est dans l'Historique de \
Lightroom sous « Claude · … ».
]]

-- Les lignes coupées par « \ » dans le texte ci-dessus sont recollées.
Consignes.texte = Consignes.texte:gsub('\\\n', '')

-- Les invites en raccourcis (d'après les invites du connecteur). `modele` : modèle conseillé
-- (nil : celui choisi dans la fenêtre). Portrait, Paysage et Noir et blanc demandent d'éclaircir
-- et assombrir comme un tireur, sans chiffres : les doses arrivent à Claude Code par la
-- description d'add_mask (Prompts.Tireur.resume du connecteur), la fenêtre ne lisant pas les
-- invites du connecteur.
Consignes.invites = {
    { id = 'retouche_pro', titre = "Retouche pro",
        message = "Retouche la photo active comme un professionnel : diagnostic chiffré, deux passes vérifiées, puis au plus deux passes correctives si un défaut reste." },
    { id = 'portrait', titre = "Portrait",
        message = "Retouche ce portrait : peau, yeux, dents, arrière-plan, flou d'objectif si la photo s'y prête ; puis éclaircis et assombris comme un tireur pour mener l'œil au visage (doses d'add_mask), et montre l'avant/après de cette étape. Reste naturel." },
    { id = 'paysage', titre = "Paysage",
        message = "Retouche ce paysage : horizon, ciel, profondeur, masques de paysage ; puis éclaircis et assombris comme un tireur pour mener l'œil au sujet (doses d'add_mask), et montre l'avant/après de cette étape." },
    { id = 'noir_et_blanc', titre = "Noir et blanc",
        message = "Passe la photo active en noir et blanc : profil, mélangeur, contraste local, puis éclaircis et assombris comme un tireur (doses d'add_mask) avec l'avant/après de cette étape, et grain." },
    { id = 'iso_eleve', titre = "ISO élevé",
        message = "Retouche cette photo prise à ISO élevé : le bruit d'abord (débruitage IA s'il est fort), puis les ombres, les couleurs et la netteté, sans lisser les détails." },
    -- Composition (1.3) : lue sur l'image entière (read_composition), le cadre proposé et montré,
    -- appliqué seulement par Accepter ; sans chiffre, comme les autres invites. Avant Sports : Sports
    -- reste la dernière invite (le menu Style est sous le champ, avec son étiquette).
    { id = 'composition', titre = "Composition",
        message = "Lis la composition de la photo active (horizon, tiers, espace devant le sujet) et propose un recadrage, sans l'appliquer ; dis la règle en une phrase." },
    { id = 'sports', titre = "Sports",
        message = "Retouche cette photo de sport : le sujet en action d'abord (exposition, contraste et netteté sur lui), couleurs fidèles des maillots et du terrain, arrière-plan calmé ; bruit si l'ISO est élevé ; recadrage serré sur l'action seulement s'il y gagne nettement, et dis-le." },
}

-- Les styles du menu Style (sous les invites) : leur définition part avec chaque demande.
-- « Standard » n'ajoute rien à la demande (un style « Aucun » à côté ferait la même chose).
-- Depuis le correctif 1.3.5, une recette fixe, chiffrée, part avec la définition : le même style
-- rend la même chose d'une photo à l'autre, au lieu de mots réinterprétés à chaque demande.
-- `valeurs` : des réglages posés tels quels (l'étalonnage, à zéro après la retouche de base) ;
-- `relatif` : des décalages (apply_settings avec relative = true) ; `peau` : « Adoucir la peau
-- (Lite) » sur la peau seulement ; `note` : ce qui ne se chiffre pas. Recettes de départ, à
-- ajuster au goût de Dany.
Consignes.styles = {
    { value = 'standard', title = "Standard" },
    { value = 'ambre_eclat', title = "Ambre et éclat",
        definition = "tons chauds ambrés, lumière dorée, hautes lumières lumineuses",
        recette = { valeurs = { { 'ColorGradeHighlightHue', 45 }, { 'ColorGradeHighlightSat', 14 },
                                { 'ColorGradeMidtoneHue', 40 }, { 'ColorGradeMidtoneSat', 6 } },
                    relatif = { { 'Vibrance', 8 }, { 'Highlights2012', -10 }, { 'Whites2012', 8 } } } },
    { value = 'or_peau_douce', title = "Or et peau douce",
        definition = "tons dorés chaleureux, peau adoucie (texture et clarté réduites sur la peau seulement), contraste doux",
        recette = { valeurs = { { 'ColorGradeGlobalHue', 50 }, { 'ColorGradeGlobalSat', 8 },
                                { 'ColorGradeHighlightHue', 48 }, { 'ColorGradeHighlightSat', 10 } },
                    relatif = { { 'Contrast2012', -10 } }, peau = true } },
    { value = 'or_rose_eclat', title = "Or rose et éclat",
        definition = "tons rosés dorés, rendu lumineux",
        recette = { valeurs = { { 'ColorGradeHighlightHue', 25 }, { 'ColorGradeHighlightSat', 12 },
                                { 'ColorGradeShadowHue', 340 }, { 'ColorGradeShadowSat', 6 } },
                    relatif = { { 'Whites2012', 6 }, { 'Vibrance', 6 } } } },
    { value = 'eclatant_peau_douce', title = "Éclatant et peau douce",
        definition = "couleurs vives mais naturelles (vibrance plutôt que saturation), peau adoucie",
        recette = { relatif = { { 'Vibrance', 18 }, { 'Contrast2012', 8 }, { 'Clarity2012', 4 } }, peau = true } },
    { value = 'neutre', title = "Neutre",
        definition = "balance neutre, couleurs fidèles, aucune dominante",
        recette = { valeurs = { { 'ColorGradeGlobalSat', 0 }, { 'ColorGradeHighlightSat', 0 },
                                { 'ColorGradeMidtoneSat', 0 }, { 'ColorGradeShadowSat', 0 } },
                    note = "tons neutres ramenés sous 2 en a* et b* (white_balance_point sur un gris, s'il y en a un)" } },
    { value = 'rose_froid_peau_douce', title = "Rose froid et peau douce",
        definition = "tons froids légèrement rosés, peau adoucie",
        recette = { valeurs = { { 'ColorGradeShadowHue', 215 }, { 'ColorGradeShadowSat', 10 },
                                { 'ColorGradeHighlightHue', 345 }, { 'ColorGradeHighlightSat', 8 } },
                    relatif = { { 'Vibrance', 4 } }, peau = true } },
    -- Ton style sur une photo neuve (1.3.5) : le guide de style de Dany d'abord, sans recette.
    { value = 'ma_facon', title = "À ma façon",
        definition = "ton guide de style d'abord : le lire (remember_style avec read) et appliquer chacune de ses préférences telle quelle, en première passe ; puis la méthode habituelle seulement pour ce qu'il ne dit pas ; sans guide, le dire et retoucher normalement" },
}

function Consignes.style(valeur)
    for _, s in ipairs(Consignes.styles) do
        if s.value == valeur then
            return s
        end
    end
    return nil
end

-- « Vibrance +8, Highlights2012 -10 » : des clés exactes, des nombres sans ambiguïté.
local function reglagesRecette(liste, signe)
    local parties = {}
    for _, r in ipairs(liste or {}) do
        local valeur = r[2]
        parties[#parties + 1] = r[1] .. " " .. ((signe and valeur > 0) and "+" or "") .. tostring(valeur)
    end
    return table.concat(parties, ", ")
end

-- La recette fixe d'un style, en texte ; nil sans recette.
function Consignes.texteRecette(s)
    local r = s and s.recette
    if not r then
        return nil
    end
    local parties = {}
    if r.valeurs and #r.valeurs > 0 then parties[#parties + 1] = "en valeurs : " .. reglagesRecette(r.valeurs, false) end
    if r.relatif and #r.relatif > 0 then parties[#parties + 1] = "en relatif (relative = true) : " .. reglagesRecette(r.relatif, true) end
    if r.peau then parties[#parties + 1] = "peau : « Adoucir la peau (Lite) » d'add_mask, sur la peau seulement" end
    if r.note then parties[#parties + 1] = r.note end
    return "recette fixe, la même à chaque photo : l'appliquer telle quelle après la retouche de base, en une étape « style : "
        .. s.title .. " » ; " .. table.concat(parties, " ; ")
end

-- La ligne de style jointe à une demande ; nil pour Standard (ou un style inconnu).
function Consignes.ligneStyle(valeur)
    local s = Consignes.style(valeur)
    if not s or not s.definition then
        return nil
    end
    local recette = Consignes.texteRecette(s)
    return "[Style demandé : " .. s.title .. " — " .. s.definition .. (recette and (". " .. recette) or "") .. "]"
end

-- Les modèles proposés (valeur passée à `claude --model`).
Consignes.modeles = {
    { value = 'fable', title = "Fable · le plus capable" },
    { value = 'opus', title = "Opus · retouche fine" },
    { value = 'sonnet', title = "Sonnet · courant" },
    { value = 'haiku', title = "Haiku · rapide" },
}

-- Les efforts (valeur passée à `claude --effort`), le même pour les quatre modèles ; « max » par
-- défaut (Chemins.defauts). Claude Code 2.1.303 les accepte tous les cinq avec chacun des quatre
-- modèles (constaté le 20 octobre 2026). Modèle et effort se choisissent dans le Gestionnaire de
-- modules externes (PluginInfoProvider.lua).
Consignes.efforts = {
    { value = 'max', title = "Effort maximal" },
    { value = 'xhigh', title = "Effort très élevé" },
    { value = 'high', title = "Effort élevé" },
    { value = 'medium', title = "Effort moyen" },
    { value = 'low', title = "Effort faible" },
}

local function parValeur(liste, valeur)
    for _, e in ipairs(liste) do
        if e.value == valeur then
            return e
        end
    end
    return nil
end

function Consignes.modele(valeur)
    return parValeur(Consignes.modeles, valeur)
end

function Consignes.effort(valeur)
    return parValeur(Consignes.efforts, valeur)
end

-- Éléments des menus Modèle et Effort du Gestionnaire de modules externes (tables neuves).
local function items(liste)
    local r = {}
    for _, e in ipairs(liste) do
        r[#r + 1] = { title = e.title, value = e.value }
    end
    return r
end

function Consignes.itemsModeles()
    return items(Consignes.modeles)
end

function Consignes.itemsEfforts()
    return items(Consignes.efforts)
end

-- « Obtenir », sous la carte de l'onglet Proposition (Fenetre.obtenir ; décision de Dany du
-- 25 octobre 2026, à la place de la proposition préparée à l'ouverture de la fenêtre) : `demande`
-- part à Claude, `fil` est ce que le fil montre de la demande de Dany, court comme une invite.
Consignes.obtenir = {
    fil = "Propose-moi une retouche de cette photo, sans rien appliquer.",
    demande = "Prépare une proposition de retouche de la photo active, rendu naturel : note-la d'abord si elle n'est pas encore évaluée, puis montre ce que tu changerais avec preview_settings, sans rien appliquer. J'accepterai, refuserai ou ajusterai dans l'onglet Proposition.",
}

-- Réponses aux propositions (boutons du panneau Proposition).
Consignes.accepter = "J'accepte la proposition : applique-la (confirm = true)."
Consignes.refuser = "Je refuse cette proposition : ne l'applique pas. Dis-moi ce que tu proposerais d'autre, sans rien appliquer."
function Consignes.ajuster(texte)
    return "Ajuste la proposition avant de l'appliquer : " .. texte .. ". Montre-moi la nouvelle proposition."
end


-- Ajustements d'un clic de la fenêtre Ajuster.
Consignes.ajustementsRapides = { "Moins chaud", "Peau plus naturelle", "Garder le ciel", "Plus de contraste" }

-- Ceux d'une proposition de recadrage (1.3, Composition lue : preview_settings avec un crop),
-- à la place des précédents ; Claude relit la composition au besoin (read_composition) et montre
-- le nouveau cadre, sans l'appliquer.
Consignes.ajustementsCadre = { "Plus serré", "Plus large", "Horizon au tiers haut", "Format 4:5", "Seulement redresser" }

-- (« Demander à Claude ce qu'il en pense › », la ligne d'action de la page Carnet de progrès, et sa
-- demande Consignes.carnet sont retirées avec la page au correctif 1.3.6 : la fenêtre Suivi montre le
-- carnet sans Claude.)


-- Joint à chaque demande de la fenêtre Demande rapide (Moteur.envoyerRapide) : une seule demande,
-- sans suite ni carte. `rapide` : plusieurs photos (ou la case Autre photo décochée), dans une
-- conversation jamais gardée ; `rapidePhoto` : une photo seule, dans sa conversation, que la fenêtre
-- Claude reprendra (correctif 1.3.6, « une photo, une conversation »).
Consignes.rapide = "[Demande rapide] Une seule demande, sans suite : la conversation n'est pas gardée et rien ne pourra être accepté ensuite. Elle vise toutes les photos sélectionnées dans Lightroom (selection = true ; list_selection puis chacune jusqu'à 30 photos), pas seulement la photo active, sauf si elle en nomme une. Fais ce qui est demandé sans noter les photos d'abord (sauf si on te le demande), puis dis ce qui a changé, photo par photo si elles sont plusieurs. Pas de titre."
Consignes.rapidePhoto = "[Demande rapide] Une seule demande, faite depuis la fenêtre Demande rapide dans la conversation de cette photo, que la fenêtre Claude reprendra : la Demande rapide ne montre que ta réponse, et rien n'y pourra être accepté. Elle vise la photo active, seule sélectionnée. Fais ce qui est demandé sans noter la photo d'abord (sauf si on te le demande), puis dis ce qui a changé. Pas de titre."

-- Les boutons de la Demande rapide, à gauche du champ (FenetreRapide.ACTIONS, demandés par Dany le
-- 24 octobre 2026), visent toutes les photos sélectionnées, comme une demande tapée : le premier
-- les note et pose les notes de Claude (le clic vaut la demande, comme « note ces photos ») ; les
-- deux autres reprennent les invites Retouche pro et Portrait (Consignes.invite : une seule copie
-- de leurs messages), pour chaque photo sélectionnée (Consignes.surLaSelection).
Consignes.noterRapide = "Note chaque photo sélectionnée selon le standard de notation, même déjà évaluée : cull_photos avec selection = true, view_photo avec af_point = true sur chacune (plus de 30 photos : planche par planche, puce Notes de tes consignes), puis propose_ratings avec apply = true pour poser les notes. Dis chaque note posée et sa raison en une phrase."

function Consignes.invite(id)
    for _, invite in ipairs(Consignes.invites) do
        if invite.id == id then
            return invite
        end
    end
    error("invite inconnue : " .. tostring(id), 2)
end

-- Le message d'une invite pour toutes les photos sélectionnées, une à une (« la photo active » de
-- l'invite y devient « chaque photo »).
function Consignes.surLaSelection(message)
    return "Pour toutes les photos sélectionnées dans Lightroom, une à une : " .. (message:gsub('la photo active', 'chaque photo'))
end

-- Ajouté au message envoyé (pas affiché) tant que la conversation n'a pas de titre : la consigne
-- seule ne suffit pas (constaté avec Haiku, 19 octobre 2026).
Consignes.rappelTitre = "(Pour la fenêtre, à ne pas mentionner : dès que tu vois la photo, commence ton message suivant par la ligne seule [titre : <ce que montre la photo, 3 à 6 mots>].)"

return Consignes
