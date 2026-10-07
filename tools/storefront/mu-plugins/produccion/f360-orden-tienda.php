<?php
/**
 * Plugin Name: Fuxia 360 · orden de la tienda (producción)
 * Description: The shop page's default order is the one Fuxia 360 decides (Mario 2026-10-06): ⭐ destacados → most sold →
 *              newest, written by the publisher as each product's menu_order ("Orden en la tienda" → "Aplicar a la tienda").
 *              Only the DEFAULT changes: a customer who picks another order (price, etc.) still gets it.
 * Apagar: borrar este archivo de wp-content/mu-plugins/ (vuelve el orden anterior de WooCommerce).
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only
add_filter('woocommerce_default_catalog_orderby', function () { return 'menu_order'; }, 99);
