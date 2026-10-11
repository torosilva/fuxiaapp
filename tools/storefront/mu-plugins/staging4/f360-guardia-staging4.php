<?php
/**
 * Plugin Name: F360 · Guardia de staging4
 * Description: Red de seguridad de staging4, que es una copia nocturna de producción (docs/fuxia360/ops/STAGING_REFRESH.md).
 *   1) Ningún correo sale a nadie: wp_mail se corta y queda en el registro de PHP (solo destinatario y asunto).
 *   2) Ninguna llamada HTTP del servidor llega a producción ni a cuentas reales: Supabase de prod, la tienda real,
 *      Meta (Graph API) y Google Merchant Center.
 *   3) Si el sitio no es staging4, el plugin no hace nada (no debe vivir en producción).
 * Version: 1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

$f360_guard_host = strtolower( (string) wp_parse_url( get_option( 'home' ), PHP_URL_HOST ) );
if ( 'staging4.fuxiaballerinas.com' !== $f360_guard_host ) {
	return;
}

// 1) Correo: nunca sale.
add_filter(
	'pre_wp_mail',
	static function ( $short, $atts ) {
		$to = is_array( $atts['to'] ?? null ) ? implode( ',', $atts['to'] ) : (string) ( $atts['to'] ?? '' );
		error_log( '[f360-guardia-staging4] correo bloqueado → ' . $to . ' · ' . (string) ( $atts['subject'] ?? '' ) );
		return true; // "enviado" para WordPress, sin salir del servidor.
	},
	1,
	2
);

// 2) HTTP saliente hacia producción o cuentas reales: bloqueado.
add_filter(
	'pre_http_request',
	static function ( $pre, $args, $url ) {
		$host = strtolower( (string) wp_parse_url( $url, PHP_URL_HOST ) );
		$blocked = array(
			'tgzgiwfzddsghnxgkcqd.supabase.co',   // Supabase de producción.
			'fuxiaballerinas.com',                // Tienda real.
			'www.fuxiaballerinas.com',
			'nuevo.fuxiaballerinas.com',
			'graph.facebook.com',                 // Catálogo / píxel de Meta.
			'shoppingcontent.googleapis.com',     // Google Merchant Center.
			'merchantapi.googleapis.com',
		);
		if ( in_array( $host, $blocked, true ) ) {
			error_log( '[f360-guardia-staging4] HTTP bloqueado → ' . $host );
			return new WP_Error( 'f360_staging_guard', 'staging4 no puede llamar a ' . $host );
		}
		return $pre;
	},
	1,
	3
);
