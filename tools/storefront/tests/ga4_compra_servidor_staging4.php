<?php
/**
 * Pruebas de tools/storefront/mu-plugins/propuestas/f360-ga4-compra-servidor.php en STAGING4 (wp eval-file).
 * Crea pedidos de prueba con datos personales FALSOS (marcadores PRUEBAPII), simula cada pasarela y cada cambio de estado, y
 * revisa lo que el plugin manda. Los envíos reales van solo a https://www.google-analytics.com/debug/mp/collect (no registra nada).
 * Al final borra sus pedidos de prueba. Uso (lo corre scripts/f360/test_ga4_compra_staging4.sh):
 *   wp eval-file ga4_compra_servidor_staging4.php
 */
if (home_url() !== 'https://staging4.fuxiaballerinas.com') { echo "ABORT: no es staging4\n"; exit(1); }
if (!defined('F360_GA4_HOOK')) { echo "ABORT: el plugin no está cargado\n"; exit(1); }
if (F360_GA4_LIVE) { echo "ABORT: el plugin está en modo producción\n"; exit(1); }

$GLOBALS['f360t_http'] = array();       // cada request del plugin: [url sin secreto, cuerpo]
$GLOBALS['f360t_falla'] = null;         // null | 'http500' | 'formato'
add_filter('pre_http_request', function ($pre, $args, $url) {
  if (strpos($url, 'google-analytics.com') === false) return $pre;
  if (strpos($url, '/debug/mp/collect') === false) { echo "FALLA GRAVE: intento de envío real a $url\n"; exit(2); }
  $GLOBALS['f360t_http'][] = array(preg_replace('/api_secret=[^&]*/', 'api_secret=***', $url), $args['body']);
  if ($GLOBALS['f360t_falla'] === 'http500') return array('headers' => array(), 'body' => '', 'response' => array('code' => 500, 'message' => 'x'), 'cookies' => array(), 'filename' => null);
  if ($GLOBALS['f360t_falla'] === 'formato') return array('headers' => array(), 'body' => '{"validationMessages":[{"fieldPath":"x","description":"prueba","validationCode":"VALUE_INVALID"}]}', 'response' => array('code' => 200, 'message' => 'OK'), 'cookies' => array(), 'filename' => null);
  return $pre;   // real: va a /debug/mp/collect
}, 10, 3);

// wp eval-file corre dentro de una función: los contadores van en $GLOBALS, no en variables del archivo
$GLOBALS['f360t_ok'] = 0; $GLOBALS['f360t_mal'] = 0;
function f360t($cond, $msg) { if ($cond) { $GLOBALS['f360t_ok']++; echo "  PASA  $msg\n"; } else { $GLOBALS['f360t_mal']++; echo "  FALLA $msg\n"; } }
function f360t_acciones($id) { return count(as_get_scheduled_actions(array('hook' => F360_GA4_HOOK, 'args' => array('order_id' => (int) $id), 'status' => ActionScheduler_Store::STATUS_PENDING, 'group' => 'f360'), 'ids')); }
function f360t_correr($id) {   // lo que hace el runner de Action Scheduler: ejecuta la acción y la quita de la cola
  as_unschedule_all_actions(F360_GA4_HOOK, array('order_id' => (int) $id), 'f360');
  $n = count($GLOBALS['f360t_http']);
  do_action(F360_GA4_HOOK, (int) $id);
  return array_slice($GLOBALS['f360t_http'], $n);
}
function f360t_pedido($metodo, $moneda, $cid = true) {
  $ids = wc_get_products(array('type' => 'variable', 'status' => 'publish', 'limit' => 2, 'return' => 'ids'));
  $o = wc_create_order();
  foreach ($ids as $pid) {
    $p = wc_get_product($pid); $vars = $p->get_children();
    $o->add_product(wc_get_product($vars[0]), 1);
  }
  $o->set_address(array('first_name' => 'PRUEBAPII Nombre', 'last_name' => 'PRUEBAPII Apellido', 'email' => 'pruebapii@staging.invalid',
    'phone' => '5550001111', 'address_1' => 'PRUEBAPII Calle 123', 'city' => 'PRUEBAPII Ciudad', 'postcode' => '01234', 'country' => 'MX'), 'billing');
  $o->set_address(array('first_name' => 'PRUEBAPII Nombre', 'address_1' => 'PRUEBAPII Calle 123', 'country' => 'MX'), 'shipping');
  $o->set_customer_note('PRUEBAPII nota');
  $o->set_customer_ip_address('203.0.113.77');
  $o->set_payment_method($metodo);
  $o->set_currency($moneda);
  $o->set_created_via('store-api');
  $o->update_meta_data('_f360_prueba_ga4', 1);
  if ($cid) { $o->update_meta_data('_f360_ga_cid', '1111111111.2222222222'); $o->update_meta_data('_f360_ga_sid', '1760000000'); }
  $o->calculate_totals();
  $o->set_status('pending');
  $o->save();
  return $o->get_id();
}

