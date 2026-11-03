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
#   5. mises à jour par le SSD (1.7) : garde l'archive dans Developpeur/Archive et, avec un dossier
#      commun réglé, la dépose dans son dossier Installation si elle y est plus récente (l'autre Mac
#      l'installe de là, sans téléchargement) ; ni l'un ni l'autre quand l'installation vient du SSD
#      (DEVELOPPEUR_DEPUIS_SSD=1) ou d'une archive d'essai de build.sh (DEVELOPPEUR_PAS_DE_DEPOT=1)
#
# Les modèles du sens et des espèces vont dans Modeles de la racine des données (le dossier commun
# s'il est réglé). Ce qui est déjà là reste : guide de style, conversations, profils de publication,
# registre de consommation et journaux. Le catalogue et les photos ne sont jamais touchés.
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

# Modeles de la racine des données (1.7) : celui du dossier commun s'il est réglé, sinon celui de ce
# Mac (le connecteur le dit, --racine-donnees). Dossier commun réglé mais introuvable (SSD débranché) :
# rien n'est écrit dans le Modeles de ce Mac à sa place ; les modèles attendent le SSD.
MODELES_NOTE=""
if DONNEES="$("${DEST}" --racine-donnees 2>/dev/null)" && [[ -n "${DONNEES}" ]]; then
    MODELES="${DONNEES}/Modeles"
else
    MODELES=""
    MODELES_NOTE="  - Le dossier commun est introuvable (SSD débranché ?) : vocabulaire, liste des espèces et modèles
    compilés non mis à jour. Brancher le SSD, puis relancer install.sh."
fi

# La recherche par le sens (1.6) : le vocabulaire du tokeniseur de CLIP, à côté des modèles de
# MobileCLIP (qui ne viennent pas avec l'archive : hf download apple/coreml-mobileclip) ; jamais
# remplacé s'il est déjà là.
VOCABULAIRE="${HERE}/bpe_simple_vocab_16e6.txt.gz"
if [[ -n "${MODELES}" && -f "${VOCABULAIRE}" && ! -f "${MODELES}/bpe_simple_vocab_16e6.txt.gz" ]]; then
    mkdir -p "${MODELES}"
    cp "${VOCABULAIRE}" "${MODELES}/"
    printf 'Vocabulaire de la recherche par le sens : %s\n' "${MODELES}"
fi
# Les modèles de MobileCLIP compilés ici, une fois (rien s'ils le sont déjà), pour que le Suivi ne
# compile jamais sous son alarme ; sans les modèles, rien (la recherche par le sens reste absente).
if [[ -n "${MODELES}" && -f "${MODELES}/bpe_simple_vocab_16e6.txt.gz" ]]; then
    if COMPILE="$("${DEST}" --compiler-sens 2>/dev/null)"; then
        printf 'Recherche par le sens : modèles compilés (%s)\n' "${COMPILE}"
    else
        printf 'Recherche par le sens : modèles non compilés (%s)\n' "${COMPILE:-pas de réponse}"
    fi
fi
# Les espèces (1.6.3) : la liste, remplacée à chaque installation (elle change avec la version) ;
# avec BioCLIP 2 déjà installé (scripts/preparer-bioclip.sh, depuis le dépôt), les vecteurs de la
# liste se calculent ici s'ils manquent ou si la liste a changé. Sans le modèle, rien de plus.
if [[ -n "${MODELES}" && -f "${HERE}/especes.tsv" ]]; then
    mkdir -p "${MODELES}"
    cp "${HERE}/especes.tsv" "${MODELES}/especes.tsv"
fi
if [[ -n "${MODELES}" && -d "${MODELES}/bioclip2_image.mlmodelc" ]]; then
    if ESPECES="$("${DEST}" --preparer-especes 2>/dev/null)"; then
        printf 'Espèces : BioCLIP 2 prêt (%s)\n' "${ESPECES}"
    else
        printf 'Espèces : BioCLIP 2 non prêt (%s)\n' "${ESPECES:-pas de réponse}"
    fi
