-- Consignes.lua : ce que la fenêtre Claude ajoute aux consignes de Claude Code
-- (`--append-system-prompt-file`), celles d'une séance de notation, les invites en raccourcis,
-- les messages des passes de notation et les réponses aux propositions.
-- La méthode de retouche et le standard de notation restent ceux du connecteur MCP-Développeur
-- (ses consignes MCP, la ressource developpeur://notation) : ici, seulement ce qui tient à la
-- fenêtre et à celui qui s'en sert.

local Consignes = {}

Consignes.texte = [[
# Fenêtre Claude dans Lightroom

Tu es piloté par la fenêtre « Claude » de Lightroom Classic (module « Développeur ») : \
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

## Garde-fous
- Mode « Proposer d'abord » (réglage du module, montré dans la fenêtre, ou demandé dans le \
message) : montre la \
proposition avec preview_settings (compare = true), puis arrête-toi et attends. La fenêtre affiche \
Accepter, Refuser et Ajuster ; Dany répond par un message. Seulement après « J'accepte » : l'outil \
avec confirm = true.
- save_preset et remember_style (ajout) : seulement si Dany le demande dans le message.
- Notes (étoiles et drapeau Rejeter) : propose-les par propose_ratings, selon le standard de \
notation (developpeur://notation, ou propose_ratings avec read_standard = true), avec la raison \
critère par critère. Dany les accepte ou les change dans la fenêtre : jamais set_metadata pour une \
note ou un drapeau sans qu'il le demande dans le message. Jamais 5 ★ : Dany seul les pose.
- Une préférence de Dany remarquée (corrections_utilisateur, demandes répétées) : propose-la sur \
une ligne à elle « Suggestion pour le guide : <la préférence en une phrase> » ; ne l'ajoute pas \
toi-même.

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
habituelle et en restant naturel ; dis-le dans ton résumé. « Peau adoucie » : un masque de la peau \
(visage et corps) avec texture et clarté réduites, jamais sur toute la photo. Sans cette ligne, \
pas de style particulier.

## Fin d'une tâche
Après une retouche, termine par un résumé de ce qui a changé et pourquoi, en quelques puces. \
Après une tâche sur plusieurs photos, donne aussi les numéros des photos à revoir. Chaque étape \
est dans l'Historique de Lightroom sous « Claude · … ».
]]

-- Ajouté aux consignes d'une conversation de séance de notation (fenêtre « Claude · Séance de
-- notation ») : chaque passe arrive par un message tout fait (Consignes.passes).
Consignes.texteNotation = [[
# Séance de notation

Cette conversation est une séance de notation, ouverte dans la fenêtre « Claude · Séance de \
notation » de Lightroom. Chaque demande commence par « [Lightroom : séance de notation « … », \
N photos ; passe n] » au lieu de la photo active ; la demande donne les photos (identifiants du \
catalogue) et la passe.

## Méthode
- Le standard de notation fait foi : lis-le une fois au début (developpeur://notation, ou \
propose_ratings avec read_standard = true). Une passe pose une seule question.
- Le plancher technique : cull_photos (netteté, exposition, yeux, bruit, rafales). Ses plafonds \
bornent la note ; ils ne la donnent pas.
- Regarde par planches (contact_sheet, 24 à 30 photos), view_photo seulement pour les \
candidates à 4 ★ (passe 3) ou un doute précis.
- Propose par propose_ratings, avec pass et session tels que la demande les donne, les quatre \
critères et une raison courte ; les cas douteux avec to_check = true. Une photo de nuit se note \
après le débruitage : dis-le plutôt que de la noter.
- Rien ne change dans le catalogue pendant une séance : Dany accepte, change ou met à vérifier \
dans la fenêtre. Jamais set_metadata, jamais de retouche, sauf s'il le demande. Jamais 5 ★.
- Pas de ligne [titre : …] : la séance a déjà son titre.

## Réponse
Quelques lignes : combien de propositions, lesquelles sont à vérifier et pourquoi, en une phrase \
chacune. Les détails sont dans la fenêtre : ne répète pas chaque note.
]]

-- Les lignes coupées par « \ » dans les textes ci-dessus sont recollées.
Consignes.texte = Consignes.texte:gsub('\\\n', '')
Consignes.texteNotation = Consignes.texteNotation:gsub('\\\n', '')

-- Les consignes d'une conversation : celles de la fenêtre, et pour une séance de notation
-- (c.genre == 'notation'), celles de la séance en plus.
function Consignes.pour(c)
    if type(c) == 'table' and c.genre == 'notation' then
        return Consignes.texte .. '\n' .. Consignes.texteNotation
    end
    return Consignes.texte
end

-- Les invites en raccourcis (d'après les invites du connecteur). `modele` : modèle conseillé
-- (nil : celui choisi dans la fenêtre).
Consignes.invites = {
    { id = 'retouche_pro', titre = "Retouche pro",
        message = "Retouche la photo active comme un professionnel : diagnostic chiffré, deux passes vérifiées, puis au plus deux passes correctives si un défaut reste." },
    { id = 'portrait', titre = "Portrait",
        message = "Retouche ce portrait : peau, yeux, dents, arrière-plan, flou d'objectif si la photo s'y prête. Reste naturel." },
    { id = 'paysage', titre = "Paysage",
        message = "Retouche ce paysage : horizon, ciel, profondeur, masques de paysage." },
    { id = 'noir_et_blanc', titre = "Noir et blanc",
        message = "Passe la photo active en noir et blanc : profil, mélangeur, contraste local, grain." },
    { id = 'iso_eleve', titre = "ISO élevé",
        message = "Retouche cette photo prise à ISO élevé : le bruit d'abord (débruitage IA s'il est fort), puis les ombres, les couleurs et la netteté, sans lisser les détails." },
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

-- Les modèles proposés dans la fenêtre (valeur passée à `claude --model`).
Consignes.modeles = {
    { value = 'opus', title = "Opus · retouche fine" },
    { value = 'sonnet', title = "Sonnet · courant" },
    { value = 'haiku', title = "Haiku · rapide" },
}

function Consignes.titreModele(valeur)
    for _, m in ipairs(Consignes.modeles) do
        if m.value == valeur then
            return m.title
        end
    end
    return tostring(valeur)
end

-- Réponses aux propositions (boutons du panneau Proposition).
Consignes.accepter = "J'accepte la proposition : applique-la (confirm = true)."
Consignes.refuser = "Je refuse cette proposition : ne l'applique pas. Dis-moi ce que tu proposerais d'autre, sans rien appliquer."
function Consignes.ajuster(texte)
    return "Ajuste la proposition avant de l'appliquer : " .. texte .. ". Montre-moi la nouvelle proposition."
end

-- Notes ----------------------------------------------------------------------------------------

-- Le bouton Noter de la carte Note, pour la photo active (une seule photo).
Consignes.noterPhoto = "Note la photo active selon le standard de notation : son plancher technique avec cull_photos, puis regarde-la (view_photo), et propose sa note par propose_ratings avec la raison critère par critère. Ne pose rien toi-même ; jamais 5 ★."

-- « 53636309, 53636310 » : les identifiants des photos d'une séance.
local function identifiants(photos)
    local liste = {}
    for _, id in ipairs(type(photos) == 'table' and photos or {}) do
        liste[#liste + 1] = type(id) == 'number' and string.format('%d', id) or tostring(id)
    end
    return table.concat(liste, ', ')
end

-- Les photos visées par une passe : la séance (Notation.seance : id, titre, source, photos), sa
-- collection s'il y en a une, et les identifiants.
local function cible(seance)
    seance = type(seance) == 'table' and seance or {}
    local photos = type(seance.photos) == 'table' and seance.photos or {}
    local n = #photos
    local titre = type(seance.titre) == 'string' and seance.titre ~= '' and (" « " .. seance.titre .. " »") or ''
    local source = type(seance.source) == 'table' and seance.source or {}
    local collection = ''
    if source.portee == 'collection' and source.collection ~= nil then
        collection = " (collection " .. identifiants({ source.collection }) .. ")"
    end
    return string.format("Séance%s%s, %s : %s.", titre, collection,
        n == 1 and "1 photo" or (n .. " photos"), n > 0 and identifiants(photos) or "aucune photo")
end

-- Où ranger les propositions d'une passe. L'identifiant de la séance est écrit comme une valeur
-- de paramètre (entre guillemets droits), pour que Claude le passe tel quel.
local function ranger(seance, passe)
    local id = type(seance) == 'table' and seance.id or nil
    if id ~= nil then
        return string.format(' Propositions par propose_ratings avec pass = %d et session = "%s".', passe, tostring(id))
    end
    return string.format(" Propositions par propose_ratings avec pass = %d.", passe)
end

-- Les quatre passes de la Séance de notation, une question chacune (standard de notation) :
-- titre et question pour la fenêtre, message(seance) envoyé à Claude par « Lancer la passe ».
Consignes.passes = {
    { numero = 1, titre = "1 · Rejets", question = "Rejeter ? Les douteux : à vérifier.",
        message = function(seance)
            return "Passe 1 de la séance de notation : rejeter ou non ? " .. cible(seance) .. ranger(seance, 1)
                .. " Mesure d'abord le plancher technique (cull_photos), puis regarde les photos par planches (contact_sheet)."
                .. " Propose le drapeau reject pour un défaut majeur, involontaire et confirmé à l'œil ; les cas douteux (groupe, nuit, flou peut-être voulu) avec to_check = true ;"
                .. " la seule photo de sa scène : plutôt 1 ★ à vérifier. Rien pour les photos gardées : elles attendent la passe 2."
        end },
    { numero = 2, titre = "2 · Trois étoiles", question = "3 ★ ou non ? Sinon : 2 ★.",
        message = function(seance)
            return "Passe 2 de la séance de notation : 3 ★ ou non ? " .. cible(seance) .. ranger(seance, 2)
                .. " Pour chaque photo gardée (sans drapeau Rejeter) : 3 ★ si elle tient seule devant quelqu'un qui ne connaît ni les gens ni le lieu,"
                .. " sinon 2 ★ (1 ★ au passage), dans les plafonds de cull_photos. Regarde par planches (contact_sheet)."
        end },
    { numero = 3, titre = "3 · Quatre étoiles", question = "Parmi les 3 ★, monter à 4 ?",
        message = function(seance)
            return "Passe 3 de la séance de notation : parmi les 3 ★ (posées dans le catalogue ou proposées à la passe 2), monter à 4 ★ ? " .. cible(seance) .. ranger(seance, 3)
                .. " Regarde toute la sortie (contact_sheet), puis les candidates à 100 % (view_photo)."
                .. " 4 ★ seulement pour une photo qui a de l'impact, nette à 100 % sur le sujet et meilleure vue de son moment ; souvent 5 à 10 % d'une sortie, sans quota."
                .. " Les autres gardent leur note : ne les propose pas de nouveau."
        end },
    { numero = 4, titre = "4 · Cinq étoiles", question = "5 ★ ? Après le développement, vous seul.",
        message = function(seance)
            return "Passe 4 de la séance de notation : 5 ★ ? " .. cible(seance)
                .. " Le 5 ★ est à Dany seul, après le développement : ne propose aucune note."
                .. " Pour les photos à 4 ★, dis seulement ce que la finition laisse voir (halos aux bords des masques, peau plastique, saturation) et ce qui resterait à corriger."
        end },
}

-- Ajustements d'un clic de la fenêtre Ajuster.
Consignes.ajustementsRapides = { "Moins chaud", "Peau plus naturelle", "Garder le ciel", "Plus de contraste" }

-- Ajouté au message envoyé (pas affiché) tant que la conversation n'a pas de titre : la consigne
-- seule ne suffit pas (constaté avec Haiku, 19 octobre 2026).
Consignes.rappelTitre = "(Pour la fenêtre, à ne pas mentionner : dès que tu vois la photo, commence ton message suivant par la ligne seule [titre : <ce que montre la photo, 3 à 6 mots>].)"

return Consignes
