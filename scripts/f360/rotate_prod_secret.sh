#!/usr/bin/env bash
# Fuxia 360 · controlled rotation of ONE production secret (Mario 2026-10-10, after the 10-oct exposure).
# Never prints, logs or commits a secret: values live only in chmod-600 files under $HOME and travel through files / stdin.
#   sync     F360_SYNC_SECRET   → Edge env (f360-woo-sync) + Vault 'f360_sync_secret' (pg_cron ticks), same window
#   webhook  WOO_WEBHOOK_SECRET → Edge env (f360-woo-orders) + the 2 production order webhooks (#5/#6) via prod_woo_order_webhooks.sh
# Each step verifies; on failure it restores the previous value everywhere (the old one is kept in <file>.old until `finish`).
# Usage (repo root):  scripts/f360/rotate_prod_secret.sh sync|webhook rotate     → rotate + verify
#                     scripts/f360/rotate_prod_secret.sh sync|webhook rollback   → put the previous value back
#                     scripts/f360/rotate_prod_secret.sh sync|webhook finish     → delete the kept old value
set -euo pipefail
umask 077
REF="tgzgiwfzddsghnxgkcqd"; FN_URL="https://$REF.supabase.co/functions/v1"
KIND="${1:-}"; ACT="${2:-}"
case "$KIND" in
  sync)    NAME=F360_SYNC_SECRET;   FILE="$HOME/.fuxia-sync.secret" ;;
  webhook) NAME=WOO_WEBHOOK_SECRET; FILE="$HOME/.fuxia-woo-orders.secret" ;;
  *) echo "uso: $0 sync|webhook rotate|rollback|finish"; exit 1 ;;
esac
cd "$(dirname "$0")/../.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
T="$(security find-generic-password -s "Supabase CLI" -a supabase -w 2>/dev/null || true)"
case "$T" in go-keyring-base64:*) T="$(printf '%s' "${T#go-keyring-base64:}" | base64 -d)";; esac
[ -n "$T" ] || { echo "ABORT: sin sesión de la CLI de Supabase"; exit 4; }

set_edge() {   # $1 = file holding the value
  printf '%s=%s\n' "$NAME" "$(tr -d '\n' < "$1")" > "$TMP/env"
  supabase secrets set --project-ref "$REF" --env-file "$TMP/env" >/dev/null
  rm -f "$TMP/env"
}
set_vault() {  # $1 = file; Management API query, value only inside the TLS request body
  python3 - "$1" > "$TMP/q.json" <<'PY'
import json, sys
v = open(sys.argv[1]).read().strip()
assert len(v) >= 32 and all(c in '0123456789abcdef' for c in v)
print(json.dumps({'query': "SELECT count(*) AS updated FROM (SELECT vault.update_secret(id, '%s') FROM vault.secrets WHERE name = 'f360_sync_secret') x" % v}))
PY
  curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" -H "Authorization: Bearer $T" -H "Content-Type: application/json" --data-binary @"$TMP/q.json" \
    | python3 -c "import json,sys; r=json.load(sys.stdin); n=(r[0].get('updated') if isinstance(r,list) and r else None); print('vault actualizado:', n); sys.exit(0 if n==1 else 1)"
  rm -f "$TMP/q.json"
}
set_hooks() { scripts/f360/prod_woo_order_webhooks.sh | sed -E 's/#[0-9]+/#…/' ; }   # reads $FILE; prints only names
code_sync() {  # $1 = file → HTTP status of a commerce_poll call (same body the cron sends)
  curl -s -o /dev/null -w '%{http_code}' -X POST "$FN_URL/f360-woo-sync" -H "Authorization: Bearer $(tr -d '\n' < "$1")" -H 'Content-Type: application/json' --data '{"action":"commerce_poll"}'
}
code_hook() {  # $1 = file → HTTP status of a signed NON-order delivery (the function verifies the signature, then ignores the topic)
  local body='{"f360":"rotation-check"}' sig
  sig="$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$(tr -d '\n' < "$1")" -binary | base64)"
  curl -s -o /dev/null -w '%{http_code}' -X POST "$FN_URL/f360-woo-orders" -H "x-wc-webhook-topic: action.f360_rotation_check" -H "x-wc-webhook-signature: $sig" \
    -H 'Content-Type: application/json' --data "$body"
}
verify() {     # new must be accepted, old must be refused (Edge env takes a few seconds to roll out)
  local want_new=200 got_new got_old
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if [ "$KIND" = sync ]; then got_new="$(code_sync "$FILE")"; got_old="$(code_sync "$FILE.old")"; else got_new="$(code_hook "$FILE")"; got_old="$(code_hook "$FILE.old")"; fi
    [ "$got_new" = "$want_new" ] && [ "$got_old" = 401 ] && { echo "verificado: valor nuevo $got_new · valor anterior $got_old"; return 0; }
    sleep 10
  done
  echo "FALLO de verificación: nuevo $got_new · anterior $got_old"; return 1
}

case "$ACT" in
  rotate)
    [ -s "$FILE" ] || { echo "ABORT: falta $FILE"; exit 1; }
    [ -e "$FILE.old" ] && { echo "ABORT: ya hay una rotación sin terminar ($FILE.old). Usa finish o rollback."; exit 1; }
    cp -p "$FILE" "$FILE.old"
    openssl rand -hex 32 > "$FILE.new"
    echo "1/3 Edge env ${NAME}…"; cp -p "$FILE.new" "$FILE"; set_edge "$FILE"
    if [ "$KIND" = sync ]; then echo "2/3 Vault f360_sync_secret…"; set_vault "$FILE" || { echo "FALLO vault → recuperando"; cp -p "$FILE.old" "$FILE"; set_edge "$FILE"; set_vault "$FILE" || true; exit 2; }
    else echo "2/3 webhooks de pedidos (#5/#6)…"; set_hooks || { echo "FALLO webhooks → recuperando"; cp -p "$FILE.old" "$FILE"; set_edge "$FILE"; set_hooks || true; exit 2; }; fi
    rm -f "$FILE.new"
    echo "3/3 verificación…"
    verify || { echo "→ recuperando el valor anterior"; cp -p "$FILE.old" "$FILE"; set_edge "$FILE"; if [ "$KIND" = sync ]; then set_vault "$FILE" || true; else set_hooks || true; fi; exit 3; }
    echo "LISTO ${NAME} rotado. El anterior queda en $FILE.old hasta 'finish'." ;;
  rollback)
    [ -s "$FILE.old" ] || { echo "ABORT: no hay valor anterior guardado"; exit 1; }
    cp -p "$FILE.old" "$FILE"; set_edge "$FILE"; if [ "$KIND" = sync ]; then set_vault "$FILE"; else set_hooks; fi
    echo "recuperado el valor anterior de $NAME" ;;
  finish)
    rm -P "$FILE.old" 2>/dev/null || rm -f "$FILE.old"; echo "valor anterior de ${NAME} eliminado" ;;
  *) echo "uso: $0 sync|webhook rotate|rollback|finish"; exit 1 ;;
esac
