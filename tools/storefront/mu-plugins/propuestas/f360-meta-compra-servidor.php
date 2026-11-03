<?php
/**
 * Plugin Name: Fuxia 360 · Compra a Meta desde el servidor (Conversions API)
 * Description: El único Purchase que recibe el pixel 951926154215387 sale de aquí, desde el servidor, cuando el pedido queda
 *              PAGADO (Procesando o Completado), aunque ePayco o Mercado Pago confirmen minutos después por webhook.
 *              Por qué y pruebas: docs/fuxia360/growth/META_COMPRA_SERVIDOR.md.
 * Reglas:
 *  · Meta for WooCommerce deja de mandar Purchase. Tanto el de navegador como su CAPI salían al CREAR el pedido (estados
 *    válidos del plugin: processing, completed, on-hold y pending), así que contaba pedidos que nunca se pagaron. Se quitan
 *    sus 4 enganches de inject_purchase_event. El resto del plugin (PageView, ViewContent, AddToCart, InitiateCheckout,
 *    catálogo) sigue igual.
 *  · La etiqueta de Meta en GTM-W2PZG3L5 deja de escuchar el evento `purchase`. Ese cambio va en el contenedor (versión
 *    nueva), no aquí, porque comparte el evento con la etiqueta de GA4. El paso está en el documento.
 *  · Solo pedidos PAGADOS: $order->is_paid() y estado processing/completed, revisado de nuevo justo antes de enviar.
 *    Nunca pending, on-hold, failed, cancelled ni refunded.
 *  · Una sola vez por pedido: una acción agendada por pedido (única en Action Scheduler) y la marca `_f360_meta_capi`.
 *    event_id = número de pedido.
 *  · Contexto de la clienta (`_f360_meta_ctx`): _fbp, _fbc, IP, user agent y URL. Se guarda desde SU navegador al crear el
 *    pedido en el checkout. Si después paga un link de pago (order-pay), se reemplaza por el del navegador que paga.
 *  · Datos personales: solo en hash SHA-256 normalizado (correo, teléfono con lada, nombre, apellido, ciudad, estado, CP,
 *    país, id de clienta registrada). Nunca en texto, nunca en logs.
 *  · Producción manda en vivo. Cualquier otro dominio (staging4) SOLO manda con `test_event_code` (opción
 *    `f360_meta_capi_test_code`); sin código no manda nada. En "Probar eventos" se ve, y no cuenta en los informes.
 *  · Token: opción `f360_meta_capi_token` (token de Conversions API del pixel; nunca en el repo, en la URL ni en logs).
 *  · Errores: no se marca como enviado; hasta 3 intentos (ahora, +10 min, +1 h); después `_f360_meta_capi_error` y una nota.
 *  · Meta solo acepta eventos de hasta 7 días: un pago más viejo queda "omitido".
 * HPOS: solo la API de pedidos de Woo (get_meta/update_meta_data/save).
 * Apagar: borrar este archivo de wp-content/mu-plugins/. Meta for WooCommerce vuelve a mandar su Purchase solo.
 */
if (!defined('ABSPATH')) exit;
$f360_host = strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST));
if ($f360_host !== 'fuxiaballerinas.com' && $f360_host !== 'www.fuxiaballerinas.com') return;   // production store only

define('F360_META_PIXEL', '951926154215387');
define('F360_META_API', 'https://graph.facebook.com/v24.0/');
define('F360_META_LIVE', $f360_host === 'fuxiaballerinas.com' || $f360_host === 'www.fuxiaballerinas.com');
define('F360_META_HOOK', 'f360_meta_capi_compra');
define('F360_META_REINTENTOS', array(600, 3600));   // segundos hasta el 2º y 3er intento
define('F360_META_ORIGENES', array('store-api', 'checkout', 'f360_pay_link'));   // pedidos de la tienda en línea y links de pago

