#!/bin/sh
#
# relais.sh — garde Claude Code ouvert pour une conversation de la fenêtre Claude (module
# Développeur de Lightroom).
# Lightroom ne sait ni lancer un processus avec ses tuyaux ni lui écrire : la fenêtre ajoute une
# ligne JSON par message à entree.jsonl, que `tail -f` passe à Claude Code ; Claude Code écrit ses
# événements dans sortie.jsonl, que la fenêtre relit. Le forfait Claude Code est employé (connexion
# claude.ai), jamais une clé d'API.
#
# Usage : relais.sh <dossier> <claude> <modèle> <effort ou ""> <session à reprendre ou "">
#                   <dossier de travail> <config MCP> <consignes> <pid de Lightroom ou 0>
#
# Fichiers dans <dossier> : entree.jsonl (écrit par la fenêtre), consignes.md (les consignes de
# cette session, passées en <consignes>), sortie.jsonl, erreurs.log, relais.pid, claude.pid ;
# « arreter » (créé par la fenêtre) ferme Claude Code ; fin.code (écrit à la fin) contient son code
# de sortie.
#
# Dossier commun (3 novembre 2026 : deux Mac, un SSD, reprendre la conversation sur l'autre) : le
# module pose DEVELOPPEUR_DONNEES (la racine des données) seulement quand un dossier commun est
# réglé. Claude Code range l'échange d'une session dans
# ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<dossier de travail encodé>/<id>.jsonl ; avant de lancer
# Claude Code avec --resume, « <racine>/Claude Code/<id>.jsonl » y est copié s'il manque, ou si
# l'échange local en est le début (jamais un échange local qui a des tours de plus : il est gardé,
# et le journal le dit) ; après sa fin (normale, en erreur, ou par un signal TERM, HUP ou INT :
# `trap`), l'échange de la session (l'id repris, ou celui que Claude Code a donné dans sa sortie,
# champ session_id) est copié vers « <racine>/Claude Code/ » ; si l'échange du dossier commun n'en
# était pas le début (l'autre Mac y a ajouté des tours), il est d'abord gardé à côté,
# « <id>.jsonl.avant-<date> » : rien n'est perdu. Seulement ces .jsonl : jamais les fichiers de
# connexion de Claude Code, ni ~/.claude.json. Ce qui est copié est noté dans dossier-commun.log
# (dans <dossier>) ; une copie manquée, ou le dossier commun disparu à la fin, est écrite dans
# dossier-commun.erreur, que la fenêtre lit avec fin.code (Journal et note de la conversation).
# Sans DEVELOPPEUR_DONNEES, rien ne change.
#
# relais.sh --projet <dossier de travail> écrit le dossier du projet de Claude Code de ce dossier
# de travail (le même encodage) : le réglage du dossier commun y prend les échanges des
# conversations à copier.

# Le dossier du projet de Claude Code pour un dossier de travail : son chemin physique (celui que
# Claude Code voit), chaque caractère qui n'est ni une lettre ASCII ni un chiffre remplacé par « - »
# (un caractère accentué compte pour un, d'où la locale UTF-8 : « Le Développeur » donne
# « Le-D-veloppeur », constaté dans ~/.claude/projects). Rien si le dossier est introuvable.
dossierProjet() {
    physique=$(cd "$1" 2>/dev/null && pwd -P)
    [ -n "$physique" ] || return 1
    encode=$(printf '%s' "$physique" | LC_ALL=en_US.UTF-8 sed 's/[^abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]/-/g')
    printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$encode"
}

if [ "$1" = "--projet" ]; then
    dossierProjet "$2"
    exit $?
fi

dossier=$1
claude=$2
modele=$3
effort=$4
reprise=$5
travail=$6
config=$7
consignes=$8
lightroom=${9:-0}

cd "$dossier" || exit 1
echo $$ > relais.pid

