#!/usr/bin/env bash
# Fuxia 360 · READ-ONLY inventory of the contacts the old WooCommerce store collected (Mario 2026-11-09: "falta migrar todo
# lo que teníamos de carrito perdido y todo lo que se ha registrado de correos y celulares, también toda la gente que se ha
# suscrito"). Prints ONLY table names, row counts, date ranges and the coupon's rules — never an e-mail, phone or name.
# Nothing is written on the server. Run by Mario (SSH to production): scripts/f360/wp_contactos_inventario.sh
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
WP='~/www/fuxiaballerinas.com/public_html'
"${SSH[@]}" bash -s <<EOF
set -e
cd $WP
test "\$(wp option get home)" = 'https://fuxiaballerinas.com' || { echo "ABORT: no es fuxiaballerinas.com"; exit 1; }
P=\$(wp db prefix)
echo "== Plugins activos"; wp plugin list --status=active --field=name | tr '\n' ' '; echo
echo "== Tablas con contactos (filas)"
wp db query "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema = DATABASE() AND (table_name LIKE '%cart%' OR table_name LIKE '%abandon%' OR table_name LIKE '%lead%' OR table_name LIKE '%subscri%' OR table_name LIKE '%newsletter%' OR table_name LIKE '%mailpoet%' OR table_name LIKE '%fuxia%' OR table_name LIKE '%wc_customer_lookup%')" --skip-column-names
for T in \${P}cartflows_ca_cart_abandonment \${P}fuxia_leads \${P}wc_customer_lookup; do
  if wp db query "SELECT 1 FROM \$T LIMIT 1" >/dev/null 2>&1; then
    echo "== \$T: columnas"; wp db query "SELECT GROUP_CONCAT(column_name) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '\$T'" --skip-column-names
  fi
done
if wp db query "SELECT 1 FROM \${P}cartflows_ca_cart_abandonment LIMIT 1" >/dev/null 2>&1; then
  echo "== Carritos abandonados por estado (y fechas)"
  wp db query "SELECT order_status, unsubscribed, COUNT(*), MIN(time), MAX(time) FROM \${P}cartflows_ca_cart_abandonment GROUP BY order_status, unsubscribed" --skip-column-names
fi
echo "== Opciones con 'lead' en el nombre"; wp option list --search='*lead*' --fields=option_name,size_bytes --format=csv | head -20
echo "== Publicaciones tipo lead"; wp db query "SELECT post_type, COUNT(*) FROM \${P}posts WHERE post_type LIKE '%lead%' OR post_type LIKE '%subscri%' GROUP BY post_type" --skip-column-names
echo "== Clientas Woo registradas"; wp user list --role=customer --format=count
echo "== Cupón BIENVENIDA10 (reglas, sin datos de clientas)"
wp db query "SELECT p.ID, p.post_status, MAX(CASE WHEN m.meta_key='discount_type' THEN m.meta_value END) tipo, MAX(CASE WHEN m.meta_key='coupon_amount' THEN m.meta_value END) monto,
  MAX(CASE WHEN m.meta_key='usage_limit_per_user' THEN m.meta_value END) por_clienta, MAX(CASE WHEN m.meta_key='usage_limit' THEN m.meta_value END) limite,
  MAX(CASE WHEN m.meta_key='usage_count' THEN m.meta_value END) usos, MAX(CASE WHEN m.meta_key='minimum_amount' THEN m.meta_value END) minimo,
  MAX(CASE WHEN m.meta_key='exclude_sale_items' THEN m.meta_value END) sin_rebajas, MAX(CASE WHEN m.meta_key='individual_use' THEN m.meta_value END) solo,
  MAX(CASE WHEN m.meta_key='date_expires' THEN m.meta_value END) vence
  FROM \${P}posts p JOIN \${P}postmeta m ON m.post_id = p.ID WHERE p.post_type = 'shop_coupon' AND UPPER(p.post_title) = 'BIENVENIDA10' GROUP BY p.ID, p.post_status"
EOF
