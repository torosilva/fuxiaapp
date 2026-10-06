#!/usr/bin/env bash
# Fuxia 360 · the ONLY way this repo writes to PRODUCTION (tgzg…), approved by Mario as a Claude Code permission rule.
# Sends ONE SQL file to the production database through the Supabase Management API (CLI login in the macOS keychain;
# no database password). Guards:
#   · the file must be tracked by git and committed (no uncommitted changes) → every production change is reviewed history;
#   · the file must start with BEGIN; and end with COMMIT; (all-or-nothing);
#   · it is first run as a DRY-RUN (COMMIT replaced by ROLLBACK); only if that succeeds is it applied;
#   · every run is logged to ~/fuxia360-respaldos/prod-sql.log (file, commit, result) — never credentials or data.
# Usage: scripts/f360/prod_sql.sh <path/to/file.sql>          (dry-run then apply)
#        scripts/f360/prod_sql.sh --dry-run <path/to/file.sql> (dry-run only)
set -euo pipefail
PROD_REF="tgzgiwfzddsghnxgkcqd"
DRY_ONLY=0
if [ "${1:-}" = "--dry-run" ]; then DRY_ONLY=1; shift; fi
FILE="${1:-}"
[ -n "$FILE" ] && [ -f "$FILE" ] || { echo "uso: $0 [--dry-run] <archivo.sql>" >&2; exit 2; }
cd "$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel)"
REL="$(git ls-files --full-name --error-unmatch "$OLDPWD/$FILE" 2>/dev/null || git ls-files --full-name --error-unmatch "$FILE" 2>/dev/null)" \
  || { echo "ABORT: $FILE no está en git. Commitea el archivo primero." >&2; exit 3; }
git diff --quiet HEAD -- "$REL" || { echo "ABORT: $REL tiene cambios sin commitear." >&2; exit 3; }
COMMIT="$(git log -1 --format=%h -- "$REL")"
first="$(awk '!/^[[:space:]]*(--|$)/ { print; exit }' "$REL")"; last="$(awk '!/^[[:space:]]*(--|$)/ { l = $0 } END { print l }' "$REL")"
[ "$first" = "BEGIN;" ] && [ "$last" = "COMMIT;" ] || { echo "ABORT: el archivo debe empezar con BEGIN; y terminar con COMMIT;" >&2; exit 3; }

T="$(security find-generic-password -s "Supabase CLI" -a supabase -w 2>/dev/null || true)"
case "$T" in go-keyring-base64:*) T="$(printf '%s' "${T#go-keyring-base64:}" | base64 -d)";; esac
[ -n "$T" ] || { echo "ABORT: no hay sesión de la CLI de Supabase (supabase login)." >&2; exit 4; }
LOG="$HOME/fuxia360-respaldos/prod-sql.log"; mkdir -p "$(dirname "$LOG")"

send() {   # $1 = SQL text → prints "<http code> <body>"
  python3 -c "import json,sys;print(json.dumps({'query': sys.stdin.read()}))" <<<"$1" \
    | curl -s -X POST "https://api.supabase.com/v1/projects/$PROD_REF/database/query" -H "Authorization: Bearer $T" \
        -H "Content-Type: application/json" --data-binary @- -w '\n%{http_code}'
}
SQL="$(cat "$REL")"
DRY="$(printf '%s' "$SQL" | sed '$ s/^COMMIT;$/ROLLBACK;/')"
out="$(send "$DRY")"; code="${out##*$'\n'}"; body="${out%$'\n'*}"
echo "$(date -u +%FT%TZ) DRY-RUN $REL@$COMMIT http=$code" >> "$LOG"
if [ "$code" != "201" ]; then echo "DRY-RUN FALLÓ (http $code): ${body:0:600}" >&2; exit 5; fi
echo "DRY-RUN OK ($REL@$COMMIT)"
[ "$DRY_ONLY" = 1 ] && exit 0
out="$(send "$SQL")"; code="${out##*$'\n'}"; body="${out%$'\n'*}"
echo "$(date -u +%FT%TZ) APPLY   $REL@$COMMIT http=$code" >> "$LOG"
if [ "$code" != "201" ]; then echo "APLICACIÓN FALLÓ (http $code): ${body:0:600}" >&2; exit 6; fi
echo "APLICADO en producción ($REL@$COMMIT): ${body:0:300}"
