#!/usr/bin/env bash
# Fuxia 360 · Copia PRODUCCIÓN → STAGING, con las clientas anonimizadas. Decisión de Mario (2026-10-11):
# staging = producción, cada noche, anonimizado. Guía: docs/fuxia360/ops/STAGING_REFRESH.md
#
#   refresh.sh --rehearsal   ensayo completo en staging que termina en ROLLBACK (staging no cambia)
#   refresh.sh --apply       copia real: respalda staging, reemplaza, reaplica migraciones pendientes, sincroniza fotos
#
# Producción solo se LEE (sesión read-only). Todo lo que se escribe en staging va en UNA transacción: si algo falla
# —incluida la verificación de que no quedó ningún dato personal— no se aplica nada.
# Credenciales: ~/.fuxia-prod.env (PROD_DB_URL) y ~/.fuxia-staging.env (STAGING_DB_URL). Nunca se imprimen.
set -euo pipefail

MODE="${1:-}"
# --woo-mirrored: staging4 se copió de la tienda real esta misma noche (woo_refresh.sh); ver post_restore.sql §6.
WOO_MIRRORED=off; [ "${2:-}" = "--woo-mirrored" ] && WOO_MIRRORED=on
case "$MODE" in
  --rehearsal) FINISH="ROLLBACK" ;;
  --apply)     FINISH="COMMIT" ;;
  *) echo "uso: $0 --rehearsal | --apply [--woo-mirrored]" >&2; exit 2 ;;
esac

PROD_REF="tgzgiwfzddsghnxgkcqd"
STAGING_REF="faltxpkaicwpnlqaxrdu"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
export PATH="/opt/homebrew/opt/libpq/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# ── Credenciales y barreras ────────────────────────────────────────────────────────────────────────────────
PROD_DB_URL="$(set -a; . "$HOME/.fuxia-prod.env"; printf '%s' "${PROD_DB_URL:-}")"
STAGING_DB_URL="$(set -a; . "$HOME/.fuxia-staging.env"; printf '%s' "${STAGING_DB_URL:-}")"
[[ "$PROD_DB_URL" == *"postgres.$PROD_REF:"* ]] || { echo "ABORT: PROD_DB_URL no es el proyecto de producción." >&2; exit 3; }
[[ "$STAGING_DB_URL" == *"postgres.$STAGING_REF:"* ]] || { echo "ABORT: STAGING_DB_URL no es staging." >&2; exit 3; }
[[ "$STAGING_DB_URL" != *"$PROD_REF"* ]] || { echo "ABORT: STAGING_DB_URL menciona producción." >&2; exit 3; }
PGV="$(pg_dump --version | grep -oE '[0-9]+' | head -1)"
[ "$PGV" -ge 18 ] || { echo "ABORT: se necesita psql/pg_dump 18+ (brew install libpq)." >&2; exit 3; }

BASE="$HOME/fuxia360-respaldos/staging-refresh"
TS="$(date +%Y-%m-%d_%H%M%S)"
WORK="$BASE/$TS${MODE/--/_}"
umask 077
mkdir -p "$WORK"
mkdir "$BASE/.lock" 2>/dev/null || { echo "ABORT: ya hay una copia corriendo ($BASE/.lock)." >&2; exit 4; }
trap 'rmdir "$BASE/.lock" 2>/dev/null || true' EXIT
# Las contraseñas van en un .pgpass temporal (modo 600), nunca en los argumentos (se verían en `ps`).
export PGPASSFILE="$WORK/.pgpass"
U1="$PROD_DB_URL" U2="$STAGING_DB_URL" python3 - > "$PGPASSFILE" <<'PY'
import os, urllib.parse as u
for url in (os.environ['U1'], os.environ['U2']):
    p = u.urlsplit(url)
    esc = lambda x: u.unquote(x or '').replace('\\', '\\\\').replace(':', '\\:')
    print(':'.join([esc(p.hostname), str(p.port or 5432), esc(p.path.lstrip('/') or 'postgres'), esc(p.username), esc(p.password)]))
