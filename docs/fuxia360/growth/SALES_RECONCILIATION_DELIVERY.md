# Conciliación de Ventas — entrega en STAGING (2026-10-10)

> Producción, WooCommerce y pasarelas **no tocados**. P0D no importado. Staging: `fuxia360-staging.vercel.app/growth?vista=conciliacion` (pestaña **Conciliación**, solo Carolina y Mario).
> Diseño aprobado: `SALES_RECONCILIATION_DESIGN.md` + decisiones de Mario del 2026-10-10.

## 1. Qué se construyó
| Pieza | Archivo |
|---|---|
| Migración (aditiva) | `supabase/migrations/20261022000100_f360_sales_reconciliation.sql` |
| Rollback | `supabase/rollbacks/20261022000100_f360_sales_reconciliation.down.sql` (borra decisiones/evidencias/exclusiones registradas; Commerce Facts intacto) |
| Pruebas SQL | `supabase/staging/test_sales_reconciliation.sql` R1–R15 |
| Evidencia Woo (solo lectura) | `fuxia-native/supabase/functions/_shared/f360-woo/evidence.ts`, acción `order_evidence` en `f360-woo-sync/handler.ts`, `listOrderNotes` en `commerce.ts`; pruebas `test/evidence.test.ts` |
| Pantalla | `admin-web/src/app/(app)/growth/Conciliacion.tsx`, `ConciliacionForms.tsx`, `conciliacion-actions.ts`, `src/lib/sales-rec.ts`, `sales-rec-labels.ts`; E2E `admin-web/e2e/conciliacion.spec.ts` |

**Base de datos.** Tres tablas append-only (trigger `reject_audit_change`, RLS sin políticas, sin grants a `anon`/`authenticated`):
- `f360.sales_rec_evidence` — foto mínima por consulta: fuente + referencia (`woo_staging4:order/N`), estado Woo, fecha de pago, referencia de transacción, método, total, moneda, reembolso, resultado, códigos de señal, huella sha256, quién y cuándo. Sin texto de notas, sin datos de la clienta y sin nada con forma de tarjeta: un valor de 13 a 19 dígitos se descarta y queda la señal `tx_redacted`.
- `f360.sales_rec_decisions` — decisión, comentario, "duplicado de", evidencia vista, estado Woo y estado financiero que la persona vio, a qué decisión reemplaza, quién y cuándo.
- `f360.sales_rec_exclusions` — excluir/incluir en métricas, con motivo obligatorio, quién y cuándo.

Vistas derivadas (no copian pedidos): `f360.sales_rec_cases` / `sales_rec_cases_state`, que leen `commerce_woo_orders`, las líneas y los reembolsos, y calculan marcas y estados.

RPCs, todas con `f360.require_pii_viewer()` (Carolina y Mario): `f360_rec_list`, `f360_rec_summary`, `f360_rec_case`, `f360_rec_decide`, `f360_rec_set_analytics` y `f360_rec_can_view`. `f360_rec_evidence_record` es **solo service role**: la llama la función después de verificar a la persona, y vuelve a revisar que el actor sea viewer.

**Evidencia en WooCommerce.**
1. `f360-woo-sync` valida el JWT de la persona y, con su propio token, que sea viewer **antes** de leer nada.
2. Luego hace **solo GET** de `/orders/{id}` y `/orders/{id}/notes`.
3. El número de transacción sale de `transaction_id` (ePayco, PayPal) o, si está vacío, de metas en lista blanca (`_Mercado_Pago_Payment_IDs`, porque Mercado Pago no llena `transaction_id`).
4. El resultado de la pasarela sale de la última nota del sistema que mencione a la pasarela. Las notas de cambio de estado de Woo y las de la clienta no cuentan.
5. Se devuelven para verse, **sin guardarse**: el nombre y correo de la clienta y las notas de la pasarela con correos, teléfonos y números largos ocultos.
6. Si Woo ya no tiene el pedido, eso se registra como evidencia (`order_missing`).

## 2. Los cinco estados (separados)
| Estado | De dónde sale | Lo cambia una persona |
|---|---|---|
| Estado WooCommerce | `commerce_woo_orders.woo_status` | No |
| Evidencia financiera | Commerce Facts + última consulta a Woo: Sin cobro · Woo registró pago (pasarela sin consultar) · Pago con transacción de la pasarela · Pago sin transacción · Contradictoria · Reembolsado/parcial · Ya no existe en Woo | No |
| Clasificación humana | `sales_rec_decisions` (la última; el historial completo queda) | Sí |
| Conciliación | Calculado: Discrepancia sin revisar · Por revisar · Cambió después de revisar · En investigación · Conflicto · Revisado · Sin novedad | No (es derivado) |
| Métricas | `sales_rec_exclusions` | Sí, acción aparte con motivo |

Ejemplos de **conflicto**:
- "Venta confirmada" sobre un pedido sin cobro, sin transacción, con evidencia contradictoria, reembolsado o inexistente en Woo.
- "No se concretó" sobre un pedido pagado y sin reembolso.
- "Prueba" o "Duplicado" con pago y sin reembolso.
- "Reembolso" sin reembolso en Woo.

Si Woo cambia después de una revisión (otro estado u otros montos), el pedido vuelve a la cola como **"Cambió después de revisar"**.

## 3. Marcas (cada una dice por qué)
- **Financieras:**
  - Pagado y cancelado (sin reembolso).
  - Pagado sin evidencia: sin fecha de pago, sin método, o consultado y sin transacción.
  - Evidencia contradice: nota "rechazado" con pago en Woo, o "aprobado" sin pago.
  - Ya no está en Woo (si tenía pago).
