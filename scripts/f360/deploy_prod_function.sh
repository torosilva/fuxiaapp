#!/usr/bin/env bash
# Fuxia 360 · the ONLY way this repo deploys the store-facing functions to PRODUCTION (tgzg…), approved by Mario as a permission rule.
# Usage: scripts/f360/deploy_prod_function.sh f360-store-reserve | f360-hilo-intake | f360-woo-orders
#   · whitelist only (never the app's own functions: hilo-chat, whatsapp-otp, woocommerce-*, …);
#   · the function must be committed with no local changes;
#   · f360-store-reserve: F360_RESERVE_ORIGINS = fuxiaballerinas.com only, F360_STOREFRONT_TARGET = woo_production. The Woo key
#     (WOO_BASE_URL/USER/SECRET) is already a project secret (deploy_prod_publisher.sh), so the payment link creates REAL orders
#     in fuxiaballerinas.com. No test phones in production (the 2-hour hold stays closed until real WhatsApp codes exist).
#   · f360-woo-orders (Mario 2026-10-08): online orders → Fuxia 360 inventory. WOO_WEBHOOK_SECRET is generated ONCE into
#     ~/.fuxia-woo-orders.secret (chmod 600, never printed) and is the secret of the store's order webhooks
#     (scripts/f360/prod_woo_order_webhooks.sh). The Woo REST key (read-only use: refund detail) is already a project secret.
#   · f360-hilo-intake: F360_HILO_SECRET is generated ONCE into ~/.fuxia-hilo-intake.secret (chmod 600, never printed); Mario pastes
#     it into Railway (F360_INTAKE_SECRET) with pbcopy.
# Rollback: `supabase functions delete <name> --project-ref tgzgiwfzddsghnxgkcqd` (the store widget then falls back to WhatsApp).
set -euo pipefail
PROD_REF="tgzgiwfzddsghnxgkcqd"
FN="${1:-}"
case "$FN" in f360-store-reserve|f360-hilo-intake|f360-woo-orders) ;; *) echo "ABORT: solo f360-store-reserve, f360-hilo-intake o f360-woo-orders" >&2; exit 1;; esac
cd "$(dirname "$0")/../.."
git diff --quiet HEAD -- "fuxia-native/supabase/functions/$FN" || { echo "ABORT: $FN tiene cambios sin commitear." >&2; exit 1; }
[ -z "$(git ls-files --others --exclude-standard "fuxia-native/supabase/functions/$FN")" ] || { echo "ABORT: $FN tiene archivos sin commitear." >&2; exit 1; }
TMP="$(mktemp)"; chmod 600 "$TMP"; trap 'rm -f "$TMP"' EXIT
if [ "$FN" = "f360-store-reserve" ]; then
  printf 'F360_RESERVE_ORIGINS=https://fuxiaballerinas.com,https://www.fuxiaballerinas.com\nF360_STOREFRONT_TARGET=woo_production\n' > "$TMP"
elif [ "$FN" = "f360-woo-orders" ]; then
  SECRET_FILE="$HOME/.fuxia-woo-orders.secret"
  if [ ! -s "$SECRET_FILE" ]; then ( umask 077; openssl rand -hex 32 > "$SECRET_FILE" ); echo "Secreto nuevo generado en $SECRET_FILE"; fi
  printf 'WOO_WEBHOOK_SECRET=%s\n' "$(tr -d '\n' < "$SECRET_FILE")" > "$TMP"
else
  SECRET_FILE="$HOME/.fuxia-hilo-intake.secret"
  if [ ! -s "$SECRET_FILE" ]; then ( umask 077; openssl rand -hex 32 > "$SECRET_FILE" ); echo "Secreto nuevo generado en $SECRET_FILE"; fi
  printf 'F360_HILO_SECRET=%s\n' "$(tr -d '\n' < "$SECRET_FILE")" > "$TMP"
fi
( cd fuxia-native && supabase secrets set --env-file "$TMP" --project-ref "$PROD_REF" >/dev/null )
echo "Secretos de $FN puestos en producción ($(cut -d= -f1 "$TMP" | tr '\n' ' '))."
( cd fuxia-native && supabase functions deploy "$FN" --no-verify-jwt --project-ref "$PROD_REF" 2>&1 | grep -E "Deployed|Error" )
URL="https://$PROD_REF.supabase.co/functions/v1/$FN"
if [ "$FN" = "f360-store-reserve" ]; then
  bad=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Origin: https://evil.example' -H 'Content-Type: application/json' -d '{"action":"catalog"}')
  good=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Origin: https://fuxiaballerinas.com' -H 'Content-Type: application/json' -d '{"action":"scarcity","woo_variation_id":1}')
  echo "Otro dominio (debe rechazar 403): $bad · fuxiaballerinas.com (debe 200): $good"
  [ "$bad" = "403" ] && [ "$good" = "200" ] || { echo "ATENCIÓN: respuesta inesperada" >&2; exit 2; }
elif [ "$FN" = "f360-woo-orders" ]; then
  # Woo's own ping (no signature, no topic): proves it is up without JWT and does NOT open a "webhook_rejected" aviso,
  # which an unsigned '{}' would (deploys of 2026-10-08 09:10 and 11:24 did exactly that).
  ping=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Content-Type: application/x-www-form-urlencoded' -d 'webhook_id=0')
  echo "Ping de Woo (debe 200): $ping"
  [ "$ping" = "200" ] || { echo "ATENCIÓN: respuesta inesperada al ping" >&2; exit 2; }
else
  bad=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Content-Type: application/json' -d '{}')
  echo "Sin secreto (debe rechazar 401/403): $bad"
  [ "$bad" = "401" ] || [ "$bad" = "403" ] || { echo "ATENCIÓN: respuesta inesperada sin secreto" >&2; exit 2; }
fi
echo "LISTO: $FN en producción."
