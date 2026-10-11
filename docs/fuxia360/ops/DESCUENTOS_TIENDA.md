# Descuentos en la venta de tienda

**Decisión:** Mario, 2026-10-11. **Estado:** en STAGING. Producción, pendiente (ver §7).
Este documento cambia la decisión Q3 del Sprint 0, que decía "las vendedoras no descuentan" (`docs/fuxia360/audit/SPRINT_0_IMPLEMENTATION_PLAN.md`).

## 1. Reglas (Mario; ninguna inventada)
| Regla | Cómo queda |
|---|---|
| Forma | **Un solo porcentaje sobre toda la venta.** No es por par ni un monto en pesos. |
| Vendedora | Puede dar **hasta 10 %** sola. |
| Más de 10 % | Lo aprueba **Carolina**, de dos formas: escribe **su PIN en el teléfono de la vendedora** si está en la tienda, o **aprueba una solicitud** desde Fuxia 360 → Avisos si no está. |
| Carolina con su propio turno | Puede dar cualquier porcentaje. |
| Quién es "Carolina" | Quien tenga el permiso `store_discount` en `f360.approval_scopes`. En producción, **solo Carolina**. Tener rol owner **no basta**, porque Mario y Adrián también son owners. |
| Cambios | Un par vendido con descuento **no tiene cambio** (`offline_sales.no_exchange`). La app lo muestra antes de cobrar y en la pantalla de venta lista. |

## 2. Qué decide el servidor
- **La app manda solo** el porcentaje y, si pasa de 10 %, la referencia de la aprobación.
- **El servidor pone** el precio de lista, el subtotal, el monto del descuento, el total neto y quién lo autorizó.
- **Una aprobación sirve para una sola venta y caduca a los 30 minutos.** Además debe coincidir exactamente con la venta: misma vendedora y tienda, mismos productos y cantidades, mismo subtotal y mismo porcentaje. Si cambia el precio o la bolsa, hay que pedirla de nuevo.
- **Solicitud remota:** vence a los 15 minutos si nadie la decide.
- **PIN de Carolina:**
  - Tras 5 intentos equivocados en 15 minutos, se rechaza incluso el PIN correcto.
  - Cada intento queda registrado en `f360.seller_auth_events`.
  - El PIN de Mario no aprueba.
- **Montos:**
  - Cada renglón conserva su `unit_price` de lista y guarda su `line_total` **neto**; el centavo del redondeo va al último renglón. Así Σ renglones = total, y los reportes (`commerce_orders`) lo cuentan **VERIFIED** con el **neto**.
  - Esos reportes todavía muestran el descuento de tienda como 0, es decir, cuentan la venta neta. El detalle del descuento está en `offline_sales`.
- **Club Fuxia:** los puntos siguen siendo por par (sin cambio). Se registran el monto neto y el precio unitario neto.

## 3. Archivos
| Archivo | Qué |
|---|---|
| `supabase/migrations/20261025000100_f360_store_discounts.sql` | Scope `store_discount`; columnas de descuento en `offline_sales`; tabla `f360.store_discount_requests`; RPCs de política, PIN, solicitud, estado, bandeja y decisión. `f360_record_store_sale` y `_for` reciben dos parámetros **opcionales**, así que la app publicada sigue funcionando. |
| `supabase/rollbacks/20261025000100_f360_store_discounts.down.sql` | Reversión. Conserva las columnas, porque son historial. |
| `supabase/staging/f360_store_discounts_tests.sql` | Pruebas D1–D20 (39 verificaciones). |
| `scripts/f360/sql_test_one.mjs`, `scripts/f360/staging_apply_migration.mjs` | Correr un solo archivo de pruebas en staging, y aplicar una sola migración en staging sin arrastrar las de otras sesiones. |
| `fuxia-native/components/SaleDiscount.tsx`, `app/vendedora/venta.tsx`, `lib/f360Store.ts` | En "Cobrar": Sin descuento / 5 % / 10 % / Otro; desglose; motivo opcional; "Carolina está aquí · su PIN" o "Enviar a Carolina" (con espera y respuesta). Si el servidor no tiene descuentos, el bloque no aparece y la venta sin descuento hace la llamada de siempre. |
| `admin-web/src/app/(app)/avisos/DiscountInbox.tsx`, `avisos/page.tsx`, `actions.ts` | "Descuentos por aprobar" en Avisos, solo para quien aprueba: Aprobar / No aprobar, nota, actualización cada 10 s, últimos 7 días. |

## 4. Seguridad
- **Tablas:** `f360.store_discount_requests` solo es accesible para `service_role`. Las apps usan RPCs `SECURITY DEFINER`.
- **Acceso:** anónimos no tienen acceso (D15).
- **Quién aprueba:** se comprueba con `f360.can_approve('store_discount', auth.uid())`. Ni la vendedora ni Mario pueden aprobar (D10c/D10d/D13a).
- **El precio nunca viene de la app** (D5b).
- **Riesgo que ya existía y sigue abierto:** la pantalla vieja `app/vendedora/sale.tsx` y las políticas RLS de `offline_sales` todavía dejan escribir el total desde el teléfono en tiendas que no están en Fuxia 360. Eso evita cualquier tope en esas tiendas. Cerrarlo es la tarea A2 pendiente (`supabase/pending/s00a/…_a2_remove_anon_operational_access.sql`).

## 5. Verificación
- **Staging:** `scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/f360_store_discounts_tests.sql` → **39 PASS / 0 FAIL**. Cubre límites, porcentajes inválidos, PIN equivocado y correcto, uso único, que la venta cambie (productos, porcentaje, precio), solicitud remota (pendiente, aprobada, rechazada, vencida), quién no puede aprobar, turno propio de Carolina y de Mario, bloqueo por PIN, acceso anónimo, repetición de la misma venta, la llamada de la app actual, `_for`, los reportes y el inventario.
  - La primera corrida encontró un error real (no se podía cancelar una aprobación previa) y se corrigió.
- **Migración aplicada en staging** con `staging_apply_migration.mjs`.
- **Sin correr:** la regresión completa `db_tests.mjs`. Staging ya no tiene las usuarias de laboratorio `1555010001x` ni una única "Carolina", porque otra sesión cambió los datos. Volver a sembrarlas requiere el OK de Mario.
- **Compilación:** `tsc` de fuxia-native y del admin, y `eslint` del admin: OK.

## 6. Criterios de aceptación
- [x] Una vendedora cobra con 0–10 % sin pedir nada; con más de 10 % la venta no pasa sin la aprobación de Carolina.
- [x] Carolina aprueba con su PIN en la tienda, o desde Avisos con la vendedora esperando en su teléfono.
- [x] Cada venta con descuento guarda el porcentaje, el monto, el motivo, quién lo autorizó y cómo, y queda marcada "sin cambio".
- [ ] Probado a mano en el teléfono de una vendedora y en el admin de Carolina (staging), después del pase.

## 7. Para producción
1. **Depende de `20261024000100`** (`f360.approval_scopes`, del trabajo de tipos de cambio de otra sesión), que todavía **no está en producción**. Se aplica antes, o se extrae `approval_scopes` a su propio pase.
2. Pase: la migración + `INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name) VALUES ('store_discount', <Carolina prod>, 'Carolina', 'Mario 2026-10-11')`.
3. **Carolina necesita un PIN** (Vendedoras → PIN) para aprobar en la tienda.
4. Después: desplegar el admin y publicar la app (OTA iOS 1.0.1 y Android 1.0.2). Antes de eso no se ve nada, por diseño.
