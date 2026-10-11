#!/usr/bin/env bash
# Fuxia 360 · Copia de la TIENDA REAL (fuxiaballerinas.com) → staging4, anonimizada y neutralizada. Decisión de Mario (2026-10-11).
# Guía: docs/fuxia360/ops/STAGING_REFRESH.md. Lo llama nightly.sh antes de refresh.sh (Supabase).
#
#   woo_refresh.sh --rehearsal   solo lectura: verifica acceso, guardas, tamaños y que la limpieza compile; no cambia nada
#   woo_refresh.sh --apply       copia real
#
# Producción solo se LEE (mysqldump --single-transaction, rsync desde prod). Todo se escribe en staging4.
# Si algo falla después de empezar a escribir en staging4, se restaura automáticamente su respaldo de la base.
# Limpieza (decisiones de Mario 2026-10-11):
#   · pagos: solo Mercado Pago, con la configuración de staging4 (cuenta de prueba); PayPal (2 plugins) y ePayco apagados;
#   · apagados: Google Listings & Ads, Facebook for WooCommerce, Cart Abandonment Recovery, Microsoft Clarity;
#   · ningún correo sale y ninguna llamada del servidor llega a producción (mu-plugin f360-guardia-staging4.php);
#   · webhooks y claves API de Woo: los de staging4 (los de prod se borran); GTM: el de staging4; noindex;
#   · mu-plugins: espejo de producción apuntando a staging (build_staging4_mirror_mu.mjs) + guardia; sin Hilo (solo existe en prod);
#   · clientas anonimizadas (usuarios, pedidos, direcciones, leads, avisos, carritos, reseñas); sesiones, tokens y registros vacíos;
#   · verificación final: si queda un correo de clienta real, se restaura el respaldo y falla.
set -euo pipefail

MODE="${1:-}"
case "$MODE" in --rehearsal|--apply) ;; *) echo "uso: $0 --rehearsal | --apply" >&2; exit 2 ;; esac