// 0) Meta for WooCommerce no manda Purchase. Su integración se arma en `init` (10); aquí se quitan sus enganches.
function f360_meta_quitar_purchase_del_plugin() {
  global $wp_filter;
  $quitados = 0;
  foreach (array('woocommerce_new_order', 'woocommerce_process_shop_order_meta', 'woocommerce_checkout_update_order_meta', 'woocommerce_thankyou') as $hook) {
    if (empty($wp_filter[$hook])) continue;
    foreach ($wp_filter[$hook]->callbacks as $prio => $cbs) {
      foreach ($cbs as $cb) {
        $f = $cb['function'];
        if (is_array($f) && is_object($f[0]) && $f[0] instanceof WC_Facebookcommerce_EventsTracker && $f[1] === 'inject_purchase_event') {
          remove_action($hook, $f, $prio);
          $quitados++;
        }
      }
    }
  }
  $GLOBALS['f360_meta_purchase_plugin_quitados'] = $quitados;
}
add_action('init', 'f360_meta_quitar_purchase_del_plugin', 1000);

// 1) Contexto de la clienta, tomado de SU navegador (checkout o página de pago del link).
function f360_meta_contexto($origen) {
  $ck = function ($k) { return isset($_COOKIE[$k]) ? sanitize_text_field(wp_unslash($_COOKIE[$k])) : ''; };
  $fbp = $ck('_fbp'); $fbc = $ck('_fbc');
  $ctx = array(
    'fbp' => preg_match('/^fb\.\d\.\d+\.\d+$/', $fbp) ? $fbp : '',
    'fbc' => preg_match('/^fb\.\d\.\d+\.[A-Za-z0-9_\-]+$/', $fbc) ? $fbc : '',
    'ip' => class_exists('WC_Geolocation') ? (string) WC_Geolocation::get_ip_address() : '',
    'ua' => isset($_SERVER['HTTP_USER_AGENT']) ? substr(sanitize_text_field(wp_unslash($_SERVER['HTTP_USER_AGENT'])), 0, 500) : '',
    'url' => '',
    'origen' => $origen,
    'at' => gmdate('c'),
  );
  $ref = isset($_SERVER['HTTP_REFERER']) ? esc_url_raw(wp_unslash($_SERVER['HTTP_REFERER'])) : '';
  if ($ref && strtolower((string) wp_parse_url($ref, PHP_URL_HOST)) === strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST))) $ctx['url'] = strtok($ref, '?');
  if (!filter_var($ctx['ip'], FILTER_VALIDATE_IP)) $ctx['ip'] = '';
  return $ctx;
}
function f360_meta_capturar($order) {
  if (!$order instanceof WC_Order || $order->get_meta('_f360_meta_ctx')) return;
  $order->update_meta_data('_f360_meta_ctx', wp_json_encode(f360_meta_contexto('checkout')));
  if ($order->get_id()) $order->save_meta_data();
}
add_action('woocommerce_store_api_checkout_update_order_meta', 'f360_meta_capturar');   // checkout de bloques
add_action('woocommerce_checkout_create_order', 'f360_meta_capturar');                   // checkout clásico
// Link de pago (order-pay): quien paga es la clienta en su navegador; su contexto reemplaza el de quien creó el pedido.
add_action('woocommerce_before_pay_action', function ($order) {
  if (!$order instanceof WC_Order || $order->get_meta('_f360_meta_capi')) return;
  $order->update_meta_data('_f360_meta_ctx', wp_json_encode(f360_meta_contexto('pago')));
  $order->save_meta_data();
});

// 2) Al pagarse (cualquier pasarela, webhook repetido o cambio de estado): UNA acción por pedido.
function f360_meta_agendar($order_id) {
  $order = wc_get_order($order_id);
  if (!$order || !$order->is_paid() || $order->get_meta('_f360_meta_capi')) return;
  if (!in_array($order->get_created_via(), apply_filters('f360_meta_capi_origenes', F360_META_ORIGENES), true)) return;
  if (!function_exists('as_schedule_single_action')) return;
  $args = array('order_id' => (int) $order->get_id());
  if (as_has_scheduled_action(F360_META_HOOK, $args, 'f360')) return;
  as_schedule_single_action(time() + 5, F360_META_HOOK, $args, 'f360', true);
}
add_action('woocommerce_payment_complete', 'f360_meta_agendar');
add_action('woocommerce_order_status_processing', 'f360_meta_agendar');
add_action('woocommerce_order_status_completed', 'f360_meta_agendar');

