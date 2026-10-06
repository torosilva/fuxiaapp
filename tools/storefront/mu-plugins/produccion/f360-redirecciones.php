<?php
/**
 * Fuxia 360 · redirecciones de productos viejos (PRODUCCIÓN, fuxiaballerinas.com). Mario 2026-10-06.
 * When Fuxia 360 puts a model's new product live, it marks each OLD product of that model with _f360_redirect_to = <new product id>
 * (and clears it when the new product is hidden again). Visiting an old product URL then 301-redirects to the new product,
 * but ONLY while the new product is published. Nothing else on the site is touched. Source: repo tools/storefront/mu-plugins/produccion/.
 */
if ( ! defined( 'ABSPATH' ) ) { exit; }
add_action( 'template_redirect', function () {
	$host = isset( $_SERVER['HTTP_HOST'] ) ? strtolower( (string) $_SERVER['HTTP_HOST'] ) : '';
	if ( 'fuxiaballerinas.com' !== $host && 'www.fuxiaballerinas.com' !== $host ) { return; }   // production only
	if ( ! is_singular( 'product' ) ) { return; }
	$to = (int) get_post_meta( get_queried_object_id(), '_f360_redirect_to', true );
	if ( $to <= 0 || $to === get_queried_object_id() || 'publish' !== get_post_status( $to ) ) { return; }
	$url = get_permalink( $to );
	if ( ! $url ) { return; }
	if ( ! empty( $_SERVER['QUERY_STRING'] ) ) { $url .= ( false === strpos( $url, '?' ) ? '?' : '&' ) . $_SERVER['QUERY_STRING']; }   // keep utm / campaign params
	wp_safe_redirect( $url, 301, 'Fuxia 360' );
	exit;
}, 1 );
