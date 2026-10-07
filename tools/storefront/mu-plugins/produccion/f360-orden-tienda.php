<?php
/**
 * Plugin Name: Fuxia 360 · orden de la tienda (producción)
 * Description: The shop page's default order is the one Fuxia 360 decides (Mario 2026-10-06): ⭐ destacados → most sold →
 *              newest, written by the publisher as each product's menu_order ("Orden en la tienda" → "Aplicar a la tienda").
 *              Only the DEFAULT changes (no ?orderby in the URL): a customer who picks another order still gets it. Until
 *              Fuxia 360 has applied an order (every menu_order still 0) nothing changes.
 *              Bricks' products element passes its own order (date) instead of WooCommerce's default, so the catalog ordering
 *              args are replaced as well — on shop / category pages only.
 * Apagar: borrar este archivo de wp-content/mu-plugins/ (vuelve el orden anterior).
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only

if (!function_exists('f360_orden_aplicado')) {
  /** true once Fuxia 360 wrote positions (some published product has menu_order > 0). Cached 10 minutes. */
  function f360_orden_aplicado() {
    $v = get_transient('f360_orden_aplicado');
    if ($v === false) {
      global $wpdb;
      $v = (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type = 'product' AND post_status = 'publish' AND menu_order > 0") > 0 ? 'si' : 'no';
      set_transient('f360_orden_aplicado', $v, 10 * MINUTE_IN_SECONDS);
    }
    return $v === 'si';
  }
}
add_filter('woocommerce_default_catalog_orderby', function ($o) { return f360_orden_aplicado() ? 'menu_order' : $o; }, 99);
add_filter('woocommerce_get_catalog_ordering_args', function ($args) {
  if (isset($_GET['orderby']) || is_admin() || !f360_orden_aplicado()) return $args;
  if (!(function_exists('is_shop') && (is_shop() || is_product_taxonomy()))) return $args;
  $args['orderby'] = 'menu_order title';
  $args['order'] = 'ASC';
  $args['meta_key'] = '';
  return $args;
}, 99);
