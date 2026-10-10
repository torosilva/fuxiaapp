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

---

# Fase 2 — exclusiones en el War Room, validación de casos y preparación de P0D (2026-10-10, STAGING)

> Autorización de Mario: continuar solo en staging. Producción, WooCommerce y pasarelas no tocados. P0D **no** ejecutado.
> Seguridad (P0): `docs/fuxia360/SECURITY_EXPOSURE_2026-10-10.md` contiene el inventario, la verificación y los pasos de rotación, sin valores. No se rotó nada.

## A. Exclusiones auditadas → War Room
- **Migración** `20261022000200_f360_growth_exclusions.sql`:
  - nueva función `f360.growth_adjustments()`;
  - `f360_growth_cockpit` agrega a cada mercado un bloque `adjustments` con lo original, lo excluido, lo ajustado, los clasificados sin excluir y el detalle.
  - **Las tarjetas KPI y todos los desgloses siguen siendo las cifras originales de WooCommerce**; no cambian.
- **Rollback** `20261022000200_f360_growth_exclusions.down.sql`: restaura el cockpit de S-G1 y borra la función. Ensayado.
- **Reglas:**
  - Clasificar no excluye. Los pagados marcados como prueba o duplicado siguen contando y se muestran como "siguen contando".
  - Excluir es una acción aparte: motivo, quién y cuándo, en un registro que no se edita. Se revierte con otro evento.
  - Cuenta solo el estado vigente de cada pedido, así que nunca se resta dos veces.
  - Efecto = lo que el pedido aportaba a la cifra original. Un pagado resta su venta neta (ya descontados sus reembolsos), 1 pedido y sus pares. Uno nunca pagado, o cancelado/reembolsado después del pago, no tiene efecto ("ya no contaba").
  - El detalle (pedidos, motivos, quién) solo lo ven Carolina y Mario; Adrián y los operadores ven solo los totales.
- **Pantalla:** en el War Room, bajo las tarjetas de cada país, el panel **"Ventas originales vs. ajustadas"** (originales − excluidos = ajustados, con ticket) y la lista de exclusiones con motivo.
- **Pruebas** `supabase/staging/test_growth_exclusions.sql` G1–G8 — **ENSAYO OK**:
  - G1: original = KPIs; sin exclusiones, ajustado = original, en cada país.
  - G2: clasificar no cambia nada.
  - G3: excluir un pagado resta una sola vez y el KPI original no se mueve.
  - G4: no se puede excluir dos veces; excluir → incluir → excluir resta una vez; incluir regresa al original.
  - G5: nunca pagado y pagado-cancelado no tienen efecto.
  - G6: reembolso parcial resta solo la venta neta.
  - G7: original − excluidos = ajustados, y el detalle suma lo excluido, en cada país.
  - G8: el dueño sin acceso a datos de clientas ve totales sin detalle.
  - Regresión: `test_sg1_cockpit` OK · `test_sales_reconciliation` OK · `db_tests` ALL PASS · Node 71/71 · `tsc`/eslint OK.
- **E2E** (staging): exclusión de ejemplo del #3654 → MX original $130,690 / 38 pedidos / 53 pares → excluido −$2,800 / −1 / −1 → ajustado $127,890 / 37 / 52 (ticket $3,439 → $3,456). La tarjeta original no cambió. En el celular no hay scroll horizontal.
- **Capturas:** `admin-web/e2e-screenshots/conciliacion/` 09 (panel, desktop), 10 (War Room MX completo), 11 (panel, móvil).

