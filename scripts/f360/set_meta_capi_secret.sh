#!/usr/bin/env bash
# Fuxia 360 · stores the Conversions API token of pixel 951926154215387 in WordPress (option f360_meta_capi_token) for
# f360-meta-compra-servidor.php. The token is read from ~/.fuxia-meta-capi.token (Mario saves it there himself with
#   ! pbpaste > ~/.fuxia-meta-capi.token && chmod 600 ~/.fuxia-meta-capi.token
# ) and travels over SSH stdin: never in arguments, URLs, logs or the terminal.
# Usage: scripts/f360/set_meta_capi_secret.sh staging4 <TEST_EVENT_CODE>   (staging4 only sends with the test code)
#        scripts/f360/set_meta_capi_secret.sh produccion                     (borra cualquier test code)
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
TOKEN_FILE="$HOME/.fuxia-meta-capi.token"
[ -s "$TOKEN_FILE" ] || { echo "ABORT: falta $TOKEN_FILE" >&2; exit 1; }
case "${1:-}" in
  staging4)   WP='~/www/staging4.fuxiaballerinas.com/public_html'; HOME_URL='https://staging4.fuxiaballerinas.com'
              CODE="${2:?falta el test_event_code de Probar eventos}"
              [[ "$CODE" =~ ^TEST[0-9A-Za-z]+$ ]] || { echo "ABORT: el test_event_code debe verse como TEST12345" >&2; exit 1; } ;;
  produccion) WP='~/www/fuxiaballerinas.com/public_html'; HOME_URL='https://fuxiaballerinas.com'; CODE='' ;;
  *) echo "uso: $0 staging4 <TEST_EVENT_CODE> | produccion" >&2; exit 1 ;;
esac
"${SSH[@]}" "test \"\$(cd $WP && wp option get home)\" = '$HOME_URL'" || { echo "ABORT: el destino no es $HOME_URL" >&2; exit 1; }
tr -d '\n\r ' < "$TOKEN_FILE" | "${SSH[@]}" "cd $WP && wp eval '\$t = trim(stream_get_contents(STDIN)); if (!preg_match(\"/^[A-Za-z0-9]{50,}\$/\", \$t)) { fwrite(STDERR, \"token con formato inesperado\n\"); exit(2); } update_option(\"f360_meta_capi_token\", \$t, false); echo \"token guardado (\" . strlen(\$t) . \" caracteres)\n\";'"
if [ -n "$CODE" ]; then
  "${SSH[@]}" "cd $WP && wp option update f360_meta_capi_test_code '$CODE' --autoload=no >/dev/null && echo 'test_event_code guardado'"
else
  "${SSH[@]}" "cd $WP && wp option delete f360_meta_capi_test_code >/dev/null 2>&1; echo 'sin test_event_code (producción manda en vivo)'"
fi
