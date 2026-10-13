# D12 · Fase B: migración progresiva a cuentas individuales — PLAN TÉCNICO v2 (no ejecutado) — 2026-10-13

> **Autorización de Mario (2026-10-13):** preparar el plan técnico, con migración progresiva de las tiendas a cuentas individuales.
> **No** se cierra todavía el acceso anónimo, **no** se rotan NIP y **no** se modifica producción.
> **Condiciones:** no fusionar tiendas, no alterar inventarios, no modificar ventas históricas, no vincular identidades por inferencia.
>
> v1 (2026-10-11) proponía un cierre único. Esta v2 lo reemplaza por **oleadas por tienda**: cada tienda pasa a cuentas F360 mientras la app anterior **sigue funcionando** para las que no han pasado. El acceso anónimo se cierra solo al final (§5) y con nueva autorización.
>
> Fuentes: consultas de solo lectura en producción (2026-10-11 y 2026-10-13). Detalle en `D12_INVESTIGACION_2026-10-13.md` y `../ops/AJUSTES_POSIBLES_VENTAS_2026-10-13.md`.

## 1. Situación de partida (producción, 2026-10-13)
| Tienda / canal | Cómo vende hoy | Vendedoras F360 | Ventas F360 | App anterior (60 d) | Qué falta |
|---|---|---|---|---|---|
| **Tienda Polanco** (F360) | turno F360 desde el 8-oct; app anterior hasta el 5-oct | Carolina Muñoz, Valeria García, Valeria Pérez y Reyna Vega: activas, con cuenta | 9 desde el 8-oct | 6 (Reyna 5, "Valeria" 1) | quitar la entrada a la app anterior **cuando Carolina confirme** que nadie la usa |
| **Amsterdam 264** (F360) | **sin vendedoras ni ventas F360**; las ventas aparecen como *ajustes de salida* ("vendido semana 5-10 oct") | ninguna | 0 | — | dar de alta a sus vendedoras y abrir turno F360 |
| **San Jerónimo Lídice** (F360) | sin ventas F360 | Dulce Sur, **pendiente** (sin cuenta) | 0 | — | que active su cuenta; confirmar la relación con Contreras (§1.1) |
| **La Noria** (F360) | sin ventas F360 | ninguna | 0 | — | vendedoras y turno |
| **Torreón** (F360, bazar) | sin actividad | ninguna | 0 | — | cuando vuelva a operar |
| **Guadalajara** (solo app anterior, bazar) | app anterior con NIP | ninguna; **no existe la ubicación F360** | 0 | 27 (Paola 24, Chelita 3); última el 30-sep | ubicación, conteo y cuentas (§3, oleada 3) |
| **Contreras** (solo app anterior) | app anterior con NIP | — | 0 | 1 (17-sep) | **sin decisión**: no se fusiona con San Jerónimo sin evidencia |
| Monterrey / Cali (app anterior) | sin ventas desde mayo / nunca | — | 0 | 0 | Cali no entra a F360 (casa matriz); Monterrey por decidir |

### 1.1 Restricciones que este plan respeta
- **Contreras y San Jerónimo** siguen separadas: no se vincula `legacy_channel_id` ni se suman inventarios hasta que Carolina lo confirme.
- **"Valeria" anterior ↔ Valeria García/Pérez:** no se vincula. El retiro de la app anterior en Polanco **no requiere** saber cuál es: basta con que ninguna vendedora de Polanco vuelva a usar el NIP anterior.
- **Inventario:** los 5 pares de Guadalajara, los 153 de Contreras y demás saldos de la app anterior **no se migran** sin conteo físico.

## 2. Mecanismo técnico (ya existe en producción; no hay que construirlo)
| Necesidad | Pieza existente |
|---|---|
| Alta de vendedora (nombre, WhatsApp, tienda, NIP) | `f360_admin_seller_add` (pantalla Vendedoras del admin web) |
| NIP cifrado con bcrypt y bloqueo por intentos | `f360.sellers.pin_hash`, `f360.seller_credentials` |
| Cuenta propia | inicio de sesión por WhatsApp; la cuenta se vincula a `f360.sellers` |
| Turno ligado a una sola tienda | `f360_start_seller_shift`, `f360_seller_session` |
| Venta con precio y puntos calculados por el servidor; baja de inventario atómica | `f360_record_store_sale` (con `p_customer_qr`) |
| Apartados y descuentos con autorización | `f360_reservation_*`, `f360_store_discount_*` |
| Ajuste de inventario auditado | `f360_adjust_inventory` (operadora o dueña) |
| Cambio de tienda, NIP nuevo, baja | `f360_admin_seller_set_store`, `_reset_pin`, `_deactivate` |
| Devoluciones y cambios | **no existe**. Diseño en `../ops/DEVOLUCIONES_DISENO.md`; requiere decisión de negocio |

**Pieza nueva, pequeña, solo de la app:** un interruptor por tienda para que su personal anterior ya no vea la pantalla de NIP.
- Propuesta: `public.channels.legacy_pin_enabled boolean DEFAULT true`, leído por `vendedora/index.tsx`.
- No cierra la base de datos (eso es §5). Solo guía a cada tienda migrada al turno F360. Se publica por OTA.
- **Requiere su propia autorización:** cambio de esquema y de app.