$hpos = class_exists('Automattic\WooCommerce\Utilities\OrderUtil') && Automattic\WooCommerce\Utilities\OrderUtil::custom_orders_table_usage_is_enabled();
echo "staging4 · HPOS " . ($hpos ? 'ACTIVO' : 'apagado (tablas clásicas)') . " · Woo " . WC()->version . "\n";

echo "\n1) Captura del client_id al crear el pedido\n";
$o = wc_create_order(); $o->update_meta_data('_f360_prueba_ga4', 1); $o->save();
$_COOKIE['_ga'] = 'GA1.1.123456789.1700000000'; $_COOKIE['_ga_8C1244627P'] = 'GS2.1.s1760111111$o5$g1$t1760111200$j60$l0$h0';
f360_ga4_capturar_ids($o); $o = wc_get_order($o->get_id());
f360t($o->get_meta('_f360_ga_cid') === '123456789.1700000000' && $o->get_meta('_f360_ga_sid') === '1760111111', 'cookie GS2: client_id y session_id guardados');
$o2 = wc_create_order(); $o2->update_meta_data('_f360_prueba_ga4', 1); $o2->save();
$_COOKIE['_ga_8C1244627P'] = 'GS1.1.1760222222.3.1.1760222300.0.0.0'; f360_ga4_capturar_ids($o2); $o2 = wc_get_order($o2->get_id());
f360t($o2->get_meta('_f360_ga_sid') === '1760222222', 'cookie GS1: session_id guardado');
$o3 = wc_create_order(); $o3->update_meta_data('_f360_prueba_ga4', 1); $o3->save();
$_COOKIE['_ga'] = 'basura'; f360_ga4_capturar_ids($o3); $o3 = wc_get_order($o3->get_id());
f360t(!$o3->get_meta('_f360_ga_cid'), 'cookie inválida: no guarda nada');
unset($_COOKIE['_ga'], $_COOKIE['_ga_8C1244627P']);

echo "\n2) Solo pedidos pagados\n";
$id = f360t_pedido('woo-mercado-pago-custom', 'MXN');
f360t(f360t_acciones($id) === 0, 'pending: nada agendado');
f360t(count(f360t_correr($id)) === 0, 'pending: la acción no manda nada aunque se ejecute');
wc_get_order($id)->update_status('on-hold'); f360t(f360t_acciones($id) === 0 && count(f360t_correr($id)) === 0, 'on-hold: nada');
wc_get_order($id)->update_status('failed'); f360t(f360t_acciones($id) === 0 && count(f360t_correr($id)) === 0, 'failed: nada');

echo "\n3) Mercado Pago asíncrono: pending → webhook → processing\n";
$mp = f360t_pedido('woo-mercado-pago-custom', 'MXN');
wc_get_order($mp)->update_status('processing');
f360t(f360t_acciones($mp) === 1, 'webhook: una acción agendada');
$req = f360t_correr($mp); $o = wc_get_order($mp);
f360t(count($req) === 1 && strpos($req[0][0], '/debug/mp/collect') !== false, 'un solo request, al endpoint de validación');
f360t((int) $o->get_meta('_ga_tracked') === 1 && strpos((string) $o->get_meta('_f360_ga4_mp'), 'validado') === 0, 'Google validó sin errores → _ga_tracked = 1');
$body = json_decode($req[0][1], true); $p = $body['events'][0]['params'];
f360t($p['transaction_id'] === (string) $o->get_order_number(), 'transaction_id = número de pedido (' . $p['transaction_id'] . ')');
f360t($p['currency'] === $o->get_currency() && abs($p['value'] - (float) $o->get_total()) < 0.01, 'moneda e importe = Woo (' . $p['value'] . ' ' . $p['currency'] . ')');
$lineas = array_values($o->get_items());
$cuadra = count($p['items']) === count($lineas);
foreach ($lineas as $i => $it) $cuadra = $cuadra && $p['items'][$i]['item_id'] === (string) $it->get_product_id() && (int) $p['items'][$i]['quantity'] === (int) $it->get_quantity() && abs($p['items'][$i]['price'] * $it->get_quantity() - (float) $it->get_total()) < 0.02;
f360t($cuadra, 'productos, cantidades y precios = líneas de Woo');
f360t($body['client_id'] === '1111111111.2222222222' && $p['session_id'] === '1760000000', 'client_id y session_id de la clienta');

