#!/usr/bin/env bash
# Fuxia 360 · fuxiaballerinas.com footer: "Cambios y devoluciones" (link "#") → "Cambios" (link /cambios/).
# Mario 2026-10-08: "en ningún lado diga que hay devoluciones" (política de Carolina 2026-10-03: solo cambios).
# Bricks template "Footer" (post 38, meta _bricks_page_footer_2). Backs the meta up first (~/f360-backups on the server),
# changes exactly one occurrence or aborts, then purges the SiteGround cache.
# Rollback: wp post meta update 38 _bricks_page_footer_2 --format=json < ~/f360-backups/footer38_<fecha>.json && wp sg purge
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
"${SSH[@]}" 'cd ~/www/fuxiaballerinas.com/public_html \
  && test "$(wp option get home)" = "https://fuxiaballerinas.com" \
  && mkdir -p ~/f360-backups \
  && B=~/f360-backups/footer38_$(date +%Y%m%d%H%M%S).json \
  && wp post meta get 38 _bricks_page_footer_2 --format=json > "$B" && echo "Respaldo: $B" \
  && wp eval '"'"'
$k = "_bricks_page_footer_2"; $s = get_post_meta(38, $k, true);
$from = "<a href=\"#\" title=\"Página pendiente de crear\">Cambios y devoluciones</a>"; $to = "<a href=\"/cambios/\">Cambios</a>";
$n = 0;
$walk = function ($v) use (&$walk, $from, $to, &$n) {
  if (is_array($v)) { foreach ($v as $i => $x) { $v[$i] = $walk($x); } return $v; }
  if (is_string($v) && strpos($v, $from) !== false) { $n += substr_count($v, $from); return str_replace($from, $to, $v); }
  return $v;
};
$new = $walk($s);
if ($n !== 1) { echo "ABORT: encontrado $n veces (se esperaba 1); no se cambió nada", PHP_EOL; exit(1); }
update_post_meta(38, $k, wp_slash($new)); wp_cache_delete(38, "post_meta");
// Bricks protects Code elements: saved outside its editor by someone without code permission, the old code is put back
// silently (2026-10-08 18:53 this script said "cambiado" and nothing changed). Read it back before claiming success.
if (strpos(wp_json_encode(get_post_meta(38, $k, true)), "devoluciones") !== false) {
  echo "NO SE GUARDÓ: Bricks regresó el bloque de código. Cámbialo en wp-admin → Bricks → Plantillas → Footer → Editar con Bricks.", PHP_EOL; exit(1);
}
echo "Menú cambiado: Cambios y devoluciones → Cambios (/cambios/)", PHP_EOL;
'"'"' \
  && wp sg purge'
echo "Comprobación pública:"
curl -s https://fuxiaballerinas.com/ | grep -o '<a href="[^"]*">Cambios[^<]*</a>' | head -2
