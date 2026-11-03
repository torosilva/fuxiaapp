<?php
/**
 * Pruebas de tools/storefront/mu-plugins/propuestas/f360-meta-compra-servidor.php en STAGING4. Las corre
 * scripts/f360/test_meta_compra_staging4.sh: wp --require=meta_cargar_plugin_fb.php eval-file meta_compra_servidor_staging4.php
 * Meta for WooCommerce va activo SOLO en este proceso, y todo request a Meta queda bloqueado y registrado (meta_cargar_plugin_fb.php).
 * Si staging4 tiene token y test_event_code, el caso 13 manda UNA compra real a "Probar eventos" (no cuenta en informes).
 * Pedidos con datos personales FALSOS (PRUEBAPII); al final se borran todos.
 */
if (home_url() !== 'https://staging4.fuxiaballerinas.com') { fwrite(STDOUT, "ABORT: no es staging4\n"); exit(1); }
if (!defined('F360_META_HOOK')) { fwrite(STDOUT, "ABORT: el plugin f360-meta-compra-servidor no está cargado\n"); exit(1); }
if (F360_META_LIVE) { fwrite(STDOUT, "ABORT: el plugin está en modo producción\n"); exit(1); }
if (!class_exists('WC_Facebookcommerce_EventsTracker')) { fwrite(STDOUT, "ABORT: Meta for WooCommerce no se cargó en este proceso\n"); exit(1); }

// Todo lo que imprime la prueba va directo a STDOUT: Meta for WooCommerce abre búferes de salida que se tragarían un echo.
$GLOBALS['f360t_ok'] = 0; $GLOBALS['f360t_mal'] = 0;
function f360t($cond, $msg) { if ($cond) { $GLOBALS['f360t_ok']++; fwrite(STDOUT, "  PASA  $msg\n"); } else { $GLOBALS['f360t_mal']++; fwrite(STDOUT, "  FALLA $msg\n"); } }
function f360t_fb() { return $GLOBALS['f360t_fb_bloqueados']; }
function f360t_nuevos($n) { return array_slice($GLOBALS['f360t_fb_bloqueados'], $n); }
function f360t_purchases($reqs) {   // requests con un Purchase (CAPI del plugin o nuestro)
  return array_values(array_filter($reqs, function ($r) { return strpos($r['body'], 'Purchase') !== false; }));
}
function f360t_acciones($id) { return count(as_get_scheduled_actions(array('hook' => F360_META_HOOK, 'args' => array('order_id' => (int) $id), 'status' => ActionScheduler_Store::STATUS_PENDING, 'group' => 'f360'), 'ids')); }
function f360t_correr($id) {
  as_unschedule_all_actions(F360_META_HOOK, array('order_id' => (int) $id), 'f360');
  $n = count($GLOBALS['f360t_fb_bloqueados']);
  do_action(F360_META_HOOK, (int) $id);
  return array_slice($GLOBALS['f360t_fb_bloqueados'], $n);
}
function f360t_pedido($metodo, $moneda, $pais = 'MX', $via = 'store-api') {
  $ids = wc_get_products(array('type' => 'variable', 'status' => 'publish', 'limit' => 2, 'return' => 'ids'));
  $o = wc_create_order();
  foreach ($ids as $pid) { $vars = wc_get_product($pid)->get_children(); $o->add_product(wc_get_product($vars[0]), 1); }
  $o->set_address(array('first_name' => 'PRUEBAPII Nombre', 'last_name' => 'PRUEBAPII Apellido', 'email' => 'PruebaPII@Staging.Invalid',
    'phone' => $pais === 'CO' ? '300 123 4567' : '55 5000 1111', 'address_1' => 'PRUEBAPII Calle 123', 'city' => 'Ciudad de México',
    'state' => $pais === 'CO' ? 'DC' : 'CMX', 'postcode' => '01234', 'country' => $pais), 'billing');
  $o->set_customer_note('PRUEBAPII nota');
  $o->set_payment_method($metodo);
  $o->set_currency($moneda);
  $o->set_created_via($via);
  $o->update_meta_data('_f360_prueba_meta', 1);
  $o->update_meta_data('_f360_meta_ctx', wp_json_encode(array('fbp' => 'fb.1.1760000000000.1234567890', 'fbc' => 'fb.1.1760000000000.IwPRUEBA', 'ip' => '203.0.113.77',
    'ua' => 'Mozilla/5.0 (PRUEBA)', 'url' => 'https://staging4.fuxiaballerinas.com/mx/finalizar-compra/', 'origen' => 'checkout', 'at' => gmdate('c'))));
  $o->calculate_totals();
  $o->set_status('pending');
  $o->save();
  return $o->get_id();
}
$token_real = (string) get_option('f360_meta_capi_token', '');
$code_real = (string) get_option('f360_meta_capi_test_code', '');
// Para los casos 1–12 el token y el código son marcadores: todo request a Meta queda bloqueado de todos modos.
add_filter('pre_option_f360_meta_capi_token', function () { return empty($GLOBALS['f360t_meta_real']) ? 'TOKEN-DE-PRUEBA' : false; });
add_filter('pre_option_f360_meta_capi_test_code', function () { return empty($GLOBALS['f360t_meta_real']) ? 'TEST-PRUEBA' : false; });

