#!/bin/bash
#
# uninstall.sh — retire « Développeur » : l'inscription du serveur « MCP-Developpeur » dans
# Claude Desktop et Claude Code, le serveur mcp-developpeur, le module « Développeur » de
# Lightroom Classic et ses paramètres prédéfinis invisibles (Lightroom fermé seulement), et les
# fichiers de travail que le module refait seul (sessions de Claude Code, dossier de travail,
# configuration MCP et consignes de la fenêtre Claude).
#
# Usage : bash uninstall.sh [--tout]
#         --tout : retire aussi ce que le module et le serveur ont gardé pour l'utilisateur, qui
#                  reste sans cette option : guide de style, conversations de la fenêtre Claude,
#                  profils de publication, registre de consommation, et les journaux
#                  (~/Library/Logs/Developpeur)
#
# Le catalogue et les photos ne sont jamais touchés : les retouches déjà faites restent (elles
# s'annulent dans le panneau Historique).

set -euo pipefail

DEST_DIR="${HOME}/Library/Application Support/Developpeur"
DEST="${DEST_DIR}/mcp-developpeur"
PLUGIN_DEST="${HOME}/Library/Application Support/Adobe/Lightroom/Modules/Developpeur.lrplugin"
PRESETS_DIR="${HOME}/Library/Application Support/Adobe/Lightroom/Plugin Develop Presets/com.danymenard.developpeur"
JOURNAUX="${HOME}/Library/Logs/Developpeur"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# Fichiers de travail, refaits par le module ou le serveur au besoin (voir Chemins.lua).
TRAVAIL=(
    "${DEST}"
    "${DEST}.nouveau"
    "${DEST_DIR}/Sessions"
    "${DEST_DIR}/Atelier"
    "${DEST_DIR}/Temporaire"
    "${DEST_DIR}/connecteur.json"
    "${DEST_DIR}/consignes.md"
)

TOUT=0
for arg in "$@"; do
    case "${arg}" in
        --tout) TOUT=1 ;;
        *) printf 'Option inconnue : %s\nUsage : bash uninstall.sh [--tout]\n' "${arg}" >&2; exit 2 ;;
    esac
done

retirer() {
    if [[ -e "$1" || -L "$1" ]]; then
        rm -rf "$1"
        printf 'Supprimé : %s\n' "$1"
    fi
}

# Claude Desktop ouvert garde sa configuration en mémoire et la réécrit, inscription comprise
# (constaté le 20 octobre 2026, voir install.sh) : le retrait ne tient que Claude Desktop fermé.
# -a : pgrep voit aussi Claude Desktop depuis une session de Claude Code qu'il a lancée.
if pgrep -xaq Claude; then
    printf 'Claude Desktop est ouvert : il peut remettre « MCP-Developpeur » en réécrivant sa configuration.\n' >&2
    printf "Après l'avoir quitté (⌘Q), retirer « MCP-Developpeur » de mcpServers dans ~/Library/Application Support/Claude/claude_desktop_config.json s'il y est encore.\n" >&2
fi

# Inscription d'abord : l'exécutable installé la retire, sinon celui de l'archive décompressée.
if [[ -x "${DEST}" ]]; then
    "${DEST}" --uninstall
elif [[ -x "${HERE}/mcp-developpeur" ]]; then
    "${HERE}/mcp-developpeur" --uninstall
else
    printf 'Aucun exécutable trouvé : les inscriptions dans Claude ne peuvent pas être retirées automatiquement.\n' >&2
    printf 'Retirer « MCP-Developpeur » de mcpServers dans ~/Library/Application Support/Claude/claude_desktop_config.json et ~/.claude.json.\n' >&2
fi

retirer "${PLUGIN_DEST}"
# Paramètres prédéfinis invisibles créés par le module : Lightroom les charge à son lancement.
if [[ -d "${PRESETS_DIR}" ]]; then
    if pgrep -xq "Adobe Lightroom Classic"; then
        printf 'Gardé (Lightroom ouvert) : %s ; le supprimer Lightroom fermé.\n' "${PRESETS_DIR}"
    else
        retirer "${PRESETS_DIR}"
    fi
fi

if [[ "${TOUT}" == 1 ]]; then
    retirer "${DEST_DIR}"
    retirer "${JOURNAUX}"
else
    for chemin in "${TRAVAIL[@]}"; do
        retirer "${chemin}"
    done
    # Le dossier ne reste que s'il garde quelque chose pour l'utilisateur.
    if [[ -d "${DEST_DIR}" ]]; then
        rm -f "${DEST_DIR}/.DS_Store"
        rmdir "${DEST_DIR}" 2>/dev/null && printf 'Supprimé : %s\n' "${DEST_DIR}"
    fi
    GARDES=()
    [[ -d "${DEST_DIR}" ]] && GARDES+=("${DEST_DIR} (guide de style, conversations, profils de publication, consommation)")
    [[ -d "${JOURNAUX}" ]] && GARDES+=("${JOURNAUX} (journaux)")
    if [[ ${#GARDES[@]} -gt 0 ]]; then
        printf 'Gardé pour vous :\n'
        printf '  - %s\n' "${GARDES[@]}"
        printf 'Pour les retirer aussi : bash uninstall.sh --tout\n'
    fi
fi

printf 'Terminé. Relancer Claude Desktop, ouvrir une nouvelle session Claude Code et relancer Lightroom Classic pour que le connecteur et le module disparaissent.\n'