## 3. Oleadas (cada una con ensayo en staging, aviso a las sesiones 2d y d5, y "sí" de Mario/Carolina)
**Oleada 1 · Polanco (ya tiene cuentas).**
1. Carolina confirma qué vendedoras están activas y que todas venden con su turno F360.
2. Durante 14 días se vigila que no haya ventas de la app anterior en Polanco (`offline_sales.created_by_rpc = false`).
3. `legacy_pin_enabled = false` para Polanco y desactivar en `public.staff` a Reyna y "Valeria" de Polanco (`active = false`, no se borran).

**Oleada 2 · Amsterdam 264, La Noria y San Jerónimo Lídice** (ubicaciones F360 sin turno de venta).
1. Alta de sus vendedoras con WhatsApp real (Carolina); Dulce Sur activa su cuenta.
2. **Primer día acompañado:** cada venta por turno F360, no por ajuste. Así se termina la práctica de "vendido semana …" como ajuste.
3. **No se reconstruyen** las ventas ya registradas como ajustes: reporte aparte, solo para revisión.

**Oleada 3 · Guadalajara (bazar).** Depende de decisiones de Carolina (cuestionario).
1. Crear la ubicación F360 "Guadalajara", tipo `bazaar`.
2. **Conteo físico** como inventario inicial. Si hay mercancía nueva, transferencia desde Bodega CDMX.
3. Alta de Paola y Chelita Gómez con su WhatsApp real.
4. La app anterior sigue activa hasta el primer bazar completo en F360. Después: 14 días sin ventas de la app anterior, interruptor apagado y personal anterior desactivado.

**Oleada 4 · Contreras, Monterrey y Cali.**
- Solo con decisión explícita: Contreras (¿= San Jerónimo?), Monterrey (¿opera?), Cali (casa matriz, fuera de F360).
- Si no operan: desactivar su personal anterior. **Sin borrar historial.**

### Pruebas en cada oleada (staging, identidades ficticias, BEGIN…ROLLBACK)
- **Venta:** turno → venta con y sin clienta → baja el inventario de F360 exacto → puntos solo por el servidor → idempotencia (doble envío = una sola venta).
- **Ajuste de inventario:** la operadora ajusta; queda en el ledger con actor y motivo; la vendedora **no** puede ajustar.
- **Devolución o cambio:** cuando exista (§2), las pruebas D1–D8 del diseño.
- **Apartado y descuento:** como en sus suites (`f360_store_discounts_tests.sql`, `f360_reservations_tests.sql`).
- **Regresión de la fase A:** `test_d12_phase_a.sql`.

## 4. Fallas de autenticación (día de cada oleada)
| Falla | Respuesta |
|---|---|
| NIP olvidado o bloqueado | La admin hace `f360_admin_seller_reset_pin`; el NIP se da en persona |
| No llega el código de WhatsApp | La operadora o dueña abre el turno de esa tienda en su teléfono (su rol lo permite) |
| La app o Supabase caídos | Venta en papel (folio, artículos, pago, teléfono de la clienta) y captura posterior auditada por la operadora |
| Algo sale mal en una oleada | `legacy_pin_enabled = true` para esa tienda y reactivar su personal anterior: la app anterior vuelve el mismo día. No hay migración de base que revertir |

## 5. Cierre técnico final (NO autorizado; solo cuando §6.1–6.3 se cumplan)
1. Quitar `anon_read_active_staff`, `anon_insert_offline_sales`, `anon_read_offline_sales`, `anon_read_own_sales` y `anon_update_inventory_sold`, más `admins_all_inventory` y `admins_all_channels` (`user_metadata`), con la reversión ensayada.
2. Quitar los permisos de tabla de `anon` sobre las tablas de la app anterior.
3. **App:** quitar la pantalla de NIP anterior (OTA).
4. **`claim-sale`:** quitar `scan_qr` (puntos con el total del cliente) y llevar el reclamo a `f360_claim_store_sale`.
5. **Rotación de NIP** (no autorizada aún):
   - todos los NIP de `public.staff` se consideran expuestos;
   - ninguno se reutiliza en F360 (ya se comprobó que ninguno coincide);
   - al desactivar el personal anterior, el NIP queda sin uso;
   - en el cierre se vacía la columna o se reemplaza por un hash.

**Contingencia, si una tienda no puede migrar a tiempo:** NIP validado en el servidor.
- `d12_legacy_shift_start(p_channel, p_pin)` compara contra `staff.pin_hash` (bcrypt), con bloqueo por intentos, y devuelve un token de turno de 8 h. **Nunca** devuelve el NIP ni la lista del personal.
- `d12_legacy_sale(p_token, …)` toma el precio de `channel_inventory.price`, baja de forma atómica sin negativos, pone `created_by_rpc = true` y aplica puntos con `loyalty_apply`.
- `anon` solo podría ejecutar esas dos funciones.

## 6. Criterios de cierre definitivo de D12
1. Todas las tiendas que operan pasaron su oleada. Hubo 14 días sin ventas de la app anterior (`created_by_rpc = false`) antes del cierre técnico.
2. Toda vendedora activa tiene cuenta F360 (`status = 'activa'`, `auth_user_id` no nulo). El personal anterior está desactivado, salvo donde Mario apruebe la contingencia.
3. Las tiendas F360 venden por turno, no por ajuste: hubo 14 días sin "Ajuste · vendido…" (reporte de ajustes).
4. Cierre técnico (§5) aplicado. Prueba anónima con la llave pública: 0 filas y 0 escrituras en las tablas de la app anterior.
5. `claim-sale` sin `scan_qr` o despublicada. NIP rotados o eliminados.
6. `SECURITY_FINDING_2026-10-11_LEGACY_RLS.md` marcado como **cerrado**, con evidencia.
