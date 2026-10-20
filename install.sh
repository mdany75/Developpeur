#!/bin/bash
#
# install.sh — installe « Développeur » pour l'utilisateur courant : le serveur MCP
# « mcp-developpeur » (le connecteur MCP-Développeur), inscrit dans Claude Desktop et Claude Code,
# et le module « Développeur » de Lightroom Classic (liaison avec le serveur et fenêtre Claude).
#
# Usage : bash install.sh      (depuis le dossier décompressé de l'archive, ou via ./build.sh --install)
#
# Ce que fait le script :
#   1. copie mcp-developpeur dans ~/Library/Application Support/Developpeur/ et retire
#      l'attribut de quarantaine (archive téléchargée) pour que Claude puisse le lancer
#   2. copie Developpeur.lrplugin dans ~/Library/Application Support/Adobe/Lightroom/Modules/,
#      d'où Lightroom Classic charge ses modules au lancement (l'ancienne version est remplacée
#      en entier)
#   3. mcp-developpeur --install : ajoute le serveur « MCP-Developpeur » dans
#      ~/Library/Application Support/Claude/claude_desktop_config.json et ~/.claude.json
#      (une copie « .avant-mcp-developpeur » de chaque fichier est gardée à côté) et retire
#      l'ancien connecteur « lightroom » (MCP Lightroom) ; Claude Desktop doit être fermé
#   4. Lightroom fermé seulement : efface les paramètres prédéfinis invisibles que le module crée
#      (un fichier par masque IA, flou d'objectif ou mode automatique) ; il recrée ceux qu'il utilise
#
# Ce qui est déjà là reste : guide de style, conversations, profils de publication, registre de
# consommation et journaux. Le catalogue et les photos ne sont jamais touchés.
# Aucun droit d'administrateur : rien n'est écrit hors du dossier personnel.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${HERE}/mcp-developpeur"
PLUGIN_SOURCE="${HERE}/Developpeur.lrplugin"
DEST_DIR="${HOME}/Library/Application Support/Developpeur"
DEST="${DEST_DIR}/mcp-developpeur"
MODULES_DIR="${HOME}/Library/Application Support/Adobe/Lightroom/Modules"
PLUGIN_DEST="${MODULES_DIR}/Developpeur.lrplugin"
PRESETS_DIR="${HOME}/Library/Application Support/Adobe/Lightroom/Plugin Develop Presets/com.danymenard.developpeur"
# Où le module cherche Claude Code pour sa fenêtre Claude (Chemins.claudeParDefaut).
CLAUDE_CODE=(
    "${HOME}/.local/bin/claude"
    "/opt/homebrew/bin/claude"
    "/usr/local/bin/claude"
)

die() { printf 'Erreur : %s\n' "$1" >&2; exit 1; }

[[ -x "${SOURCE}" ]] || die "mcp-developpeur introuvable à côté de install.sh (depuis le dépôt : ./build.sh --install)"
[[ -f "${PLUGIN_SOURCE}/Info.lua" ]] || die "Developpeur.lrplugin introuvable à côté de install.sh"

LIGHTROOM_OUVERT=0
if pgrep -xq "Adobe Lightroom Classic"; then
    LIGHTROOM_OUVERT=1
fi
# Claude Desktop ouvert garde sa configuration en mémoire et la réécrit : l'inscription faite
# pendant ce temps se perd (constaté le 20 octobre 2026 : « MCP-Developpeur » perdu, l'ancienne
# clé « lightroom » revenue). -a : sans lui, pgrep ne voit pas Claude Desktop depuis une session
# de Claude Code qu'il a lancée (il exclut les processus parents).
CLAUDE_DESKTOP_OUVERT=0
if pgrep -xaq Claude; then
    CLAUDE_DESKTOP_OUVERT=1
fi

# --- 1. Serveur ---------------------------------------------------------------
#
# Copié à côté puis renommé : un serveur déjà lancé par Claude garde l'ancien fichier jusqu'à sa
# relance, et l'installation n'est jamais à moitié faite.

mkdir -p "${DEST_DIR}"
cp -f "${SOURCE}" "${DEST}.nouveau"
chmod 755 "${DEST}.nouveau"
xattr -d com.apple.quarantine "${DEST}.nouveau" 2>/dev/null || true
mv -f "${DEST}.nouveau" "${DEST}"
printf 'Serveur installé : %s (version %s)\n' "${DEST}" "$("${DEST}" --version)"

