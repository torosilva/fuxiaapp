#!/usr/bin/env bash
# Fuxia 360 · runs tools/storefront/tests/meta_compra_servidor_staging4.php on STAGING4 only. Meta for WooCommerce is loaded
# ONLY inside that wp-cli process (tests/meta_cargar_plugin_fb.php) and every request to Meta is blocked and recorded, except
# the optional real sends with test_event_code ("Probar eventos", not counted in reports). Creates and deletes its own orders.
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
WP='~/www/staging4.fuxiaballerinas.com/public_html'
cd "$(dirname "$0")/../.."
T=tools/storefront/tests/meta_compra_servidor_staging4.php
R=tools/storefront/tests/meta_cargar_plugin_fb.php
"${SSH[@]}" "test \"\$(cd $WP && wp option get home)\" = 'https://staging4.fuxiaballerinas.com'" || { echo "ABORT: el destino no es staging4" >&2; exit 1; }
"${SSH[@]}" "mkdir -p ~/f360-tests && cat > ~/f360-tests/meta.php" < "$T"
"${SSH[@]}" "cat > ~/f360-tests/meta_fb.php" < "$R"
"${SSH[@]}" "php -l ~/f360-tests/meta.php >/dev/null && php -l ~/f360-tests/meta_fb.php >/dev/null" || { echo "ABORT: php -l" >&2; exit 2; }
"${SSH[@]}" "cd $WP && wp --require=\$HOME/f360-tests/meta_fb.php eval-file ~/f360-tests/meta.php 2>&1; rc=\$?; rm -f ~/f360-tests/meta.php ~/f360-tests/meta_fb.php; exit \$rc"