PY
chmod 600 "$PGPASSFILE"
nopw() { U="$1" python3 -c 'import os,urllib.parse as u;p=u.urlsplit(os.environ["U"]);print(u.urlunsplit((p.scheme,f"{p.username}@{p.hostname}:{p.port or 5432}",p.path,p.query,"")))'; }
PROD_DB_URL="$(nopw "$PROD_DB_URL")"
STAGING_DB_URL="$(nopw "$STAGING_DB_URL")"
trap 'rm -f "$PGPASSFILE"; rmdir "$BASE/.lock" 2>/dev/null || true' EXIT
LOG="$WORK/refresh.log"
exec > >(tee -a "$LOG") 2>&1

notify() {  # aviso de macOS (no falla si no hay sesión gráfica)
  osascript -e "display notification \"$2\" with title \"Fuxia staging\" subtitle \"$1\"" >/dev/null 2>&1 || true
}
fail() { echo "FALLÓ: $1"; notify "Copia de producción FALLÓ" "$1 — ver $LOG"; exit 1; }
step() { echo; echo "── $(date +%H:%M:%S) · $1"; }

echo "Fuxia 360 · copia producción → staging · modo ${MODE#--} · $TS"

# ── 1. Respaldo de staging (solo en --apply) ───────────────────────────────────────────────────────────────
if [ "$MODE" = "--apply" ]; then
  step "Respaldo de staging antes de reemplazar"
  pg_dump "$STAGING_DB_URL" -Fc -n public -n f360 -n f360_board -n supabase_migrations -f "$WORK/staging_before_app.dump" \
    || fail "respaldo de staging (esquemas de la app)"
  pg_dump "$STAGING_DB_URL" -Fc --data-only -t auth.users -t auth.identities -f "$WORK/staging_before_auth.dump" \
    || fail "respaldo de staging (usuarios)"
  ls -lh "$WORK"/staging_before_*.dump | awk '{print "   ", $5, $NF}'
fi

# ── 2. Lectura de producción (pg_dump siempre lee en una transacción READ ONLY) ──────────────────────────────────────────────────────
step "Leyendo producción (solo lectura)"
# Esquema: mismos filtros que usa `supabase db dump` (omite lo que administra la plataforma).
pg_dump "$PROD_DB_URL" --schema-only --quote-all-identifiers -n public -n f360 -n f360_board \
  | sed -E 's/^\\(un)?restrict .*$/-- &/' \
  | sed -E 's/^CREATE SCHEMA "/CREATE SCHEMA IF NOT EXISTS "/' \
  | sed -E 's/^CREATE PUBLICATION "supabase_realtime/-- &/' \
  | sed -E 's/^CREATE EVENT TRIGGER /-- &/' \
  | sed -E 's/^         WHEN TAG IN /-- &/' \
  | sed -E 's/^   EXECUTE FUNCTION /-- &/' \
  | sed -E 's/^ALTER EVENT TRIGGER /-- &/' \
  | sed -E 's/^ALTER PUBLICATION "supabase_realtime_/-- &/' \
  | sed -E 's/^ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin"/-- &/' \
  | sed -E 's/^COMMENT ON EXTENSION (.+)/-- &/' \
  | sed -E 's/^SET transaction_timeout = 0;/-- &/' \
  > "$WORK/prod_schema.sql" || fail "lectura del esquema de producción"

# Datos de la app. Nunca salen de prod: tokens de teléfonos, códigos OTP, sesiones y bandejas de mensajes por enviar.
pg_dump "$PROD_DB_URL" --data-only --quote-all-identifiers -n public -n f360 -n f360_board \
  --exclude-table-data='"public"."push_tokens"' \
  --exclude-table-data='"public"."otp_verifications"' \
  --exclude-table-data='"f360"."seller_sessions"' \
  --exclude-table-data='"f360"."whatsapp_outbox"' \
  --exclude-table-data='"f360"."email_outbox"' \
  --exclude-table-data='"f360"."push_outbox"' \
  --exclude-table-data='"f360"."reserve_codes"' \
  | sed -E 's/^\\(un)?restrict .*$/-- &/' > "$WORK/prod_data_app.sql" || fail "lectura de datos de producción"

