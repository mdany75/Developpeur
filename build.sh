#!/bin/bash
#
# build.sh — vérifie, compile et produit l'archive d'installation « build/Developpeur.zip » :
# le serveur MCP « mcp-developpeur » (le connecteur MCP-Développeur de Claude) et le module
# « Développeur » de Lightroom Classic.
#
# Usage : ./build.sh [--install] [--sans-tests]     (depuis n'importe quel dossier courant)
#         --install     : installe ensuite le serveur et le module depuis l'archive produite, et
#                         inscrit le serveur dans Claude Desktop et Claude Code (install.sh)
#         --sans-tests  : saute les deux suites de tests (essai rapide ; jamais pour une version
#                         publiée)
#
# Variables d'environnement :
#   SIGN_IDENTITY="-"   signature ad hoc même si un certificat est présent
#   SKIP_NOTARIZE=1     signe avec le certificat mais ne notarise pas (essai rapide)
#   NOTARY_PROFILE=nom  profil de « xcrun notarytool store-credentials » (défaut : notarisation)
#
# Étapes :
#   1. vérification que le numéro de version est le même partout (Resources/Info.plist,
#      Info.lua et Liaison.lua du module) et que CHANGELOG.md a sa section « ## X.Y — date »
#   2. les deux suites de tests : swift test (serveur, faux module) et scripts/tester-module.sh
#      (module, Lightroom simulé) ; aucune ne touche Lightroom, Claude ni les photos
#   3. swift build -c release du produit mcp-developpeur
#   4. assemblage d'un dossier « Developpeur » (exécutable, module Developpeur.lrplugin,
#      install.sh, uninstall.sh, README.md, CHANGELOG.md, LICENSE) dans un dossier temporaire
#   5. signature de l'exécutable : Developer ID et runtime durci (ad hoc sans certificat)
#   6. archive « build/Developpeur.zip », notarisée chez Apple
#   7. installation, seulement avec --install : l'archive est décompressée dans le dossier
#      temporaire et son install.sh lancé (on installe exactement ce qui sera publié)
#
# build/ est ignoré par git ; l'archive est publiée en Release GitHub (voir CLAUDE.md).
# Le script s'arrête à la première erreur et n'écrit que dans build/, .build/ et un dossier
# temporaire supprimé à la fin.

set -euo pipefail

PRODUCT="mcp-developpeur"
ARCHIVE_NAME="Developpeur"
IDENTIFIER="com.danymenard.mcp-developpeur"
PLUGIN_NAME="Developpeur.lrplugin"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_DIR="${ROOT_DIR}/Lightroom/${PLUGIN_NAME}"
DIST_DIR="${ROOT_DIR}/build"
STAGE_DIR=""
INSTALL=0
TESTS=1
for arg in "$@"; do
    case "${arg}" in
        --install) INSTALL=1 ;;
        --sans-tests) TESTS=0 ;;
        *) printf 'Option inconnue : %s\nUsage : ./build.sh [--install] [--sans-tests]\n' "${arg}" >&2; exit 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$1"; }
die()  { printf 'Erreur : %s\n' "$1" >&2; exit 1; }
# Toujours vrai : le code de sortie du script reste celui de la dernière étape.
cleanup() { if [[ -n "${STAGE_DIR}" && -d "${STAGE_DIR}" ]]; then rm -rf "${STAGE_DIR}"; fi; }
trap cleanup EXIT

[[ -f "${ROOT_DIR}/Package.swift" ]] || die "Package.swift introuvable dans ${ROOT_DIR}"
[[ -f "${PLUGIN_DIR}/Info.lua" ]] || die "module Lightroom introuvable : ${PLUGIN_DIR}"
[[ -f "${PLUGIN_DIR}/Liaison.lua" ]] || die "Liaison.lua introuvable dans ${PLUGIN_DIR}"
[[ -f "${ROOT_DIR}/CHANGELOG.md" ]] || die "CHANGELOG.md introuvable dans ${ROOT_DIR}"
for fichier in install.sh uninstall.sh README.md LICENSE; do
    [[ -f "${ROOT_DIR}/${fichier}" ]] || die "${fichier} introuvable dans ${ROOT_DIR}"
