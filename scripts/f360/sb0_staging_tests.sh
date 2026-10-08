#!/usr/bin/env bash
# Strategy & Board SB0 — runs every SB0 check against STAGING, each in its own ROLLED-BACK transaction. Never commits.
# Usage: scripts/f360/sb0_staging_tests.sh rehearse   # SB0 migrations + staging membership prepended inside each transaction
#        scripts/f360/sb0_staging_tests.sh applied    # SB0 already applied to staging: tests only
# Seller flows (test 20): the existing rehearsals f360_s02 (seller shift), f360_c3 (F360 store sale), f360_s05_s03 (legacy
# store sale), f360_reservations(_app) (apartados), and test_store_sale_customer (counter sign-up + record_store_sale_for).
# test_store_sale_customer needs 20261013000100/0200; when staging lacks them they are prepended (rolled back too).
set -euo pipefail
PROD_REF="tgzgiwfzddsghnxgkcqd"; STAGING_REF="faltxpkaicwpnlqaxrdu"
MODE="${1:-}"; case "$MODE" in rehearse|applied) ;; *) echo "usage: $0 rehearse|applied" >&2; exit 2;; esac
set -a; . "$HOME/.fuxia-staging.env"; set +a
case "$STAGING_DB_URL" in *"$PROD_REF"*) echo "ABORT: production ref" >&2; exit 1;; *"$STAGING_REF"*) ;; *) echo "ABORT: not staging" >&2; exit 1;; esac
PSQL="$(command -v psql || echo /opt/homebrew/opt/libpq@18/bin/psql)"
cd "$(dirname "$0")/../.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SB0=(supabase/migrations/20261015000100_f360_board_sb0_access.sql supabase/migrations/20261015000200_f360_board_sb0_finance_foundation.sql
     supabase/migrations/20261015000300_f360_board_sb0_governance_plan.sql supabase/migrations/20261015000400_f360_d13_intent_reports_operator.sql
     supabase/staging/sb0_board_members_staging.sql)
have() { "$PSQL" "$STAGING_DB_URL" -X -A -t -c "SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version = '$1'"; }
fail=0
run() {   # $1 = label, $2 = test file, $3.. = extra files to prepend
  local label="$1" test="$2"; shift 2; local f="$TMP/run.sql"
  { echo '\set ON_ERROR_STOP 1'; echo 'BEGIN;'
    for p in "$@"; do echo "\\i $p"; done
    [ "$MODE" = rehearse ] && for p in "${SB0[@]}"; do echo "\\i $p"; done
    echo '\unset ON_ERROR_STOP'
    sed -E '/^(BEGIN|ROLLBACK|COMMIT);[[:space:]]*$/d' "$test"
    echo 'ROLLBACK;'; } > "$f"
  local out; out="$("$PSQL" "$STAGING_DB_URL" -X -q -f "$f" 2>&1 || true)"
  local bad; bad="$(printf '%s\n' "$out" | grep -E 'ERROR' | grep -v 'ENSAYO OK' || true)"
  local fails; fails="$(printf '%s\n' "$out" | grep -E '^ *FAIL *\|' || true)"
  if [ -n "$bad" ] || [ -n "$fails" ]; then fail=1; echo "FAIL  $label"; printf '%s\n%s\n' "$bad" "$fails" | sed 's/^/      /' | head -20
  else echo "PASS  $label  ($(printf '%s\n' "$out" | grep -cE 'PASS|passed|ENSAYO OK') pass lines)"; fi
  printf '%s\n' "$out" | grep -E 'NOTICE: +PASS' | sed -E 's/^.*NOTICE: +/      /' | cut -c1-170 || true
}
run "SB0 access (T0–T7, PII, T19)" supabase/staging/test_sb0_access.sql
run "SB0 history (T8, close, D10B, D11, D12)" supabase/staging/test_sb0_history.sql
for t in f360_s02_tests f360_c3_tests f360_s05_s03_tests f360_reservations_tests f360_reservations_app_tests; do
  run "T20 seller flow: $t" "supabase/staging/$t.sql"
done
PRE=()
for v in 20261012001100 20261013000100 20261013000200; do
  if [ "$(have $v)" = 0 ]; then PRE+=("$(ls supabase/migrations/${v}_*.sql)"); fi
done
[ ${#PRE[@]} -gt 0 ] && echo "      (staging lacks ${#PRE[@]} prod migration(s) needed by test_store_sale_customer: prepended, rolled back)"
run "T20 seller flow: test_store_sale_customer (shift, catalog, customer find/register, record_store_sale_for)" supabase/staging/test_store_sale_customer.sql ${PRE[@]+"${PRE[@]}"}
[ $fail = 0 ] && echo "ALL SB0 CHECKS PASS (nothing committed)" || { echo "SOME CHECKS FAILED"; exit 1; }
