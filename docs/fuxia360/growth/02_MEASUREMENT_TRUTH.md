# 02 · Verdad de medición (Measurement Truth)

**Fecha:** 2026-10-08. **Base:** regla de Mario del 2026-10-04 (`G2B_MEASUREMENT_CORRECTION_PLAN.md` §0), modelo G1 (`G1_COMMERCE_FACTS_DESIGN.md`, `G1B_COMMERCE_FACTS_IMPLEMENTATION.md`) y contrato V1 (`G2_MEASUREMENT_CONTRACT.md`). Este documento **consolida** esas reglas en un solo lugar para Growth; donde agrega algo nuevo lo marca **PROPUESTA** (requiere aprobación).

---

## 1. Jerarquía de fuentes

| Rango | Fuente | Es la verdad de | Nunca es la verdad de | Objeto |
|---|---|---|---|---|
| 1 | **Commerce Facts (online)** | Pedidos, pedidos pagados, revenue, AOV, unidades vendidas, moneda, mercado, método de pago, atribución first-party del pedido | Sesiones, funnel | `f360.commerce_woo_orders` → vista `f360.commerce_orders` / `commerce_order_lines` |
| 1 | **Ventas de tienda F360** | Venta física registrada por la vendedora (precio del maestro, append-only) | — | `public.offline_sales` con `created_by_rpc` (incluidas sin copia en `commerce_orders`) |
| 2 | **Resúmenes históricos** | Totales por periodo antes de F360 (bazares, cierres) | Pedidos, clientas, productos | `f360.historical_sales_active` (marcados como históricos) |
| 3 | **Identidad canónica** | Qué producto / variante es cada línea, evento o favorito | — | `f360.channel_variant_identity` (`20261008000300`) |
| 3 | **Clientas / consentimiento** | Quién es, cómo contactarla, qué aceptó | Revenue | `public.customers`, `f360.customer_consent_events`, `f360.order_shipping` |
| 4 | **Señales de intención F360** | Favoritos, búsquedas, Avísame, casos Hilo | Ventas | `favorite_events`, `storefront_searches`, `stock_intents`, `customer_cases` |
| 5 | **GA4** | Sesiones, usuarios, fuente de la sesión, funnel de comportamiento, dispositivo | Revenue, pedidos (su `purchase` cubre ≤ 54%, `G2A5` §8) | Propiedad 519011849 (sin API hoy) |
| 6 | **Meta / Google Ads** | Gasto, impresiones, clics, alcance, IDs de campaña/anuncio | Ventas, ROAS "verdadero" (Meta Purchase = pedido creado, DQ-01) | Sin acceso hoy |
| 7 | **Loyalty** (`transactions`, `unmatched_orders`) | Puntos y nivel | Revenue (solo socias; montos del webhook legacy) | `public.transactions` |
| — | Clarity | Comportamiento cualitativo | Nada cuantitativo | — |

**Regla de conflicto:** si dos fuentes difieren sobre ventas, gana el rango menor (Commerce Facts). La diferencia se **reporta** como métrica de calidad (cobertura de GA4, sobreconteo de Meta), nunca se "corrige" una fuente con otra.

---

## 2. Definiciones

### 2.1 Pedido
Una fila en `f360.commerce_orders`: un pedido Woo (`source_system = 'woo'`, llave `(target_id, woo_order_id)`) o una venta de tienda (`f360_store`, `store_sale:<id>`). **Una venta = una fila de origen** (`G1B` §2.3).

### 2.2 Venta pagada (PAID SALE)
`status_class = 'countable'`, es decir estado Woo ∈ {`processing`, `completed`, `refunded`} (`f360.commerce_status_class`, `20261008000100:180-188`) o venta de tienda registrada por RPC.
- `pending` / `on-hold` → `pending_payment` (no cuenta).
- `failed` / `checkout-draft` → `not_paid`.
- `cancelled` nunca pagado → `cancelled`; `cancelled` con `ever_paid` → `reversed` (**excepción**, `PARTIAL paid_value_unknown` si no hay foto de lo pagado).
- `trash` → `excluded`.
- **"En espera" (on-hold) NO es venta**, aunque GTM4WP lo cuente como `purchase` (`G2A5` A13).

