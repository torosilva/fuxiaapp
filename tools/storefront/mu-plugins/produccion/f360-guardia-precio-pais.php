<?php
/**
 * Plugin Name: Fuxia 360 · guardia de precio por país (producción)
 * Description: INCIDENTE 2026-10-06 (prueba de Instagram): en /co/ los productos publicados desde Fuxia 360 sin precio en COP
 *              mostraban y COBRABAN el número de México con etiqueta COP (COP$3,000 en vez de ~COP$450,000). El tema
 *              (bricks-child → fuxia_variation_precios_pais) usa la meta _price_cop / _price_usd de cada variación y, si falta,
 *              deja el precio base (MXN). Esta guardia: en CO / US, una variación SIN precio de ese país NO se puede comprar
 *              (Woo la quita también de carritos ya hechos) y su precio dice "Consultar precio". México no se toca; los
 *              productos con precio del país tampoco. Se apaga sola en cuanto cada producto tiene su precio.
 * Apagar: borrar este archivo de wp-content/mu-plugins/ (¡solo cuando todos los productos tengan precio COP/USD!).
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only

if (!function_exists('f360_guardia_meta_pais')) {
  /** '_price_cop' / '_price_usd' for the visitor's country, or null (Mexico / unknown → base price is right). */
  function f360_guardia_meta_pais() {
    if (is_admin() && !wp_doing_ajax()) return null;
    if (!function_exists('fuxia_get_selected_country')) return null;
    $c = fuxia_get_selected_country();
    return $c === 'CO' ? '_price_cop' : ($c === 'US' ? '_price_usd' : null);
  }
  function f360_guardia_sin_precio($variation_id) {
    $key = f360_guardia_meta_pais(); if (!$key) return false;
    $v = get_post_meta($variation_id, $key, true);
    return $v === '' || $v === false || floatval($v) <= 0;
  }
}
add_filter('woocommerce_variation_is_purchasable', function ($ok, $variation) {
  return ($ok && f360_guardia_sin_precio($variation->get_id())) ? false : $ok;
}, 999, 2);
add_filter('woocommerce_is_purchasable', function ($ok, $product) {
  if (!$ok || !$product) return $ok;
  if ($product->is_type('variation')) return f360_guardia_sin_precio($product->get_id()) ? false : $ok;
  if ($product->is_type('variable') && f360_guardia_meta_pais()) {
    foreach ($product->get_children() as $vid) if (!f360_guardia_sin_precio($vid)) return $ok;   // at least one size has its price
    return false;
  }
  return $ok;
}, 999, 2);
add_filter('woocommerce_get_price_html', function ($html, $product) {
  if (!$product || !f360_guardia_meta_pais()) return $html;
  $ids = $product->is_type('variable') ? $product->get_children() : array($product->get_id());
  foreach ($ids as $id) if (!f360_guardia_sin_precio($id)) return $html;
  return '<span class="f360-consultar-precio">Consultar precio</span>';
}, 1000, 2);