// 3) Normalización y hash según la especificación de Meta (customer information parameters).
function f360_meta_h($v) { $v = trim((string) $v); return $v === '' ? null : hash('sha256', $v); }
function f360_meta_minus($v) { return function_exists('mb_strtolower') ? mb_strtolower(trim((string) $v), 'UTF-8') : strtolower(trim((string) $v)); }
function f360_meta_telefono($tel, $pais) {
  $d = ltrim(preg_replace('/\D/', '', (string) $tel), '0');
  if ($d === '') return '';
  $lada = array('MX' => '52', 'CO' => '57');
  $pais = strtoupper((string) $pais);
  if (isset($lada[$pais]) && strlen($d) === 10) $d = $lada[$pais] . $d;   // celular nacional de 10 dígitos → con lada del país
  return $d;
}
function f360_meta_user_data($order, $ctx) {
  $pais = $order->get_billing_country() ?: $order->get_shipping_country();
  $u = array(
    'em' => f360_meta_h(f360_meta_minus($order->get_billing_email())),
    'ph' => f360_meta_h(f360_meta_telefono($order->get_billing_phone(), $pais)),
    'fn' => f360_meta_h(f360_meta_minus($order->get_billing_first_name())),
    'ln' => f360_meta_h(f360_meta_minus($order->get_billing_last_name())),
    'ct' => f360_meta_h(preg_replace('/\s+/', '', f360_meta_minus($order->get_billing_city()))),
    'st' => f360_meta_h(preg_replace('/[^\p{L}\p{N}]/u', '', f360_meta_minus($order->get_billing_state()))),
    'zp' => f360_meta_h(preg_replace('/\s+/', '', f360_meta_minus($order->get_billing_postcode()))),
    'country' => f360_meta_h(f360_meta_minus($pais)),
    'external_id' => $order->get_customer_id() ? f360_meta_h('wc_' . $order->get_customer_id()) : null,
  );
  foreach ($u as $k => $v) { if ($v === null) unset($u[$k]); else $u[$k] = array($v); }
  if (!empty($ctx['ip'])) $u['client_ip_address'] = $ctx['ip'];
  if (!empty($ctx['ua'])) $u['client_user_agent'] = $ctx['ua'];
  if (!empty($ctx['fbp'])) $u['fbp'] = $ctx['fbp'];
  if (!empty($ctx['fbc'])) $u['fbc'] = $ctx['fbc'];
  return $u;
}

// 4) El evento. content_ids con el mismo id que el catálogo de Meta for WooCommerce (id de la variación, filtro del plugin).
function f360_meta_evento($order) {
  $ctx = json_decode((string) $order->get_meta('_f360_meta_ctx'), true);
  if (!is_array($ctx)) $ctx = array();
  $ids = array(); $contents = array(); $n = 0;
  foreach ($order->get_items() as $item) {
    $qty = max(1, (int) $item->get_quantity());
    $product = $item->get_product();
    $id = $product ? (string) apply_filters('wc_facebook_fb_retailer_id', (string) $product->get_id(), $product) : (string) $item->get_product_id();
    $ids[] = $id;
    $contents[] = array('id' => $id, 'quantity' => $qty, 'item_price' => round((float) $item->get_total() / $qty, 2));
    $n += $qty;
  }
  $paid = $order->get_date_paid();
  $ev = array(
    'event_name' => 'Purchase',
    'event_time' => $paid ? $paid->getTimestamp() : time(),
    'event_id' => (string) $order->get_order_number(),
    'action_source' => 'website',
    'event_source_url' => !empty($ctx['url']) ? $ctx['url'] : wc_get_checkout_url(),
    'user_data' => f360_meta_user_data($order, $ctx),
    'custom_data' => array(
      'currency' => $order->get_currency(),
      'value' => round((float) $order->get_total(), 2),
      'content_ids' => array_values(array_unique($ids)),
      'contents' => $contents,
      'content_type' => 'product',
      'num_items' => $n,
      'order_id' => (string) $order->get_order_number(),
    ),
  );
  return $ev;
}

