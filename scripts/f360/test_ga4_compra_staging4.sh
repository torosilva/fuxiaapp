#!/usr/bin/env bash
# Fuxia 360 · runs tools/storefront/tests/ga4_compra_servidor_staging4.php on STAGING4 only (wp eval-file). Creates and then deletes
# its own test orders; the plugin only validates against GA4's /debug/mp/collect (nothing is recorded in Analytics).
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
WP='~/www/staging4.fuxiaballerinas.com/public_html'
cd "$(dirname "$0")/../.."
T=tools/storefront/tests/ga4_compra_servidor_staging4.php
"${SSH[@]}" "test \"\$(cd $WP && wp option get home)\" = 'https://staging4.fuxiaballerinas.com'" || { echo "ABORT: el destino no es staging4" >&2; exit 1; }
"${SSH[@]}" "mkdir -p ~/f360-tests && cat > ~/f360-tests/ga4.php" < "$T"
"${SSH[@]}" "cd $WP && wp eval-file ~/f360-tests/ga4.php 2>&1; rc=\$?; rm -f ~/f360-tests/ga4.php; exit \$rc"
