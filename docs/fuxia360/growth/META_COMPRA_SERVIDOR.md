# Meta: la compra se cuenta solo cuando el pedido está pagado

**Estado: STAGING (propuesta en staging4), 2026-11-03.** No está en producción.
Mario lo pidió el 2026-11-03 ("opción B, sin parches, la mejor forma"). FUXIA_NOV_MX_VENTAS espera a que esto esté en producción.

## El problema (verificado)

En **octubre**, Ads Manager reportó **18 compras** (México y Colombia juntos).
WooCommerce tuvo **12 pedidos pagados**, y de anuncios pudieron venir como máximo 10.
Día por día, Meta contó una compra por cada pedido **creado**: 17 oct en Colombia, 5 creados, 5 compras para Meta y 2 pagados.

Hay tres emisores de Purchase al pixel `951926154215387`:

| Emisor | Cuándo manda Purchase | `event_id` | Problema |
|---|---|---|---|
| Meta for WooCommerce 3.7.8, servidor (CAPI) | `woocommerce_new_order`, `process_shop_order_meta` y `checkout_update_order_meta`, con estados válidos `processing`, `completed`, `on-hold` **y `pending`** (`track_web_purchase_event`) | UUID propio (`_meta_event_id`) | Sale **al crear el pedido**, antes de pagar. No se corrige si el pago falla. |
| Meta for WooCommerce, navegador | `woocommerce_thankyou` | el mismo UUID | Sale aunque el pedido no esté pagado (pending) |
| GTM-W2PZG3L5 v8, etiqueta 9 (plantilla Facebook Pixel, nombre de evento variable) | Regla 1: `event` ∈ `view_item\|add_to_cart\|begin_checkout\|purchase`. La **misma regla** dispara GA4 (etiqueta 6) | **ninguno** | Meta no la puede deduplicar contra las otras |

El `purchase` del dataLayer lo empuja GTM4WP en "pedido recibido" si el estado es processing, on-hold o completed y el pedido no tiene `_ga_tracked`.

## La solución

**Un solo Purchase por pedido, desde el servidor, cuando se confirma el pago.**

1. **Plugin `tools/storefront/mu-plugins/propuestas/f360-meta-compra-servidor.php`** (en producción va a `produccion/`):
   - **Quita los 4 enganches de `inject_purchase_event` de Meta for WooCommerce.** No hay filtro público para cambiar sus estados válidos, y los métodos son privados. El resto del plugin no cambia: PageView, ViewContent, AddToCart, InitiateCheckout y el catálogo.
   - **Al crear el pedido, guarda `_f360_meta_ctx`** con `_fbp`, `_fbc`, IP, user agent y la URL de pago, tomados del navegador de la clienta. Se usan dos ganchos: checkout de bloques y checkout clásico. En un link de pago (order-pay), se reemplaza con el contexto del navegador que paga.
   - **Al pagarse, agenda una sola acción** en Action Scheduler (única). Se dispara con `woocommerce_payment_complete` o con el estado `processing`/`completed`, así que también funciona cuando ePayco o Mercado Pago confirman después por webhook.
   - **La acción vuelve a revisar todo:** `is_paid()`, el estado, que no tenga ya la marca `_f360_meta_capi`, el origen (`store-api`, `checkout` o `f360_pay_link`) y que el pago no tenga más de 7 días. Luego manda `POST graph.facebook.com/v24.0/951926154215387/events` con:
     - `event_name` Purchase;
     - `event_id` = número de pedido;
     - `event_time` = hora del pago;
     - `action_source` website y `event_source_url`;
     - `user_data`: em, ph (con lada 52/57), fn, ln, ct, st, zp, country y external_id, todos en **SHA-256**; además IP, user agent, fbp y fbc;
     - `custom_data`: value, currency (MXN o COP, la del pedido), content_ids (mismo id que el catálogo, filtro `wc_facebook_fb_retailer_id`), contents, num_items y order_id.
   - **Si funciona:** marca `_f360_meta_capi` = "enviado … fbtrace …" y agrega una nota en el pedido.
   - **Si falla:** reintenta a los 10 min y a la 1 h. Al tercer fallo deja `_f360_meta_capi_error` y una nota. Nunca se marca como enviado si Meta no respondió `events_received: 1`.
   - **Token** en la opción `f360_meta_capi_token`. Se carga con `scripts/f360/set_meta_capi_secret.sh` desde `~/.fuxia-meta-capi.token`, siempre por stdin. Va en el cuerpo del POST, nunca en la URL ni en logs.
   - **Fuera de producción** solo manda con `test_event_code` (opción `f360_meta_capi_test_code`): se ve en "Probar eventos" y no cuenta.
2. **GTM-W2PZG3L5:** hay que publicar una versión nueva (v9) en la que la regla de la etiqueta 9 (Meta) **ya no incluya `purchase`**: `view_item|add_to_cart|begin_checkout`.
   - Hace falta crear un activador propio para Meta. Hoy comparte la regla con GA4, y **GA4 no se toca**.
   - Requiere permiso de edición y publicación en el contenedor; hoy no lo tenemos.
   - Va **el mismo día** que el plugin en producción. Sin v9, el Purchase de GTM sin `event_id` se sumaría al nuestro en los pedidos pagados que vean "pedido recibido".