fwrite(STDOUT, "staging4 · Woo " . WC()->version . " · Meta for WooCommerce " . (defined('WC_Facebookcommerce::VERSION') ? WC_Facebookcommerce::VERSION : (function_exists('facebook_for_woocommerce') ? facebook_for_woocommerce()->get_version() : '?')) . "\n");

fwrite(STDOUT, "\n1) Meta for WooCommerce ya no tiene enganchado su Purchase\n");
global $wp_filter;
$quedan = 0;
foreach (array('woocommerce_new_order', 'woocommerce_process_shop_order_meta', 'woocommerce_checkout_update_order_meta', 'woocommerce_thankyou') as $h) {
  if (empty($wp_filter[$h])) continue;
  foreach ($wp_filter[$h]->callbacks as $cbs) foreach ($cbs as $cb) if (is_array($cb['function']) && $cb['function'][0] instanceof WC_Facebookcommerce_EventsTracker && $cb['function'][1] === 'inject_purchase_event') $quedan++;
}
f360t((int) ($GLOBALS['f360_meta_purchase_plugin_quitados'] ?? 0) === 4 && $quedan === 0, 'se quitaron sus 4 enganches (' . (int) ($GLOBALS['f360_meta_purchase_plugin_quitados'] ?? 0) . ') y no queda ninguno');

fwrite(STDOUT, "\n2) Control: así se comportaba el plugin (pedido SIN pagar → Purchase)\n");
$ctl = f360t_pedido('woo-mercado-pago-custom', 'MXN');
$n = count(f360t_fb());
$tracker = null;
foreach (array('woocommerce_add_to_cart', 'woocommerce_after_checkout_form') as $h) foreach ($wp_filter[$h]->callbacks ?? array() as $cbs) foreach ($cbs as $cb) if (is_array($cb['function']) && $cb['function'][0] instanceof WC_Facebookcommerce_EventsTracker) $tracker = $cb['function'][0];
if ($tracker) $tracker->inject_purchase_event($ctl);
f360t($tracker && count(f360t_purchases(f360t_nuevos($n))) >= 1, 'llamado a mano, el plugin manda Purchase con el pedido en pending (lo que pasaba en producción)');

fwrite(STDOUT, "\n3) Crear el pedido y ver \"pedido recibido\" SIN pagar: 0 Purchase de nadie\n");
$pe = f360t_pedido('woo-mercado-pago-custom', 'MXN');
$n = count(f360t_fb());
$o = wc_get_order($pe);
do_action('woocommerce_new_order', $pe, $o);
do_action('woocommerce_checkout_update_order_meta', $pe, array());
ob_start(); do_action('woocommerce_thankyou', $pe); $html = ob_get_clean();
f360t(count(f360t_purchases(f360t_nuevos($n))) === 0, 'woocommerce_new_order + checkout_update_order_meta: ningún Purchase por CAPI');
f360t(stripos($html, 'Purchase') === false, 'página de gracias: el plugin no imprime fbq Purchase');
f360t(f360t_acciones($pe) === 0, 'nada agendado');
foreach (array('on-hold', 'failed', 'cancelled') as $st) {
  $x = f360t_pedido('epayco', 'COP', 'CO'); wc_get_order($x)->update_status($st);
  f360t(f360t_acciones($x) === 0 && count(f360t_correr($x)) === 0, "$st: ni agenda ni manda");
}