done
for tool in swift codesign ditto plutil security xcrun; do
    command -v "${tool}" >/dev/null 2>&1 || die "outil introuvable : ${tool}"
done
plutil -lint "${ROOT_DIR}/Resources/Info.plist" >/dev/null || die "Resources/Info.plist invalide"

# --- 1. Version ----------------------------------------------------------------
#
# Trois endroits portent le numéro : CFBundleShortVersionString (incrusté dans l'exécutable),
# VERSION d'Info.lua ({ major = 1, minor = 0, revision = 0, … } vaut 1.0) et Liaison.VERSION
# (que le module annonce au serveur). Le CHANGELOG doit avoir la section de cette version, la
# plus récente du fichier (« ## Non publié » peut rester au-dessus).

PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw "${ROOT_DIR}/Resources/Info.plist")"
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
step "Version ${PLIST_VERSION} (Info.plist, Info.lua, Liaison.lua et CHANGELOG.md d'accord)"

# --- Signature et notarisation ------------------------------------------------
#
# Avec le certificat « Developer ID Application » dans le trousseau, l'exécutable est signé
# avec le runtime durci, puis l'archive est notarisée chez Apple : elle s'ouvre sans
# avertissement sur n'importe quel Mac. Sans certificat (autre machine), signature ad hoc et
# pas de notarisation. Le module Lightroom (Lua, un script shell, du JavaScript, des images)
# n'a rien à signer.

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarisation}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    SIGN_ARGS=(--sign -)
    NOTARIZE=0; NOTARIZE_WHY="signature ad hoc, aucun certificat Developer ID"
elif [[ "${SKIP_NOTARIZE:-0}" != "0" ]]; then
    SIGN_ARGS=(--options runtime --timestamp --sign "${SIGN_IDENTITY}")
    NOTARIZE=0; NOTARIZE_WHY="SKIP_NOTARIZE=1"
else
    SIGN_ARGS=(--options runtime --timestamp --sign "${SIGN_IDENTITY}")
    NOTARIZE=1; NOTARIZE_WHY=""
fi

# sign_code OPTIONS… CHEMIN : signe, puis vérifie. Le serveur d'horodatage d'Apple renvoie
# parfois une heure décalée de quelques minutes, que « codesign --verify --strict » refuse
# (« timestamps differ ») : on signe alors de nouveau, jusqu'à trois fois.
sign_code() {
    local attempt
    for attempt in 1 2 3; do
        codesign --force "$@"
        codesign --verify --deep --strict "${@:$#}" && return 0
        printf 'Vérification de la signature refusée (essai %s/3), nouvelle signature…\n' "${attempt}" >&2
        sleep 2
    done
    die "signature impossible à vérifier : ${@:$#}"
}

# notarize_file FICHIER : soumet l'archive à Apple et attend le verdict (quelques minutes).
notarize_file() {
    local file="$1" output id
    step "Notarisation de « $(basename "${file}") » (profil « ${NOTARY_PROFILE} »)"
    if ! output="$(xcrun notarytool submit "${file}" --keychain-profile "${NOTARY_PROFILE}" --wait 2>&1)"; then
        printf '%s\n' "${output}" >&2
        die "notarisation impossible : session verrouillée (le profil n'est lisible qu'écran déverrouillé) ou profil « ${NOTARY_PROFILE} » absent (xcrun notarytool store-credentials)"
    fi
    printf '%s\n' "${output}"
    if ! grep -q '^ *status: Accepted' <<< "${output}"; then
        id="$(sed -n 's/^ *id: //p' <<< "${output}" | head -n 1)"
        [[ -z "${id}" ]] || xcrun notarytool log "${id}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
        die "notarisation refusée par Apple (détail ci-dessus)"
    fi
}

