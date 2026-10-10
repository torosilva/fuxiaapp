#!/usr/bin/env bash
# Fuxia 360 · production store (fuxiaballerinas.com): replace the STAGING f360-store-reserve URL left inside Bricks page content
# (copied from staging4 on 2026-10-08) with production's. Today the mu-plugin f360-un-solo-origen.php rewrites it at render time;
# after this fix the mu-plugin can be retired.
#   dry-run (default): read only — lists page id, title, meta key and occurrences. Nothing is written.
#   apply:             backs up each affected meta value to ~/f360-backups/bricks-<page>-<meta>-<ts>.json ON THE SERVER, then
#                      replaces ONLY that exact URL (recursive over the Bricks array) with update_post_meta. Needs Mario's OK.
#   restore <file>:    puts a backed-up value back.
# Usage: scripts/f360/prod_bricks_staging_urls.sh [dry-run|apply|restore <server-file>]
set -euo pipefail
MODE="${1:-dry-run}"
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
WP='~/www/fuxiaballerinas.com/public_html'
FROM='https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-store-reserve'
TO='https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-store-reserve'
case "$MODE" in dry-run|apply) ;; restore) [ -n "${2:-}" ] || { echo "uso: $0 restore <archivo>"; exit 1; } ;; *) echo "uso: $0 [dry-run|apply|restore <archivo>]"; exit 1 ;; esac
"${SSH[@]}" "test \"\$(cd $WP && wp option get home)\" = 'https://fuxiaballerinas.com'" || { echo "ABORT: el destino no es fuxiaballerinas.com"; exit 1; }
if [ "$MODE" = restore ]; then
  "${SSH[@]}" "cd $WP && wp eval '
    \$b = json_decode(file_get_contents(\"$2\"), true); if (!\$b || empty(\$b[\"post_id\"])) { echo \"ABORT: respaldo inválido\"; exit(1); }
    update_post_meta((int) \$b[\"post_id\"], \$b[\"meta_key\"], \$b[\"value\"]); echo \"restaurado: página \", \$b[\"post_id\"], \" \", \$b[\"meta_key\"], PHP_EOL;'"
  exit 0
fi
"${SSH[@]}" "cd $WP && F360_MODE=$MODE wp eval '
  global \$wpdb; \$from = \"$FROM\"; \$to = \"$TO\"; \$apply = getenv(\"F360_MODE\") === \"apply\";
  \$rows = \$wpdb->get_results(\$wpdb->prepare(\"SELECT post_id, meta_key FROM {\$wpdb->postmeta} WHERE meta_value LIKE %s\", \"%\" . \$wpdb->esc_like(\$from) . \"%\"));
  if (!\$rows) { echo \"sin referencias a staging\", PHP_EOL; exit(0); }
  \$walk = function (\$v) use (&\$walk, \$from, \$to) { if (is_array(\$v)) { foreach (\$v as \$k => \$x) \$v[\$k] = \$walk(\$x); return \$v; } return is_string(\$v) ? str_replace(\$from, \$to, \$v) : \$v; };
  foreach (\$rows as \$r) {
    \$val = get_post_meta(\$r->post_id, \$r->meta_key, true);
    \$n = substr_count(maybe_serialize(\$val), \$from);
    echo (\$apply ? \"aplicando\" : \"simulación\"), \": página \", \$r->post_id, \" (\", get_the_title(\$r->post_id), \") · \", \$r->meta_key, \" · \", \$n, \" referencia(s)\", PHP_EOL;
    if (!\$apply) continue;
    \$dir = getenv(\"HOME\") . \"/f360-backups\"; if (!is_dir(\$dir)) mkdir(\$dir, 0700, true);
    \$file = \$dir . \"/bricks-\" . \$r->post_id . \"-\" . \$r->meta_key . \"-\" . gmdate(\"Ymd\\THis\") . \".json\";
    file_put_contents(\$file, wp_json_encode([\"post_id\" => (int) \$r->post_id, \"meta_key\" => \$r->meta_key, \"value\" => \$val])); chmod(\$file, 0600);
    update_post_meta(\$r->post_id, \$r->meta_key, \$walk(\$val));
    \$left = substr_count(maybe_serialize(get_post_meta(\$r->post_id, \$r->meta_key, true)), \$from);
    echo \"  respaldo: \", \$file, \" · quedan \", \$left, PHP_EOL;
  }
'"