**Fecha de la venta:** `paid_at` (Woo `date_paid_gmt`) en zona **America/Mexico_City** (la que usan `f360_commerce_summary` y `f360_exec_dashboard`). Si falta `paid_at`, `occurred_at`.

### 2.3 Revenue
| Término | Definición | Campo |
|---|---|---|
| **Ventas de producto (net product)** — *métrica principal de Growth* | Σ `line.total` (después de cupones y rebajas, sin envío, sin impuestos) − reembolsos de producto | `commerce_orders.net_product` |
| Total cobrado | `order_total` (producto + envío + impuestos + comisiones) | `commerce_orders.order_total` |
| Bruto | Σ `line.subtotal` antes de descuentos | `product_gross` |
| Descuento | `product_gross − product_net` | `discount` |
| Revenue para ROAS / MER | **net product** (PROPUESTA; ver §2.6) | — |

`list_price_hint` (precio WDR) **nunca** se usa para construir revenue (`G1B` §5).

### 2.4 Reembolsos y cambios
- Fuxia opera con **cambios**, no reembolsos (`G1B` §8). `refund_total ≠ 0` es una **excepción técnica a revisar**, no "revenue perdido".
- Un pedido `reversed` (pagado → cancelado) **no** resta revenue automáticamente: se excluye de `countable` y se lista aparte ("No cuentan como venta", `CommerceFacts.tsx:51-64`).
- Cambios = track futuro (`G1B` §8.1). Hasta entonces, un cambio no altera la venta original.

### 2.5 Moneda (MX / CO / ROW)
- Cada pedido se guarda en su **moneda original** (`currency_original`). `market` = `MX` (MXN), `CO` (COP), `ROW` (USD), `UNKNOWN` (`f360.commerce_market`).
- `market_conflict` = moneda ≠ ruta de entrada (`/mx/`, `/co/`) → `PARTIAL`.
- **Nunca se suman monedas.** No existe tabla de tipo de cambio (`f360.currencies` solo tiene código, símbolo, decimales y meta de precio de Woo).
- **COP** se muestra sin decimales (`CommerceFacts.tsx:11`).
- Ventas de tienda: MXN implícito (`currency_implied_mxn`).
- GA4 convierte todo a MXN con su propia tasa: su revenue **no es comparable** (`G2A5` §3).
- **PROPUESTA (decisión D-FX):** si Mario quiere una cifra consolidada (p. ej. MER total), se usa una tabla `f360.fx_rates` con tasa **mensual fija aprobada** (no de mercado diario), marcada `kind = 'CONVERTED'`, y la vista por moneda original sigue siendo la principal. Hasta aprobarla: KPIs por mercado y la cifra consolidada muestra **DATA INCOMPLETE (FX)**.

### 2.6 ROAS / MER: qué revenue
**PROPUESTA:** ROAS y MER usan **net product en moneda original** del mercado de la campaña. El gasto de Meta se reporta en la moneda de la cuenta publicitaria; si la cuenta es en MXN y la campaña vende en CO, el ROAS de CO requiere FX → DATA INCOMPLETE hasta D-FX.

### 2.7 Clienta nueva vs recurrente
**PROPUESTA (depende de D-C1 y D-C3):**
- **Clave de clienta para Growth** (en orden): `customers.id` si el pedido está ligado (`loyalty_customer_id` u `order_shipping.customer_id`); si no, un **hash** del teléfono normalizado (`f360.normalize_phone`) o del correo en minúsculas del pedido pagado (calculado sobre `order_shipping`, nunca expuesto); si no, `woo_customer_id`; si no, "sin identidad" (no cuenta como nueva ni recurrente).
- **Nueva** en el periodo = su **primera** venta pagada (cualquier canal) cae en el periodo.
- **Recurrente** = tiene ≥ 1 venta pagada **anterior** al pedido.
- **Requisito de historia:** la clasificación solo es válida si la historia cubre la **ventana de lookback** (PROPUESTA: 24 meses). Hoy la historia online empieza el 2026-10-08 → cualquier "nueva" sería falsa. Mientras tanto: **DATA INCOMPLETE (sin historial)**.
- Fuentes de historia anteriores aceptables (con etiqueta `provenance`): backfill de Woo (D-C1), `transactions` de loyalty (solo socias), `unmatched_orders` (2026-08 → 2026-09).

