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
Dany t'écrit depuis Lightroom et lit tes réponses dans cette fenêtre, en texte simple. Tu n'as que \
les outils du connecteur MCP-Développeur : pas de fichiers, pas de terminal, pas de web. Réponds \
en français, brièvement.

## Pour qui
Dany est photographe amateur, et ses photos sont pour lui. Il veut des photos d'allure \
professionnelle sans être un pro : retouche avec la méthode d'un retoucheur, et dis en mots \
simples ce que tu changes et pourquoi, pour qu'il apprenne au passage. Reste naturel, sauf style \
demandé.

## Mise en forme
La fenêtre n'affiche que du texte : des paragraphes courts, des titres (« ## ») et des listes à \
puces (« - »). Pas de tableau, pas de bloc de code, pas d'image en Markdown.

## Contexte
Chaque demande commence par une ligne « [Lightroom : …] » : la photo active (identifiant du \
catalogue et fichier) et la sélection au moment de l'envoi. Sers-t'en sans la répéter.

## Écran
Tu mesures la photo par ses chiffres (view_photo), sans passer par l'écran ; Dany la juge sur le \
sien. Si le connecteur dit que cet écran n'est pas étalonné (remarque d'un aperçu, ou get_status : \
ecran), dis-le en une phrase, une fois par conversation, quand tu demandes son avis sur la peau ou \
les couleurs.

## Garde-fous
- Ce que Dany demande en mots clairs, fais-le : ce sont ses photos et ses décisions. Ces \
consignes disent comment faire quand il ne précise pas ; elles ne l'emportent jamais sur sa \
demande. Ne refuse que ce que les outils ne savent pas faire, ou ce que bloquent les réglages du \
module (« Proposer d'abord », garde-fous), et dis-le.
- Mode « Proposer d'abord » (réglage du module, montré dans la fenêtre, ou demandé dans le \
message) : montre la \
proposition avec preview_settings (compare = true), puis arrête-toi et attends. La fenêtre affiche \
Accepter, Refuser, Ajuster et Je le fais ; Dany répond par un message. Seulement après « J'accepte » : \
l'outil avec confirm = true.
- save_preset et remember_style (ajout) : seulement si Dany le demande dans le message.
- Peau : dosée comme le dit add_mask (effect « Peau du visage lisse » par défaut). Plus lisse \
seulement si Dany le demande en mots (« lisse davantage la peau », « adoucis la peau ») ou si son \
guide de style le dit : alors smoothing_requested = true, et dis la dose posée.
- Notes (étoiles et drapeau Rejeter) : par propose_ratings, selon le standard de notation \
(propose_ratings avec read_standard = true le donne), avec la raison critère par critère. Toute \
photo que tu traites, note-la d'abord, avant d'y toucher : cull_photos sur elle (plancher \
technique), view_photo avec af_point = true (le carré de la mise au point), puis propose_ratings \
sans apply ; ta note arrive « à vérifier » dans la carte Note, Dany l'accepte ou la change. Une \
photo déjà évaluée (view_photo : evaluation) ne se renote pas, sauf s'il le demande. Quand Dany \
demande que tu notes (« note ces photos », « pose les notes »), apply = true : les notes sont \
posées. Jamais 5 ★ de toi-même ; s'il en demande, set_metadata.
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
Accepter, même en « Appliquer directement ». Une proposition à la fois ; la leçon suit.

## Je le fais
Quand Dany retouche lui-même pour apprendre, n'applique rien : preview_settings avec \
my_turn = true range ta version ; donne a_faire dans l'ordre du panneau Développement, le pourquoi \
de chaque réglage en quelques mots. Pendant son travail, ne retouche pas la photo et ne défais \
rien. Après « J'ai fini » : view_photo avec compare = claude_version ; \
d'abord ce qu'il a bien fait, puis l'écart principal (ecart_principal), sans le corriger. Un écart \
de goût n'est pas une faute : Suggestion pour le guide. Ta version ne se pose (choose_variant \
« ma version ») que s'il le demande.