# --- 2. Module Lightroom ------------------------------------------------------

mkdir -p "${MODULES_DIR}"
rm -rf "${PLUGIN_DEST}.nouveau"
ditto "${PLUGIN_SOURCE}" "${PLUGIN_DEST}.nouveau"
xattr -dr com.apple.quarantine "${PLUGIN_DEST}.nouveau" 2>/dev/null || true
rm -rf "${PLUGIN_DEST}"
mv "${PLUGIN_DEST}.nouveau" "${PLUGIN_DEST}"
printf 'Module Lightroom installé : %s\n' "${PLUGIN_DEST}"

# --- 3. Inscription dans Claude Desktop et Claude Code ------------------------
#
# Faite même Claude Desktop ouvert : celle de Claude Code tient ; celle de Claude Desktop est à
# refaire, Claude Desktop fermé (voir les prochaines étapes).

"${DEST}" --install

# --- 4. Paramètres prédéfinis invisibles du module ----------------------------
#
# Lightroom les charge à son lancement : on n'y touche donc que Lightroom fermé.

PRESETS_NOTE=""
if [[ -d "${PRESETS_DIR}" ]]; then
    if [[ "${LIGHTROOM_OUVERT}" == 1 ]]; then
        PRESETS_NOTE="  - Paramètres prédéfinis invisibles du module gardés (Lightroom ouvert) : relancer install.sh Lightroom fermé pour les effacer."
    else
        NOMBRE="$(find "${PRESETS_DIR}" -maxdepth 1 -name '*.lrtemplate' | wc -l | tr -d ' ')"
        find "${PRESETS_DIR}" -maxdepth 1 -name '*.lrtemplate' -delete
        printf 'Paramètres prédéfinis invisibles du module effacés : %s fichier(s)\n' "${NOMBRE}"
    fi
fi

# --- Claude Code, pour la fenêtre Claude du module ----------------------------
#
# La fenêtre Claude de Lightroom passe par Claude Code et le forfait claude.ai (jamais l'API).
# Rien n'est installé ici : on dit seulement s'il manque.

CLAUDE_NOTE=""
CLAUDE_TROUVE=""
for chemin in "${CLAUDE_CODE[@]}"; do
    if [[ -x "${chemin}" ]]; then
        CLAUDE_TROUVE="${chemin}"
        break
    fi
done
if [[ -z "${CLAUDE_TROUVE}" ]]; then
    CLAUDE_NOTE="  - Claude Code introuvable (~/.local/bin, /opt/homebrew/bin, /usr/local/bin) : la fenêtre Claude de
    Lightroom en a besoin, connecté au compte claude.ai. L'installer, ou régler son chemin dans
    Fichier › Gestionnaire de modules externes › Développeur."
fi

if [[ "${CLAUDE_DESKTOP_OUVERT}" == 1 ]]; then
    DESKTOP_NOTE="  - Claude Desktop est ouvert : il réécrira sa configuration sans le connecteur. Le quitter (⌘Q),
    puis lancer \"${DEST}\" --install, puis le rouvrir : le connecteur « MCP-Developpeur »
    apparaît dans ses outils."
else
    DESKTOP_NOTE="  - Ouvrir Claude Desktop : le connecteur « MCP-Developpeur » apparaît dans ses outils."
fi

if [[ "${LIGHTROOM_OUVERT}" == 1 ]]; then
    LIGHTROOM_NOTE="  - Lightroom Classic est ouvert : le quitter et le relancer pour charger cette version du module."
else
    LIGHTROOM_NOTE="  - Ouvrir Lightroom Classic : le module se charge et démarre la liaison avec Claude."
fi

cat <<FIN

Prochaines étapes :
${LIGHTROOM_NOTE}
    Il apparaît dans Fichier › Gestionnaire de modules externes, sous « Développeur ».
${DESKTOP_NOTE}
  - Dans Claude Code, ouvrir une nouvelle session pour avoir les outils (/clear ne suffit pas).
  - Pour vérifier la liaison (Lightroom ouvert) : "${DEST}" --status
FIN
if [[ -n "${CLAUDE_NOTE}" ]]; then
    printf '%s\n' "${CLAUDE_NOTE}"
fi
if [[ -n "${PRESETS_NOTE}" ]]; then
    printf '%s\n' "${PRESETS_NOTE}"
fi