### 2.8 Conversión
`Conversion Rate = pedidos pagados (Commerce Facts) ÷ sesiones (GA4)` por mercado y día. **Mezcla dos fuentes**: se etiqueta `CROSS_SOURCE` y se reporta junto con la cobertura de GA4. Nunca se usa el `purchase` de GA4 como numerador.

---

## 3. Deduplicación

| Riesgo | Regla |
|---|---|
| El mismo pedido por webhook, poll y backfill | Una sola función de escritura (`f360_capture_order_economics`) y una llave `(target_id, woo_order_id)`; `economics_hash` → `unchanged` / `stale` (`G1B` §7) |
| Pedido de inventario vs pedido comercial | `woo_orders` (inventario) **no tiene dinero**; nunca se suma con `commerce_woo_orders` |
| Loyalty (`transactions`) vs Commerce Facts | `transactions` se usa **solo para ligar clienta**, nunca como dinero (`G1B` §2.3). Ojo: `customer_purchases` del CRM sí lo usa como historial (`01_…` §D) |
| Venta de tienda | Fila de origen `offline_sales` (no se copia). Las legacy sin `created_by_rpc` **no cuentan** |
| Históricos vs pedidos | `historical_sales` solo en los periodos que cubren y marcados; un pedido F360 dentro de un periodo histórico se cuenta **una vez** (regla de `f360_exec_dashboard`; verificar en `f360_exec_dashboard_tests.sql` antes de reusar) |
| GA4 `purchase` | Nunca sumado; solo cobertura. F360 **no envía** `purchase` a GA4 (`G2B` §3, regla) |
| Meta Purchase | Nunca usado (DQ-01) |
| Pedido de prueba | `payment_category = 'test'` y `sales_targets.is_test`; el pedido 5351 de producción hay que **clasificar** (UNKNOWN si fue prueba). **PROPUESTA:** lista explícita `f360.commerce_exclusions(target_id, woo_order_id, reason, decided_by)` en vez de borrar |
| Pedidos de link de pago | Son pedidos Woo normales (misma llave). Hoy quedan `origin_unknown` (`01_…` §C): **PROPUESTA** mapear `f360_pay_link` → `storefront_rescue` |

---

## 4. Calidad del dato (vocabulario único)

Se reutiliza el de G1 (`G1B` §10), sin columnas nuevas de estado:

| Nivel | Significado | Qué muestra el cockpit |
|---|---|---|
| VERIFIED | Cuadra y la fuente está fresca | El número |
| PARTIAL | Cuadra con salvedades | El número + ⚠ con el motivo |
| UNVERIFIED | No cuadra o fuente nunca verificada | El número tachado o "por verificar" |
| STALE | La fuente no se ha sincronizado en > 60 min | Banner de frescura |
| **DATA INCOMPLETE** (nuevo término de UI, no de BD) | Falta un insumo para el KPI (gasto, sesiones, historia, FX) | Texto "DATA INCOMPLETE: falta X", **nunca 0** |

**Bloqueo actual:** `commerce_source_health` excluye producción (`20261008000100:455`), así que la frescura de producción es invisible. Corregirlo es requisito de G0 (`09_…`).

---

## 5. Zonas horarias

| Sistema | Zona | Efecto |
|---|---|---|
| Commerce Facts, tablero | America/Mexico_City | Día de negocio |
| GA4 | **America/Tijuana** (`G2A5` A4) | Los días no cortan igual (1 h de diferencia; 2 h fuera de horario de verano de Tijuana). Cambiarla es decisión P4 de `G2B1` §G (solo afecta datos futuros) |
| Meta Ads | UNKNOWN (zona de la cuenta publicitaria) | Verificar al obtener acceso |
| Colombia | America/Bogota | **PROPUESTA:** reportes de CO también en CDMX para un solo calendario, documentado |