# finalize_archive ARCHIVE : notarise l'archive chez Apple. Le ticket d'un exécutable seul ne
# s'agrafe pas : macOS retrouve le ticket en ligne au premier lancement. Sans notarisation,
# dit seulement pourquoi.
finalize_archive() {
    local archive="$1"
    if [[ "${NOTARIZE}" -eq 0 ]]; then
        step "Archive non notarisée (${NOTARIZE_WHY}) : macOS peut bloquer l'exécutable sur un autre Mac"
        return 0
    fi
    notarize_file "${archive}"
    step "Archive notarisée : $(basename "${archive}")"
}

# --- 2. Tests -----------------------------------------------------------------

if [[ "${TESTS}" -eq 1 ]]; then
    step "Tests du serveur (swift test)"
    swift test --package-path "${ROOT_DIR}"
    step "Tests du module (scripts/tester-module.sh)"
    bash "${ROOT_DIR}/scripts/tester-module.sh"
else
    step "Tests sautés (--sans-tests) : archive pour essai seulement, à ne pas publier"
fi

# --- 3. Compilation -----------------------------------------------------------

step "Compilation (release, version ${PLIST_VERSION})"
swift build -c release --product "${PRODUCT}" --package-path "${ROOT_DIR}"
BIN_DIR="$(swift build -c release --product "${PRODUCT}" --package-path "${ROOT_DIR}" --show-bin-path)"
BINARY="${BIN_DIR}/${PRODUCT}"
[[ -x "${BINARY}" ]] || die "exécutable introuvable après la compilation : ${BINARY}"

# --- 4. Assemblage ------------------------------------------------------------

step "Assemblage de « ${ARCHIVE_NAME} »"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/developpeur.XXXXXX")"
STAGE="${STAGE_DIR}/${ARCHIVE_NAME}"
mkdir -p "${STAGE}"
cp "${BINARY}" "${STAGE}/${PRODUCT}"
chmod 755 "${STAGE}/${PRODUCT}"
ditto "${PLUGIN_DIR}" "${STAGE}/${PLUGIN_NAME}"
find "${STAGE}/${PLUGIN_NAME}" \( -name '.DS_Store' -o -name '._*' \) -delete
cp "${ROOT_DIR}/install.sh" "${ROOT_DIR}/uninstall.sh" "${ROOT_DIR}/README.md" \
    "${ROOT_DIR}/CHANGELOG.md" "${ROOT_DIR}/LICENSE" "${STAGE}/"
chmod 755 "${STAGE}/install.sh" "${STAGE}/uninstall.sh"

# --- 5. Signature -------------------------------------------------------------

step "Signature (${SIGN_IDENTITY})"
xattr -cr "${STAGE}"
sign_code "${SIGN_ARGS[@]}" --identifier "${IDENTIFIER}" "${STAGE}/${PRODUCT}"
VERSION="$("${STAGE}/${PRODUCT}" --version)"
[[ "${VERSION}" == "${PLIST_VERSION}" ]] || die "l'exécutable donne la version « ${VERSION} » au lieu de ${PLIST_VERSION}"

# --- 6. Archive ---------------------------------------------------------------

step "Archive « ${ARCHIVE_NAME}.zip » (version ${VERSION})"
mkdir -p "${DIST_DIR}"
ditto -c -k --keepParent "${STAGE}" "${STAGE_DIR}/${ARCHIVE_NAME}.zip"
mv -f "${STAGE_DIR}/${ARCHIVE_NAME}.zip" "${DIST_DIR}/${ARCHIVE_NAME}.zip"
finalize_archive "${DIST_DIR}/${ARCHIVE_NAME}.zip"

# --- 7. Installation (avec --install) -----------------------------------------

if [[ "${INSTALL}" -eq 1 ]]; then
    step "Installation depuis build/${ARCHIVE_NAME}.zip"
    mkdir -p "${STAGE_DIR}/installation"
    ditto -x -k "${DIST_DIR}/${ARCHIVE_NAME}.zip" "${STAGE_DIR}/installation"
    bash "${STAGE_DIR}/installation/${ARCHIVE_NAME}/install.sh"
fi

step "Terminé"
printf '%s\n' "${DIST_DIR}/${ARCHIVE_NAME}.zip"