# Usuarios (sin sesiones ni tokens) e historia de migraciones.
pg_dump "$PROD_DB_URL" --data-only --quote-all-identifiers \
  -t auth.users -t auth.identities -t supabase_migrations.schema_migrations \
  | sed -E 's/^\\(un)?restrict .*$/-- &/' > "$WORK/prod_data_auth.sql" || fail "lectura de usuarios de producción"

# Políticas de archivos (storage) de prod, como sentencias CREATE POLICY.
psql "$PROD_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 > "$WORK/prod_storage_policies.sql" <<'SQL' || fail "lectura de políticas de storage"
begin read only;
set local search_path = '';
select format('create policy %I on storage.objects as %s for %s to %s%s%s;',
              policyname, lower(permissive), cmd,
              (select string_agg(case when r = 'public' then 'public' else quote_ident(r) end, ', ') from unnest(roles) r),
              case when qual is not null then ' using (' || qual || ')' else '' end,
              case when with_check is not null then ' with check (' || with_check || ')' else '' end)
  from pg_policies where schemaname = 'storage' and tablename = 'objects' order by policyname;
commit;
SQL
# Permisos exactos de prod (tablas, vistas, secuencias, funciones). Sin esto, los permisos por defecto de staging se suman
# a los del esquema copiado (p. ej. anon/authenticated con acceso total a tablas que en prod solo ve service_role).
# Por cada objeto de postgres: se quita todo a PUBLIC/anon/authenticated/service_role y se da exactamente lo de prod.
psql "$PROD_DB_URL" -X -q -A -t -v ON_ERROR_STOP=1 > "$WORK/prod_acls.sql" <<'SQL' || fail "lectura de permisos de producción"
begin read only;
set local search_path = '';
with objs as (
  select case c.relkind when 'S' then 'sequence' else 'table' end as kind,
         format('%I.%I', n.nspname, c.relname) as name,
         coalesce(c.relacl, acldefault((case c.relkind when 'S' then 's' else 'r' end)::"char", c.relowner)) as acl
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'f360', 'f360_board') and c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
     and pg_get_userbyid(c.relowner) = 'postgres'
  union all
  select 'routine', p.oid::regprocedure::text, coalesce(p.proacl, acldefault('f'::"char", p.proowner))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'f360', 'f360_board') and pg_get_userbyid(p.proowner) = 'postgres'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
), grants as (
  select o.kind, o.name, a.privilege_type, a.is_grantable,
         case a.grantee when 0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end as grantee
    from objs o cross join lateral aclexplode(o.acl) a
   where a.grantee = 0 or pg_get_userbyid(a.grantee) in ('anon', 'authenticated', 'service_role')
)
select stmt from (
  select 0 as ord, name, format('revoke all on %s %s from public, anon, authenticated, service_role;', kind, name) as stmt from objs
  union all
  select 1, name, format('grant %s on %s %s to %s%s;', string_agg(privilege_type, ', ' order by privilege_type), kind, name, grantee,
                         case when is_grantable then ' with grant option' else '' end)
    from grants group by kind, name, grantee, is_grantable
) s order by ord, name, stmt;
commit;
SQL
ls -lh "$WORK"/prod_*.sql | awk '{print "   ", $5, $NF}'

# ── 3. Reemplazo en staging: una sola transacción. El esquema (~7,000 sentencias) va en modo pipeline de psql 18:
#    se envía sin esperar respuesta de cada sentencia (sin esto, ~12 min de latencia con staging bloqueado). ──────────────────────────────────────────────────────────
step "Reemplazando staging (una transacción; termina en $FINISH)"
cat > "$WORK/run.sql" <<SQL
\\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = 0;
SET LOCAL lock_timeout = '60s';
SELECT set_config('fuxia.target_ref', '$STAGING_REF', true), set_config('fuxia.woo_mirrored', '$WOO_MIRRORED', true);
\\! date '+   · %H:%M:%S'
\\echo '     guardando configuración de staging y vaciando esquemas'
\\i $HERE/pre_restore.sql
\\! date '+   · %H:%M:%S'
\\echo '     esquema de producción'
\\startpipeline
\\i $WORK/prod_schema.sql
\\endpipeline
SET search_path = public, extensions;
SELECT set_config('fuxia.target_ref', '$STAGING_REF', true), set_config('fuxia.woo_mirrored', '$WOO_MIRRORED', true);
\\! date '+   · %H:%M:%S'
\\echo '     datos de producción'
SET session_replication_role = replica;
\\i $WORK/prod_data_app.sql
\\i $WORK/prod_data_auth.sql
SET session_replication_role = origin;
\\! date '+   · %H:%M:%S'
\\echo '     políticas de archivos'
\\i $WORK/prod_storage_policies.sql
\\! date '+   · %H:%M:%S'
\\echo '     permisos exactos de producción'
\\i $WORK/prod_acls.sql
\\! date '+   · %H:%M:%S'
\\echo '     anonimizar, devolver configuración de staging y verificar'
\\i $HERE/post_restore.sql
$FINISH;
SQL
psql "$STAGING_DB_URL" -X -q -v ON_ERROR_STOP=1 -P pager=off -f "$WORK/run.sql" > "$WORK/psql.out" 2>&1 \
  || { grep -vE '^(SET|set_config|-+|\(1 row\)|$)' "$WORK/psql.out" | tail -25; fail "reemplazo en staging (no se aplicó nada)"; }
