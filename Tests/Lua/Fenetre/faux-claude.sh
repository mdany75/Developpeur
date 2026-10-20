#!/bin/sh
#
# faux-claude.sh — imite `claude -p --input-format stream-json --output-format stream-json` pour
# éprouver relais.sh et le moteur sans Claude ni quota : une ligne init, puis pour chaque message
# reçu, un texte partiel, un message avec un appel d'outil, son résultat (avec l'image
# $FAUX_IMAGE_B64), un relevé du forfait et un result. Écrit ses arguments dans arguments.txt
# (dans son dossier de travail). Un message « ARRETE-TOI » le fait quitter avec le code 3, une
# demande d'interruption répond comme Claude Code.

printf '%s\n' "$@" > arguments.txt
session=session-essai
[ -n "$ANTHROPIC_API_KEY" ] && echo "cle-api-presente" >> arguments.txt
printf '%s\n' '{"type":"system","subtype":"init","session_id":"'$session'","model":"claude-essai","mcp_servers":[{"name":"developpeur","status":"connected"}],"tools":[]}'
while IFS= read -r ligne; do
    case "$ligne" in
        *control_request*)
            printf '%s\n' '{"type":"control_response","response":{"subtype":"success","request_id":"interruption-1"}}'
            printf '%s\n' '{"type":"result","subtype":"error_during_execution","is_error":true,"session_id":"'$session'"}' ;;
        *ARRETE-TOI*)
            echo "panne simulée" >&2
            exit 3 ;;
        *LENT*)
            printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Je réfléchis"}}}'
            sleep 30 ;;
        *)
            printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"[titre : Flamant"}}}'
            printf '%s\n' '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":" rose au zoo]\nBonjour"}}}'
            printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"[titre : Flamant rose au zoo]\nBonjour, je regarde la photo."},{"type":"tool_use","id":"outil-1","name":"mcp__developpeur__view_photo","input":{"photo_id":53636309}}]}}'
            printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"outil-1","content":[{"type":"text","text":"{\\"exposition\\":0.2}"},{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"%s"}},{"type":"text","text":"[Image: source: /tmp/x.jpg]"}]}]}}\n' "$(cat "$FAUX_IMAGE_B64")"
            printf '%s\n' '{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.23},"seven_day":{"utilization":0.41,"resetsAt":1790000000}}}}'
            printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"## Diagnostic\n- **Exposition** : juste\n- Dominante chaude"}]}}'
            printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"'$session'","duration_ms":1200,"num_turns":2,"usage":{"input_tokens":10,"output_tokens":20},"modelUsage":{"claude-essai":{}}}' ;;
    esac
done
