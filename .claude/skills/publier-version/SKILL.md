---
name: publier-version
description: Procédure complète pour publier une version de Développeur (numéro aux trois endroits, CHANGELOG, commit, build.sh --install notarisé, essai réel dans Lightroom, tag, Release GitHub, mise à jour de la page Analyse en artefact privé). À charger dès qu'il faut publier, sortir, livrer ou taguer une version, ou faire une Release GitHub.
---

# Publier une version

Sorti de `CLAUDE.md` le 31 octobre 2026 ; à lire quand on publie une version. Les interdictions
(archive notarisée et construite avec les tests, essai réel réussi avant le tag, documents pour
Dany en artefact privé) restent aussi dans `CLAUDE.md`.

Dans cet ordre :

1. Mettre le numéro à jour aux trois endroits : `CFBundleShortVersionString` dans
   `Resources/Info.plist`, `VERSION` dans `Lightroom/Developpeur.lrplugin/Info.lua` et
   `Liaison.VERSION` dans `Liaison.lua` (et l'essai « Versions » de `Tests/Lua/Fenetre/tests.lua`,
   qui attend le numéro de `Info.lua`) ; ajouter la section `## X.Y — AAAA-MM-JJ` dans
   `CHANGELOG.md`, écrite pour l'utilisateur. `scripts/verifier-versions.sh` (lancé par `build.sh`
   et par la CI) refuse si les trois numéros diffèrent ou si cette section n'est pas la plus récente
   des sections numérotées (« ## Non publié » peut rester au-dessus) : le lancer seul pour vérifier
   avant le commit.
2. `git add -A && git commit -m "Version X.Y" && git push origin main`
3. `./build.sh --install` (produit `build/Developpeur.zip`, signé Developer ID et notarisé : attend
   la réponse d'Apple, quelques minutes ; met l'installation à jour). Puis relancer Lightroom et
   Claude Desktop (s'il était ouvert pendant l'installation : le quitter, lancer
   `mcp-developpeur --install`, puis le rouvrir), ouvrir une nouvelle session Claude Code, et
   faire l'essai réel sur la collection « Développeur › Essais » : la recette (`--recette`,
   section « Recette d'une version » du skill `commandes-diagnostic`), puis une demande dans la
   fenêtre Claude (⌃⌥C) sur l'une de ces photos, défaite ensuite. L'essai doit réussir avant le tag.
4. `git tag -a vX.Y -m "Version X.Y" && git push origin vX.Y`
5. `gh release create vX.Y "build/Developpeur.zip" --title "Développeur X.Y" --notes "$(~/.claude/skills/standard-projet/scripts/notes-version.sh X.Y)"`
6. Mettre à jour la page Analyse du Développeur, en artefact privé
   (https://claude.ai/artifact/9kQ7kKQk5VuXrrAWFrvVKS, source `docs/artefacts/analyse-1-5.html`,
   analyse de la 1.4 du 27 octobre 2026) : la relire (Artifact, `read`), marquer faits les constats
   que la version livre et corriger ce qui est devenu faux, puis la republier à la même adresse.
   Feuille de route, Les 35 outils et Ordinogramme d'une retouche sont supprimées, avec leurs
   sources, à la demande de Dany le 27 octobre 2026, comme Guide des demandes et Apprendre avec
   Claude le même jour. Tout document nouveau pour Dany (guide, compte rendu, plan) se fait en page
   HTML publiée en artefact privé (outil Artifact ; Dany le relit et l'annote par les commentaires
   de l'artefact), sa source dans `docs/artefacts/`, commitée et poussée, jamais un document Claude
   Docs. Lavish n'est plus utilisé depuis le 31 octobre 2026.

Le README pointe vers
`https://github.com/mdany75/Developpeur/releases/latest/download/Developpeur.zip`.
