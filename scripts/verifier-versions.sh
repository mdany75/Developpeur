#!/bin/bash
#
# verifier-versions.sh — vérifie que le numéro de version est le même partout, avant une
# construction (build.sh) et à chaque envoi sur main (.github/workflows/tests.yml).
#
# Usage : scripts/verifier-versions.sh     (depuis n'importe quel dossier courant)
#
# Trois endroits portent le numéro : CFBundleShortVersionString de Resources/Info.plist (incrusté
# dans l'exécutable), VERSION d'Info.lua ({ major = 1, minor = 0, revision = 0, … } vaut 1.0) et
# Liaison.VERSION (que le module annonce au serveur). Le CHANGELOG doit avoir la section de cette
# version, la plus récente du fichier (« ## Non publié » peut rester au-dessus).
#
# Sortie : une ligne « Version X (Info.plist, Info.lua, Liaison.lua et CHANGELOG.md d'accord) »
# et le code 0 ; sinon « Erreur : … » sur stderr et le code 1. Ne lit que ces quatre fichiers,
# trouvés depuis le chemin du script (racine du dépôt = dossier parent de scripts/).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PLUGIN_DIR="${ROOT_DIR}/Lightroom/Developpeur.lrplugin"

die() { printf 'Erreur : %s\n' "$1" >&2; exit 1; }

[[ -f "${ROOT_DIR}/Resources/Info.plist" ]] || die "Resources/Info.plist introuvable dans ${ROOT_DIR}"
[[ -f "${PLUGIN_DIR}/Info.lua" ]] || die "module Lightroom introuvable : ${PLUGIN_DIR}"
[[ -f "${PLUGIN_DIR}/Liaison.lua" ]] || die "Liaison.lua introuvable dans ${PLUGIN_DIR}"
[[ -f "${ROOT_DIR}/CHANGELOG.md" ]] || die "CHANGELOG.md introuvable dans ${ROOT_DIR}"
command -v plutil >/dev/null 2>&1 || die "outil introuvable : plutil"

PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw "${ROOT_DIR}/Resources/Info.plist" 2>/dev/null || true)"
LIAISON_VERSION="$(sed -nE "/^[[:space:]]*VERSION = ['\"]/{s/^[[:space:]]*VERSION = ['\"]([^'\"]*)['\"].*/\1/p;q;}" "${PLUGIN_DIR}/Liaison.lua")"
INFO_LUA_VERSION="$(sed -nE '/^[[:space:]]*VERSION = \{/{s/.*major = ([0-9]+), minor = ([0-9]+), revision = ([0-9]+).*/\1.\2.\3/p;q;}' "${PLUGIN_DIR}/Info.lua")"
CHANGELOG_VERSION="$(sed -nE '/^## [0-9]+\.[0-9]+(\.[0-9]+)? — /{s/^## ([0-9.]+) — .*/\1/p;q;}' "${ROOT_DIR}/CHANGELOG.md")"
[[ "${PLIST_VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || die "numéro de version illisible dans Resources/Info.plist : « ${PLIST_VERSION} »"
[[ "${LIAISON_VERSION}" == "${PLIST_VERSION}" ]] \
    || die "version différente : Info.plist ${PLIST_VERSION}, Liaison.lua ${LIAISON_VERSION:-absente}"
[[ "${INFO_LUA_VERSION%.0}" == "${PLIST_VERSION}" || "${INFO_LUA_VERSION}" == "${PLIST_VERSION}" ]] \
    || die "version différente : Info.plist ${PLIST_VERSION}, Info.lua ${INFO_LUA_VERSION:-absente}"
grep -Eq "^## ${PLIST_VERSION//./\\.} — [0-9]{4}-[0-9]{2}-[0-9]{2}" "${ROOT_DIR}/CHANGELOG.md" \
    || die "CHANGELOG.md n'a pas de section « ## ${PLIST_VERSION} — AAAA-MM-JJ »"
[[ "${CHANGELOG_VERSION}" == "${PLIST_VERSION}" ]] \
    || die "la section la plus récente de CHANGELOG.md est ${CHANGELOG_VERSION:-absente}, pas ${PLIST_VERSION}"
printf "Version %s (Info.plist, Info.lua, Liaison.lua et CHANGELOG.md d'accord)\n" "${PLIST_VERSION}"
