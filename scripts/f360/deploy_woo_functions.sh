#!/usr/bin/env bash
# STAGING ONLY — the ONE way to deploy the Fuxia 360 Woo functions. Always --no-verify-jwt (their callers are pg_cron with
# Bearer F360_SYNC_SECRET and Woo webhooks with an HMAC signature; the functions authenticate them). Then runs the
# post-deploy guard; a failing guard exits 1 (rollback = redeploy the previous commit with this same script).
# Usage (from the repo root): scripts/f360/deploy_woo_functions.sh f360-woo-sync [f360-woo-orders f360-woo-publish]
# Incident that motivated it: 2026-10-04 17:47–17:48 UTC, cron 401 after a deploy without --no-verify-jwt.
set -euo pipefail
STAGING_REF="faltxpkaicwpnlqaxrdu"
[ $# -gt 0 ] || { echo "uso: $0 <función> [función…]"; exit 1; }
for fn in "$@"; do
  case "$fn" in f360-woo-sync|f360-woo-orders|f360-woo-publish) ;; *) echo "ABORT: $fn no es una función Woo de Fuxia 360"; exit 1;; esac
done
cd "$(dirname "$0")/../.."
( cd fuxia-native && supabase functions deploy "$@" --no-verify-jwt --project-ref "$STAGING_REF" )
echo "Esperando un tick del cron (70 s) antes del guard…"
sleep 70
scripts/s00a/run.sh ../f360/check_woo_functions.mjs