fwrite(STDOUT, "\n4) Mercado Pago: pending → webhook → processing = 1 Purchase\n");
$mp = f360t_pedido('woo-mercado-pago-custom', 'MXN');
wc_get_order($mp)->update_status('processing');
f360t(f360t_acciones($mp) === 1, 'una acción agendada');
$req = f360t_correr($mp); $o = wc_get_order($mp);
f360t(count($req) === 1 && strpos($req[0]['url'], 'graph.facebook.com/v24.0/951926154215387/events') !== false, 'un request, al pixel 951926154215387');
$b = json_decode($req[0]['body'], true); $e = $b['data'][0];
f360t(strpos($req[0]['url'], 'TOKEN') === false, 'el token no va en la URL');
f360t($e['event_name'] === 'Purchase' && $e['event_id'] === (string) $o->get_order_number() && $e['action_source'] === 'website', 'Purchase, event_id = número de pedido (' . $e['event_id'] . '), action_source website');
f360t($b['test_event_code'] === 'TEST-PRUEBA', 'staging: lleva test_event_code');
f360t($e['custom_data']['currency'] === 'MXN' && abs($e['custom_data']['value'] - (float) $o->get_total()) < 0.01, 'moneda y valor = Woo (' . $e['custom_data']['value'] . ' MXN)');
$vids = array(); foreach ($o->get_items() as $it) { $pr = $it->get_product(); $vids[] = (string) apply_filters('wc_facebook_fb_retailer_id', (string) $pr->get_id(), $pr); }
f360t($e['custom_data']['content_ids'] === $vids && count($e['custom_data']['contents']) === count($vids) && $e['custom_data']['num_items'] === count($vids), 'content_ids = ids del catálogo (variaciones): ' . implode(',', $vids));
$u = $e['user_data'];
f360t($u['em'][0] === hash('sha256', 'pruebapii@staging.invalid'), 'correo en minúsculas, SHA-256');
f360t($u['ph'][0] === hash('sha256', '525550001111'), 'teléfono MX: 52 + 10 dígitos, SHA-256');
f360t($u['fn'][0] === hash('sha256', 'pruebapii nombre') && $u['country'][0] === hash('sha256', 'mx') && $u['ct'][0] === hash('sha256', 'ciudaddeméxico'), 'nombre, ciudad y país normalizados en hash');
f360t($u['fbp'] === 'fb.1.1760000000000.1234567890' && $u['fbc'] === 'fb.1.1760000000000.IwPRUEBA' && $u['client_ip_address'] === '203.0.113.77' && $u['client_user_agent'] === 'Mozilla/5.0 (PRUEBA)', '_fbp, _fbc, IP y user agent del pedido');
f360t($e['event_source_url'] === 'https://staging4.fuxiaballerinas.com/mx/finalizar-compra/', 'event_source_url = página de pago de la clienta');
f360t(strpos((string) $o->get_meta('_f360_meta_capi'), 'prueba') === 0, 'marca _f360_meta_capi puesta');

fwrite(STDOUT, "\n5) Después de enviado: nada se repite\n");
$n = count(f360t_fb());
wc_get_order($mp)->payment_complete(); wc_get_order($mp)->update_status('completed'); wc_get_order($mp)->update_status('refunded');
f360t(f360t_acciones($mp) === 0 && count(f360t_correr($mp)) === 0 && count(f360t_fb()) === $n, 'payment_complete, completed y refunded: nada');

fwrite(STDOUT, "\n6) ePayco (COP): 3 webhooks + completed = 1 Purchase\n");
$ep = f360t_pedido('epayco', 'COP', 'CO');
wc_get_order($ep)->payment_complete(); wc_get_order($ep)->payment_complete(); wc_get_order($ep)->payment_complete(); wc_get_order($ep)->update_status('completed');
f360t(f360t_acciones($ep) === 1, 'una sola acción');
$req = f360t_correr($ep); $e = json_decode($req[0]['body'], true)['data'][0];
f360t(count($req) === 1 && $e['custom_data']['currency'] === 'COP' && $e['user_data']['ph'][0] === hash('sha256', '573001234567'), 'un envío, COP, teléfono con 57');

