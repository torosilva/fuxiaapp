#!/usr/bin/env bash
# Fuxia 360 · Inventario de SOLO LECTURA de las dos tiendas WordPress (fuxiaballerinas.com y staging4), para diseñar
# la copia nocturna prod → staging4 (docs/fuxia360/ops/STAGING_REFRESH.md). Solo ejecuta consultas WP-CLI de lectura
# (get/list/size/du) y nunca imprime valores de opciones: solo nombres, conteos y tamaños.
# Uso: scripts/f360/wp_inventory.sh
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
"${SSH[@]}" 'bash -s' <<'REMOTE'
set -u
for site in fuxiaballerinas.com staging4.fuxiaballerinas.com; do
  WP=~/www/$site/public_html
  cd "$WP" || continue
  echo "=== $site"
  echo "home: $(wp option get home)"
  echo "prefijo: $(wp config get table_prefix)"
  echo "tamaño BD: $(wp db size --size_format=mb 2>/dev/null)"
  echo "uploads: $(du -sh wp-content/uploads 2>/dev/null | cut -f1) · plugins: $(du -sh wp-content/plugins | cut -f1) · themes: $(du -sh wp-content/themes | cut -f1)"
  echo "pedidos HPOS: $(wp option get woocommerce_custom_orders_table_enabled 2>/dev/null)"
  echo "blog_public: $(wp option get blog_public)"
  echo "plugins activos: $(wp plugin list --status=active --field=name | tr '\n' ' ')"
  echo "mu-plugins: $(ls wp-content/mu-plugins 2>/dev/null | tr '\n' ' ')"
  echo "pasarelas activas: $(wp wc payment_gateway list --user=1 --fields=id,enabled --format=csv 2>/dev/null | awk -F, '$2=="true"||$2=="yes"{print $1}' | tr '\n' ' ')"
  echo "webhooks (id,estado,tema): $(wp wc webhook list --user=1 --fields=id,status,topic --format=csv 2>/dev/null | tail -n +2 | tr '\n' ' ')"
  echo "tablas: $(wp db tables --all-tables-with-prefix --format=csv 2>/dev/null)"
  echo "opciones relevantes (solo nombres): $(wp option list --search='*f360*' --field=option_name 2>/dev/null | tr '\n' ' ') $(wp option list --search='*mercado*' --field=option_name 2>/dev/null | tr '\n' ' ') $(wp option list --search='*paypal*' --field=option_name 2>/dev/null | tr '\n' ' ') $(wp option list --search='*gtm4wp*' --field=option_name 2>/dev/null | tr '\n' ' ') $(wp option list --search='*hilo*' --field=option_name 2>/dev/null | tr '\n' ' ')"
  echo "usuarios por rol: $(wp user list --fields=roles --format=csv 2>/dev/null | tail -n +2 | sort | uniq -c | tr '\n' ' ')"
  echo
done
REMOTE
