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
kill $lecteur 2>/dev/null
rm -f tuyau
echo $code > fin.code
