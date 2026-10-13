# GA4: compra desde el servidor (Measurement Protocol)

**Estado: EN PRODUCCIÓN desde el 2026-10-13 a las 19:06 (cf32dac).** Mario autorizó ("si dale tu por fa"), aceptó los términos de Measurement Protocol, guardó el secreto (`f360_ga4_mp_secret`, 22 caracteres) y corrió `deploy_prod_wp.sh`. Prueba como clienta: 74 productos OK. Respaldo: `~/f360-backups/prod-mu/20261013-190608/`. **Pendiente:** revisar la primera venta pagada (paso 4).

| | |
|---|---|
| Fecha | 2026-10-13 |
| Autorización | Mario, 2026-10-13: "SÍ AUTORIZO preparar… únicamente revisar y probar el plugin en staging4, utilizando el endpoint de validación". Excluye: instalar en producción, crear o usar secretos de producción, enviar eventos a la propiedad real y modificar GTM4WP en producción |
| Plugin | `tools/storefront/mu-plugins/produccion/f360-ga4-compra-servidor.php`. El espejo de staging4 lo reinstala la copia nocturna en modo validación |
| Prueba | `tools/storefront/tests/ga4_compra_servidor_staging4.php`, que corre con `scripts/f360/test_ga4_compra_staging4.sh` |
| Instalación en staging4 | `scripts/f360/deploy_staging4_wp.sh --propuesta f360-ga4-compra-servidor.php` |
| Por qué hace falta | `ANALISIS_WEB_2026-06_A_2026-10.md` §2: GA4 vio 26 de 56 ventas pagadas, y ninguna de Colombia |

## Causa confirmada en el código de GTM4WP 2.0.6

- `ProductData::is_order_status_trackable` solo empuja el `purchase` si el pedido está en un estado de la lista `WCPURCHASESTATUSES` (por defecto: processing, on-hold, completed) **cuando carga la página de gracias**.
- Con Mercado Pago, el pedido sigue en `pending` en ese momento.
- Con ePayco y la tarjeta de PayPal, la clienta no regresa a la página.

## Resultado en staging4 (2026-10-13)

- Woo 11.2.1, **con HPOS activo**.
- **34 de 34 pruebas pasan.**
- Los 29 pedidos de prueba se borraron; quedan 0.
- Ninguno llegó a Supabase de staging.
- "Comprar como clienta" en staging4, con el plugin puesto: 70 productos revisados en computadora y celular, carrito y pago OK.

| # | Lo que pidió Mario | Cómo se probó | Resultado |
|---|---|---|---|
| 1 | Solo se manda si el pedido está realmente pagado | Pedidos en `pending`, `on-hold` y `failed`, más uno pagado y cancelado antes del envío. El plugin vuelve a revisar `is_paid()` y el estado justo antes de enviar | Ninguno manda nada |
| 2 | ePayco, PayPal, Mercado Pago y pagos asíncronos | MP: `pending` → webhook → `processing`. ePayco (COP): 3 webhooks y luego `completed`. PayPal tarjeta (COP) y PayPal (USD): `payment_complete()` | Un envío por pedido, con la moneda correcta. **Límite:** en staging4 ePayco y PayPal están apagados por diseño (copia nocturna), así que se simuló lo que hacen esas pasarelas al confirmar: `payment_complete()` o el cambio de estado |
| 3 | Deduplicación con GTM4WP | **El navegador primero** (`_ga_tracked`=1 antes del pago): no agenda nada. **El navegador durante la espera de 2 min:** la acción no manda. **El servidor primero:** deja `_ga_tracked`=1, la misma marca que GTM4WP revisa (`ProductData::is_purchase_already_tracked`). **Confirmaciones repetidas:** `payment_complete` otra vez y luego `completed` no agendan nada. **Reintentos del webhook antes del envío:** 3 webhooks dejan una sola acción. **Cambios de estado después del envío:** `completed` y `refunded` no hacen nada | Sin duplicados |
| 4 | HPOS y metadatos de Woo | Staging4 tiene HPOS activo, como producción tras la copia. El plugin solo usa la API de pedidos de Woo (`get_meta`, `update_meta_data`, `save`). Las metas propias empiezan con `_f360_`. Además lee y escribe `_ga_tracked`, la marca de GTM4WP | Pasa |
| 5 | Nada personal | Pedidos con nombre, correo, teléfono, dirección, código postal, nota e IP falsos (`PRUEBAPII`). Se revisaron los 9 requests | Ninguno sale. Campos enviados: `client_id`, `events`, `timestamp_micros`, `transaction_id`, `value`, `currency`, `tax`, `shipping`, `items` (id, nombre, talla y color, categoría, precio, cantidad), `engagement_time_msec`, `session_id`, y `coupon` si hay cupón |
| 6 | Consentimiento y sin `client_id` | La tienda **no tiene** banner de cookies ni Consent Mode (revisado en el HTML de producción). **Regla:** solo se usa el `client_id` que la clienta ya tenía en su cookie `_ga`. **Sin cookie no se manda nada**, y el pedido queda con `_f360_ga4_mp` = "omitido…". Esto incluye a quien bloqueó Analytics y a los links de pago creados por Fuxia 360 (`created_via` = `f360_pay_link`), que se crean sin navegador. El filtro `f360_ga4_mp_permitido` queda listo para un futuro banner | Las dos pruebas pasan |
| 7 | `transaction_id`, moneda, importes y productos | Se compara contra el pedido de Woo | Coinciden: número de pedido, moneda, total (envío incluido, igual que GTM4WP), y por cada línea id del producto padre, cantidad y precio con descuento |
| 8 | Errores y reintentos | Simulación de http 500 y de "Google rechaza el formato" | **Nunca se marca como enviado si Google no lo aceptó.** 3 intentos (ahora, +10 min, +1 h), siempre con el mismo `client_id`. Después se detiene y deja `_f360_ga4_mp_error` y una nota. Si un reintento sale bien, se marca una sola vez |
| 9 | Secretos | En staging se usa un marcador (`staging-solo-validacion`); el debug no lo valida | El secreto de producción iría en la opción `f360_ga4_mp_secret` de WordPress, nunca en el repo. Los logs solo llevan el código de error, nunca la URL; `str_replace` enmascara el secreto. Action Scheduler solo guarda el motivo |
| 10 | Reporte y rollback | Este documento | Abajo |

