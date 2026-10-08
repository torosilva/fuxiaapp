#!/usr/bin/env bash
# Fuxia 360 · connects fuxiaballerinas.com orders to Fuxia 360 (Mario 2026-10-08: "yes sync please it is very important").
# Creates (once) the two WooCommerce webhooks order.created + order.updated → f360-woo-orders in production, signed with the
# secret in ~/.fuxia-woo-orders.secret (made by deploy_prod_function.sh f360-woo-orders; sent over SSH stdin, never printed,
# never on a command line). Idempotent: an existing webhook to the same URL is reactivated, not duplicated.
# Order: 1) pase D7 (orders_mode on)  2) deploy_prod_function.sh f360-woo-orders  3) this script.
# Emergency off: wp-admin → WooCommerce → Ajustes → Avanzado → Webhooks → pausar "Fuxia 360 · pedidos" (and orders_mode='off').
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
WP='~/www/fuxiaballerinas.com/public_html'
URL='https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-woo-orders'
SECRET_FILE="$HOME/.fuxia-woo-orders.secret"
[ -s "$SECRET_FILE" ] || { echo "ABORT: falta $SECRET_FILE (corre antes scripts/f360/deploy_prod_function.sh f360-woo-orders)" >&2; exit 1; }
"${SSH[@]}" "test \"\$(cd $WP && wp option get home)\" = 'https://fuxiaballerinas.com'" || { echo "ABORT: el destino no es fuxiaballerinas.com" >&2; exit 1; }
tr -d '\n' < "$SECRET_FILE" | "${SSH[@]}" "cd $WP && wp eval '
  \$secret = trim(stream_get_contents(STDIN)); if (strlen(\$secret) < 32) { echo \"ABORT: secreto vacío\"; exit(1); }
  \$admin = get_users([\"role\" => \"administrator\", \"number\" => 1, \"fields\" => \"ID\"])[0];
  \$ds = new WC_Webhook_Data_Store();
  foreach ([\"order.created\" => \"Fuxia 360 · pedidos (creado)\", \"order.updated\" => \"Fuxia 360 · pedidos (actualizado)\"] as \$topic => \$name) {
    \$found = null;
    foreach (\$ds->search_webhooks([\"limit\" => -1]) as \$id) { \$w = wc_get_webhook(\$id); if (\$w && \$w->get_delivery_url() === \"$URL\" && \$w->get_topic() === \$topic) { \$found = \$w; } }
    \$w = \$found ?: new WC_Webhook();
    \$w->set_name(\$name); \$w->set_topic(\$topic); \$w->set_delivery_url(\"$URL\"); \$w->set_secret(\$secret);
    \$w->set_api_version(\"wp_api_v3\"); \$w->set_user_id(\$admin); \$w->set_status(\"active\"); \$w->save();
    echo (\$found ? \"reactivado\" : \"creado\"), \": \", \$name, \" (#\", \$w->get_id(), \")\", PHP_EOL;
  }
'"
echo "LISTO: los pedidos de fuxiaballerinas.com llegan a Fuxia 360. Apagado de emergencia: pausar los webhooks 'Fuxia 360 · pedidos'."
