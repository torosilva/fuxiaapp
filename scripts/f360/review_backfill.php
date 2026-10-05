<?php
/**
 * Fuxia 360 · CRO-3B1 — sync existing CusRev reviews to Fuxia 360 and print the verification report.
 * Runs ON the WordPress server (WP-CLI), never in a browser:
 *   F360_KEY=<server key from stdin> F360_URL=<edge function url> wp eval-file review_backfill.php [--dry-run]
 * Sends per review ONLY: ids, stars, moderation state, media count, date, and the claims Fuxia 360 needs to verify:
 *   - woo_user_id (registered account), sha256(lowercase e-mail) and the ids of the reviewer's PAID orders containing the product.
 * Never sends or prints the review text, the author's name, e-mail or phone. Fuxia 360 decides the verification from its
 * own facts (Commerce Facts, store sales); nothing here marks a review as verified. Nothing is written to WordPress.
 * Safe to re-run (idempotent; a verified review stays verified).
 */
if ( ! defined( 'WP_CLI' ) ) { exit; }
$dry = in_array( '--dry-run', $GLOBALS['argv'] ?? [], true ) || getenv( 'F360_DRY_RUN' ) === '1';
$url = getenv( 'F360_URL' );
$key = getenv( 'F360_KEY' );
if ( ! $dry && ( ! $url || ! $key || strlen( $key ) < 24 ) ) { WP_CLI::error( 'F360_URL / F360_KEY no configurados.' ); }
if ( strpos( home_url(), 'staging4.' ) === false && getenv( 'F360_ALLOW_HOST' ) !== wp_parse_url( home_url(), PHP_URL_HOST ) ) {
	WP_CLI::error( 'Solo staging4 (para otro sitio: F360_ALLOW_HOST=<host> explícito).' );
}

$status_map = [ 'approved' => 'approved', 'unapproved' => 'hold', 'spam' => 'spam', 'trash' => 'trash' ];
$reviews = get_comments( [ 'type' => 'review', 'status' => 'all', 'number' => 0, 'orderby' => 'comment_ID', 'order' => 'ASC' ] );
$spam = get_comments( [ 'type' => 'review', 'status' => 'spam', 'number' => 0 ] );
$trash = get_comments( [ 'type' => 'review', 'status' => 'trash', 'number' => 0 ] );
$all = [];
foreach ( array_merge( $reviews, $spam, $trash ) as $c ) { $all[ $c->comment_ID ] = $c; }
ksort( $all );

$rows = [];
foreach ( $all as $c ) {
	$pid = (int) $c->comment_post_ID;
	$email = strtolower( trim( (string) $c->comment_author_email ) );
	$order_ids = [];
	if ( $email || $c->user_id ) {
		$args = [ 'limit' => 50, 'status' => [ 'wc-processing', 'wc-completed', 'wc-refunded' ], 'return' => 'objects' ];
		$found = [];
		if ( $email ) { $found = array_merge( $found, wc_get_orders( $args + [ 'billing_email' => $email ] ) ); }
		if ( $c->user_id ) { $found = array_merge( $found, wc_get_orders( $args + [ 'customer_id' => (int) $c->user_id ] ) ); }
		foreach ( $found as $o ) {
			foreach ( $o->get_items() as $it ) {
				if ( (int) $it->get_product_id() === $pid ) { $order_ids[ $o->get_id() ] = true; }
			}
		}
	}
	$review = [
		'woo_review_id' => (int) $c->comment_ID,
		'woo_product_id' => $pid,
		'rating' => (int) get_comment_meta( $c->comment_ID, 'rating', true ),
		'status' => $status_map[ wp_get_comment_status( $c ) ] ?? 'hold',
		'media_count' => (int) get_comment_meta( $c->comment_ID, 'ivole_media_count', true ),
		'woo_verified' => (bool) get_comment_meta( $c->comment_ID, 'verified', true ),
		'reviewed_at' => mysql2date( 'c', $c->comment_date_gmt ?: get_gmt_from_date( $c->comment_date ), false ),
		'claims' => [
			'woo_user_id' => (int) $c->user_id ?: null,
			'email_sha256' => $email ? hash( 'sha256', $email ) : null,
			'woo_order_ids' => array_map( 'intval', array_keys( $order_ids ) ),
		],
	];
	$res = [ 'verification' => 'DRY_RUN' ];
	if ( $review['rating'] < 1 ) { $res = [ 'verification' => 'SKIPPED', 'detail' => [ 'reason' => 'sin_calificacion' ] ]; }
	elseif ( ! $dry ) {
		$r = wp_remote_post( $url, [ 'timeout' => 20, 'headers' => [ 'Content-Type' => 'application/json', 'x-f360-key' => $key ],
			'body' => wp_json_encode( [ 'action' => 'review_sync', 'review' => $review ] ) ] );
		$res = is_wp_error( $r ) ? [ 'verification' => 'ERROR', 'error' => $r->get_error_message() ] : json_decode( wp_remote_retrieve_body( $r ), true );
	}
	$rows[] = [
		'review' => $review['woo_review_id'], 'woo_product' => $pid, 'producto' => html_entity_decode( get_the_title( $pid ) ),
		'fecha' => substr( $review['reviewed_at'], 0, 10 ), 'estado' => $review['status'], 'estrellas' => $review['rating'],
		'media' => $review['media_count'], 'woo_verificada' => $review['woo_verified'] ? 'sí' : 'no',
		'cuenta' => $review['claims']['woo_user_id'] ? 'sí' : 'no', 'pedidos_pagados_wp' => count( $review['claims']['woo_order_ids'] ),
		'modelo_f360' => $res['product_key'] ?? '—', 'f360' => $res['verification'] ?? ( $res['error'] ?? '?' ),
		'motivo' => $res['detail']['reason'] ?? ( $res['detail']['identity'] ?? ( $res['error'] ?? '' ) ),
	];
}
WP_CLI\Utils\format_items( 'table', $rows, array_keys( $rows[0] ?? [ 'review' => 1 ] ) );
$by = array_count_values( array_column( $rows, 'f360' ) );
WP_CLI::log( 'Resumen F360: ' . wp_json_encode( $by ) );
