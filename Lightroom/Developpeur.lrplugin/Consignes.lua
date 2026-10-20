-- Consignes.lua : ce que la fenêtre Claude ajoute aux consignes de Claude Code
-- (`--append-system-prompt-file`), les invites en raccourcis et les réponses aux propositions.
-- La méthode de retouche reste celle du connecteur MCP-Développeur (ses consignes MCP) : ici,
-- seulement ce qui tient à la fenêtre et à celui qui s'en sert.

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

-- Les lignes coupées par « \ » dans le texte ci-dessus sont recollées.
Consignes.texte = Consignes.texte:gsub('\\\n', '')

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

-- Ajustements d'un clic de la fenêtre Ajuster.
Consignes.ajustementsRapides = { "Moins chaud", "Peau plus naturelle", "Garder le ciel", "Plus de contraste" }

-- Ajouté au message envoyé (pas affiché) tant que la conversation n'a pas de titre : la consigne
-- seule ne suffit pas (constaté avec Haiku, 19 octobre 2026).
Consignes.rappelTitre = "(Pour la fenêtre, à ne pas mentionner : dès que tu vois la photo, commence ton message suivant par la ligne seule [titre : <ce que montre la photo, 3 à 6 mots>].)"

return Consignes
