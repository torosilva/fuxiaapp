#!/usr/bin/env bash
# Fuxia 360 · pase C1 — the ONLY way to put the catalog publisher in PRODUCTION (tgzg…), approved by Mario as a permission rule.
# Deploys ONLY f360-woo-publish (never the stock/orders functions) and sets ONLY its store secrets:
#   WOO_TARGET_KEY=woo_production, WOO_BASE_URL / WOO_USER / WOO_SECRET from ~/.fuxia-woo-prod.env (written by Mario; never printed,
#   never in the repo, never on the command line). The publisher itself refuses unless the channel's catalog is ON, never touches
#   store stock while stock sync is OFF, and requires the store to confirm its identity before writing.
set -euo pipefail
PROD_REF="tgzgiwfzddsghnxgkcqd"
ENV_FILE="$HOME/.fuxia-woo-prod.env"
[ -f "$ENV_FILE" ] || { echo "ABORT: falta $ENV_FILE" >&2; exit 1; }
cd "$(dirname "$0")/../.."
git diff --quiet HEAD -- fuxia-native/supabase/functions/f360-woo-publish fuxia-native/supabase/functions/_shared/f360-woo \
  || { echo "ABORT: el publicador tiene cambios sin commitear." >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a
[[ "${WOO_PROD_BASE_URL:-}" == "https://fuxiaballerinas.com" ]] || { echo "ABORT: WOO_PROD_BASE_URL no es https://fuxiaballerinas.com" >&2; exit 1; }
[[ "${WOO_PROD_USER:-}" == ck_* && "${WOO_PROD_SECRET:-}" == cs_* ]] || { echo "ABORT: llave de WooCommerce incompleta" >&2; exit 1; }
TMP="$(mktemp)"; chmod 600 "$TMP"; trap 'rm -f "$TMP"' EXIT
printf 'WOO_TARGET_KEY=woo_production\nWOO_BASE_URL=%s\nWOO_USER=%s\nWOO_SECRET=%s\n' "$WOO_PROD_BASE_URL" "$WOO_PROD_USER" "$WOO_PROD_SECRET" > "$TMP"
( cd fuxia-native && supabase secrets set --env-file "$TMP" --project-ref "$PROD_REF" >/dev/null )
echo "Secretos de la tienda puestos en producción (WOO_TARGET_KEY, WOO_BASE_URL, WOO_USER, WOO_SECRET)."
( cd fuxia-native && supabase functions deploy f360-woo-publish --no-verify-jwt --project-ref "$PROD_REF" 2>&1 | grep -E "Deployed|Error" )
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "https://$PROD_REF.supabase.co/functions/v1/f360-woo-publish" -H 'Content-Type: application/json' -d '{}')"
echo "Prueba sin sesión (debe rechazar): http $code"
[ "$code" = "401" ] || [ "$code" = "403" ] || { echo "ATENCIÓN: respuesta inesperada sin sesión" >&2; exit 2; }
echo "LISTO: f360-woo-publish en producción, solo para woo_production."
