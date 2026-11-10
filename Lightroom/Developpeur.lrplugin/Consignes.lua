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
- Ce que Lightroom ne sait pas faire (changer un vêtement, ajouter ou retirer un objet) : \
generative_edit (Fibo 2, local), seulement sur sa demande ; d'abord les corrections de base, puis \
generative_edit, puis les finitions sur la nouvelle photo, qui devient la photo active. Consigne \
en anglais, sa traduction montrée à Dany (instruction_fr) ; plusieurs changements en un appel \
(edits) ; l'arrière-plan, le ciel, une personne : mask (masque de Lightroom) plutôt que region ; \
une zone que Dany a peinte dans Lightroom : mask avec existing, son nom ; \
le décor ou un vêtement d'une autre photo : reference (avec region ou mask) ; \
la couleur d'un objet se change dans Lightroom par un masque, pas par generative_edit.
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
dit « suite ») et propose_ratings pour ses photos, jusqu'à la dernière, dans le même tour : la \
planche suffit pour juger et confirmer les rejets que le tri propose ; jamais list_selection pour \
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

-- Le corps de l'invite Classer, sans sa fin : la fenêtre Claude attend l'accord dans la conversation,
-- la Demande rapide ne fait que proposer (Consignes.classerRapide). get_settings › classement rend la
-- légende déjà écrite (relecture du 2 novembre 2026 : elle manquait, et Claude l'aurait remplacée).
local CLASSER = "Classe la photo active, sans rien écrire d'abord : regarde-la (view_photo) et lis son classement (get_settings : mots-clés, légende, lieu et position GPS déjà posés), puis propose des mots-clés, en reprenant ceux du catalogue (list_keywords), un lieu seulement s'il est sûr (repris d'un champ de lieu ou d'un mot-clé de lieu déjà posé ; la position GPS seule ne nomme pas le lieu : donne-la et laisse-moi le nommer, jamais deviné) et une légende courte, sans remplacer celle que j'ai déjà écrite."

-- Le guide de style de Dany, lu au début de chaque retouche lancée par un bouton (invites marquées
-- `retouche`, fenêtre Claude et Demande rapide ; relecture du 2 novembre 2026 : seuls la peau, les
-- suggestions et le style « À ma façon » le citaient). En fin de message, pour que le titre tiré de
-- la demande reste son début ; retiré du message à Claude quand le style « À ma façon », qui le fait
-- déjà lire, est choisi (Consignes.sansDoublonGuide).
Consignes.LIRE_GUIDE = "Avant tout, lis mon guide de style (remember_style avec read = true) et suis ses préférences."

local function avecGuide(message)
    return message .. " " .. Consignes.LIRE_GUIDE
end

-- Les invites en raccourcis (d'après les invites du connecteur). `modele` : modèle conseillé
-- (nil : celui choisi dans la fenêtre). Portrait, Paysage et Noir et blanc demandent d'éclaircir
-- et assombrir comme un tireur, sans chiffres : les doses arrivent à Claude Code par la
-- description d'add_mask (Prompts.Tireur.resume du connecteur), la fenêtre ne lisant pas les
-- invites du connecteur.
Consignes.invites = {
    { id = 'retouche_pro', titre = "Retouche pro",
        retouche = true,
        message = avecGuide("Retouche la photo active comme un professionnel : diagnostic chiffré, deux passes vérifiées, puis au plus deux passes correctives si un défaut reste.") },
    { id = 'portrait', titre = "Portrait",
        retouche = true,
        message = avecGuide("Retouche ce portrait : peau, yeux, dents, arrière-plan, flou d'objectif si la photo s'y prête ; puis éclaircis et assombris comme un tireur pour mener l'œil au visage (doses d'add_mask), et montre l'avant/après de cette étape. Reste naturel.") },
    { id = 'paysage', titre = "Paysage",
        retouche = true,
        message = avecGuide("Retouche ce paysage : horizon, ciel, profondeur, masques de paysage ; puis éclaircis et assombris comme un tireur pour mener l'œil au sujet (doses d'add_mask), et montre l'avant/après de cette étape.") },
    { id = 'noir_et_blanc', titre = "Noir et blanc",
        retouche = true,
        message = avecGuide("Passe la photo active en noir et blanc : profil, mélangeur, contraste local, puis éclaircis et assombris comme un tireur (doses d'add_mask) avec l'avant/après de cette étape, et grain.") },
    { id = 'iso_eleve', titre = "ISO élevé",
        retouche = true,
        message = avecGuide("Retouche cette photo prise à ISO élevé : le bruit d'abord (débruitage IA s'il est fort), puis les ombres, les couleurs et la netteté, sans lisser les détails.") },
    -- Composition (1.3) : lue sur l'image entière (read_composition), le cadre proposé et montré,
    -- appliqué seulement par Accepter ; sans chiffre, comme les autres invites. Avant Sports (le menu
    -- Style est sous le champ, avec son étiquette).
    { id = 'composition', titre = "Composition",
        message = "Lis la composition de la photo active (horizon, tiers, espace devant le sujet) et propose un recadrage, sans l'appliquer ; dis la règle en une phrase." },
    { id = 'sports', titre = "Sports",
        retouche = true,
        message = avecGuide("Retouche cette photo de sport : le sujet en action d'abord (exposition, contraste et netteté sur lui), couleurs fidèles des maillots et du terrain, arrière-plan calmé ; bruit si l'ISO est élevé ; recadrage serré sur l'action seulement s'il y gagne nettement, et dis-le.") },
    -- Classer (correctif après la 1.6, point « Le Suivi et le classement : fonctions faites, mais
    -- sans bouton » de la page Analyse) : mots-clés, lieu et légende proposés, jamais écrits sans
    -- l'accord de Dany, quel que soit le mode du module (« Proposer d'abord » par défaut). Le lieu
    -- seulement s'il est sûr : repris d'un champ de lieu ou d'un mot-clé de lieu déjà posé ; aucun
    -- outil ne traduit la position GPS en ville, Claude la donne et Dany nomme le lieu (relecture
    -- du 2 novembre 2026). Après Sports, la dernière invite ; la Demande rapide en a sa version
    -- (Consignes.classerRapide). Pendant du connecteur : l'invite classer (Prompts.classer).
    -- Dans la fenêtre Claude, son bouton est en haut, à gauche de « Repartir à neuf » (`entete`,
    -- Vues.boutonClasser ; demandé par Dany le 10 novembre 2026), plus dans la rangée des invites.
    { id = 'classer', titre = "Classer", entete = true,
        message = CLASSER .. " Montre ta proposition et attends mon accord avant set_metadata, même en mode Appliquer." },
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
    -- Les décalages s'ajoutent à la retouche de base : un plafond de dose du serveur peut refuser
    -- l'étape (Vibrance de base 15 + 18). Le style, Dany l'a choisi : c'est sa demande, l'étape se
    -- repose entière avec strong_dose_requested (plafonds : DevelopCatalogue.plafondsDose).
    if r.relatif and #r.relatif > 0 then
        parties[#parties + 1] = "en relatif (relative = true) : " .. reglagesRecette(r.relatif, true)
            .. " (refusée pour un plafond de dose : la reposer entière avec strong_dose_requested = true, ce style est sa demande)"
    end
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

-- Le message à Claude d'une demande, sans la phrase du guide (Consignes.LIRE_GUIDE) quand le style
-- « À ma façon » est choisi : sa ligne de style le fait déjà lire, en première passe. Le fil garde
-- la demande telle quelle.
function Consignes.sansDoublonGuide(texte, style)
    if style ~= 'ma_facon' or type(texte) ~= 'string' then
        return texte
    end
    local debut, fin = texte:find(Consignes.LIRE_GUIDE, 1, true)
    if not debut then
        return texte
    end
    local reste = (texte:sub(1, debut - 1) .. " " .. texte:sub(fin + 1)):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
    return reste
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

-- La proposition la plus complète possible (demandé par Dany le 2 novembre 2026 : « Je veux que la
-- proposition soit le plus complète possible ») : la méthode d'une Retouche pro, sans rien
-- appliquer. Tous les panneaux que la photo demande (pas tout par principe) dans un seul
-- preview_settings, qui fait la carte de l'onglet Proposition ; les retouches locales proposées par
-- add_mask avec preview = true (Conversation.ceQueTouche les lit pour la boîte Ajuster) ; un
-- recadrage seulement s'il y gagne nettement. Partagée par Obtenir (Consignes.obtenir) et le bouton
-- « Proposer et appliquer » de la Demande rapide (Consignes.proposerAppliquerRapide).
-- L'étendue partagée par la proposition (preview) et la retouche appliquée du 5ᵉ bouton de la
-- Demande rapide : les panneaux que la photo demande.
local ETENDUE = "tous les panneaux que la photo demande, pas tout par principe "
    .. "(profil, corrections d'objectif et Upright si utile, balance des blancs, tonalité, présence, TSL, étalonnage, courbe, "
    .. "détail et bruit, vignetage ou radial inversé, jamais les deux)"
Consignes.PROPOSITION_COMPLETE = "comme une Retouche pro, mais sans rien appliquer : view_photo (mesures, bilan, intention_boitier) "
    .. "pour le diagnostic ; puis, dans un seul preview_settings, " .. ETENDUE .. " ; les retouches locales utiles (ciel, sujet, peau…) par "
    .. "add_mask avec preview = true ; un recadrage seulement s'il y gagne nettement. Donne chaque changement avec sa raison courte."
-- La même étendue, appliquée tout de suite (5ᵉ bouton de la Demande rapide en mode Appliquer ;
-- relecture du 2 novembre 2026) : ni « sans rien appliquer » ni preview, qui contrediraient la
-- demande et feraient tout calculer deux fois ; view_photo vérifie, comme la Retouche pro.
Consignes.RETOUCHE_COMPLETE = "comme une Retouche pro, appliquée dans ce même tour (c'est la demande) : view_photo (mesures, bilan, "
    .. "intention_boitier) pour le diagnostic ; puis, dans un seul apply_settings avec confirm = true, " .. ETENDUE .. " ; les retouches "
    .. "locales utiles (ciel, sujet, peau…) par add_mask avec confirm = true, sans preview ; un recadrage seulement s'il y gagne "
    .. "nettement ; puis view_photo pour vérifier, et une passe corrective seulement si un défaut est constaté."

-- « Obtenir », sous la carte de l'onglet Proposition (Fenetre.obtenir ; décision de Dany du
-- 25 octobre 2026, à la place de la proposition préparée à l'ouverture de la fenêtre) : `demande`
-- part à Claude, `fil` est ce que le fil montre de la demande de Dany, court comme une invite.
-- Depuis le 2 novembre 2026, la proposition la plus complète possible (Consignes.PROPOSITION_COMPLETE),
-- guide de style lu d'abord, comme les boutons de retouche (Consignes.LIRE_GUIDE).
Consignes.obtenir = {
    fil = "Propose-moi une retouche de cette photo, sans rien appliquer.",
    demande = avecGuide("Prépare la proposition de retouche la plus complète possible de la photo active : note-la d'abord si elle n'est pas encore évaluée, puis fais-la "
        .. Consignes.PROPOSITION_COMPLETE .. " J'accepterai, refuserai ou ajusterai dans l'onglet Proposition."),
}

-- Réponses aux propositions (boutons du panneau Proposition).
-- Accepter applique la proposition entière : les réglages de preview_settings et les retouches
-- locales proposées avec elle (add_mask avec preview = true), sans preview cette fois (2 novembre
-- 2026, la proposition complète).
Consignes.accepter = "J'accepte la proposition : applique-la (confirm = true), réglages et retouches locales proposées (add_mask sans preview, confirm = true)."
Consignes.refuser = "Je refuse cette proposition : ne l'applique pas. Dis-moi ce que tu proposerais d'autre, sans rien appliquer."
function Consignes.ajuster(texte)
    return "Ajuste la proposition avant de l'appliquer : " .. texte .. ". Montre-moi la nouvelle proposition."
end


-- Ajustements d'un clic de la fenêtre Ajuster, en repli : quand on ne sait rien de ce que touche la
-- proposition (Consignes.ajustementsPour).
Consignes.ajustementsRapides = { "Moins chaud", "Peau plus naturelle", "Garder le ciel", "Plus de contraste" }
Consignes.MAX_AJUSTEMENTS = 6

-- Les réglages lus, par l'écart proposé : { clé, bouton si l'écart monte, bouton s'il descend,
-- bouton quand le sens n'est pas lu (nil : aucun) }. Le bouton tempère le changement proposé (une
-- proposition qui réchauffe offre « Moins chaud »). Dans cet ordre, avant la peau et le ciel.
local AJUSTEMENTS_REGLAGES = {
    { 'Temperature', "Moins chaud", "Plus chaud", "Moins chaud" },
    { 'Tint', "Moins magenta", "Moins vert" },
    { 'Exposure2012', "Moins clair", "Plus clair" },
    { 'Contrast2012', "Moins de contraste", "Plus de contraste", "Plus de contraste" },
    { 'Shadows2012', "Ombres plus sombres", "Ombres plus claires" },
    { 'Highlights2012', "Hautes lumières plus sombres", "Hautes lumières plus claires" },
    { 'Vibrance', "Couleurs plus douces", "Couleurs plus vives" },
    { 'Saturation', "Couleurs plus douces", "Couleurs plus vives" },
    { 'Clarity2012', "Moins de clarté", "Plus de clarté" },
    { 'Dehaze', "Moins de correction du voile", "Plus de correction du voile" },
}

-- Les clés du mélangeur TSL d'une couleur (orange : la peau ; bleu : le ciel).
local function cleTSL(cle, couleur)
    return type(cle) == 'string' and cle:match('^%a+Adjustment' .. couleur .. '$') ~= nil
end

-- Les ajustements d'un clic choisis d'après ce que touche la proposition en attente
-- (Conversation.ceQueTouche) : `reglages`, { [clé] = écart (après − avant), ou false quand le sens
-- n'est pas lu } ; `zones`, { ciel = true, peau = true } des masques proposés avec elle. Le sens de
-- chaque bouton suit celui du changement ; la peau seulement si la proposition y touche (masque de
-- peau, effet de peau, orange du mélangeur), le ciel de même (masque du ciel, bleu du mélangeur).
-- MAX_AJUSTEMENTS au plus ; la liste fixe en repli quand on ne sait rien ou que rien n'est reconnu.
function Consignes.ajustementsPour(reglages, zones)
    reglages, zones = reglages or {}, zones or {}
    local liste, vus = {}, {}
    local function ajouter(titre)
        if titre and not vus[titre] and #liste < Consignes.MAX_AJUSTEMENTS then
            vus[titre] = true
            liste[#liste + 1] = titre
        end
    end
    for _, r in ipairs(AJUSTEMENTS_REGLAGES) do
        local ecart = reglages[r[1]]
        if type(ecart) == 'number' and ecart > 0 then
            ajouter(r[2])
        elseif type(ecart) == 'number' and ecart < 0 then
            ajouter(r[3])
        elseif ecart == false then
            ajouter(r[4])
        end
    end
    local peau, ciel = zones.peau == true, zones.ciel == true
    for cle in pairs(reglages) do
        peau = peau or cleTSL(cle, 'Orange')
        ciel = ciel or cleTSL(cle, 'Blue')
    end
    if peau then ajouter("Peau plus naturelle") end
    if ciel then ajouter("Garder le ciel") end
    if #liste == 0 then
        local repli = {}
        for i, a in ipairs(Consignes.ajustementsRapides) do
            repli[i] = a
        end
        return repli
    end
    return liste
end

-- Ceux d'une proposition de recadrage (1.3, Composition lue : preview_settings avec un crop),
-- à la place des précédents ; Claude relit la composition au besoin (read_composition) et montre
-- le nouveau cadre, sans l'appliquer.
Consignes.ajustementsCadre = { "Plus serré", "Plus large", "Horizon au tiers haut", "Format 4:5", "Seulement redresser" }

-- (« Demander à Claude ce qu'il en pense › », la ligne d'action de la page Carnet de progrès, et sa
-- demande Consignes.carnet sont retirées avec la page au correctif 1.3.6 : la fenêtre Suivi montre le
-- carnet sans Claude.)


-- Joint à chaque demande de la fenêtre Demande rapide (Moteur.envoyerRapide) : une seule demande,
-- sans carte, faite en entier dans le tour (« sans suite » faisait renoncer Claude à noter 951 photos
-- planche par planche, le 26 octobre 2026). `rapide` : plusieurs photos (ou la case Autre photo décochée), dans une
-- conversation jamais gardée ; `rapidePhoto` : une photo seule, dans sa conversation, que la fenêtre
-- Claude reprendra (correctif 1.3.6, « une photo, une conversation »).
Consignes.rapide = "[Demande rapide] Une seule demande : la conversation n'est pas gardée et rien ne pourra être accepté ensuite, alors fais-la en entier dans ce tour, même longue (noter une grande sélection : toutes ses planches, jusqu'à la dernière), sans t'arrêter pour demander la suite. Elle vise toutes les photos sélectionnées dans Lightroom (selection = true ; list_selection puis chacune jusqu'à 30 photos), pas seulement la photo active, sauf si elle en nomme une. Fais ce qui est demandé sans noter les photos d'abord (sauf si on te le demande), puis dis ce qui a changé, photo par photo si elles sont plusieurs (plus de 30 : en résumé). Pas de titre."
Consignes.rapidePhoto = "[Demande rapide] Une seule demande, faite depuis la fenêtre Demande rapide dans la conversation de cette photo, que la fenêtre Claude reprendra : la Demande rapide ne montre que ta réponse, et rien n'y pourra être accepté. Elle vise la photo active, seule sélectionnée. Fais ce qui est demandé sans noter la photo d'abord (sauf si on te le demande), puis dis ce qui a changé. Pas de titre."

-- Les boutons de la Demande rapide, à gauche du champ (FenetreRapide.ACTIONS, demandés par Dany le
-- 24 octobre 2026), visent toutes les photos sélectionnées, comme une demande tapée : le premier
-- les note et pose les notes de Claude (le clic vaut la demande, comme « note ces photos ») ; les
-- trois autres reprennent les invites Retouche pro, Portrait et Classer (Consignes.invite : une
-- seule copie de leurs messages), pour chaque photo sélectionnée (Consignes.surLaSelection ;
-- Retouche pro par groupes de lumière, Consignes.retoucheProSurLaSelection).
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

-- Retouche pro sur plusieurs photos (bouton de la Demande rapide ; relecture du 2 novembre 2026) :
-- par groupes de lumière plutôt qu'une à une. match_series avec groups (rien d'écrit) donne les
-- groupes et la référence de chacun ; la référence se retouche selon l'invite, ses réglages vont
-- aux autres photos du groupe (copy_settings), puis match_series les harmonise. Une photo seule
-- dans son groupe se retouche seule. La phrase du guide (Consignes.LIRE_GUIDE) passe en tête, une
-- fois pour toute la sélection. Les autres boutons restent « une à une » (Consignes.surLaSelection).
function Consignes.retoucheProSurLaSelection(message)
    local debut, fin = message:find(Consignes.LIRE_GUIDE, 1, true)
    local guide = debut and (Consignes.LIRE_GUIDE .. " ") or ""
    if debut then
        message = (message:sub(1, debut - 1) .. message:sub(fin + 1)):gsub('%s+$', '')
    end
    local corps = message:gsub('la photo active', 'sa photo de référence'):gsub('^%u', string.lower)
    return guide .. "Pour toutes les photos sélectionnées dans Lightroom, par groupes de lumière : d'abord match_series "
        .. "avec groups = true et selection = true (les groupes et la référence de chacun, rien d'écrit). Puis, dans chaque "
        .. "groupe, " .. corps .. " Ensuite copy_settings de la référence vers les autres photos du groupe, et match_series "
        .. "(reference_id : la référence, confirm = true : c'est la demande ; en « Proposer d'abord », le plan seulement) pour les harmoniser. Une photo seule dans son groupe se retouche seule, de la même "
        .. "façon ; une seule photo sélectionnée : retouche-la, sans groupes."
end

-- Le 4ᵉ bouton de la Demande rapide, Classer (FenetreRapide.ACTIONS) : proposer seulement, pour
-- chaque photo sélectionnée. Consignes.rapide dit de tout faire dans ce tour, et sur plusieurs
-- photos la conversation n'est pas gardée : un « attends mon accord » y serait sans issue (Dany
-- répondrait dans une conversation neuve, sans la proposition ; relecture du 2 novembre 2026).
Consignes.classerRapide = Consignes.surLaSelection(CLASSER) .. " Dans cette Demande rapide, la demande entière est ta proposition, photo par photo (mots-clés, lieu, légende) : n'appelle pas set_metadata, même en mode Appliquer. Finis en disant comment l'écrire : si cette conversation est gardée (la fenêtre Claude la reprend), en répondant dans la fenêtre Claude ; sinon, elle sera perdue : par l'invite Classer de la fenêtre Claude, photo par photo, ou par une nouvelle demande qui nomme ce qu'il faut écrire."

-- Le 5ᵉ bouton de la Demande rapide, « Proposer et appliquer » (FenetreRapide.ACTIONS ; demandé par
-- Dany le 2 novembre 2026 : « un bouton qui donne et applique la proposition rapide »), pour la
-- photo active ou chaque photo sélectionnée une à une (Consignes.surLaSelection), dit en lignes
-- courtes (FenetreRapide.LIGNES_RESULTAT : 12 se lisent sans défiler). `mode` : celui du module
-- (Lightroom.mode, lu au clic) ; `gardee` : la conversation de la demande est celle d'une photo
-- seule, que la fenêtre Claude reprend (Moteur.rapideGardee). Rend le message pour Claude, ou nil
-- et le texte que la fenêtre montre d'elle-même. En mode Appliquer : la retouche complète appliquée
-- (Consignes.RETOUCHE_COMPLETE). En « Proposer d'abord », le mode n'est pas contourné : la
-- proposition complète (Consignes.PROPOSITION_COMPLETE), à accepter dans l'onglet Proposition,
-- seulement si la conversation est gardée ; sinon rien ne part à Claude (relecture du 2 novembre
-- 2026) : une proposition jetable serait du forfait perdu, et Consignes.rapide la ferait finir.
Consignes.rapideProposerSeulement = "Mode « Proposer d'abord » : Proposer et appliquer ne fait que proposer, et la proposition "
    .. "s'accepte dans la fenêtre Claude, dans la conversation de la photo. Ici, elle ne serait pas gardée : rien n'est demandé "
    .. "à Claude. Ouvrez la fenêtre Claude et, pour chaque photo, cliquez Obtenir puis Accepter dans l'onglet Proposition ; "
    .. "ou choisissez une seule photo, case Autre photo cochée dans le Gestionnaire de modules externes."
function Consignes.proposerAppliquerRapide(mode, gardee)
    local debut = "Prépare la retouche la plus complète possible de la photo active, "
    if mode ~= 'proposer' then
        return Consignes.surLaSelection(avecGuide(debut .. Consignes.RETOUCHE_COMPLETE
            .. " Finis en lignes courtes, une par changement fait, avec sa raison (vingt lignes se lisent sans défiler)."))
    end
    if not gardee then
        return nil, Consignes.rapideProposerSeulement
    end
    return avecGuide("Prépare la proposition de retouche la plus complète possible de la photo active, " .. Consignes.PROPOSITION_COMPLETE
        .. " Le module est en mode « Proposer d'abord » : n'applique rien (jamais confirm = true), propose seulement ; "
        .. "la proposition entière est la demande de ce tour. Finis en lignes courtes, une par changement proposé, avec sa raison ; "
        .. "puis dis de l'accepter par Accepter dans l'onglet Proposition de la fenêtre Claude (cette conversation y est gardée).")
end

-- Ajouté au message envoyé (pas affiché) tant que la conversation n'a pas de titre : la consigne
-- seule ne suffit pas (constaté avec Haiku, 19 octobre 2026).
Consignes.rappelTitre = "(Pour la fenêtre, à ne pas mentionner : dès que tu vois la photo, commence ton message suivant par la ligne seule [titre : <ce que montre la photo, 3 à 6 mots>].)"

return Consignes
