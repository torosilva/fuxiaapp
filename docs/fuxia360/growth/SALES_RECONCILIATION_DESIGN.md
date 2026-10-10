# Conciliación de Ventas (Growth 360) — PROPUESTA DE DISEÑO (2026-10-10)

> Solo diseño. Sin migraciones, sin despliegues. Espera aprobación de Mario.

## 0. Lo que ya existe (auditoría)
| Pieza | Dónde | Qué tiene / qué no |
|---|---|---|
| Pedidos de Woo | `f360.commerce_woo_orders` (+ `commerce_woo_order_lines`, `commerce_woo_attribution`, vista `f360.commerce_orders`) | id, estado Woo, fechas (creado, pagado, completado), `ever_paid`, totales, moneda, mercado, método de pago, id de cliente Woo, país. **Sin** nombre/correo/teléfono ni número de transacción (lista blanca de S-G0, `_shared/f360-woo/commerce.ts:2`). |
| Datos de envío | `f360.order_shipping` | nombre/WhatsApp/correo/dirección, **solo pedidos pagados desde el 8 oct** (producción). |
| Evidencia de pasarela | **no se guarda** | Woo la tiene: `transaction_id`, `date_paid`, `payment_method_title`, notas del pedido (mensajes de Mercado Pago / ePayco), reembolsos. Legible con la llave REST de solo lectura que ya usa `f360-woo-sync`. |
| Estado financiero | `commerce_orders.status_class` / `payment_state` | la verdad financiera actual (countable / reversed / never_paid…). |
| Patrones reutilizables | `require_pii_viewer()` (Carolina, Mario), triggers append-only (`reject_audit_change`), `legacy_store_sale_imports` (needs_review), Board decisions | |

## 1. Principios
1. **No duplicar pedidos**: la lista sale de Commerce Facts; solo se agrega lo que hoy no existe — la **decisión humana** y la **evidencia que se vio al decidir**.
2. **Clasificación humana ≠ estado financiero.** La decisión se guarda aparte; `commerce_orders` no cambia. Una "Venta confirmada" sobre un pedido sin cobro verificado se muestra como **conflicto** ("confirmada por persona · sin cobro verificado"), nunca como venta cobrada.
3. **Datos personales solo para Carolina y Mario**, leídos **en el momento** desde Woo (no se copian a Fuxia 360).
4. **Nada se escribe en WooCommerce ni en las pasarelas.**

## 2. Discrepancias que el sistema marca (automáticas, explicables)
| Código | Regla | Con qué datos |
|---|---|---|
| `PAGO_Y_CANCELADO` | se registró pago (`ever_paid`) y hoy está cancelado / fallido | Commerce Facts |
| `PAGADO_SIN_EVIDENCIA` | estado processing/completed sin fecha de pago; al abrirlo, sin `transaction_id` ni nota de aprobación de la pasarela | Commerce Facts + evidencia al abrir |
| `POSIBLE_DUPLICADO` | mismo cliente Woo (o, al abrir, mismo correo) + mismo total + mismos productos en ≤ 48 h | Commerce Facts (+ Woo al abrir) |
| `SIN_PAGO` | nunca pagado (pending / failed / cancelled sin pago) | Commerce Facts |
| `REEMBOLSO` | reembolso total o parcial registrado | Commerce Facts |
Cada marca dice **por qué** (la regla y el dato).

## 3. Decisiones humanas
`VENTA_CONFIRMADA` · `NO_SE_CONCRETO` · `DUPLICADO` (indica de cuál) · `PRUEBA` · `REEMBOLSO` · `REQUIERE_INVESTIGACION`.
Se registra: quién (id de cuenta + nombre), cuándo, decisión, comentario (obligatorio en Duplicado / Prueba / Investigación) y **evidencia** = foto mínima de lo que la persona vio (estado Woo, fecha de pago, `transaction_id`, título del método, extractos de notas de pasarela sin datos personales, total) + huella (hash). **Nunca se edita ni se borra**: cambiar de opinión es una decisión nueva que reemplaza a la anterior (historial completo).

## 4. Cambios propuestos (para aprobar)
**Base de datos (1 migración):**
- `f360.sales_reconciliation_decisions` — append-only (trigger), FK lógica a `(target_id, woo_order_id)`, `decision`, `duplicate_of`, `comment`, `evidence jsonb`, `evidence_hash`, `decided_by`, `decided_by_name`, `decided_at`, `supersedes`. RLS on, sin políticas; solo RPC.
- Vista `f360.sales_reconciliation_cases` — por pedido: datos de Commerce Facts + marcas de discrepancia + decisión vigente + "estado financiero verificado" (de `commerce_orders`, sin tocarlo) + conflicto humano/financiero.
- RPCs (PII viewers = Carolina, Mario; acceso registrado en `customer_access_log`): `f360_reconciliation_list(desde, hasta, mercado, estado, método, discrepancia, decisión)`, `f360_reconciliation_summary(...)` (pendientes / revisados / discrepancias por tipo y mercado), `f360_reconciliation_case(target, pedido)` (detalle + historial), `f360_reconciliation_decide(target, pedido, decisión, comentario, evidencia, duplicado_de)`.

**Evidencia en vivo (sin copiar datos):** nueva acción `order_evidence` en la función `f360-woo-sync` (ya tiene la llave de solo lectura de Woo): valida que quien pide sea Carolina o Mario (JWT → `f360_reconciliation_can_view`), lee `GET /orders/{id}` y `/orders/{id}/notes` y regresa solo: estado, fechas, `transaction_id`, método, total, reembolsos, notas de pasarela, y **cliente (nombre, correo, teléfono)** solo para mostrar. Nada se guarda salvo la foto mínima al decidir.

**Pantalla:** Growth → pestaña **Conciliación**: resumen arriba (pendientes, revisados, discrepancias, por México / Colombia), filtros (fecha, país, estado Woo, método de pago, discrepancia, decisión), tabla (ID, fecha, cliente\*, total y moneda, estado Woo, método, transacción\*, evidencia, marcas, decisión), y detalle del pedido con productos, origen, evidencia de la pasarela, cliente\* e historial de decisiones + formulario de decisión. (\* se carga al abrir, solo Carolina/Mario.)

## 5. Lo que NO hace
No cambia estados en Woo, no reembolsa, no consulta Mercado Pago / ePayco directo (fase 2, requiere sus llaves de lectura), no excluye pedidos de las métricas automáticamente, no importa P0D.

## 6. Decisiones para Mario
1. ¿Acceso solo Carolina y Mario (con datos de cliente), o también un operador sin datos personales?
2. Prueba / Duplicado: ¿deben **excluirse de las métricas** de Growth? Propuesta: no automático; botón aparte "excluir de métricas" con su propio registro.
3. ¿Guardamos la foto mínima de evidencia al decidir (recomendado) o solo el comentario?
4. Fase 2: ¿conectamos Mercado Pago y ePayco en modo lectura para confirmar el cobro contra la pasarela misma?

## 7. Pruebas previstas (staging)
Permisos (operador/vendedora/anónimo rechazados), decisiones append-only (update/delete rechazados), reemplazo con historial, la decisión no cambia `commerce_orders` ni métricas, conflicto "confirmada sin cobro", cada regla de discrepancia con fixtures, filtros, separación MX/CO y monedas, evidencia sin datos personales guardados, Woo de staging4 solo lectura.
