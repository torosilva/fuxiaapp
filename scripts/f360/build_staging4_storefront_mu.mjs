// Fuxia 360 · builds the STAGING4 store mu-plugin for ♡ Favoritos V1 from the single snippet sources (tools/storefront/):
//   · f360-favoritos.html in every page footer (after Club Fuxia, before the account icon);
//   · the shop search (f360-tienda.html) swapped in place of the copy pasted in Bricks, so the carousels carry the product id.
// The snippets already point at the STAGING service (faltx). Output: tools/storefront/mu-plugins/staging4/f360-favoritos-staging4.php
// (commit it; scripts/f360/deploy_staging4_wp.sh installs it). Production gets its own build later, only with approval.
import { readFileSync, writeFileSync } from 'node:fs';
const fav = readFileSync('tools/storefront/f360-favoritos.html', 'utf8');
let tienda = readFileSync('tools/storefront/f360-tienda.html', 'utf8').replace(/^<!--[\s\S]*?-->\s*/, '');
for (const [n, h] of [['favoritos', fav], ['tienda', tienda]]) {
  if (/tgzgiwfzddsghnxgkcqd/.test(h)) throw new Error(`${n}: apunta a PRODUCCIÓN; staging4 solo usa staging.`);
  if (h.includes('F360SNIP')) throw new Error(`${n}: contiene el delimitador.`);
}
if (!tienda.startsWith('<div class="f360-tienda">')) throw new Error('f360-tienda.html debe empezar con <div class="f360-tienda">.');
const php = `<?php
/**
 * Plugin Name: Fuxia 360 · Favoritos V1 (STAGING4)
 * Description: ♡ en tarjetas, carruseles, ficha y header + "Mis favoritos"; captura anónima en Fuxia 360 (staging).
 *              GENERADO por scripts/f360/build_staging4_storefront_mu.mjs — no editar a mano.
 * Apagar: borrar este archivo de wp-content/mu-plugins/ en staging4.
 */
if (!defined('ABSPATH')) exit;
if (strpos((string) wp_parse_url(home_url(), PHP_URL_HOST), 'staging4.') !== 0) return;   // staging4 only, never production
add_action('wp_footer', function () {
  if (is_admin() || isset($_GET['bricks'])) return;
  echo <<<'F360SNIP'
${fav.trimEnd()}
F360SNIP;
  echo "\\n";
}, 30);
// the shop search pasted in Bricks → the repo's version (carousel cards carry data-f360-product-id for the ♡)
add_action('template_redirect', function () {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST) || isset($_GET['bricks'])) return;
  if (!function_exists('is_shop') || !(is_shop() || is_product_taxonomy())) return;
  ob_start(function ($page) {
    $start = strpos($page, '<div class="f360-tienda">');
    if ($start === false) return $page;
    $mark = strpos($page, 'filtros de la Tienda', $start);
    $end = $mark === false ? false : strpos($page, '</script>', $mark);
    if ($end === false) return $page;
    $c = strrpos(substr($page, 0, $start), '<!--');
    if ($c !== false && strpos(substr($page, $c, $start - $c), 'Fuxia 360 · Página de TIENDA') !== false) $start = $c;
    return substr($page, 0, $start) . <<<'F360SNIP'
${tienda.trimEnd()}
F360SNIP
      . substr($page, $end + strlen('</script>'));
  });
}, 1);
`;
writeFileSync('tools/storefront/mu-plugins/staging4/f360-favoritos-staging4.php', php);
console.log(`escrito f360-favoritos-staging4.php (${php.length} bytes)`);