### Ejemplo real validado por Google (debug, nada registrado)

```json
{"client_id":"1111111111.2222222222","events":[{"name":"purchase","params":{"transaction_id":"5696","value":5600,"currency":"MXN","tax":0,"shipping":0,
 "items":[{"item_id":"5614","item_name":"Lazo","price":2800,"quantity":1,"item_variant":"negro,35","item_category":"Ballerinas"},
          {"item_id":"5605","item_name":"Tango","price":2800,"quantity":1,"item_variant":"negro,35","item_category":"Ballerinas"}],
 "engagement_time_msec":1,"session_id":"1760000000"}}],"timestamp_micros":"1791928004000000"}
```

## Riesgos y límites que quedan

- **Captura del `client_id` en un checkout real.** Se probó con las cookies simuladas y con los dos formatos de cookie de GA4 (GS1 y GS2), no con una compra real en el navegador. La primera venta en producción se revisa a mano: tiene que tener `_f360_ga_cid` y `_f360_ga4_mp`.
- **Duplicado residual.** GTM4WP escribe `_ga_tracked` cuando confirma que el navegador entregó el evento. Si el navegador dispara en los mismos segundos en que el servidor manda, GA4 deduplica el `purchase` por `transaction_id` con el mismo `client_id`. Ese es el mismo mecanismo con el que GTM4WP evita sus propios duplicados.
- **Producción valida antes de enviar.** `/mp/collect` responde 2xx aunque el evento sea inválido, así que en producción el plugin primero valida con `/debug/mp/collect` y solo si no hay errores manda a `/mp/collect`.
- **No recupera el histórico.** GA4 solo acepta eventos de hasta 72 horas atrás. Los 30 pedidos que faltan de junio a octubre no se pueden enviar por Measurement Protocol; solo se recuperarían con una importación de datos.
- **No cambia la página de gracias ni GTM4WP.** Colombia seguirá sin regresar a "pedido recibido". Eso es experiencia de pago, no medición.
- **Staging4 lo pierde cada noche.** La copia nocturna solo reinstala los espejos de `produccion/`, así que la propuesta desaparece de staging4. Se vuelve a instalar con el comando de arriba.

## Pasos para producción (requieren la autorización expresa de Mario)

1. **Mario crea el secreto.** GA4 → Administrador → Flujos de datos → "Fuxia Ballerinas - Web" (G-8C1244627P) → Secretos de la API de Measurement Protocol → Crear. No se pega en el chat.
2. **Mario guarda el secreto por SSH.** `wp option add f360_ga4_mp_secret '<secreto>' --autoload=no` en `~/www/fuxiaballerinas.com/public_html`.
3. **Mover el plugin a producción.** `git mv` de `propuestas/f360-ga4-compra-servidor.php` a `produccion/`, regenerar el espejo, commit, y Mario corre `scripts/f360/deploy_prod_wp.sh`. Ese script instala todos los archivos de `produccion/` y luego corre la prueba de comprar como clienta.
4. **Verificar** la primera venta pagada:
   - nota "compra enviada a Google Analytics";
   - `_ga_tracked` = 1;
   - el `transaction_id` aparece en GA4 (Data API, al día siguiente).

## Rollback

- **Producción:** borrar `wp-content/mu-plugins/f360-ga4-compra-servidor.php`, o restaurar desde `~/f360-backups/prod-mu/<ts>/`. Las metas `_f360_*` no afectan nada más. Lo que ya llegó a GA4 no se puede borrar de GA4.
- **Staging4:** borrar el mismo archivo. Respaldo: `~/f360-backups/staging4-mu/20261013-184557/`.
- **Secreto:** `wp option delete f360_ga4_mp_secret` y revocarlo en GA4, en la misma pantalla del paso 1.
