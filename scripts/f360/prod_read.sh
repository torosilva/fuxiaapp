#!/usr/bin/env bash
# Fuxia 360 · READ-ONLY query against PRODUCTION (tgzg…). The SQL is wrapped in BEGIN READ ONLY … COMMIT, so Postgres
# refuses any write. Same login as prod_sql.sh (Supabase CLI session in the macOS keychain); nothing is logged but the time.
# Usage: scripts/f360/prod_read.sh <<'SQL'
#          SELECT …
#        SQL
set -euo pipefail
PROD_REF="tgzgiwfzddsghnxgkcqd"
T="$(security find-generic-password -s "Supabase CLI" -a supabase -w 2>/dev/null || true)"
case "$T" in go-keyring-base64:*) T="$(printf '%s' "${T#go-keyring-base64:}" | base64 -d)";; esac
[ -n "$T" ] || { echo "ABORT: no hay sesión de la CLI de Supabase (supabase login)." >&2; exit 4; }
Q="$(cat)"
case "$Q" in *";"*) echo "ABORT: una sola consulta, sin ';'." >&2; exit 3;; esac
python3 -c "import json,sys;print(json.dumps({'query': 'BEGIN READ ONLY; '+sys.stdin.read()+'; COMMIT;'}))" <<<"$Q" \
  | curl -s -X POST "https://api.supabase.com/v1/projects/$PROD_REF/database/query" -H "Authorization: Bearer $T" \
      -H "Content-Type: application/json" --data-binary @-
echo