echo "\n4) Confirmaciones repetidas y cambios de estado después de enviado\n";
$n = count($GLOBALS['f360t_http']);
$o = wc_get_order($mp); $o->payment_complete(); wc_get_order($mp)->update_status('completed');
f360t(f360t_acciones($mp) === 0, 'payment_complete otra vez + completed: nada agendado');
f360t(count(f360t_correr($mp)) === 0 && count($GLOBALS['f360t_http']) === $n, 'ejecutar la acción otra vez: no manda nada');
wc_get_order($mp)->update_status('refunded'); f360t(f360t_acciones($mp) === 0, 'refunded: nada');

echo "\n5) Reintentos del webhook ANTES de enviar (ePayco)\n";
$ep = f360t_pedido('epayco', 'COP');
$o = wc_get_order($ep); $o->payment_complete(); wc_get_order($ep)->payment_complete(); wc_get_order($ep)->payment_complete(); wc_get_order($ep)->update_status('completed');
f360t(f360t_acciones($ep) === 1, '3 webhooks + completed: UNA acción');
$req = f360t_correr($ep); f360t(count($req) === 1 && json_decode($req[0][1], true)['events'][0]['params']['currency'] === 'COP', 'ePayco COP: un envío, moneda COP');

echo "\n6) PayPal (tarjeta y botón)\n";
foreach (array('ppcp-card-button-gateway' => 'COP', 'ppcp-gateway' => 'USD') as $m => $cur) {
  $pp = f360t_pedido($m, $cur); wc_get_order($pp)->payment_complete();
  $req = f360t_correr($pp); f360t(count($req) === 1 && (int) wc_get_order($pp)->get_meta('_ga_tracked') === 1, "$m $cur: un envío validado");
}

echo "\n7) Navegador primero (GTM4WP ya marcó _ga_tracked)\n";
$nb = f360t_pedido('woo-mercado-pago-custom', 'MXN');
$o = wc_get_order($nb); $o->update_meta_data('_ga_tracked', 1); $o->save(); wc_get_order($nb)->payment_complete();
f360t(f360t_acciones($nb) === 0 && count(f360t_correr($nb)) === 0, 'no agenda ni manda');
$nb2 = f360t_pedido('woo-mercado-pago-custom', 'MXN'); wc_get_order($nb2)->payment_complete();
$o = wc_get_order($nb2); $o->update_meta_data('_ga_tracked', 1); $o->save();   // el navegador lo midió durante los 2 minutos de espera
f360t(count(f360t_correr($nb2)) === 0, 'el navegador lo midió durante la espera: la acción no manda');

echo "\n8) Cambia de estado durante la espera\n";
$ce = f360t_pedido('woo-mercado-pago-custom', 'MXN'); wc_get_order($ce)->payment_complete(); wc_get_order($ce)->update_status('cancelled');
f360t(count(f360t_correr($ce)) === 0, 'pagado y luego cancelado antes del envío: no manda');

echo "\n9) Sin client_id / sin permiso de consentimiento\n";
$sc = f360t_pedido('woo-mercado-pago-custom', 'MXN', false); wc_get_order($sc)->payment_complete();
f360t(count(f360t_correr($sc)) === 0 && strpos((string) wc_get_order($sc)->get_meta('_f360_ga4_mp'), 'omitido') === 0, 'sin cookie _ga: no manda, queda "omitido"');
add_filter('f360_ga4_mp_permitido', '__return_false');
$cn = f360t_pedido('woo-mercado-pago-custom', 'MXN'); wc_get_order($cn)->payment_complete();
f360t(count(f360t_correr($cn)) === 0 && strpos((string) wc_get_order($cn)->get_meta('_f360_ga4_mp'), 'omitido') === 0, 'filtro de consentimiento en false: no manda');
remove_filter('f360_ga4_mp_permitido', '__return_false');