fwrite(STDOUT, "\n7) Pagado y cancelado antes de enviar · origen que no es la tienda · pago de hace 8 días\n");
$ce = f360t_pedido('woo-mercado-pago-custom', 'MXN'); wc_get_order($ce)->payment_complete(); wc_get_order($ce)->update_status('cancelled');
f360t(count(f360t_correr($ce)) === 0, 'cancelado antes del envío: no manda');
$ad = f360t_pedido('woo-mercado-pago-custom', 'MXN', 'MX', 'admin'); wc_get_order($ad)->payment_complete();
f360t(f360t_acciones($ad) === 0 && count(f360t_correr($ad)) === 0, 'pedido creado en el admin: no manda');
$vj = f360t_pedido('woo-mercado-pago-custom', 'MXN'); $o = wc_get_order($vj); $o->payment_complete();
$o = wc_get_order($vj); $o->set_date_paid(time() - 8 * DAY_IN_SECONDS); $o->save();
f360t(count(f360t_correr($vj)) === 0 && strpos((string) wc_get_order($vj)->get_meta('_f360_meta_capi'), 'omitido') === 0, 'pago de hace 8 días: omitido (Meta no lo acepta)');

fwrite(STDOUT, "\n8) Link de pago: el contexto es el del navegador que paga\n");
$pl = f360t_pedido('woo-mercado-pago-custom', 'MXN', 'MX', 'f360_pay_link');
$_COOKIE['_fbp'] = 'fb.1.1761111111111.999'; $_COOKIE['_fbc'] = 'fb.1.1761111111111.IwLINK'; $_SERVER['HTTP_USER_AGENT'] = 'Mozilla/5.0 (CLIENTA)';
do_action('woocommerce_before_pay_action', wc_get_order($pl));
unset($_COOKIE['_fbp'], $_COOKIE['_fbc']);
wc_get_order($pl)->payment_complete();
$req = f360t_correr($pl); $u = json_decode($req[0]['body'], true)['data'][0]['user_data'];
f360t(count($req) === 1 && $u['fbp'] === 'fb.1.1761111111111.999' && $u['fbc'] === 'fb.1.1761111111111.IwLINK' && $u['client_user_agent'] === 'Mozilla/5.0 (CLIENTA)', 'manda con _fbp/_fbc/user agent de quien pagó');

fwrite(STDOUT, "\n9) Captura al crear el pedido\n");
$cp = wc_create_order(); $cp->update_meta_data('_f360_prueba_meta', 1); $cp->save();
$_COOKIE['_fbp'] = 'fb.1.1762222222222.555'; $_COOKIE['_fbc'] = '<script>'; $_SERVER['HTTP_REFERER'] = 'https://staging4.fuxiaballerinas.com/co/finalizar-compra/?x=1';
f360_meta_capturar($cp); $c = json_decode((string) wc_get_order($cp->get_id())->get_meta('_f360_meta_ctx'), true);
f360t($c['fbp'] === 'fb.1.1762222222222.555' && $c['fbc'] === '' && $c['url'] === 'https://staging4.fuxiaballerinas.com/co/finalizar-compra/' && $c['origen'] === 'checkout', '_fbp válido guardado, _fbc inválido descartado, URL sin parámetros');
unset($_COOKIE['_fbp'], $_COOKIE['_fbc'], $_SERVER['HTTP_REFERER']);

fwrite(STDOUT, "\n10) Errores: nunca se marca como enviado si Meta no lo aceptó\n");
$er = f360t_pedido('woo-mercado-pago-custom', 'MXN'); wc_get_order($er)->payment_complete();
$GLOBALS['f360t_respuesta'] = array('code' => 500, 'body' => '{"error":{"message":"prueba"}}');
f360t_correr($er); $o = wc_get_order($er);
f360t(!$o->get_meta('_f360_meta_capi') && f360t_acciones($er) === 1, 'http 500: sin marca y reintento agendado');
f360t_correr($er); f360t(f360t_acciones($er) === 1, '2º intento falla: 3er intento agendado');
f360t_correr($er); $o = wc_get_order($er);
f360t(f360t_acciones($er) === 0 && $o->get_meta('_f360_meta_capi_error') && !$o->get_meta('_f360_meta_capi'), '3er intento falla: se detiene con _f360_meta_capi_error y nota');
$GLOBALS['f360t_respuesta'] = array('code' => 200, 'body' => '{"events_received":0}');
$e0 = f360t_pedido('woo-mercado-pago-custom', 'MXN'); wc_get_order($e0)->payment_complete(); f360t_correr($e0);
f360t(!wc_get_order($e0)->get_meta('_f360_meta_capi') && f360t_acciones($e0) === 1, 'Meta responde events_received 0: sin marca, reintento');
unset($GLOBALS['f360t_respuesta']);
f360t(count(f360t_correr($e0)) === 1 && wc_get_order($e0)->get_meta('_f360_meta_capi'), 'el reintento sale bien: se marca una vez');

