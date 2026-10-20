#!/bin/bash
#
# tester-module.sh — vérifie le module Lightroom « Développeur » hors de Lightroom, avec LuaJIT
# (Lua 5.1, comme Lightroom) : la forme du module (fichiers nommés dans Info.lua, noms requis),
# la syntaxe et les globales de chaque fichier, la syntaxe de relais.sh, les liens entre les
# fichiers, puis les deux suites de tests, chacune sur son Lightroom simulé
# (Tests/Lua/<suite>/Simulation.lua) :
#   - Liaison : les commandes du serveur MCP (retouche, masques, tri, livraison…) ;
#   - Fenetre : la fenêtre Claude (relais.sh et le moteur avec un faux Claude Code, ni Claude ni
#     quota), Publication et Consommation.
# Aucune ne touche Lightroom, Claude ni les fichiers de Claude : les fichiers vont dans un dossier
# personnel simulé ou temporaire.
#
# Usage : scripts/tester-module.sh      (LuaJIT : brew install luajit)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PLUGIN_DIR="${ROOT_DIR}/Lightroom/Developpeur.lrplugin"
TESTS_DIR="${ROOT_DIR}/Tests/Lua"

command -v luajit >/dev/null 2>&1 || { printf 'LuaJIT introuvable : brew install luajit\n' >&2; exit 1; }

# Forme du module ---------------------------------------------------------------------------------

erreurs=0
echec() {
    printf 'ÉCHEC  %s\n' "$1" >&2
    erreurs=$((erreurs + 1))
}

# Les fichiers, tels qu'écrits sur le disque (le disque du Mac ignore la casse : « require 'fil' »
# trouverait Fil.lua sur le Mac, pas forcément ailleurs).
fichiers=()
for file in "${PLUGIN_DIR}"/*.lua; do
    fichiers+=("$(basename "${file}" .lua)")
done
existe() {
    local nom
    for nom in "${fichiers[@]}"; do
        [[ "${nom}" == "$1" ]] && return 0
    done
    return 1
}

# Deux fichiers qui ne diffèrent que par la casse rendraient un nom requis ambigu.
doublons="$(printf '%s\n' "${fichiers[@]}" | tr '[:upper:]' '[:lower:]' | sort | uniq -d)"
[[ -z "${doublons}" ]] || echec "noms de fichiers ambigus (casse) : ${doublons}"

# Lightroom refuse de charger un module nommé Versions.lua (constaté).
existe Versions && echec "un fichier s'appelle Versions.lua : Lightroom ne le charge pas"

# Plus de fichiers de fusion (InfoFenetre.lua, InitFenetre.lua…) : un seul Info, Init, Arret et
# PluginInfoProvider pour le module.
for nom in "${fichiers[@]}"; do
    [[ "${nom}" == ?*Fenetre ]] && echec "fichier de fusion restant : ${nom}.lua"
done

# Chaque fichier nommé dans Info.lua existe.
nommes=0
while read -r nom; do
    nommes=$((nommes + 1))
    existe "${nom%.lua}" || echec "Info.lua nomme ${nom}, introuvable"
done < <(LC_ALL=C sed -nE "s/.*(file|Lr[A-Za-z]+Plugin|LrPluginInfoProvider|LrMetadataProvider)[[:space:]]*=[[:space:]]*'([^']+\.lua)'.*/\2/p" "${PLUGIN_DIR}/Info.lua" | sort -u)

# Chaque nom requis est celui d'un fichier du module, à la casse près (ou un module de Lua).
requis=0
while read -r nom; do
    requis=$((requis + 1))
    existe "${nom}" || echec "require '${nom}' : aucun fichier ${nom}.lua dans le module"
done < <(cat "${PLUGIN_DIR}"/*.lua | LC_ALL=C grep -oE "require[[:space:]]*\(?[[:space:]]*'[A-Za-z_][A-Za-z0-9_]*'" | LC_ALL=C sed -E "s/.*'([^']+)'/\1/" | sort -u)

[[ ${erreurs} -eq 0 ]] || exit 1
printf 'Forme : %d fichiers nommés dans Info.lua, %d modules requis, tous présents ; aucun nom ambigu\n' "${nommes}" "${requis}"

# Syntaxe et globales de chaque fichier ------------------------------------------------------------

for file in "${PLUGIN_DIR}"/*.lua; do
    FICHIER="${file}" luajit -e "local f, e = loadfile(os.getenv('FICHIER')); if not f then io.stderr:write(e, '\n'); os.exit(1) end"
done
printf 'Syntaxe : %s fichiers vérifiés\n' "${#fichiers[@]}"

# Globales : seulement celles de Lua et du SDK (import, _PLUGIN). Une fonction d'un autre module
# oubliée dans les alias d'un fichier se lirait comme une globale vide.
PERMISES='_PLUGIN error getmetatable import io ipairs math next os pairs pcall require select setmetatable string table tonumber tostring type unpack'
inconnues=0
for file in "${PLUGIN_DIR}"/*.lua; do
    while read -r genre nom; do
        if [[ "${genre}" == GSET || " ${PERMISES} " != *" ${nom} "* ]]; then
            printf 'ÉCHEC  %s : globale %s %s\n' "$(basename "${file}")" "$([[ "${genre}" == GSET ]] && echo écrite || echo lue)" "${nom}" >&2
            inconnues=$((inconnues + 1))
        fi
    done < <(luajit -bl "${file}" | LC_ALL=C sed -nE 's/.*(GGET|GSET)[^;]*; "([^"]+)"$/\1 \2/p' | sort -u)
done
[[ ${inconnues} -eq 0 ]] || exit 1
printf 'Globales : aucune inconnue\n'

sh -n "${PLUGIN_DIR}/relais.sh"
sh -n "${TESTS_DIR}/Fenetre/faux-claude.sh"
printf 'relais.sh et faux-claude.sh : syntaxe vérifiée\n'

# Liens entre les fichiers (tous : liaison et fenêtre Claude) -------------------------------------

luajit "${TESTS_DIR}/Liaison/liens.lua" "${PLUGIN_DIR}"/*.lua

# Suite de la liaison (Tests/Lua/Liaison) ----------------------------------------------------------

printf '\nLiaison\n'
luajit "${TESTS_DIR}/Liaison/tests.lua"

# Suite de la fenêtre Claude (Tests/Lua/Fenetre) ---------------------------------------------------

printf '\nFenêtre Claude\n'
cd "${TESTS_DIR}/Fenetre"
PLUGIN_DIR="${PLUGIN_DIR}" luajit tests.lua