echo "\n10) Errores: nunca se marca como enviado si Google no lo aceptó\n";
$er = f360t_pedido('woo-mercado-pago-custom', 'MXN'); wc_get_order($er)->payment_complete();
$GLOBALS['f360t_falla'] = 'http500';
f360t_correr($er); $o = wc_get_order($er);
f360t((int) $o->get_meta('_ga_tracked') !== 1 && !$o->get_meta('_f360_ga4_mp') && f360t_acciones($er) === 1, 'http 500: sin marca y reintento agendado');
f360t_correr($er); f360t(f360t_acciones($er) === 1, '2º intento falla: 3er intento agendado');
f360t_correr($er); $o = wc_get_order($er);
f360t(f360t_acciones($er) === 0 && $o->get_meta('_f360_ga4_mp_error') && (int) $o->get_meta('_ga_tracked') !== 1, '3er intento falla: se detiene, deja _f360_ga4_mp_error y nota');
$GLOBALS['f360t_falla'] = 'formato';
$fv = f360t_pedido('woo-mercado-pago-custom', 'MXN'); wc_get_order($fv)->payment_complete(); f360t_correr($fv);
f360t((int) wc_get_order($fv)->get_meta('_ga_tracked') !== 1 && f360t_acciones($fv) === 1, 'Google reporta error de formato: sin marca, reintento');
$GLOBALS['f360t_falla'] = null;
$req = f360t_correr($fv);
f360t(count($req) === 1 && (int) wc_get_order($fv)->get_meta('_ga_tracked') === 1, 'el reintento sale bien: se marca una sola vez');
$cids = array(); foreach ($GLOBALS['f360t_http'] as $r) $cids[] = json_decode($r[1], true)['client_id'];
f360t(count(array_unique($cids)) === 1, 'todos los reintentos usan el mismo client_id');

echo "\n11) Nada personal sale del servidor\n";
$todo = implode("\n", array_column($GLOBALS['f360t_http'], 1));
f360t(stripos($todo, 'PRUEBAPII') === false && stripos($todo, 'staging.invalid') === false && strpos($todo, '5550001111') === false && strpos($todo, '203.0.113.77') === false && strpos($todo, '01234') === false,
  'ni nombre, correo, teléfono, dirección, código postal, nota ni IP en ' . count($GLOBALS['f360t_http']) . ' requests');
$claves = array(); foreach ($GLOBALS['f360t_http'] as $r) { $b = json_decode($r[1], true); $claves = array_merge($claves, array_keys($b), array_keys($b['events'][0]['params'])); }
echo '  campos enviados: ' . implode(', ', array_unique($claves)) . "\n";
f360t(strpos(implode("\n", array_column($GLOBALS['f360t_http'], 0)), 'staging-solo-validacion') === false, 'el secreto no aparece en lo registrado por la prueba');

echo "\n12) Validación real de Google (debug) sobre un pedido completo\n";
$GLOBALS['f360t_http'] = array();
$rv = f360t_pedido('woo-mercado-pago-custom', 'MXN'); wc_get_order($rv)->payment_complete(); f360t_correr($rv);
echo '  respuesta guardada: ' . wc_get_order($rv)->get_meta('_f360_ga4_mp') . "\n";
echo '  ejemplo de lo que se manda: ' . $GLOBALS['f360t_http'][0][1] . "\n";

// limpieza: TODOS los pedidos de prueba (marcados con _f360_prueba_ga4), también los que dejó una corrida anterior
$prueba = wc_get_orders(array('limit' => -1, 'status' => 'any', 'meta_key' => '_f360_prueba_ga4', 'meta_value' => '1', 'return' => 'ids'));
foreach ($prueba as $pid) { as_unschedule_all_actions(F360_GA4_HOOK, array('order_id' => (int) $pid), 'f360'); $o = wc_get_order($pid); if ($o && $o->get_meta('_f360_prueba_ga4')) $o->delete(true); }
$quedan = count(wc_get_orders(array('limit' => -1, 'status' => 'any', 'meta_key' => '_f360_prueba_ga4', 'meta_value' => '1', 'return' => 'ids')));
echo "\nRESULTADO: " . $GLOBALS['f360t_ok'] . " pasan, " . $GLOBALS['f360t_mal'] . " fallan · " . count($prueba) . " pedidos de prueba borrados, quedan $quedan\n";
exit(($GLOBALS['f360t_mal'] || $quedan) ? 1 : 0);