fwrite(STDOUT, "\n11) Nada personal en texto\n");
$todo = implode("\n", array_column(f360t_purchases(f360t_fb()), 'body'));
$propios = array_filter(f360t_fb(), function ($r) { return strpos($r['body'], '"test_event_code"') !== false; });
$txt = implode("\n", array_column($propios, 'body'));
f360t($txt !== '' && stripos($txt, 'PRUEBAPII') === false && stripos($txt, 'staging.invalid') === false && strpos($txt, '5000') === false && strpos($txt, '01234') === false && stripos($txt, 'méxico') === false,
  'ni nombre, correo, teléfono, CP ni ciudad en texto en ' . count($propios) . ' envíos (IP y user agent sí, como pide Meta)');

fwrite(STDOUT, "\n12) Lo que el plugin de Meta intentó mandar en toda la prueba (bloqueado)\n");
$tipos = array(); foreach (f360t_fb() as $r) { if (strpos($r['body'], '"test_event_code"') !== false) continue; $tipos[] = preg_replace('#https://graph\.facebook\.com/v[\d.]+/#', '', strtok($r['url'], '?')) . (strpos($r['body'], 'Purchase') !== false ? ' (Purchase)' : ''); }
$cuenta = array(); foreach (array_count_values($tipos) as $k => $v) $cuenta[] = "$k ×$v";
fwrite(STDOUT, '  ' . ($cuenta ? implode(' · ', $cuenta) : 'nada') . "\n");
f360t(count(array_filter($tipos, function ($t) { return strpos($t, 'Purchase') !== false; })) === 1, 'el único Purchase del plugin fue el del control (caso 2)');

fwrite(STDOUT, "\n13) Envío REAL a \"Probar eventos\" (solo si staging4 tiene token y test_event_code)\n");
if ($token_real !== '' && $code_real !== '') {
  $GLOBALS['f360t_meta_real'] = 1;
  foreach (array(array('woo-mercado-pago-custom', 'MXN', 'MX'), array('epayco', 'COP', 'CO')) as $c3) {
    $rv = f360t_pedido($c3[0], $c3[1], $c3[2]); wc_get_order($rv)->payment_complete(); f360t_correr($rv);
    $m = (string) wc_get_order($rv)->get_meta('_f360_meta_capi');
    f360t(strpos($m, 'prueba') === 0, $c3[1] . ' pedido ' . wc_get_order($rv)->get_order_number() . ': Meta lo recibió (' . $m . ')');
  }
  unset($GLOBALS['f360t_meta_real']);
} else fwrite(STDOUT, "  (sin token o sin test_event_code en staging4: se omite)\n");

// limpieza: todos los pedidos de prueba y sus acciones; y lo que el plugin de Meta haya agendado en este proceso
$prueba = wc_get_orders(array('limit' => -1, 'status' => 'any', 'meta_key' => '_f360_prueba_meta', 'meta_value' => '1', 'return' => 'ids'));
foreach ($prueba as $pid) { as_unschedule_all_actions(F360_META_HOOK, array('order_id' => (int) $pid), 'f360'); if (defined('F360_GA4_HOOK')) as_unschedule_all_actions(F360_GA4_HOOK, array('order_id' => (int) $pid), 'f360'); $o = wc_get_order($pid); if ($o && $o->get_meta('_f360_prueba_meta')) $o->delete(true); }
$quedan = count(wc_get_orders(array('limit' => -1, 'status' => 'any', 'meta_key' => '_f360_prueba_meta', 'meta_value' => '1', 'return' => 'ids')));
fwrite(STDOUT, "\nRESULTADO: " . $GLOBALS['f360t_ok'] . " pasan, " . $GLOBALS['f360t_mal'] . " fallan · " . count($prueba) . " pedidos de prueba borrados, quedan $quedan\n");
exit(($GLOBALS['f360t_mal'] || $quedan) ? 1 : 0);