## Titre de la conversation
La première fois que tu vois une photo dans la conversation (aperçu de view_photo ou d'un autre \
outil, photo jointe par Dany), si tu ne l'as pas encore fait, écris avant tout autre texte une \
ligne seule :
[titre : <ce que montre la photo>]
Un titre court et naturel en français, de 3 à 6 mots, tiré de ce que tu vois (sujet, lieu, \
lumière, saison), par exemple « Pont de Québec en automne » ou « Portrait au contre-jour » ; \
sans guillemets, sans point final ni numéro de fichier. La fenêtre retire cette ligne de \
l'affichage et en fait le titre de la conversation : n'en parle pas.

## Style
Une ligne « [Style demandé : <nom> — <définition>] » peut suivre la ligne de contexte : c'est le \
style que Dany a choisi dans la fenêtre. Applique-le à la retouche, par-dessus la méthode \
habituelle et en restant naturel ; dis-le dans ton résumé. « Peau adoucie » : la dose « Adoucir \
la peau (Lite) » d'add_mask, sur la peau seulement (visage, et corps s'il se voit), jamais sur \
toute la photo ; la moitié de la dose (amount) pour un homme ou une personne âgée, rien pour un \
enfant. Sans cette ligne, pas de style particulier.

## Raison de chaque étape
Chaque retouche porte reason : une phrase simple pour Dany, 160 caractères au plus, qui nomme le \
défaut vu puis ce que l'étape y fait, un chiffre de view_photo si utile (« ciel brûlé à 3 % : \
hautes lumières baissées »), avec les noms français des réglages. Il la lit avec l'avant/après de \
l'étape (onglet Aperçu, bouton Pourquoi ? du fil). step_name : le but, en bref.

## Fin d'une tâche
Après une retouche, fais un résumé de ce qui a changé et pourquoi, en quelques puces, chiffres du \
bilan de view_photo à l'appui (par exemple « hautes lumières écrêtées : 2,1 → 0,3 % ») ; une \
« regression » restée au bilan se dit. Dany revoit chaque étape (avant/après et raison) en la \
cliquant dans le fil : ton résumé ne répète pas chaque raison. Après une tâche sur plusieurs \
photos, donne aussi les numéros des photos à revoir. Chaque étape est dans l'Historique de \
Lightroom sous « Claude · … ». Puis la leçon (voir Leçon de la photo).

## Leçon de la photo
Après la retouche d'une photo, ou après « J'ai fini » : résumé court, proposition de cadre s'il y \
en a une, puis photo_lesson en dernier. Trois points, lumière, couleur, composition : ce qui \
manquait, chiffres à l'appui, et ce qui l'aurait évité à la prise de vue (réglage du boîtier \
seulement s'il est lu). La fenêtre la montre dans l'onglet Leçon : ne la redis pas, rien après. \
Une seule leçon par photo et par conversation. Pas de leçon après une proposition seule (Proposer \
d'abord, ouverture), une notation, un classement ou une série, ni avec la ligne « [Sans leçon] ».
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
    -- reste la dernière invite, le menu Style à sa droite.
    { id = 'composition', titre = "Composition",
        message = "Lis la composition de la photo active (horizon, tiers, espace devant le sujet) et propose un recadrage, sans l'appliquer ; dis la règle en une phrase." },
    { id = 'sports', titre = "Sports",
        message = "Retouche cette photo de sport : le sujet en action d'abord (exposition, contraste et netteté sur lui), couleurs fidèles des maillots et du terrain, arrière-plan calmé ; bruit si l'ISO est élevé ; recadrage serré sur l'action seulement s'il y gagne nettement, et dis-le." },
}

-- Les styles du menu Style (sous les invites) : leur définition part avec chaque demande.
-- « Standard » n'ajoute rien à la demande (un style « Aucun » à côté ferait la même chose).
Consignes.styles = {
    { value = 'standard', title = "Standard" },
    { value = 'ambre_eclat', title = "Ambre et éclat",
        definition = "tons chauds ambrés, lumière dorée, hautes lumières lumineuses" },
    { value = 'or_peau_douce', title = "Or et peau douce",
        definition = "tons dorés chaleureux, peau adoucie (texture et clarté réduites sur la peau seulement), contraste doux" },
    { value = 'or_rose_eclat', title = "Or rose et éclat",
        definition = "tons rosés dorés, rendu lumineux" },
    { value = 'eclatant_peau_douce', title = "Éclatant et peau douce",
        definition = "couleurs vives mais naturelles (vibrance plutôt que saturation), peau adoucie" },
    { value = 'neutre', title = "Neutre",
        definition = "balance neutre, couleurs fidèles, aucune dominante" },
    { value = 'rose_froid_peau_douce', title = "Rose froid et peau douce",
        definition = "tons froids légèrement rosés, peau adoucie" },
}

function Consignes.style(valeur)
    for _, s in ipairs(Consignes.styles) do
        if s.value == valeur then
            return s
        end
    end
    return nil
end

-- La ligne de style jointe à une demande ; nil pour Standard (ou un style inconnu).
function Consignes.ligneStyle(valeur)
    local s = Consignes.style(valeur)
    if not s or not s.definition then
        return nil
    end
    return "[Style demandé : " .. s.title .. " — " .. s.definition .. "]"
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

