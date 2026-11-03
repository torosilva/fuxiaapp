<?php
/**
 * Se carga con `wp --require` ANTES de WordPress, solo en el proceso de la prueba de Meta en staging4.
 * Activa Meta for WooCommerce SOLO en este proceso (en staging4 está apagado: tiene la conexión copiada de producción) y
 * bloquea cualquier request a Meta que no sea una prueba (`test_event_code`): el plugin no puede mandar eventos, ni
 * sincronizar el catálogo, ni tocar la conexión. Lo bloqueado queda en $GLOBALS['f360t_fb_bloqueados'] para la prueba.
 */
WP_CLI::add_wp_hook('option_active_plugins', function ($plugins) {
  $fb = 'facebook-for-woocommerce/facebook-for-woocommerce.php';
  if (is_array($plugins) && !in_array($fb, $plugins, true)) $plugins[] = $fb;
  return $plugins;
});
$GLOBALS['f360t_fb_bloqueados'] = array();
WP_CLI::add_wp_hook('pre_http_request', function ($pre, $args, $url) {
  $host = strtolower((string) parse_url($url, PHP_URL_HOST));
  if (!preg_match('/(^|\.)(facebook\.com|facebook\.net|fb\.com|instagram\.com)$/', $host)) return $pre;
  $body = is_string($args['body'] ?? null) ? $args['body'] : (is_array($args['body'] ?? null) ? http_build_query($args['body']) : '');
  if (!empty($GLOBALS['f360t_meta_real']) && strpos($body, 'test_event_code') !== false) return $pre;   // prueba real a "Probar eventos"
  $GLOBALS['f360t_fb_bloqueados'][] = array('url' => preg_replace('/access_token=[^&]*/', 'access_token=***', $url), 'body' => $body);
  $resp = isset($GLOBALS['f360t_respuesta']) ? $GLOBALS['f360t_respuesta'] : array('code' => 200, 'body' => '{"events_received":1,"fbtrace_id":"PRUEBA"}');
  return array('headers' => array(), 'body' => $resp['body'], 'response' => array('code' => $resp['code'], 'message' => 'x'), 'cookies' => array(), 'filename' => null);
}, 1, 3);