fi

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

# --- 5. Mises à jour par le SSD (1.7) ------------------------------------------
#
# Cette archive est gardée sur ce Mac (Developpeur/Archive/Developpeur.zip), puis déposée dans le
# dossier commun (Installation/, par le connecteur) si elle y est plus récente : l'autre Mac
# l'installera depuis le SSD, sans téléchargement. L'archive : DEVELOPPEUR_ARCHIVE, sinon le
# Developpeur.zip d'à côté s'il porte cette version, sinon refaite par ditto depuis ce dossier.
# Rien de tout ça quand l'installation vient du SSD (DEVELOPPEUR_DEPUIS_SSD) ou d'une archive
# d'essai de build.sh (DEVELOPPEUR_PAS_DE_DEPOT : non notarisée, ou sans tests).

DEPOT_NOTE=""
if [[ "${DEVELOPPEUR_DEPUIS_SSD:-0}" != 1 && "${DEVELOPPEUR_PAS_DE_DEPOT:-0}" != 1 ]]; then
    version_lua() { sed -nE 's/.*VERSION = \{ major = ([0-9]+), minor = ([0-9]+), revision = ([0-9]+).*/\1.\2.\3/p' | head -n 1; }
    NOTRE_VERSION="$(version_lua < "${PLUGIN_SOURCE}/Info.lua")"
    ARCHIVE="${DEVELOPPEUR_ARCHIVE:-}"
    REFAITE=""
    VOISINE="$(dirname "${HERE}")/Developpeur.zip"
    if [[ -z "${ARCHIVE}" && -f "${VOISINE}" ]] \
        && [[ "$(unzip -p "${VOISINE}" 'Developpeur/Developpeur.lrplugin/Info.lua' 2>/dev/null | version_lua)" == "${NOTRE_VERSION}" ]]; then
        ARCHIVE="${VOISINE}"
    fi
    if [[ -z "${ARCHIVE}" ]]; then
        REFAITE="$(mktemp -d "${TMPDIR:-/tmp}/developpeur-archive.XXXXXX")"
        ditto --norsrc --noextattr "${HERE}" "${REFAITE}/Developpeur"
        ditto -c -k --norsrc --noextattr --keepParent "${REFAITE}/Developpeur" "${REFAITE}/Developpeur.zip"
        ARCHIVE="${REFAITE}/Developpeur.zip"
    fi
    mkdir -p "${DEST_DIR}/Archive"
    cp -f "${ARCHIVE}" "${DEST_DIR}/Archive/Developpeur.zip.partiel"
    mv -f "${DEST_DIR}/Archive/Developpeur.zip.partiel" "${DEST_DIR}/Archive/Developpeur.zip"
    [[ -z "${REFAITE}" ]] || rm -rf "${REFAITE}"
    if [[ -f "${DEST_DIR}/dossier-commun.json" ]]; then
        if DEPOT="$("${DEST}" --mises-a-jour --deposer developpeur --archive "${DEST_DIR}/Archive/Developpeur.zip" 2>&1)"; then
            printf '%s\n' "$(grep -E '^Développeur IA' <<< "${DEPOT}" | tail -n 1)"
        else
            DEPOT_NOTE="  - Archive non déposée sur le SSD : $(grep -E 'Développeur IA|Aucun dossier|Le dossier commun|Une autre' <<< "${DEPOT}" | tail -n 1 | sed 's/^\[mcp-developpeur\] //')
    (mcp-developpeur --mises-a-jour --deposer developpeur, une fois le SSD branché)."
        fi
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
    Fichier › Gestionnaire de modules externes › Développeur IA pour Lightroom."
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
    Il apparaît dans Fichier › Gestionnaire de modules externes, sous « Développeur IA pour Lightroom ».
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
if [[ -n "${MODELES_NOTE}" ]]; then
    printf '%s\n' "${MODELES_NOTE}"
fi
if [[ -n "${DEPOT_NOTE}" ]]; then
    printf '%s\n' "${DEPOT_NOTE}"
fi