## B. Validación de casos (solo lectura)
| Caso | Qué se verificó | Conclusión | Origen de los datos |
|---|---|---|---|
| **#5351** | Producción: `commerce_woo_orders` (prod_read) y el destino `woo_production`, con corte en el 5351. Staging: `woo_webhook_deliveries`. | **Es un pedido real de fuxiaballerinas.com (producción)**, el único que tiene hoy Commerce Facts de producción. El 8 oct, de 13:56 a 15:11 UTC, la tienda de producción también mandó a **staging** webhooks firmados con el secreto de staging de los pedidos #5347 y #5351. Probablemente eran los webhooks de staging4 copiados al promover staging4 a producción. Staging los registró como si fueran de `woo_staging4`, y por eso staging4 no los encuentra (404). No hay datos de envío de la clienta en staging; solo cifras. | Producción + staging |
| **#3097 → #3101** | Lectura en Woo comparando solo sí/no: mismo correo, mismo nombre de pila, apellido escrito distinto. Mismo producto y talla (variación 2960), COP 420,000, 6 h de diferencia. #3097 llegó por un anuncio de Instagram, #3101 directo. | **Muy probable reintento, no comprobado como la misma intención.** La marca ahora dice "Posible reintento pagado" y pide confirmarlo (migración de texto `20261022000300`). Se registró una corrección que reemplaza la revisión de ejemplo, con esta verificación (el historial conserva ambas). | staging4 (copia de producción hasta ~4 oct) |
| **#3654** | Woo staging4: método "PRUEBA staging (sin cobro)", sin transacción ni notas de pasarela. | Sigue en **conflicto** (clasificado como prueba, pero Woo lo tiene pagado y sin reembolso). Además, como ejemplo, se **excluyó de métricas** con motivo, y el conflicto se mantiene visible. | Solo staging (método de prueba de staging4) |
| **#4114** | Woo staging4: dos notas de la pasarela ("Mercado Pago: Pago aprobado" y "Pago completado"), número de pago de Mercado Pago presente, pagado $2,800 = total. | Evidencia de cobro **según lo que Mercado Pago registró en Woo**. No es una confirmación contra Mercado Pago directo (fase 2 de pasarelas). | staging4 |

**Qué es ejemplo y qué está respaldado por producción:**
- Todas las decisiones y exclusiones viven **solo en staging**, como ejemplos (su comentario empieza con "Ejemplo de revisión/exclusión (staging)").
- Producción no tiene ninguna decisión ni exclusión, porque la Conciliación no está desplegada ahí.
- Los pedidos #3097, #3101, #3654 y #4114 están en la copia de staging4. El historial real de producción (84 pedidos) los incluye con el mismo estado y total; ver P0D. Producción no los tiene en Commerce Facts todavía.
- Solo el #5351 está hoy en Commerce Facts de producción.