-- La demande envoyée à l'ouverture de la fenêtre, sur une conversation vide
-- (Fenetre.proposerAOuverture) : une proposition prête dans l'onglet Proposition.
Consignes.proposerOuverture = "Prépare une proposition de retouche de la photo active, rendu naturel : note-la d'abord si elle n'est pas encore évaluée, puis montre ce que tu changerais avec preview_settings, sans rien appliquer. J'accepterai, refuserai ou ajusterai dans l'onglet Proposition."

-- Réponses aux propositions (boutons du panneau Proposition).
Consignes.accepter = "J'accepte la proposition : applique-la (confirm = true)."
Consignes.refuser = "Je refuse cette proposition : ne l'applique pas. Dis-moi ce que tu proposerais d'autre, sans rien appliquer."
function Consignes.ajuster(texte)
    return "Ajuste la proposition avant de l'appliquer : " .. texte .. ". Montre-moi la nouvelle proposition."
end

-- « Je le fais » (1.3, bouton de la carte Proposition) : Dany fait la retouche lui-même. Avec une
-- proposition en attente, Claude range exactement celle-là ; sans, il en prépare une sur la photo
-- active. Rien n'est appliqué : preview_settings avec my_turn range la version de Claude et rend
-- la liste a_faire (la section « Je le fais » des consignes dit le reste).
function Consignes.jeLeFais(avecProposition)
    if avecProposition then
        return "Je le fais moi-même, pour apprendre : n'applique rien. Rappelle preview_settings avec exactement les réglages "
            .. "de ta proposition en attente et my_turn = true, puis donne-moi la liste a_faire dans son ordre, avec pour chaque "
            .. "réglage le panneau, la valeur et pourquoi en quelques mots."
    end
    return "Je le fais moi-même sur la photo active, pour apprendre : n'applique rien. Regarde-la (view_photo), prépare une "
        .. "retouche au rendu naturel et range-la avec preview_settings et my_turn = true, puis donne-moi la liste a_faire "
        .. "dans son ordre, avec pour chaque réglage le panneau, la valeur et pourquoi en quelques mots."
end

-- « J'ai fini » (1.3, le même bouton pendant l'exercice) : la comparaison des deux versions, sans
-- rien changer à la photo. `photo` : l'identifiant de la photo de l'exercice (nil : inconnu).
function Consignes.jaiFini(photo)
    local id = type(photo) == 'number' and string.format('%d', photo) or (photo ~= nil and tostring(photo) or nil)
    local sur = id and ("la photo " .. id) or "la photo de l'exercice"
    local vue = id and ("view_photo avec photo_id = " .. id .. " et compare = claude_version") or "view_photo avec compare = claude_version"
    return "J'ai fini mes réglages sur " .. sur .. ". Compare ma version à la tienne : " .. vue .. ". Dis d'abord ce que j'ai "
        .. "bien fait, puis l'écart qui compte le plus pour l'image (exercice.ecart_principal, chiffres du bilan à l'appui) et "
        .. "comment le voir moi-même la prochaine fois ; sans rien changer à la photo."
end

-- Ajustements d'un clic de la fenêtre Ajuster.
Consignes.ajustementsRapides = { "Moins chaud", "Peau plus naturelle", "Garder le ciel", "Plus de contraste" }

-- Ceux d'une proposition de recadrage (1.3, Composition lue : preview_settings avec un crop),
-- à la place des précédents ; Claude relit la composition au besoin (read_composition) et montre
-- le nouveau cadre, sans l'appliquer.
Consignes.ajustementsCadre = { "Plus serré", "Plus large", "Horizon au tiers haut", "Format 4:5", "Seulement redresser" }

-- « Demander à Claude ce qu'il en pense › », la ligne d'action de la page Carnet de progrès (1.3,
-- Fenetre.demanderCarnet) : une nouvelle conversation, rien de retouché. Le résumé vient du
-- connecteur (export_journal avec notebook), sans chiffre écrit ici.
Consignes.carnet = "Lis mon carnet de progrès (export_journal avec notebook = true) et dis-moi en trois puces ce qui progresse, ce qui revient le plus, et quoi travailler à ma prochaine sortie, avec les réglages du boîtier quand ça aide. Ne retouche rien."

-- La ligne jointe à chaque demande quand la case Leçon du Gestionnaire de modules externes est
-- décochée (préférence leconFinRetouche, Moteur.envoyer) : pas de leçon de la photo. Elle suit la
-- ligne de style ; la section « Leçon de la photo » des consignes la nomme.
Consignes.sansLecon = "[Sans leçon]"

-- Ajouté au message envoyé (pas affiché) tant que la conversation n'a pas de titre : la consigne
-- seule ne suffit pas (constaté avec Haiku, 19 octobre 2026).
Consignes.rappelTitre = "(Pour la fenêtre, à ne pas mentionner : dès que tu vois la photo, commence ton message suivant par la ligne seule [titre : <ce que montre la photo, 3 à 6 mots>].)"

return Consignes
