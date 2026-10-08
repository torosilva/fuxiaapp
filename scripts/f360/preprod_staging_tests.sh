#!/usr/bin/env bash
# Pre-production gate S-G0 / SB0 — runs every SQL suite that is safe against STAGING, each in its own ROLLED-BACK transaction.
# Never commits, never seeds/resets (f360_demo_seed/reset, lab_seed/reset are NOT run). Refuses any non-staging URL.
# Usage: scripts/f360/preprod_staging_tests.sh
# Suites:
#   · gate:   test_preprod_gate (MFA, approvals, visibility, FX, spend, tax, bazaar, legacy, seller denials), test_favorites,
#             test_sg0_measurement, test_sg0_reconciliation
#   · prod-rehearsal files written for production dry-runs (prod ids, target 'woo_production', migration body inline): the
#     TEST block only (last `DO $$` to the end) is run, with the production target → woo_staging4 and Mario's production auth
#     id → Mario's staging auth id (both from the database, by person_key), because staging already has those migrations.
#   · test_sellers_admin (its DO block, migration already applied).
# The 38-file regression (scripts/f360/db_tests.mjs) and the SB0 runner (sb0_staging_tests.sh applied) are run separately.
set -euo pipefail
PROD_REF="tgzgiwfzddsghnxgkcqd"; STAGING_REF="faltxpkaicwpnlqaxrdu"
set -a; . "$HOME/.fuxia-staging.env"; set +a
case "$STAGING_DB_URL" in *"$PROD_REF"*) echo "ABORT: production ref" >&2; exit 1;; *"$STAGING_REF"*) ;; *) echo "ABORT: not staging" >&2; exit 1;; esac
PSQL="$(command -v psql || echo /opt/homebrew/opt/libpq/bin/psql)"
cd "$(dirname "$0")/../.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MARIO_PROD="d11a8d33-cae6-46a5-9d0f-bd2516e8712b"
MARIO_STG="$("$PSQL" "$STAGING_DB_URL" -X -A -t -c "SELECT auth_user_id FROM f360_board.board_members WHERE person_key = 'MARIO'")"
[ -n "$MARIO_STG" ] || { echo "ABORT: staging Mario board member missing" >&2; exit 1; }
fail=0
report() {   # $1 label, $2 output
  local label="$1" out="$2" bad fails passes
  bad="$(printf '%s\n' "$out" | grep -E '^(psql:.*)?ERROR:' | grep -v 'ENSAYO OK' || true)"
  fails="$(printf '%s\n' "$out" | grep -E '^ *FAIL *\|' || true)"
  passes="$(printf '%s\n' "$out" | grep -cE '^PASS \||NOTICE: +PASS|ENSAYO OK|all checks passed' || true)"
  if [ -n "$bad" ] || [ -n "$fails" ]; then fail=1; echo "FAIL  $label"; printf '%s\n%s\n' "$bad" "$fails" | sed '/^$/d; s/^/      /' | cut -c1-220 | head -12
  else echo "PASS  $label  ($passes pass lines)"; fi
}
run_file() {   # whole file; its own BEGIN/ROLLBACK is replaced by ours
  local label="$1" test="$2"
  { echo 'BEGIN;'; sed -E '/^(BEGIN|ROLLBACK|COMMIT);[[:space:]]*$/d' "$test"; echo 'ROLLBACK;'; } > "$TMP/run.sql"
  report "$label" "$("$PSQL" "$STAGING_DB_URL" -X -q -A -t -f "$TMP/run.sql" 2>&1 || true)"
}
# Production store sales used as fixtures by test_thanks_member / test_thanks_whatsapp (T7) do not exist in staging: inside the
# same rolled-back transaction they are recreated with the SAME ids at staging's "Tienda Polanco", sold to a carded app customer.
# test_thanks_whatsapp T8 then expects 5 claimable messages instead of 4: in production sale c30d6b65 already had its thank-you
# (ON CONFLICT DO NOTHING → T7 adds none); the staging fixture has none, so T7's thank-you is new and claimable.
PROD_SALE_FIXTURES="INSERT INTO public.offline_sales (id, code, items, total, location_id, customer_id, created_by_rpc, created_at)
  SELECT x.id, 'ZZPP' || left(x.id::text, 6), '[]', 2800, (SELECT id FROM f360.locations WHERE name = 'Tienda Polanco'),
         (SELECT c.id FROM public.customers c JOIN public.loyalty_cards l ON l.customer_id = c.id WHERE c.auth_user_id IS NOT NULL AND c.role = 'customer'
            AND f360.normalize_phone(c.phone) IS NOT NULL ORDER BY c.created_at LIMIT 1), true, now()
  FROM (VALUES ('26df917b-42a3-4805-b4b1-be90b9d0f4c1'::uuid), ('c30d6b65-f542-471c-a77e-c4ef027ad294'::uuid)) x(id) ON CONFLICT (id) DO NOTHING;"
run_tail() {   # only the last DO block of a production-rehearsal file, adapted to staging
  local label="$1" test="$2" start
  start="$(grep -n '^DO \$\$' "$test" | tail -1 | cut -d: -f1)"
  { echo 'BEGIN;'; printf '%s\n' "$PROD_SALE_FIXTURES"; tail -n +"$start" "$test" | sed -E '/^(BEGIN|ROLLBACK|COMMIT);[[:space:]]*$/d' \
      | sed -e "s/'woo_production'/'woo_staging4'/g" -e "s/$MARIO_PROD/$MARIO_STG/g" \
            -e "s/IF n <> 4 THEN RAISE EXCEPTION 'T8 claim %'/IF n <> 5 THEN RAISE EXCEPTION 'T8 claim %'/"; echo 'ROLLBACK;'; } > "$TMP/run.sql"
  report "$label" "$("$PSQL" "$STAGING_DB_URL" -X -q -A -t -f "$TMP/run.sql" 2>&1 || true)"
}
run_file "gate: test_preprod_gate (MFA · approvals · visibility · FX · spend · tax · bazaar · legacy · seller denials)" supabase/staging/test_preprod_gate.sql
run_file "favorites: test_favorites" supabase/staging/test_favorites.sql
run_file "S-G0: test_sg0_measurement (revenue defs, cancelled/refunded, currencies, FX, DATA_INCOMPLETE, legacy, cost)" supabase/staging/test_sg0_measurement.sql
run_file "S-G0: test_sg0_reconciliation (idempotent reconciliation + history import)" supabase/staging/test_sg0_reconciliation.sql
run_tail "online: test_order_shipping (adapted: woo_staging4)" supabase/staging/test_order_shipping.sql
run_tail "online: test_thanks_whatsapp (adapted: woo_staging4)" supabase/staging/test_thanks_whatsapp.sql
run_tail "online: test_thanks_member" supabase/staging/test_thanks_member.sql
run_tail "admin: test_admin_customer_add (adapted: staging Mario)" supabase/staging/test_admin_customer_add.sql
run_tail "admin: test_customer_address (adapted: staging Mario)" supabase/staging/test_customer_address.sql
run_tail "admin: test_sellers_admin" supabase/staging/test_sellers_admin.sql
[ $fail = 0 ] && echo "ALL PRE-PRODUCTION STAGING SUITES PASS (nothing committed)" || { echo "SOME SUITES FAILED"; exit 1; }