3. **staging4:** la guardia (`staging4/f360-guardia-staging4.php` v1.1.0) sigue bloqueando todo lo que va a Meta. La única excepción es un POST a `/{v}/951926154215387/events` con `test_event_code`.

## Pruebas

`scripts/f360/test_meta_compra_staging4.sh` corre `tools/storefront/tests/meta_compra_servidor_staging4.php`:
- Meta for WooCommerce se activa **solo en ese proceso** (`meta_cargar_plugin_fb.php`). En staging4 está apagado porque tiene la conexión de producción.
- Todo request a Meta queda bloqueado y registrado.

**2026-11-03: 36 de 36 pasan. Se crearon 14 pedidos de prueba y se borraron todos.**

| Caso | Resultado |
|---|---|
| Enganches de Purchase de Meta for WooCommerce | Se quitaron los 4; no queda ninguno |
| Control: el plugin llamado a mano con un pedido en pending | Manda Purchase. Confirma la causa |
| Crear pedido + `checkout_update_order_meta` + "pedido recibido" sin pagar | 0 Purchase y nada agendado |
| on-hold, failed, cancelled | 0 |
| Mercado Pago pending → webhook → processing | 1 envío al pixel. event_id = número de pedido; MXN; valor = Woo; content_ids = variaciones; hashes correctos; fbp, fbc, IP y user agent; URL de pago; marca puesta |
| Repetir payment_complete, completed, refunded | Nada |
| ePayco: 3 webhooks + completed | 1 envío, COP, teléfono con 57 |
| Pagado y cancelado antes del envío · creado en el admin · pago de hace 8 días | No manda (el último queda "omitido") |
| Link de pago | Manda con el contexto del navegador que pagó |
| Captura al crear el pedido | `_fbp` válido guardado; `_fbc` inválido descartado; URL sin parámetros |
| Errores: http 500 tres veces · `events_received` 0 | Sin marca; reintentos; error y nota al tercero; un reintento exitoso marca una sola vez |
| Datos personales | Solo SHA-256 (IP y user agent en claro, como pide Meta) |
| Lo que el plugin intentó mandar en toda la prueba | Solo el Purchase del control |

**Falta:** la prueba real en "Probar eventos", con un pedido MX y uno CO pagados (exactamente 1 Purchase cada uno) y un pedido fallido, cancelado o pendiente (0). Necesita el token y el código de prueba de Mario. Ahí van las capturas.

## Pasos que quedan

1. **Mario:** en Events Manager → pixel → Configuración → Conversions API → "Generar token de acceso", y luego `! pbpaste > ~/.fuxia-meta-capi.token && chmod 600 ~/.fuxia-meta-capi.token`. También pasar el código de "Probar eventos" (TEST…), que no es secreto.
2. `scripts/f360/set_meta_capi_secret.sh staging4 TEST…`, luego `scripts/f360/test_meta_compra_staging4.sh` (el caso 13 manda MXN y COP reales a Probar eventos) y un pedido fallido. Capturas para Mario.
3. **GTM v9** con acceso al contenedor. Se prueba antes en Preview.
4. **Producción, con OK de Mario después de las capturas:**
   - mover el plugin a `produccion/`;
   - `set_meta_capi_secret.sh produccion`;
   - `deploy_prod_wp.sh` (incluye la prueba como clienta);
   - publicar GTM v9 el mismo día.
5. **Primera venta pagada en producción:** revisar que tenga `_f360_meta_capi` = "enviado" y que Events Manager muestre 1 Purchase de servidor.

**Rollback:** borrar el archivo de `wp-content/mu-plugins/`, con lo que Meta for WooCommerce vuelve a mandar su Purchase, y en GTM, Versions → v8 → Publish.

## Antifraude de Mercado Pago en /mx/ (revisado el 2026-11-03)

- **Prueba:** Playwright en producción, computadora y celular, hasta la pantalla de pago, sin pagar. Checkout de bloques.
- **Lo que pasa hoy:**
  - `https://www.mercadopago.com/v2/security.js` carga (lo inyecta `session.min.js` del plugin al `load`).
  - `window.MP_DEVICE_SESSION_ID` existe (`armor.…`, 231 caracteres).
  - `#mpCardSessionId` está vacío al cargar, pero `build/custom.block.js` lo llena con `MP_DEVICE_SESSION_ID` al pagar (`onPaymentSetup`).
  - El plugin lo manda como encabezado `x-meli-session-id` (`src/Api/Core/PaymentsClient.php:49`).
  - SiteGround no combina ni difiere los scripts de Mercado Pago: 0 combinados, 0 con retraso.
  - WPCode y el tema hijo no tocan esos scripts.
- **Pedidos #6144 y #6145, consultados a la API de Mercado Pago:** los 3 pagos (187395537506, 187439406734 y 186342810807) salieron `rejected / cc_rejected_high_risk`. Fue la misma Visa (emisor 158), a 3 meses, desde el navegador de Instagram en iPhone; el de #6145 fue por link de pago. `three_ds_info` = null, así que no se intentó 3-D Secure.
- **Conclusión:** nada nuestro bloquea el antifraude; el rechazo lo decidió el motor de riesgo de Mercado Pago. Que el navegador de Instagram influya o que 3-D Secure lo hubiera salvado es **una hipótesis sin verificar**. Se pregunta a Mercado Pago con los 3 IDs.