- **No se concretó:** nunca pagado. Si la clienta repitió el mismo carrito y pagó en menos de 48 h, se marca además **"Reintentó y pagó"** con el pedido pagado, para que no se lea como venta perdida.
- **Para revisar:**
  - Posible prueba: método de prueba, o pagado por 0.
  - **Posible duplicado:** solo **candidato**. Exige dos pedidos *pagados* con el mismo total, los mismos productos y misma clienta (o sin cuenta) en menos de 48 h. Nunca se decide solo.
- **Reembolso:** registrado en Woo.

## 4. Lo que dice staging hoy (92 pedidos reales de staging4)
| | Pedidos | Por revisar | Con marca financiera | No concretados |
|---|---|---|---|---|
| México (MXN) | 57 | 18 | 3 | 17 |
| Colombia (COP) | 30 | 12 | 0 | 13 |
| Resto (USD) | 5 | 4 | 0 | 4 |

Hoy no hay candidatos a duplicado entre pedidos pagados. La regla anterior confundía reintentos con duplicados (por ejemplo #3097 → #3101) y se corrigió.

**Revisiones de ejemplo hechas con pedidos reales** (cuenta demo de Mario en staging; comentario "Ejemplo de revisión (staging)"):
| Pedido | Qué marcó el sistema | Evidencia consultada | Decisión | Resultado |
|---|---|---|---|---|
| #5351 MX | Pagado y cancelado | **WooCommerce staging4 ya no tiene el pedido** → "Ya no está en Woo" | Requiere investigación | En investigación |
| #3654 MX | Posible prueba (método `f360_prueba`), pagado sin transacción | Sin transacción ni nota de pasarela | Prueba | **Conflicto**: Woo lo tiene pagado y sin reembolso (correcto: la decisión no lo vuelve "no venta") |
| #3097 CO | No se concretó + Reintentó y pagó en #3101 | — | No se concretó | Revisado |
| #4114 MX | Woo registró pago | Mercado Pago "Pago aprobado" + número de pago | Venta confirmada | Revisado |

Lectura real de evidencia (sin datos de clientas):
- Mercado Pago aprobado trae número de pago en la meta.
- ePayco y PayPal pagados traen número de transacción, pero **sin nota** de la pasarela.
- Varios Mercado Pago cancelados o fallidos tienen número de pago: hubo intento de cobro.

## 5. Pruebas
- **SQL** (`test_sales_reconciliation.sql`, ensayo con ROLLBACK) — **ENSAYO OK**:
  - R1: anon, vendedora, operador y dueño sin acceso a datos de clientas (Adrián) rechazados en las 6 RPCs.
  - R2: sin grants directos; evidencia solo por service role.
  - R3: la lista es exactamente Commerce Facts; filtros; el resumen suma.
  - R4: marcas separadas (financiera vs no concretado); un reintento no es duplicado.
  - R5: duplicado solo como candidato, en ambos lados.
  - R6: actor suplantado rechazado; número tipo tarjeta descartado; texto libre no se guarda; huella.
  - R7: "venta confirmada" exige evidencia y queda en conflicto si no hay cobro.
  - R8: corregir exige motivo, reemplaza y conserva el historial.
  - R9: reglas de duplicado y prueba.
  - R10: exclusión con motivo, sin doble exclusión, reversible con un registro nuevo.
  - R11: UPDATE y DELETE rechazados en las 3 tablas.
  - R12: Commerce Facts y **War Room idénticos** antes y después de revisar.
  - R13: "cambió después de revisar".
  - R14: sin columnas de datos personales ni de tarjeta.
  - R15: "ya no existe en Woo" es discrepancia financiera y conflicto si se confirma.
- **Node** f360-woo: 70/70 (incluye 9 de evidencia: clasificación de notas, minimización, tarjeta descartada, meta de Mercado Pago, enmascarado; la función solo hace GET; un no-viewer, el secreto de cron, otra tienda o un id inválido se rechazan **antes** de leer Woo). `contract.local.test.ts` requiere la tienda Docker local y fallaba igual antes de este cambio.
- **Regresión:** `test_sg1_cockpit.sql` ENSAYO OK · `db_tests.mjs` ALL PASS · `tsc`, eslint y `next build` OK. La función se publicó en staging con `deploy_woo_functions.sh` (guard TODO OK, cron 200).
- **E2E** `e2e/conciliacion.spec.ts` contra staging: 1/1 (login, resumen, evidencia real, 4 decisiones, móvil sin scroll horizontal).
- **Capturas** (locales, no versionadas): `admin-web/e2e-screenshots/conciliacion/`. Desktop 1440: lista, casos 5351/3654/4114 y detalle. Móvil 390: lista de discrepancias y caso 5351.

## 6. Pendiente de decisión (no implementado a propósito)
1. **Aplicar las exclusiones al War Room.** Hoy se registran pero no cambian ninguna métrica, porque cambiar cifras de Growth es una regla de negocio (CLAUDE.md #13). Cuando lo apruebes, el War Room descuenta los pedidos excluidos y muestra cuántos y por qué.
2. **Segunda etapa:** lectura directa de Mercado Pago y ePayco con credenciales de solo lectura. Aprobada como objetivo, no iniciada.
3. **Producción:** esta migración depende de `20261021000100` (S-G1, que no está en producción) y de P0D para tener pedidos que conciliar. Orden propuesto: P0D → S-G1 → esta migración → publicar la función y el panel.
4. Las cuatro revisiones de ejemplo quedan en el historial de staging (no se pueden borrar, por diseño). Se identifican por el comentario "Ejemplo de revisión (staging)".