# Lightroom : le parent du shell qui a lancé ce script. Sinon le premier processus de Lightroom
# Classic, ou personne (0 : essais hors de Lightroom).
case "$(ps -p "$lightroom" -o comm= 2>/dev/null)" in
    *Lightroom*) ;;
    *) lightroom=$(pgrep -f 'Adobe Lightroom Classic.app/Contents/MacOS' 2>/dev/null | head -n 1)
       lightroom=${lightroom:-0} ;;
esac

# Le forfait, pas une clé d'API ni un autre fournisseur hérités de l'environnement.
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# Une réponse d'outil plus longue que 25 000 tokens (le défaut de Claude Code) serait rangée dans un
# fichier que Claude ne peut pas lire ici (--tools "") : constaté le 26 octobre 2026, le tri de
# 951 photos (147 000 caractères) et list_selection à 500 perdus.
export MAX_MCP_OUTPUT_TOKENS=100000

# Dossier commun --------------------------------------------------------------------------------

donnees=${DEVELOPPEUR_DONNEES:-}
echanges="$donnees/Claude Code"
projet=""
if [ -n "$donnees" ]; then
    projet=$(dossierProjet "$travail")
fi

# Vrai si le dossier commun est réglé et présent (le module refuse de lancer sinon ; ici, jamais de
# copie vers un dossier local à sa place).
commun() {
    [ -n "$donnees" ] && [ -d "$donnees" ] && [ -n "$projet" ]
}

# Une copie manquée : dans le journal de la session, et dans dossier-commun.erreur (lu par la
# fenêtre avec fin.code : Session.menage efface ensuite ce dossier).
manque() {
    printf '%s\n' "$1" >> dossier-commun.log
    printf '%s\n' "$1" >> dossier-commun.erreur
}

# Un identifiant de session sûr pour un nom de fichier (lettres, chiffres, « - », « _ »).
identifiant() {
    case "$1" in
        ''|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    return 0
}

# Vrai si le fichier $1 est le début du fichier $2 (ou lui est égal).
debutDe() {
    taille1=$(wc -c < "$1" | tr -d ' ')
    taille2=$(wc -c < "$2" | tr -d ' ')
    # (cmp -n de macOS dit « EOF » quand le premier fichier finit pile au compte : head -c.)
    [ "$taille1" -le "$taille2" ] && head -c "$taille1" "$2" | cmp -s - "$1"
}

# Copie $1 vers $2, date gardée (cp -p), par un fichier provisoire renommé ensuite (jamais un
# échange à moitié copié).
copier() {
    mkdir -p "$(dirname "$2")" || { manque "non copié : $1 -> $2"; return 1; }
    if cp -p "$1" "$2.copie" && mv -f "$2.copie" "$2"; then
        printf 'copié : %s -> %s\n' "$1" "$2" >> dossier-commun.log
        return 0
    fi
    rm -f "$2.copie"
    manque "non copié : $1 -> $2"
    return 1
}

# Avant --resume : l'échange du dossier commun ($1) vers l'échange local ($2), s'il manque en local
# ou si l'échange local en est le début. Un échange local qui a des tours que le dossier commun n'a
# pas n'est jamais remplacé : il est gardé, et le journal le dit.
reprendre() {
    [ -f "$1" ] || return 0
    if [ ! -f "$2" ]; then
        copier "$1" "$2"
    elif cmp -s "$1" "$2"; then
        return 0
    elif debutDe "$2" "$1"; then
        copier "$1" "$2"
    else
        printf "gardé : l'échange local %s a des tours que %s n'a pas\n" "$2" "$1" >> dossier-commun.log
    fi
}

# Après la fin : l'échange local ($1) vers le dossier commun ($2). Si l'échange du dossier commun
# n'est pas le début de l'échange local (l'autre Mac y a ajouté des tours), il est d'abord gardé à
# côté, « <id>.jsonl.avant-<date> » : jamais écrasé sans copie.
ranger() {
    [ -f "$1" ] || return 0
    if [ -f "$2" ]; then
        cmp -s "$1" "$2" && return 0
        if ! debutDe "$2" "$1"; then
            garde="$2.avant-$(date '+%Y-%m-%d-%H%M%S')"
            if cp -p "$2" "$garde"; then
                printf 'gardé à côté : %s -> %s\n' "$2" "$garde" >> dossier-commun.log
            else
                manque "non copié : $1 -> $2 (l'échange du dossier commun n'a pas pu être gardé à côté)"
                return 1
            fi
        fi
    fi
    copier "$1" "$2"
}

