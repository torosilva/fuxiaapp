#!/usr/bin/env bash
# Creates the throwaway local store and mirrors the LIVE catalog structure the publisher depends on
# (observed read-only in WOO_PUBLISHING_V1_PLAN §B): global attributes pa_color + pa_medida (35–40),
# the existing pa_color terms, and the 4 real categories. Writes tools/woo-docker/.env.local (gitignored).
set -euo pipefail
cd "$(dirname "$0")"
docker compose up -d
wp() { docker compose exec -T -e WP_CLI_CACHE_DIR=/tmp/wp-cli-cache cli wp --path=/var/www/html "$@"; }
until wp db check >/dev/null 2>&1; do sleep 2; done
if ! wp core is-installed 2>/dev/null; then
  wp core install --url=http://localhost:8080 --title="Fuxia Woo LOCAL (pruebas)" --admin_user=f360admin \
    --admin_password="$(openssl rand -hex 16)" --admin_email=f360admin@local.invalid --skip-email
fi
wp rewrite structure '/%postname%/' >/dev/null
docker compose exec -T -u 33 wordpress sh -c 'cat > /var/www/html/.htaccess' <<'HT'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HT
wp plugin is-installed woocommerce || wp plugin install woocommerce >/dev/null
wp plugin activate woocommerce >/dev/null
wp option update woocommerce_currency MXN >/dev/null
wp option update woocommerce_manage_stock yes >/dev/null
wp option update blog_public 0 >/dev/null

# Attributes (global) — never created by the publisher; they already exist in the real store.
attr_id() { wp wc product_attribute list --user=f360admin --fields=id,slug --format=csv 2>/dev/null | awk -F, -v s="pa_$1" '$2==s{print $1}'; }
[ -n "$(attr_id color)" ] || wp wc product_attribute create --name=Color --slug=color --user=f360admin >/dev/null
[ -n "$(attr_id medida)" ] || wp wc product_attribute create --name=Medida --slug=medida --user=f360admin >/dev/null
COLOR=$(attr_id color); MEDIDA=$(attr_id medida)
for t in Café Dorado Negro Taupe Verde Vino; do wp wc product_attribute_term create "$COLOR" --name="$t" --user=f360admin >/dev/null 2>&1 || true; done
for t in 35 36 37 38 39 40; do wp wc product_attribute_term create "$MEDIDA" --name="$t" --user=f360admin >/dev/null 2>&1 || true; done

# Categories (the 4 real ones). A few unrelated ones first so IDs are NOT 1..4 (catches any "by position" bug).
for c in Accesorios Outlet Ballerinas "Sandalia Plana" "Sandalia Alta" Botas; do
  wp wc product_cat create --name="$c" --user=f360admin >/dev/null 2>&1 || true
done

# LOCAL-ONLY mu-plugin: WordPress refuses to download images from private hosts / non-standard ports (safe remote get).
# The contract tests serve generated photos from the Mac at host.docker.internal:8099, so allow exactly that.
# The real store downloads from the public Supabase Storage HTTPS URL and needs nothing like this.
docker compose exec -T -u 33 wordpress sh -c 'mkdir -p /var/www/html/wp-content/mu-plugins && cat > /var/www/html/wp-content/mu-plugins/f360-local-test-images.php' <<'PHP'
<?php
// Fuxia 360 LOCAL test store only — never install on a real store.
add_filter('http_request_host_is_external', function ($external, $host) { return $host === 'host.docker.internal' ? true : $external; }, 10, 2);
add_filter('http_allowed_safe_ports', function ($ports) { $ports[] = 8099; $ports[] = 8787; return $ports; });
// WP-Cron is disabled locally (DISABLE_WP_CRON), so deliver webhooks synchronously instead of via Action Scheduler.
add_filter('woocommerce_webhook_deliver_async', '__return_false');
PHP

# Application password for the publisher (local only). Recreated on every setup; printed nowhere.
wp user application-password delete f360admin --all >/dev/null 2>&1 || true
PASS=$(wp user application-password create f360admin f360-publisher --porcelain)
ADMIN_PW=$(openssl rand -hex 16)   # local wp-admin login (used only by the E2E screenshots)
wp user update f360admin --user_pass="$ADMIN_PW" --skip-email >/dev/null
umask 077
cat > .env.local <<ENV
WOO_BASE_URL=http://localhost:8080
WOO_USER=f360admin
WOO_SECRET=$PASS
WP_ADMIN_USER=f360admin
WP_ADMIN_PASSWORD=$ADMIN_PW
WOO_WEBHOOK_SECRET=$(openssl rand -hex 24)
ENV
# P2.3A: order webhooks → local runner (scripts/f360/publisher_local.ts)
WHS=$(grep '^WOO_WEBHOOK_SECRET=' .env.local | cut -d= -f2)
for T in order.created order.updated; do
  wp wc webhook create --name="Fuxia 360 $T" --topic="$T" --delivery_url=http://host.docker.internal:8787/f360-woo-orders --secret="$WHS" --status=active --user=f360admin >/dev/null
done
echo "Local Woo ready at http://localhost:8080 (credentials in tools/woo-docker/.env.local)"
wp wc product_cat list --user=f360admin --fields=id,name,slug --format=csv | grep -Ei 'ballerinas|sandalia|botas'
