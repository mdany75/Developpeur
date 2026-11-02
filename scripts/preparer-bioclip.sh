#!/bin/bash
#
# preparer-bioclip.sh — installe BioCLIP 2 (les espèces, 1.6.3) dans
# ~/Library/Application Support/Developpeur/Modeles/ : télécharge le modèle imageomics/bioclip-2 de
# Hugging Face (licence MIT), convertit ses deux encodeurs en CoreML (fp16), compare leurs vecteurs
# à ceux de PyTorch (cosinus > 0,99), puis les compile (bioclip2_image.mlmodelc,
# bioclip2_text.mlmodelc). Tout reste sur ce Mac : aucune image ne part.
#
# Usage : scripts/preparer-bioclip.sh [dossier de travail] [dossier d'images d'essai]
#
#   dossier de travail : environnement Python (uv, Python 3.12, torch, open_clip_torch,
#     coremltools), poids téléchargés (1,7 Go) et .mlpackage ; par défaut un dossier temporaire,
#     effacé en entier à la fin sauf si BIOCLIP_GARDER=1. Un dossier donné garde son compte rendu
#     (le reste en est effacé de même).
#   dossier d'images : des JPEG pour la comparaison (par défaut, les captures de docs/ et des
#     images synthétiques). Jamais des originaux du catalogue.
#
# Le compte rendu (tailles, temps, écart PyTorch/CoreML, jetons du tokeniseur) s'écrit dans
# <dossier de travail>/compte-rendu.json et sur la sortie. Les jetons du tokeniseur sont comparés au
# contrat des essais (Tests/Contrats/jetons-bioclip.json), qui ne se réécrit qu'avec
# BIOCLIP_CONTRAT=1 : le dépôt ne change pas à chaque passage. Le connecteur relit ensuite les modèles
# par lui-même : `mcp-developpeur --preparer-especes` calcule le cache des vecteurs de la liste.
# Il faut /opt/homebrew/bin/uv (brew install uv) ; aucun droit d'administrateur.

set -euo pipefail
# torch 2.7.0 : la dernière version que coremltools a éprouvée (2.15 l'avertit, 2 nov. 2026).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMPORAIRE=0
[[ -n "${1:-}" ]] || TEMPORAIRE=1
TRAVAIL="${1:-$(mktemp -d "${TMPDIR:-/tmp}/bioclip.XXXXXX")}"
IMAGES="${2:-}"
MODELES="${DEVELOPPEUR_MODELES:-${HOME}/Library/Application Support/Developpeur/Modeles}"
UV="${UV:-/opt/homebrew/bin/uv}"

die() { printf 'Erreur : %s\n' "$1" >&2; exit 1; }
[[ -x "${UV}" ]] || die "uv introuvable (${UV}) : brew install uv"

mkdir -p "${TRAVAIL}"
TRAVAIL="$(cd "${TRAVAIL}" && pwd -P)"
nettoyer() {
    if [[ "${BIOCLIP_GARDER:-0}" != "1" ]]; then
        if [[ "${TEMPORAIRE}" == "1" ]]; then
            rm -rf "${TRAVAIL}"
        else
            rm -rf "${TRAVAIL}/venv" "${TRAVAIL}/cache" "${TRAVAIL}/modele" "${TRAVAIL}/coreml" "${TRAVAIL}/jetons-bioclip.json"
        fi
    fi
}
trap nettoyer EXIT

# Tout le téléchargé reste dans le dossier de travail (ni ~/.cache/uv ni ~/.cache/huggingface).
export UV_CACHE_DIR="${TRAVAIL}/cache/uv"
export UV_PYTHON_INSTALL_DIR="${TRAVAIL}/cache/python"
export HF_HOME="${TRAVAIL}/cache/hf"
export HF_HUB_DISABLE_TELEMETRY=1

printf '1. Environnement Python 3.12 (%s)\n' "${TRAVAIL}/venv"
[[ -x "${TRAVAIL}/venv/bin/python" ]] || "${UV}" venv --quiet --python 3.12 "${TRAVAIL}/venv"
"${UV}" pip install --quiet --python "${TRAVAIL}/venv/bin/python" \
    "torch==2.7.0" open_clip_torch coremltools pillow numpy safetensors huggingface_hub

printf '2. Téléchargement de imageomics/bioclip-2 (%s)\n' "${TRAVAIL}/modele"
"${TRAVAIL}/venv/bin/python" -I -c '
import sys
from huggingface_hub import snapshot_download
snapshot_download("imageomics/bioclip-2", local_dir=sys.argv[1],
                  allow_patterns=["open_clip_config.json", "open_clip_model.safetensors", "*.txt", "*token*", "README.md"])
' "${TRAVAIL}/modele"

printf '3. Conversion, comparaison et compilation\n'
"${TRAVAIL}/venv/bin/python" -I "${ROOT_DIR}/scripts/bioclip/convertir.py" \
    --modele "${TRAVAIL}/modele" --sortie "${TRAVAIL}/coreml" --modeles "${MODELES}" \
    --images "${IMAGES:-${ROOT_DIR}/docs}" --especes "${ROOT_DIR}/Resources/especes/especes.tsv" \
    --contrat "${TRAVAIL}/jetons-bioclip.json" \
    --compte-rendu "${TRAVAIL}/compte-rendu.json"

CONTRAT="${ROOT_DIR}/Tests/Contrats/jetons-bioclip.json"
if [[ "${BIOCLIP_CONTRAT:-0}" == "1" ]]; then
    cp "${TRAVAIL}/jetons-bioclip.json" "${CONTRAT}"
    printf 'Contrat des essais réécrit : %s\n' "${CONTRAT}"
elif ! cmp -s "${TRAVAIL}/jetons-bioclip.json" "${CONTRAT}"; then
    printf 'Attention : le tokeniseur de BioCLIP 2 ne rend plus les jetons du contrat des essais (%s) ;\n' "${CONTRAT}"
    printf 'relancer avec BIOCLIP_CONTRAT=1 pour le réécrire, puis swift test.\n'
fi

printf 'Modèles installés :\n'
du -sh "${MODELES}"/bioclip2_*.mlmodelc