## C. P0D — conciliación previa (no ejecutado)
- Herramienta: `scripts/f360/p0d_preflight.mjs` (solo lectura: GET a Woo producción sin campos personales + SELECT de solo lectura en producción y staging).
- Resultado: `docs/fuxia360/growth/P0D_PREFLIGHT.md`, por país, moneda y estado, y pedido por pedido.
- Resumen:
  - 84 pedidos en Woo producción desde el 1 jun.
  - **P0D importaría 83**; el #5351 ya está.
  - **83 iguales a la copia de staging4** (mismo estado y total).
  - México 48: 34 completados, 1 en proceso, 9 cancelados (2 con pago: #3138 y #5351), 4 fallidos.
  - Colombia 31: 17 completados, 14 cancelados.
  - Resto 5: 1 completado, 4 cancelados.
- Hallazgos para revisar antes de importar:
  1. **#2095 (ROW, cancelado) dice USD 405,000.** Casi seguro es un monto en COP con la moneda equivocada. No suma (está cancelado), pero hay que decidir si se importa marcado o se corrige el mercado/moneda.
  2. **#5347** llegó a staging desde producción el 8 oct, pero no aparece en la lista de pedidos de Woo producción. Probablemente se borró o está en la papelera.
  3. **No hay pedidos en línea en producción después del 8 oct** (Woo, Commerce Facts y webhooks coinciden). Si Carolina sabe de ventas en línea del 9–10 oct, hay que revisarlo antes de P0D.
  4. #3177 sigue en "procesando" desde el 23 ago.

## D. Riesgos
| Riesgo | Mitigación |
|---|---|
| Los webhooks de producción que apuntaban a staging podrían seguir activos: el siguiente pedido real llegaría también a staging. | Verificar en modo lectura (Mario): `! ssh -p 18765 u2262-72gcmsiaboij@ssh.fuxiaballerinas.com "cd ~/www/fuxiaballerinas.com/public_html && wp wc webhook list --user=1 --fields=id,name,status,delivery_url"`. Pausar los que apunten a `faltxpkaicwpnlqaxrdu` **solo con autorización** (es un cambio en WooCommerce). |
| Secretos de producción expuestos (3 vigentes, 1 posiblemente). | Rotación coordinada (documento de seguridad). |
| Una persona confunde "ajustado" con "cobrado". | Las tarjetas siguen siendo originales y el panel dice siempre de dónde sale cada número. |
| Excluir el pedido equivocado. | Motivo obligatorio, registro inmutable, reversión con un clic y otro motivo; detalle visible. |
| Datos de producción (#5347, #5351) dentro de staging. | Solo cifras, sin datos de clientas. Pueden quedarse como evidencia o borrarse de staging con autorización. |

## E. Rollback (orden inverso)
1. `20261022000300_f360_sales_rec_wording.down.sql`: regresa el texto de la vista.
2. `20261022000200_f360_growth_exclusions.down.sql`: el cockpit vuelve al de S-G1 y se borra la función.
3. `20261022000100_f360_sales_reconciliation.down.sql`: borra la capa de conciliación, incluidas sus decisiones (exportarlas antes).
4. Función: redeploy de `f360-woo-sync` del commit anterior con `deploy_woo_functions.sh`.
5. Panel: Vercel → deployment anterior.

Ningún archivo `.down.sql` trae su propio BEGIN/COMMIT: se corren dentro de una sola transacción.

## F. Checklist de producción (cuando Mario lo autorice)
- [ ] Rotación de secretos decidida y coordinada (o aceptado el riesgo por escrito).
- [ ] Webhooks de Woo producción → staging verificados (y pausados si existen, con autorización).
- [ ] Decisión sobre #2095 (moneda) y #5347.
- [ ] **P0D:** dry-run en producción → revisar contra `P0D_PREFLIGHT.md` (83 a importar) → importar → re-correr = 0 → cifras por estado iguales a Woo.
- [ ] Pase S-G1 (`20261021000100`) + panel War Room.
- [ ] Pase Conciliación (`20261022000100`, `…0200`, `…0300`) con dry-run en `prod_sql.sh`.
- [ ] `deploy_prod_function.sh f360-woo-sync` (acción `order_evidence`) y verificar el cron 200.
- [ ] `deploy_prod_admin.sh`.
- [ ] Humo en producción: Carolina y Mario ven Conciliación y un operador no; la evidencia de un pedido real carga; War Room original = Woo; sin exclusiones, ajustado = original.
- [ ] Las decisiones de ejemplo de staging **no** se copian a producción.

---

# Fase 3 — corrección comercial de moneda (#2095) y alerta (2026-10-10, STAGING)
- **Migración** `20261022000400_f360_currency_corrections.sql` (rollback `.down.sql`, ensayado):
  - `f360.commerce_currency_corrections`: append-only; motivo obligatorio; evidencia capturada por el servidor; revertir = evento nuevo.
  - Vista `f360.commerce_currency_scope`.
  - `f360.commerce_orders_reporting`, que agrega `market_reporting`, `currency_reporting` y `currency_corrected`. Las columnas de origen no cambian.
  - Alerta `f360.currency_suspicion()`.
  - RPC `f360_rec_correct_currency` (Carolina y Mario).
  - El War Room (`growth_market_block`, `growth_adjustments`) y la Conciliación usan el país y la moneda corregidos.
  - **Siguen mostrando la fuente:** Commerce Facts (técnico), Medición (`measurement_sales`) y el tablero ejecutivo, hasta su propio pase.
- **#2095 en staging:** corrección registrada (Mario demo, motivo con tu confirmación).
  - WooCommerce y Commerce Facts siguen en **USD 405,000 / ROW / cancelado**.
  - El War Room y la Conciliación lo cuentan como **COP 405,000 / Colombia, sin cobro**: +1 pedido creado sin pago en Colombia, −1 en Resto. **Los ingresos pagados no cambian.** No hay conversión cambiaria.
- **Alerta "Moneda sospechosa"** (no corrige nada sola). Se dispara si:
  - la factura es de MX o CO y no coincide con el mercado de la moneda;
  - ePayco no está en COP;
  - Mercado Pago no está en MXN;
  - el precio por par está fuera de rango (USD > 5,000; MXN > 60,000; COP < 50,000).
  En staging hoy solo marca el #2095.
  - **Corrección propia:** descarté una regla "PayPal no cobra en COP", porque staging4 tiene pedidos en COP completados con PayPal.
- **Pruebas** `test_currency_corrections.sql` K1–K8: ENSAYO OK.
  - K1 permisos · K2 la alerta encuentra solo el #2095 · K3 validaciones · K4 la fuente no cambia · K5 Conciliación (original vs corregido, sigue "Sin cobro") · K6 War Room (se mueve de mercado, ingresos sin cambio) · K7 historial inmutable, sin doble corrección, la reversión restaura · K8 evidencia capturada por el servidor.
  - Regresión: R1–R15, G1–G8 y S-G1 OK.
  - E2E: 2/2.
  - Capturas: 12 (caso desktop), 13 (War Room Colombia), 14 (móvil).
