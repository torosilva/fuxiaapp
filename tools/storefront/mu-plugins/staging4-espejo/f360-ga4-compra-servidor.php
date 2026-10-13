<?php
// GENERADO por scripts/f360/build_staging4_mirror_mu.mjs desde tools/storefront/mu-plugins/produccion/f360-ga4-compra-servidor.php — no editar a mano.
/**
 * Plugin Name: Fuxia 360 · Compra a Analytics desde el servidor (producción)
 * Description: Cuando Woo confirma el pago, manda el `purchase` a GA4 por Measurement Protocol aunque la clienta nunca regrese a
 *              "pedido recibido" (ePayco, PayPal tarjeta, Mercado Pago que confirma después). Análisis y pruebas:
 *              docs/fuxia360/growth/ANALISIS_WEB_2026-06_A_2026-10.md §2 y docs/fuxia360/growth/GA4_COMPRA_SERVIDOR.md.
 * Reglas:
 *  · Solo pedidos PAGADOS: $order->is_paid() y estado processing/completed al momento de enviar. Nunca pending, on-hold, failed,
 *    cancelled ni refunded.
 *  · Sin duplicar con GTM4WP: si el navegador ya lo midió (`_ga_tracked` = 1) no se manda; al mandarlo se marca `_ga_tracked` = 1,
 *    la misma marca que GTM4WP revisa antes de empujar el purchase (ProductData::is_purchase_already_tracked). Una sola acción
 *    agendada por pedido; espera 2 minutos para darle primero la oportunidad al navegador.
 *  · Solo con el client_id de GA4 que la clienta ya tenía en su navegador (cookie `_ga`, capturada al crear el pedido). Sin él
 *    (bloqueó Analytics, link de pago creado por Fuxia 360) NO se manda nada: queda `_f360_ga4_mp` = "omitido: sin client_id".
 *    Si algún día se instala un banner de consentimiento, el filtro `f360_ga4_mp_permitido` lo respeta.
 *  · Nada personal: ni nombre, correo, teléfono, dirección, nota del pedido ni IP. Solo número de pedido, importes, moneda, cupón,
 *    productos (id, nombre, talla, categoría, precio, cantidad) y los ids seudónimos de GA4.
 *  · Mismo formato que GTM4WP: transaction_id = número de pedido, value = total del pedido, item_id = id del producto padre,
 *    item_variant = atributos de la variación, price = precio unitario con descuento.
 *  · Producción: valida primero con /debug/mp/collect y solo si Google no reporta errores manda a /mp/collect; requiere la opción
 *    `f360_ga4_mp_secret` (nunca en el repo ni en logs). Cualquier otro dominio (staging4) SOLO valida con /debug/mp/collect:
 *    Google no registra nada.
 *  · Errores: no se marca como enviado; hasta 3 intentos (ahora, +10 min, +1 h) con el mismo client_id; después queda
 *    `_f360_ga4_mp_error` y una nota en el pedido.
 * HPOS: solo usa la API de pedidos de Woo (get_meta/update_meta_data/save), compatible con HPOS y con tablas clásicas.
 * Apagar: borrar este archivo de wp-content/mu-plugins/. Las metas que deja no afectan a nada más.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'staging4.fuxiaballerinas.com') return;   // ESPEJO: solo staging4

define('F360_GA4_MID', 'G-8C1244627P');
define('F360_GA4_LIVE', $f360_host === 'fuxiaballerinas.com' || $f360_host === 'www.fuxiaballerinas.com');
define('F360_GA4_HOOK', 'f360_ga4_mp_compra');
define('F360_GA4_REINTENTOS', array(600, 3600));   // segundos hasta el 2º y 3er intento

// 1) Al crear el pedido (en el navegador de la clienta): guarda su client_id y session_id de GA4.
function f360_ga4_capturar_ids($order) {
  if (!$order instanceof WC_Order || $order->get_meta('_f360_ga_cid')) return;
  $ga = isset($_COOKIE['_ga']) ? sanitize_text_field(wp_unslash($_COOKIE['_ga'])) : '';
  if (!preg_match('/^GA\d\.\d+\.(\d+\.\d+)$/', $ga, $m)) return;
  $order->update_meta_data('_f360_ga_cid', $m[1]);
  $ck = '_ga_' . substr(F360_GA4_MID, 2);
  $gs = isset($_COOKIE[$ck]) ? sanitize_text_field(wp_unslash($_COOKIE[$ck])) : '';
  if (preg_match('/^GS1\.\d+\.(\d+)\./', $gs, $s) || preg_match('/^GS2\.\d+\.s(\d+)/', $gs, $s)) $order->update_meta_data('_f360_ga_sid', $s[1]);
  if ($order->get_id()) $order->save_meta_data();
}
add_action('woocommerce_store_api_checkout_update_order_meta', 'f360_ga4_capturar_ids');   // checkout de bloques
add_action('woocommerce_checkout_create_order', 'f360_ga4_capturar_ids');                   // checkout clásico

// 2) Al pagarse (cualquier pasarela, webhook repetido o cambio de estado): agenda UNA acción por pedido.
function f360_ga4_agendar($order_id) {
  $order = wc_get_order($order_id);
  if (!$order || !$order->is_paid() || 1 === (int) $order->get_meta('_ga_tracked') || $order->get_meta('_f360_ga4_mp')) return;
  if (!function_exists('as_schedule_single_action')) return;
  $args = array('order_id' => (int) $order->get_id());
  if (as_has_scheduled_action(F360_GA4_HOOK, $args, 'f360')) return;
  as_schedule_single_action(time() + 120, F360_GA4_HOOK, $args, 'f360');
}
add_action('woocommerce_payment_complete', 'f360_ga4_agendar');
add_action('woocommerce_order_status_processing', 'f360_ga4_agendar');
add_action('woocommerce_order_status_completed', 'f360_ga4_agendar');

// 3) Lo que se manda. Solo campos de la lista de arriba; nada de billing/shipping/cliente.
function f360_ga4_payload($order) {
  $items = array();
  foreach ($order->get_items() as $item) {
    $qty = max(1, (int) $item->get_quantity());
    $pid = (int) $item->get_product_id();
    $line = array(
      'item_id' => (string) $pid,
      'item_name' => $pid ? get_the_title($pid) : $item->get_name(),
      'price' => round((float) $item->get_total() / $qty, 2),
      'quantity' => $qty,
    );
    $var = $item->get_variation_id() ? wc_get_product($item->get_variation_id()) : null;
    if ($var && method_exists($var, 'get_variation_attributes')) $line['item_variant'] = implode(',', $var->get_variation_attributes());
    $cats = $pid ? wp_get_post_terms($pid, 'product_cat', array('fields' => 'names')) : array();
    if (!is_wp_error($cats) && $cats) $line['item_category'] = $cats[0];
    $items[] = $line;
  }
  $params = array(
    'transaction_id' => (string) $order->get_order_number(),
    'value' => round((float) $order->get_total(), 2),
    'currency' => $order->get_currency(),
    'tax' => round((float) $order->get_total_tax(), 2),
    'shipping' => round((float) $order->get_shipping_total(), 2),
    'items' => $items,
    'engagement_time_msec' => 1,
  );
  if ($codes = $order->get_coupon_codes()) $params['coupon'] = implode(',', $codes);
  if ($sid = $order->get_meta('_f360_ga_sid')) $params['session_id'] = (string) $sid;
  $body = array('client_id' => (string) $order->get_meta('_f360_ga_cid'), 'events' => array(array('name' => 'purchase', 'params' => $params)));
  $paid = $order->get_date_paid();
  // GA4 acepta eventos de hasta 72 h; dentro de esa ventana se fecha a la hora real del pago.
  if ($paid && (time() - $paid->getTimestamp()) < 71 * 3600) $body['timestamp_micros'] = (string) ($paid->getTimestamp() * 1000000);
  return $body;
}

function f360_ga4_post($endpoint, $secret, $body) {
  $url = add_query_arg(array('measurement_id' => F360_GA4_MID, 'api_secret' => $secret), $endpoint);
  $r = wp_remote_post($url, array('timeout' => 10, 'headers' => array('Content-Type' => 'application/json'), 'body' => wp_json_encode($body)));
  $code = is_wp_error($r) ? 0 : (int) wp_remote_retrieve_response_code($r);
  // el mensaje de error nunca lleva el secreto (va en la URL)
  $err = is_wp_error($r) ? str_replace($secret, '***', $r->get_error_code()) : '';
  return array($code, is_wp_error($r) ? '' : (string) wp_remote_retrieve_body($r), $err);
}

function f360_ga4_fallo($order, $intento, $motivo) {
  error_log('[f360-ga4] pedido ' . $order->get_id() . ' intento ' . $intento . ': ' . $motivo);
  $esperas = F360_GA4_REINTENTOS;
  if ($intento <= count($esperas)) {
    as_schedule_single_action(time() + $esperas[$intento - 1], F360_GA4_HOOK, array('order_id' => (int) $order->get_id()), 'f360');
    return;
  }
  $order->update_meta_data('_f360_ga4_mp_error', $motivo . ' · ' . gmdate('c'));
  $order->add_order_note('Fuxia 360: no se pudo mandar la compra a Google Analytics tras ' . $intento . ' intentos (' . $motivo . ').');
  $order->save();
}

// 4) Envío (Action Scheduler). Vuelve a revisar todo: el pedido pudo cambiar en los 2 minutos.
add_action(F360_GA4_HOOK, function ($order_id) {
  $order = wc_get_order((int) $order_id);
  if (!$order || !$order->is_paid() || !$order->has_status(array('processing', 'completed'))) return;
  if (1 === (int) $order->get_meta('_ga_tracked') || $order->get_meta('_f360_ga4_mp')) return;
  if (!$order->get_meta('_f360_ga_cid') || !apply_filters('f360_ga4_mp_permitido', true, $order)) {
    $order->update_meta_data('_f360_ga4_mp', 'omitido: sin client_id o sin permiso · ' . gmdate('c'));
    $order->save();
    return;
  }
  $intento = (int) $order->get_meta('_f360_ga4_intentos') + 1;
  $order->update_meta_data('_f360_ga4_intentos', $intento);
  $order->save();
  $secret = F360_GA4_LIVE ? (string) get_option('f360_ga4_mp_secret', '') : 'staging-solo-validacion';
  if ($secret === '') { error_log('[f360-ga4] falta f360_ga4_mp_secret; pedido ' . $order->get_id() . ' sin mandar'); return; }
  $body = f360_ga4_payload($order);
  list($code, $resp, $err) = f360_ga4_post('https://www.google-analytics.com/debug/mp/collect', $secret, $body);
  $val = json_decode($resp, true);
  if ($code !== 200 || !is_array($val) || !array_key_exists('validationMessages', $val)) { f360_ga4_fallo($order, $intento, 'validación http ' . $code . ($err ? ' ' . $err : '')); return; }
  if (!empty($val['validationMessages'])) { f360_ga4_fallo($order, $intento, 'Google rechazó el formato: ' . wp_json_encode($val['validationMessages'])); return; }
  if (F360_GA4_LIVE) {
    list($code, , $err) = f360_ga4_post('https://www.google-analytics.com/mp/collect', $secret, $body);
    if ($code < 200 || $code >= 300) { f360_ga4_fallo($order, $intento, 'envío http ' . $code . ($err ? ' ' . $err : '')); return; }
  }
  $order->update_meta_data('_ga_tracked', 1);   // GTM4WP ya no lo repite si la clienta abre después "pedido recibido"
  $order->update_meta_data('_f360_ga4_mp', (F360_GA4_LIVE ? 'enviado ' : 'validado (staging, nada registrado) ') . gmdate('c'));
  $order->add_order_note(F360_GA4_LIVE ? 'Fuxia 360: compra enviada a Google Analytics desde el servidor.' : 'Fuxia 360 (staging): compra validada con GA4 debug; nada registrado.');
  $order->save();
});