grep -E '^ +·|NOTICE:  Verificación|\|' "$WORK/psql.out" | grep -vE 'set_config' || true
echo "   Transacción: $FINISH"

# ── 4. Migraciones del repo que prod todavía no tiene (solo --apply) ──────────────────────────────────────
MIG_STATUS="no aplica (ensayo)"
if [ "$MODE" = "--apply" ]; then
  step "Migraciones pendientes (rama fuxia-360 publicada en GitHub)"
  WT="$WORK/repo"
  git -C "$REPO" fetch -q origin fuxia-360 || fail "git fetch"
  git -C "$REPO" worktree add -q --detach "$WT" origin/fuxia-360 || fail "git worktree"
  (cd "$WT" && supabase db push --db-url "$STAGING_DB_URL" --include-all --dry-run 2>&1 | grep -vE 'new version|recommend updating') || true
  if (cd "$WT" && supabase db push --db-url "$STAGING_DB_URL" --include-all --yes 2>&1 | grep -vE 'new version|recommend updating'); then
    MIG_STATUS="ok"
  else
    MIG_STATUS="FALLÓ (staging quedó con el esquema de producción)"
  fi
  echo "   Migraciones: $MIG_STATUS"

  step "Datos propios de staging (after_refresh.list)"
  while IFS= read -r f; do
    case "$f" in ''|'#'*) continue ;; esac
    if [ -f "$WT/$f" ] && psql "$STAGING_DB_URL" -X -q -v ON_ERROR_STOP=1 -f "$WT/$f" > "$WORK/after_$(basename "$f").out" 2>&1; then
      echo "   ok  $f"
    else
      echo "   ✗   $f"; MIG_STATUS="${MIG_STATUS}; falló $f"
    fi
  done < "$WT/scripts/f360/staging_refresh/after_refresh.list"
  git -C "$REPO" worktree remove --force "$WT" || true
fi

# ── 5. Fotos de producto (product-images) ──────────────────────────────────────────────────────────────────
step "Fotos de producto"
T="$(security find-generic-password -s "Supabase CLI" -a supabase -w 2>/dev/null || true)"
case "$T" in go-keyring-base64:*) T="$(printf '%s' "${T#go-keyring-base64:}" | base64 -d)";; esac
[ -n "$T" ] || fail "no hay sesión de la CLI de Supabase (supabase login)"
SB_TOKEN="$T" node "$HERE/sync_storage.mjs" "$([ "$MODE" = "--apply" ] && echo --apply || echo --dry-run)" \
  || fail "sincronización de fotos"

# ── 6. Limpieza: se guardan 7 días de copias ───────────────────────────────────────────────────────────────
find "$BASE" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +7 -exec rm -rf {} + 2>/dev/null || true

step "Listo"
if [ "$MODE" = "--apply" ]; then
  if [ "$MIG_STATUS" = "ok" ]; then notify "Staging = producción" "Copia anonimizada aplicada ($TS)"
  else notify "Copia aplicada con avisos" "$MIG_STATUS — ver $LOG"; exit 1; fi
fi
echo "Registro: $LOG"