# Avant le lancement : l'échange de la session reprise, depuis le dossier commun.
if commun && identifiant "$reprise"; then
    reprendre "$echanges/$reprise.jsonl" "$projet/$reprise.jsonl"
fi

touch entree.jsonl
rm -f tuyau
mkfifo tuyau || { echo "mkfifo impossible" > erreurs.log; echo 1 > fin.code; exit 1; }

tail -n +1 -f entree.jsonl > tuyau &
lecteur=$!

# Seulement le connecteur MCP-Développeur (--strict-mcp-config, nommé developpeur dans la
# configuration : ses outils sont mcp__developpeur__*), aucun outil intégré (--tools ""), rien
# qui demande une permission, ni compétences ni réglages de l'utilisateur (moins de contexte).
set -- -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages \
    --mcp-config "$config" --strict-mcp-config \
    --tools "" --allowedTools "mcp__developpeur__*" --permission-prompts none \
    --disable-slash-commands --setting-sources local \
    --model "$modele" --append-system-prompt-file "$consignes"
# L'effort (low, medium, high, xhigh, max), le même pour les quatre modèles ; vide : celui de
# Claude Code.
if [ -n "$effort" ]; then
    set -- "$@" --effort "$effort"
fi
if [ -n "$reprise" ]; then
    set -- "$@" --resume "$reprise"
fi

(cd "$travail" && exec "$claude" "$@") < tuyau > sortie.jsonl 2> erreurs.log &
processus=$!
echo $processus > claude.pid

# Ferme Claude Code à la demande de la fenêtre ou quand Lightroom n'est plus là : d'abord la fin
# de son entrée (il termine proprement), puis l'arrêt s'il traîne.
fermer() {
    kill $lecteur 2>/dev/null
    attente=0
    while kill -0 $processus 2>/dev/null && [ $attente -lt 3 ]; do
        sleep 1
        attente=$((attente + 1))
    done
    kill $processus 2>/dev/null
}

# Après la fin de Claude Code (normale, en erreur ou par un signal) : l'échange de la session vers
# le dossier commun, avant fin.code (la fenêtre peut relancer dès qu'elle le lit). Une seule fois.
fini=""
finir() {
    [ -z "$fini" ] || return 0
    fini=1
    kill $lecteur 2>/dev/null
    rm -f tuyau
    if [ -n "$donnees" ]; then
        if commun; then
            session=$(sed -n 's/.*"session_id":"\([A-Za-z0-9_-]*\)".*/\1/p' sortie.jsonl 2>/dev/null | tail -n 1)
            [ -n "$session" ] || session=$reprise
            if identifiant "$session"; then
                ranger "$projet/$session.jsonl" "$echanges/$session.jsonl"
            fi
        else
            manque "non copié : le dossier commun $donnees est introuvable à la fin de Claude Code (SSD éjecté ?)"
        fi
    fi
    echo "$1" > fin.code
}

# Arrêté par un signal (fermeture de session, extinction du Mac) : Claude Code fermé, l'échange
# rangé quand même, puis la fin.
trap 'fermer; wait $processus 2>/dev/null; finir 143; exit 143' TERM
trap 'fermer; wait $processus 2>/dev/null; finir 129; exit 129' HUP
trap 'fermer; wait $processus 2>/dev/null; finir 130; exit 130' INT

while kill -0 $processus 2>/dev/null; do
    if [ -e arreter ]; then
        fermer
        break
    fi
    if [ "$lightroom" != 0 ] && ! kill -0 "$lightroom" 2>/dev/null; then
        fermer
        break
    fi
    sleep 1
done

wait $processus
code=$?
finir $code