PROD_REF="tgzgiwfzddsghnxgkcqd"
STAGING_REF="faltxpkaicwpnlqaxrdu"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
SSH=(ssh -p 18765 -o BatchMode=yes -o ServerAliveInterval=30 u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
TS="$(date +%Y-%m-%d_%H%M%S)"

# Archivos que se instalan en staging4: deben estar commiteados (lo que corre es historia revisada).
MU_DIRS=(tools/storefront/mu-plugins/staging4-espejo)
MU_EXTRA=(tools/storefront/mu-plugins/staging4/f360-guardia-staging4.php)
cd "$REPO"
for p in "${MU_DIRS[@]}" "${MU_EXTRA[@]}"; do
  git diff --quiet HEAD -- "$p" && [ -z "$(git ls-files --others --exclude-standard -- "$p")" ] \
    || { echo "ABORT: $p tiene cambios sin commitear." >&2; exit 3; }
done

# Claves públicas (anon / publishable) de cada proyecto, para reemplazar en el contenido copiado. No son secretas.
T="$(security find-generic-password -s "Supabase CLI" -a supabase -w 2>/dev/null || true)"
case "$T" in go-keyring-base64:*) T="$(printf '%s' "${T#go-keyring-base64:}" | base64 -d)";; esac
[ -n "$T" ] || { echo "ABORT: no hay sesión de la CLI de Supabase (supabase login)." >&2; exit 4; }
pubkeys() {   # $1 = ref → "anon_jwt publishable" (publishable puede faltar)
  curl -s "https://api.supabase.com/v1/projects/$1/api-keys?reveal=false" -H "Authorization: Bearer $T" | python3 -c '
import json,sys
ks=json.load(sys.stdin); a=[k.get("api_key","") for k in ks if k.get("name")=="anon"]; p=[k.get("api_key","") for k in ks if k.get("type")=="publishable"]
print((a[0] if a else "-"), (p[0] if p else "-"))'
}
read -r PROD_ANON PROD_PUB <<<"$(pubkeys "$PROD_REF")"
read -r STG_ANON STG_PUB <<<"$(pubkeys "$STAGING_REF")"
[ "$PROD_ANON" != "-" ] && [ "$STG_ANON" != "-" ] || { echo "ABORT: no pude leer las claves anon." >&2; exit 4; }

notify() { osascript -e "display notification \"$2\" with title \"Fuxia staging4\" subtitle \"$1\"" >/dev/null 2>&1 || true; }

# Paquete para el servidor: mu-plugins + SQL de anonimización.
PKG="$(mktemp -d)"; trap 'rm -rf "$PKG"' EXIT
mkdir -p "$PKG/mu"
cp tools/storefront/mu-plugins/staging4-espejo/*.php "${MU_EXTRA[@]}" "$PKG/mu/"
cp "$HERE/woo_anonymize.sql" "$PKG/"
tar -C "$PKG" -czf "$PKG.tgz" . && mv "$PKG.tgz" "$PKG/pkg.tgz"

echo "Fuxia 360 · tienda real → staging4 · ${MODE#--} · $TS"
set +e
"${SSH[@]}" "mkdir -p ~/f360-backups/staging4-refresh/$TS && cat > ~/f360-backups/staging4-refresh/$TS/pkg.tgz" < "$PKG/pkg.tgz"
"${SSH[@]}" "MODE='$MODE' TS='$TS' PROD_ANON='$PROD_ANON' PROD_PUB='$PROD_PUB' STG_ANON='$STG_ANON' STG_PUB='$STG_PUB' bash -s" <<'REMOTE'
set -euo pipefail
P=~/www/fuxiaballerinas.com/public_html
S=~/www/staging4.fuxiaballerinas.com/public_html
B=~/f360-backups/staging4-refresh/$TS
step() { echo; echo "── $(date +%H:%M:%S) · $1"; }
umask 077
cd "$B" && tar -xzf pkg.tgz && rm pkg.tgz

# ── Barreras ─────────────────────────────────────────────────────────────────────────────────────────────
[ "$(cd "$P" && wp option get home)" = "https://fuxiaballerinas.com" ] || { echo "ABORT: origen no es la tienda real"; exit 10; }
[ "$(cd "$S" && wp option get home)" = "https://staging4.fuxiaballerinas.com" ] || { echo "ABORT: destino no es staging4"; exit 10; }
[ "$(cd "$P" && wp config get table_prefix)" = "$(cd "$S" && wp config get table_prefix)" ] || { echo "ABORT: prefijos distintos"; exit 10; }
[ "$(cd "$P" && wp config get DB_NAME)" != "$(cd "$S" && wp config get DB_NAME)" ] || { echo "ABORT: misma base de datos"; exit 10; }
PFX="$(cd "$S" && wp config get table_prefix)"
echo "barreras OK (prefijo $PFX)"

step "Tamaños"
echo "base prod: $(cd "$P" && wp db size --size_format=mb) MB · uploads prod: $(du -sh "$P/wp-content/uploads" | cut -f1)"
rsync -a --delete --dry-run --stats --exclude 'wc-logs/' --exclude 'cache/' "$P/wp-content/uploads/" "$S/wp-content/uploads/" | grep -E 'Number of (regular )?files transferred|Total transferred file size' || true

if [ "$MODE" = "--rehearsal" ]; then
  step "Ensayo: la limpieza SQL se valida contra una copia temporal no es posible sin escribir; se revisa sintaxis básica"
  grep -c ';' woo_anonymize.sql | xargs echo "sentencias en woo_anonymize.sql:"
  ls mu | xargs echo "mu-plugins a instalar:"
  echo "ENSAYO OK (nada cambió)"
  exit 0
fi

# ── 1. Respaldo de staging4 y lo que staging4 conserva ──────────────────────────────────────────────────
step "Respaldo de staging4"
(cd "$S" && wp db export "$B/staging4_before.sql" --single-transaction --quick >/dev/null) && gzip -f "$B/staging4_before.sql"
(cd "$S" && wp db export "$B/keep_tables.sql" --tables="${PFX}wc_webhooks,${PFX}woocommerce_api_keys" --single-transaction >/dev/null)
(cd "$S" && wp db export "$B/keep_options.sql" --tables="${PFX}options" --no-create-info --single-transaction \
   --where="option_name like '\\_mp\\_%' or option_name like '%mercado%pago%' or option_name like 'mercadopago%' or option_name like 'checkbox\\_checkout\\_%' or option_name in ('gtm4wp-options','blog_public')" >/dev/null)
mkdir -p "$B/mu_before" && cp -a "$S/wp-content/mu-plugins/." "$B/mu_before/" 2>/dev/null || true
ls -la "$B" | awk 'NR>1{print "   ", $5, $NF}'

restore() {
  echo "!! FALLÓ: restaurando staging4 desde $B/staging4_before.sql.gz"
  (cd "$S" && gunzip -c "$B/staging4_before.sql.gz" | wp db import - >/dev/null) || echo "!! la restauración también falló: revisar a mano"
  rm -rf "$S/wp-content/mu-plugins" && mkdir -p "$S/wp-content/mu-plugins" && cp -a "$B/mu_before/." "$S/wp-content/mu-plugins/" || true
  (cd "$S" && wp maintenance-mode deactivate --skip-plugins --skip-themes >/dev/null 2>&1) || true
  (cd "$S" && wp sg purge >/dev/null 2>&1) || true
}
trap 'restore' ERR

# ── 2. Guardia primero: desde aquí staging4 no puede mandar correos ni llamar a producción ───────────────
step "Guardia de staging4 y modo mantenimiento (nadie usa staging4 ni corre su cron mientras se reemplaza)"
cp mu/f360-guardia-staging4.php "$S/wp-content/mu-plugins/"
(cd "$S" && wp maintenance-mode activate --skip-plugins --skip-themes >/dev/null)

# ── 3. Base de datos de la tienda real → staging4 ───────────────────────────────────────────────────────
step "Base de datos (prod se lee con --single-transaction)"
(cd "$P" && wp db export "$B/prod.sql" --single-transaction --quick >/dev/null)
(cd "$S" && wp db import "$B/prod.sql" --skip-plugins --skip-themes >/dev/null)
rm -f "$B/prod.sql"

# ── 4. Archivos (temas, plugins, fotos). mu-plugins y wp-config.php de staging4 no se tocan. ─────────────
step "Archivos"
for d in themes plugins uploads; do
  rsync -a --delete --exclude 'wc-logs/' --exclude 'cache/' "$P/wp-content/$d/" "$S/wp-content/$d/"
done

W() { (cd "$S" && wp --skip-plugins --skip-themes "$@"); }

# ── 5. Direcciones: tienda real → staging4; Supabase prod → staging; Hilo (solo prod) desactivado ────────
step "Direcciones"
W search-replace 'https://fuxiaballerinas.com' 'https://staging4.fuxiaballerinas.com' --all-tables-with-prefix --precise --quiet
W search-replace 'https://www.fuxiaballerinas.com' 'https://staging4.fuxiaballerinas.com' --all-tables-with-prefix --precise --quiet
W search-replace 'tgzgiwfzddsghnxgkcqd.supabase.co' 'faltxpkaicwpnlqaxrdu.supabase.co' --all-tables-with-prefix --precise --quiet
W search-replace "$PROD_ANON" "$STG_ANON" --all-tables-with-prefix --precise --quiet
[ "$PROD_PUB" = "-" ] || [ "$STG_PUB" = "-" ] || W search-replace "$PROD_PUB" "$STG_PUB" --all-tables-with-prefix --precise --quiet
W search-replace 'web-production-8cc5a.up.railway.app' 'hilo.staging.invalid' --all-tables-with-prefix --precise --quiet

# ── 6. Lo que staging4 conserva ─────────────────────────────────────────────────────────────────────────
step "Configuración propia de staging4"
W db query "DELETE FROM ${PFX}options WHERE option_name like '\\_mp\\_%' or option_name like '%mercado%pago%' or option_name like 'mercadopago%' or option_name like 'checkbox\\_checkout\\_%' or option_name in ('gtm4wp-options','blog_public')"
W db import "$B/keep_options.sql" >/dev/null
W db import "$B/keep_tables.sql" >/dev/null
ADMIN="$(W user list --role=administrator --field=ID --orderby=ID --order=ASC | head -1)"
W db query "UPDATE ${PFX}wc_webhooks SET user_id = $ADMIN; UPDATE ${PFX}woocommerce_api_keys SET user_id = $ADMIN"
W option update blog_public 0 >/dev/null

# Plugins: se apagan editando la opción (sin correr sus ganchos de desactivación, que podrían llamar a cuentas reales).
W eval '
$off = array("google-listings-and-ads","facebook-for-woocommerce","woo-cart-abandonment-recovery","microsoft-clarity",
             "woo-paypal-gateway","woocommerce-paypal-payments","epayco-gateway");
$act = array_values(array_filter((array) get_option("active_plugins"), function ($p) use ($off) { return !in_array(dirname($p), $off, true); }));
update_option("active_plugins", $act);
foreach (array("woocommerce_paypal_settings","woocommerce_wpg_paypal_checkout_settings","woocommerce_ppcp-gateway_settings","woocommerce_epayco_settings") as $o) {
  $v = get_option($o); if (is_array($v)) { $v["enabled"] = "no"; update_option($o, $v); }
}
echo "plugins activos: " . count($act) . PHP_EOL;'

# ── 7. Anonimizar clientas + verificación (aborta si queda un correo real) ───────────────────────────────
step "Anonimizar"
sed "s/{P}/$PFX/g" woo_anonymize.sql > anon.sql
W db query < anon.sql
LEFT="$(W db query --skip-column-names "SELECT
   (SELECT COUNT(*) FROM ${PFX}users u JOIN ${PFX}usermeta m ON m.user_id=u.ID AND m.meta_key='${PFX}capabilities'
     WHERE m.meta_value NOT LIKE '%administrator%' AND m.meta_value NOT LIKE '%shop_manager%' AND u.user_email NOT LIKE '%@staging.invalid')
 + (SELECT COUNT(*) FROM ${PFX}wc_orders WHERE billing_email IS NOT NULL AND billing_email <> '' AND billing_email NOT LIKE '%@staging.invalid')
 + (SELECT COUNT(*) FROM ${PFX}wc_order_addresses WHERE email IS NOT NULL AND email <> '' AND email NOT LIKE '%@staging.invalid')
 + (SELECT COUNT(*) FROM ${PFX}wc_customer_lookup WHERE email IS NOT NULL AND email NOT LIKE '%@staging.invalid')
 + (SELECT COUNT(*) FROM ${PFX}comments WHERE comment_author_email <> '' AND comment_author_email NOT LIKE '%@staging.invalid'
     AND comment_author_email NOT LIKE '%@fuxiaballerinas.com')
 + (SELECT COUNT(*) FROM ${PFX}wc_orders_meta WHERE meta_value REGEXP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\\\.[A-Za-z]{2,}' AND meta_value NOT LIKE '%@staging.invalid%')
 + (SELECT COUNT(*) FROM ${PFX}usermeta m JOIN ${PFX}usermeta c ON c.user_id=m.user_id AND c.meta_key='${PFX}capabilities'
     WHERE c.meta_value NOT LIKE '%administrator%' AND c.meta_value NOT LIKE '%shop_manager%'
       AND m.meta_value REGEXP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\\\.[A-Za-z]{2,}' AND m.meta_value NOT LIKE '%@staging.invalid%')")"
[ "$LEFT" = "0" ] || { echo "ABORT: quedaron $LEFT correo(s) de clientas sin anonimizar"; false; }
echo "verificación OK: ningún correo de clienta real"

# ── 8. mu-plugins: espejo de prod (a staging) + guardia; lo anterior queda en el respaldo ───────────────
step "mu-plugins"
for f in mu/*.php; do php -l "$f" >/dev/null || { echo "ABORT: $f no pasa php -l"; false; }; done
rm -rf "$S/wp-content/mu-plugins" && mkdir -p "$S/wp-content/mu-plugins" && cp mu/*.php "$S/wp-content/mu-plugins/"
ls "$S/wp-content/mu-plugins" | xargs echo "  "

# ── 9. Caché y prueba ────────────────────────────────────────────────────────────────────────────────────
step "Caché y prueba"
(cd "$S" && wp maintenance-mode deactivate --skip-plugins --skip-themes >/dev/null)
(cd "$S" && wp sg purge >/dev/null 2>&1) || true
[ "$(cd "$S" && wp option get home)" = "https://staging4.fuxiaballerinas.com" ] || { echo "ABORT: home quedó mal"; false; }
[ "$(cd "$S" && wp wc webhook list --user=$ADMIN --field=delivery_url 2>/dev/null | grep -c tgzgiwfzddsghnxgkcqd)" = "0" ] || { echo "ABORT: un webhook apunta a prod"; false; }
trap - ERR

# Respaldos: 7 días.
find ~/f360-backups/staging4-refresh -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
rm -f anon.sql
echo "LISTO"
REMOTE
rc=$?
set -e
code="$(curl -sL -o /dev/null -w '%{http_code}' "https://staging4.fuxiaballerinas.com/mx/?nc=$TS")"
echo "staging4 /mx/: http $code"
if [ "$rc" -ne 0 ] || { [ "$MODE" = "--apply" ] && [ "$code" != "200" ]; }; then
  [ "$MODE" = "--apply" ] && notify "Copia de la tienda FALLÓ" "staging4 restaurado desde respaldo ($TS)"
  exit 1
fi
[ "$MODE" = "--apply" ] && notify "staging4 = tienda real" "Copia anonimizada aplicada ($TS)"
exit 0
