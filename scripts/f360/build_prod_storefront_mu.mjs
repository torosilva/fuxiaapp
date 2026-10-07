// Fuxia 360 · builds the PRODUCTION store mu-plugins from the single snippet sources in tools/storefront/ (no copies to keep in sync).
// The only change to each snippet: the Fuxia 360 endpoint becomes production's f360-store-reserve; "STAGING" labels go.
// Output in tools/storefront/mu-plugins/produccion/ (commit them; scripts/f360/deploy_prod_wp.sh installs them). Each file is its
// own off switch: delete it from wp-content/mu-plugins/ and that piece is gone.
import { readFileSync, writeFileSync } from 'node:fs';
const STAGING_URL = 'https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-store-reserve';
const PROD_URL = 'https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-store-reserve';
const PIECES = [
  { src: 'tools/storefront/f360-hilo-global.html', out: 'f360-hilo.php', title: 'Fuxia 360 · Hilo (producción)',
    what: 'Botón "Hilo" en todo el sitio (asesora HiloLabs + WhatsApp + casos a la Bandeja de Fuxia 360). Reemplaza a Joinchat.',
    head: [
      "// Hilo replaces Joinchat (one button bottom-right).",
      "add_filter('joinchat_show', '__return_false', 99);",
      "// SiteGround \"AI Studio\" floating button (shown to admins only, no API key): hidden so it doesn't overlap Hilo.",
      "add_action('wp_head', function () { echo \"<style>#wp-ai-studio-container{display:none!important}</style>\\n\"; }, 99);",
    ] },
  { src: 'tools/storefront/f360-compra.html', out: 'f360-compra.php', title: 'Fuxia 360 · Compra (producción)',
    what: '"✓ Agregado" + checkout Fuxia + link de pago (pedido pendiente en Woo → página de pago de Woo) + "Pedido recibido" con el estado REAL del pago.',
    head: [
      "// \"Pedido recibido\": the order's REAL payment state for the thank-you copy (the snippet never claims a payment by itself).",
      "// Printed in <head> so it exists before the footer snippet runs. Order key checked; no personal data.",
      "add_action('wp_head', function () {",
      "  if (!function_exists('is_order_received_page') || !is_order_received_page()) return;",
      "  $order_id = absint(get_query_var('order-received'));",
      "  $order = $order_id ? wc_get_order($order_id) : null;",
      "  $key = isset($_GET['key']) ? wc_clean(wp_unslash($_GET['key'])) : '';",
      "  if (!$order || !hash_equals((string) $order->get_order_key(), (string) $key)) return;",
      "  $state = $order->has_status('failed') ? 'failed' : ($order->is_paid() ? 'paid' : 'pending');",
      "  echo '<script>window.F360_ORDER_STATE = ' . wp_json_encode($state) . ';</script>';",
      "}, 1);",
    ] },
];
// The shop search / filters (tools/storefront/f360-tienda.html) was pasted into a Bricks Code element on /tienda/ (copied from
// staging4). Instead of editing Bricks by hand, the production plugin swaps that pasted copy for the repo's current version
// on the fly, so this file is the only source. If the pasted copy is not found, the page is left untouched.
{
  const src = 'tools/storefront/f360-tienda.html';
  let html = readFileSync(src, 'utf8');
  if (!html.includes(STAGING_URL)) throw new Error(`${src}: no encontré el endpoint de staging; revisa la fuente.`);
  html = html.split(STAGING_URL).join(PROD_URL).replace(/\/\/ STAGING\b/g, '// PRODUCCIÓN').replace(/\. STAGING\./g, '. PRODUCCIÓN.')
    .replace(/^\s*STAGING: servicio de staging\.\s*$/m, '  PRODUCCIÓN: lo pone scripts/f360/build_prod_storefront_mu.mjs (f360-tienda.php).');
  html = html.replace(/^<!--[\s\S]*?-->\s*/, '');                 // the page gets the code, not the install notes
  if (/faltxpkaicwpnlqaxrdu/.test(html) || html.includes('F360SNIP')) throw new Error(`${src}: todavía apunta a staging o contiene el delimitador.`);
  if (!html.startsWith('<div class="f360-tienda">')) throw new Error(`${src}: debe empezar con <div class="f360-tienda">.`);
  const php = `<?php
/**
 * Plugin Name: Fuxia 360 · buscador de la Tienda (producción)
 * Description: Swaps the copy of the shop search / filters pasted in Bricks (/tienda/) for the repo's current version.
 *              GENERADO por scripts/f360/build_prod_storefront_mu.mjs desde ${src} — no editar a mano.
 * Apagar: borrar este archivo de wp-content/mu-plugins/ (queda la copia pegada en Bricks).
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only
add_action('template_redirect', function () {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST) || isset($_GET['bricks'])) return;   // never the Bricks editor
  if (!function_exists('is_shop') || !(is_shop() || is_product_taxonomy())) return;
  ob_start(function ($page) {
    $start = strpos($page, '<div class="f360-tienda">');
    if ($start === false) return $page;
    $mark = strpos($page, 'filtros de la Tienda', $start);
    $end = $mark === false ? false : strpos($page, '</script>', $mark);
    if ($end === false) return $page;
    // the pasted install notes (an HTML comment right before the block) go too
    $c = strrpos(substr($page, 0, $start), '<!--');
    if ($c !== false && strpos(substr($page, $c, $start - $c), 'Fuxia 360 · Página de TIENDA') !== false) $start = $c;
    return substr($page, 0, $start) . <<<'F360SNIP'
${html.trimEnd()}
F360SNIP
      . substr($page, $end + strlen('</script>'));
  });
}, 1);
`;
  writeFileSync('tools/storefront/mu-plugins/produccion/f360-tienda.php', php);
  console.log(`escrito f360-tienda.php (${php.length} bytes)`);
}
for (const p of PIECES) {
  let html = readFileSync(p.src, 'utf8');
  if (!html.includes(STAGING_URL)) throw new Error(`${p.src}: no encontré el endpoint de staging; revisa la fuente.`);
  html = html.split(STAGING_URL).join(PROD_URL).replace(/\/\/ STAGING\b/g, '// PRODUCCIÓN').replace(/\. STAGING\./g, '. PRODUCCIÓN.')
    .replace(/^\s*STAGING: endpoint de staging\..*$/m, '  PRODUCCIÓN: generado por scripts/f360/build_prod_storefront_mu.mjs.');
  if (/faltxpkaicwpnlqaxrdu/.test(html)) throw new Error(`${p.src}: todavía apunta a staging.`);
  if (html.includes('F360SNIP')) throw new Error(`${p.src}: contiene el delimitador.`);
  const php = `<?php
/**
 * Plugin Name: ${p.title}
 * Description: ${p.what}
 *              GENERADO por scripts/f360/build_prod_storefront_mu.mjs desde ${p.src} — no editar a mano.
 * Apagar: borrar este archivo de wp-content/mu-plugins/.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only
${p.head.join('\n')}
add_action('wp_footer', function () {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST)) return;
  echo <<<'F360SNIP'
${html.trimEnd()}
F360SNIP;
  echo "\\n";
}, 99);
`;
  writeFileSync(`tools/storefront/mu-plugins/produccion/${p.out}`, php);
  console.log(`escrito ${p.out} (${php.length} bytes)`);
}