function f360_meta_post($body) {
  $r = wp_remote_post(F360_META_API . F360_META_PIXEL . '/events', array('timeout' => 15,
    'headers' => array('Content-Type' => 'application/json'), 'body' => wp_json_encode($body)));
  if (is_wp_error($r)) return array(0, null, $r->get_error_code());
  return array((int) wp_remote_retrieve_response_code($r), json_decode((string) wp_remote_retrieve_body($r), true), '');
}

function f360_meta_fallo($order, $intento, $motivo) {
  error_log('[f360-meta] pedido ' . $order->get_id() . ' intento ' . $intento . ': ' . $motivo);
  $esperas = F360_META_REINTENTOS;
  if ($intento <= count($esperas)) {
    // sin "único": esta misma acción sigue en curso y Action Scheduler lo bloquearía
    as_schedule_single_action(time() + $esperas[$intento - 1], F360_META_HOOK, array('order_id' => (int) $order->get_id()), 'f360');
    return;
  }
  $order->update_meta_data('_f360_meta_capi_error', $motivo . ' · ' . gmdate('c'));
  $order->add_order_note('Fuxia 360: no se pudo mandar la compra a Meta tras ' . $intento . ' intentos (' . $motivo . ').');
  $order->save();
}

// 5) Envío (Action Scheduler). Vuelve a revisar todo: el pedido pudo cambiar desde que se agendó.
add_action(F360_META_HOOK, function ($order_id) {
  $order = wc_get_order((int) $order_id);
  if (!$order || !$order->is_paid() || !$order->has_status(array('processing', 'completed')) || $order->get_meta('_f360_meta_capi')) return;
  if (!in_array($order->get_created_via(), apply_filters('f360_meta_capi_origenes', F360_META_ORIGENES), true)) return;
  $omitir = function ($motivo) use ($order) { $order->update_meta_data('_f360_meta_capi', 'omitido: ' . $motivo . ' · ' . gmdate('c')); $order->save(); };
  if (!apply_filters('f360_meta_capi_permitido', true, $order)) { $omitir('sin permiso'); return; }
  $ev = f360_meta_evento($order);
  if (time() - $ev['event_time'] > 7 * DAY_IN_SECONDS - 3600) { $omitir('pago de hace más de 7 días'); return; }
  $token = (string) get_option('f360_meta_capi_token', '');
  if ($token === '') { error_log('[f360-meta] falta f360_meta_capi_token; pedido ' . $order->get_id() . ' sin mandar'); return; }
  $body = array('data' => array($ev), 'access_token' => $token);
  if (!F360_META_LIVE) {
    $code = (string) get_option('f360_meta_capi_test_code', '');
    if ($code === '') { error_log('[f360-meta] staging sin f360_meta_capi_test_code; pedido ' . $order->get_id() . ' sin mandar'); return; }
    $body['test_event_code'] = $code;
  }
  $intento = (int) $order->get_meta('_f360_meta_capi_intentos') + 1;
  $order->update_meta_data('_f360_meta_capi_intentos', $intento);
  $order->save();
  list($http, $resp, $err) = f360_meta_post($body);
  if ($http !== 200 || !is_array($resp) || (int) ($resp['events_received'] ?? 0) !== 1) {
    $msg = is_array($resp) && isset($resp['error']['message']) ? substr((string) $resp['error']['message'], 0, 200) : '';
    f360_meta_fallo($order, $intento, 'http ' . $http . ($err ? ' ' . $err : '') . ($msg ? ' · ' . $msg : ''));
    return;
  }
  $traza = isset($resp['fbtrace_id']) ? ' · fbtrace ' . preg_replace('/[^A-Za-z0-9_\-]/', '', (string) $resp['fbtrace_id']) : '';
  $order->update_meta_data('_f360_meta_capi', (F360_META_LIVE ? 'enviado ' : 'prueba (Probar eventos) ') . gmdate('c') . $traza);
  $order->add_order_note(F360_META_LIVE ? 'Fuxia 360: compra enviada a Meta (Conversions API) al confirmarse el pago.'
    : 'Fuxia 360 (staging): compra enviada a Meta solo como prueba (Probar eventos); no cuenta en informes.');
  $order->save();
});
