#!/usr/bin/env bash
# Ensayo de la propuesta F4b/H1b en STAGING dentro de UNA transacción que termina en ROLLBACK: aplica la migración, mide filas, permisos,
# cambiados, corre las pruebas nuevas + regresiones (M1–M15, A1–A8, N1–N6, X1–X8), aplica el rollback y verifica que las 4 funciones
# reemplazadas vuelvan exactas. No deja nada aplicado. Uso (desde la raíz del repo): docs/fuxia360/intelligence/propuesta_F4b_H1b/ensayo.sh
set -euo pipefail
set -a; . "$HOME/.fuxia-staging.env"; set +a
case "$STAGING_DB_URL" in *faltxpkaicwpnlqaxrdu*) ;; *) echo "ABORT: no es staging" >&2; exit 1;; esac
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
for t in intel_f4_f5_h2 intel_metrics ai_analyst; do grep -vE '^(BEGIN|ROLLBACK|COMMIT);$' "supabase/staging/test_$t.sql" > "$T/t_$t.sql"; done
sed "s#\$TMPDIR_TESTS#$T#g" docs/fuxia360/intelligence/propuesta_F4b_H1b/ensayo.sql > "$T/ensayo.sql"
grep -q '^ROLLBACK;$' "$T/ensayo.sql" || { echo "ABORT: el ensayo debe terminar en ROLLBACK" >&2; exit 1; }
u="${STAGING_DB_URL#*://}"; creds="${u%%@*}"; hostpart="${u#*@}"
PGUSER="${creds%%:*}" PGPASSWORD="$(python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))' "${creds#*:}")" \
PGHOST="${hostpart%%:*}" PGPORT="$(echo "$hostpart" | sed -E 's#^[^:]+:([0-9]+).*#\1#')" PGDATABASE=postgres PGSSLMODE=require \
  /opt/homebrew/opt/libpq/bin/psql -X -q -v ON_ERROR_STOP=1 -f "$T/ensayo.sql"
