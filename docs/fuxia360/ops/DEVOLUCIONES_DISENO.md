# Devoluciones y cambios en tienda: DISEÑO (no implementado) — 2026-10-13

> **Autorización de Mario (2026-10-13):** preparar el diseño. **No se cambia el flujo actual**, no se toca producción y no se migra nada.
> **Las reglas de negocio** (plazo, reembolso sí o no, quién autoriza, qué pasa con los puntos) **las decide Carolina o Mario** (cuestionario `CUESTIONARIO_CAROLINA_2026-10-13.md`).
> Aquí van marcadas como **[DECISIÓN]**, con la opción que ya usa la tienda en línea como referencia, nunca como supuesto.

## 1. Situación actual (producción, solo lecturas)
| Canal | Devolución hoy | Puntos |
|---|---|---|
| Tienda en línea (WooCommerce) | reembolso o cancelación del pedido en WooCommerce | `woocommerce-webhook` revierte **el pedido completo**: resta `points_earned` y `pairs_in_order` (nunca por debajo de 0), recalcula el nivel y marca `transactions.reversed_at`. No hay reversión parcial |
| Tienda física, app anterior | **no existe**: sin pantalla, función ni estado | no hay forma de revertirlos |
| Tienda física, F360 | **no existe**. El ledger tiene `RETURN`, pero solo se usa para "regresar al origen" una transferencia (1 caso) | no hay forma de revertirlos (`loyalty_apply` solo acredita). Corrección manual con `admin-points` (admin) |
| En la práctica | si hubo devoluciones físicas, quedaron como **"Ajuste · entrada"** sin referencia a la venta (255 ajustes de entrada; ninguno dice devolución o cambio) | sin cambio en puntos |

## 2. Requisitos (Mario, 2026-10-13) y cómo se cumplen
| Requisito | Diseño |
|---|---|
| Referencia obligatoria a la venta original | La devolución exige `sale_id` (`public.offline_sales.id`, venta registrada por F360: `created_by_rpc`) y, por artículo, la línea vendida. Sin venta no hay devolución; lo demás sigue siendo ajuste de inventario (auditado) |
| Autorización y motivo | `reason_code` de una lista cerrada **[DECISIÓN: lista]** y nota libre. Autoriza quien defina **[DECISIÓN]**. Propuesta: el mismo patrón que los descuentos de tienda (`f360_store_discount_*`), es decir, la vendedora solicita y una persona con alcance `store_return` aprueba con NIP, con fecha, hora y nombre |
| Entrada o salida de inventario trazable | Al aprobarse, un evento `RETURN` en el ledger hacia la ubicación de la tienda: `inventory_events` y `inventory_movements`, con `business_reference_type = 'store_return'` y `business_reference_id = return.id`. Si el par regresa **dañado**, va a `WRITE_OFF` **[DECISIÓN: ¿se revisa el estado?]** |
| Ajuste o reversión de puntos cuando corresponda | El servidor calcula los puntos a revertir con **la misma regla** de la venta: los puntos por par que se acreditaron en esa venta (`loyalty_apply_audit` / `transactions` de la venta). La clienta no envía puntos. **[DECISIÓN: ¿se revierten? ¿proporcional por par devuelto o venta completa como en línea? ¿mínimo 0 y bajar de nivel?]** |
| Auditoría inmutable | Tablas solo de inserción (sin UPDATE ni DELETE, ni siquiera para `service_role`), con disparador que lo impide, como `financial_commitment_events` en el Centro de Inteligencia. Cada estado (solicitada, aprobada, rechazada, aplicada) es un **evento nuevo** |
| Prevención de devoluciones duplicadas | (a) llave de idempotencia única por solicitud; (b) **cantidad devuelta por línea ≤ cantidad vendida − ya devuelta**, comprobada con bloqueo de la venta (`SELECT … FOR UPDATE`); (c) una venta 100 % devuelta no admite más |

## 3. Modelo de datos propuesto (esquema `f360`, solo inserción)
```
f360.store_returns            -- cabecera; nunca se actualiza
  id uuid PK, sale_id uuid NOT NULL → public.offline_sales(id), location_id → f360.locations,
  kind text CHECK (kind IN ('devolucion','cambio')), reason_code text NOT NULL, note text,
  requested_by uuid (auth.users), requested_by_name text, idempotency_key uuid UNIQUE NOT NULL, created_at
f360.store_return_lines       -- qué se devuelve
  return_id → store_returns, variant_id → f360.product_variants, quantity int > 0,
  unit_price numeric (copiado de la venta original, no del cliente), condition text ('vendible','dañado')
f360.store_return_events      -- estados (inmutable): solicitada → aprobada | rechazada → aplicada
  return_id, state, actor uuid, actor_name, note, inventory_event_id, loyalty_transaction_id, created_at
```
El **cambio** (otra talla u otro modelo) es **un solo evento atómico**: devolución de la línea original + venta nueva por `f360_record_store_sale`, enlazadas por `exchange_sale_id`. Si hay diferencia de precio, se cobra o se devuelve **[DECISIÓN]**.

## 4. Funciones (RPC `SECURITY DEFINER`; ningún cliente escribe en las tablas)
| RPC | Quién | Qué valida |
|---|---|---|
| `f360_store_return_request(p_token, p_sale_id, p_lines, p_kind, p_reason, p_idempotency)` | vendedora con turno abierto en **la tienda de la venta** **[DECISIÓN: ¿o en cualquier tienda?]** | venta F360 existente; plazo **[DECISIÓN]**; cantidades ≤ vendidas − devueltas; precio desde la venta |
| `f360_store_return_decide(p_return_id, p_approve, p_pin)` | quien autoriza **[DECISIÓN]** | no puede aprobar quien la solicitó |
| (dentro de la aprobación) | — | evento `RETURN` o `WRITE_OFF` en el ledger; reversión de puntos con una función nueva `loyalty_reverse` (inversa de `loyalty_apply`: idempotente, con bloqueo de la tarjeta, mínimo 0 y nivel recalculado con el mismo disparador); evento `aplicada`. **Todo en una transacción** |
| `f360_store_returns_list(p_location)` | operadora y dueña | consulta |

## 5. Pruebas previstas (staging, identidades ficticias, BEGIN…ROLLBACK)
- **D1:** sin venta original, rechazada.
- **D2:** devolver más de lo vendido, rechazado. Dos solicitudes en paralelo por el último par: solo una pasa.
- **D3:** misma llave de idempotencia, una sola devolución.
- **D4:** aprobación: inventario +1 en la tienda, por `RETURN` en el ledger y con referencia.
- **D5:** puntos revertidos exactamente según la regla decidida; nunca por debajo de 0; nivel recalculado.
- **D6:** quien solicita no puede aprobar; una vendedora de otra tienda no puede solicitar (si así se decide).
- **D7:** las tablas no admiten UPDATE ni DELETE, ni con `service_role`.
- **D8:** un cambio de talla es un solo evento atómico (si falla la venta nueva, no se aplica la devolución).

## 6. Qué NO hace este diseño
- No toca la tienda en línea: WooCommerce sigue con su reversión actual.
- No reconstruye las devoluciones pasadas registradas como ajustes.
- No aplica a ventas de la app anterior (`created_by_rpc = false`): esas no tienen líneas F360 confiables. **[DECISIÓN: ¿se aceptan devoluciones de esas ventas, y cómo?]**
