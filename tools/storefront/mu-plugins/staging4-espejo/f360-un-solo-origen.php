<?php
// GENERADO por scripts/f360/build_staging4_mirror_mu.mjs desde tools/storefront/mu-plugins/produccion/f360-un-solo-origen.php — no editar a mano.
/**
 * Plugin Name: Fuxia 360 · un solo origen (producción)
 * Description: Any Fuxia 360 snippet copied from staging4 into this site (Bricks Code elements, WPCode) still calls the
 *              STAGING service, which refuses this domain — e.g. the /tienda/ search box hid itself (Mario 2026-10-06).
 *              On the production store the page output is rewritten so those calls go to PRODUCTION's f360-store-reserve.
 *              Only that exact URL is replaced; nothing else in the page changes. Fix at the source when convenient
 *              (Bricks → Tienda → Code element), then this file can go.
 * Apagar: borrar este archivo de wp-content/mu-plugins/.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'staging4.fuxiaballerinas.com') return;   // ESPEJO: solo staging4
add_action('template_redirect', function () {
  if (is_admin() || wp_doing_ajax() || (defined('REST_REQUEST') && REST_REQUEST) || isset($_GET['bricks'])) return;   // never the Bricks editor
  ob_start(function ($html) {
    return str_replace('https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-store-reserve',
                       'https://faltxpkaicwpnlqaxrdu.supabase.co/functions/v1/f360-store-reserve', $html);
  });
}, 0);
