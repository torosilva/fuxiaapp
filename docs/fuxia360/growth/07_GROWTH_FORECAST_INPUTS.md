# 07 · Insumos de Growth para el forecast de 18 meses

**Fecha:** 2026-10-08. **Alcance:** qué **hechos** de Growth pueden alimentar un forecast **por drivers** de 18 meses, con qué confianza, y dónde hay riesgo de doble conteo. **No** se diseña el forecast (ni modelos predictivos); se especifican sus insumos.

**Lo que existe hoy:** Plan 2027 (B4), con fórmula `revenue = clientas activas × pedidos por clienta × AOV` y mezclas en % (`admin-web/src/lib/growth-model.ts:1-2,40-56`; tablas `f360.growth_plans` / `growth_scenarios` / `growth_plan_changes`). En producción: 1 plan, **0 escenarios**. El Plan dice explícitamente "objetivo, no pronóstico" (`PlanEditor.tsx`). G0 #18 marcó como CONFLICT que el modelo del Plan no usa tráfico ni conversión.

---

## 1. Dos árboles de drivers (compatibles)

**A. Árbol de adquisición online (nuevo):**
```
Revenue online (moneda, mercado) = Sesiones × CR (sesión → PS) × AOV
Sesiones = Sesiones pagadas + Sesiones no pagadas
Sesiones pagadas ≈ Spend ÷ CPC_efectivo     (o Spend ÷ CPM × CTR × 1000)
Nuevas clientas = PS de nuevas = Spend ÷ CAC (paid) + nuevas orgánicas
```

**B. Árbol de clientas (Plan B4 actual):**
```
Revenue = Clientas activas × Pedidos por clienta × AOV
Clientas activas(t) = Retenidas(t-1) × (1 − churn) + Nuevas(t)
Recompra = Repeat rate × base
```

**Puente:** A produce **nuevas clientas** y **pedidos de nuevas**; B produce **recompra**. Revenue total = revenue de nuevas (A) + revenue de recurrentes (B) + tienda física (driver aparte: ubicaciones × ventas por ubicación). **Nunca** se suman A y B completos (doble conteo, §4).

---

## 2. Inventario de insumos

| Driver | Fuente de verdad | Estado hoy | Historia disponible | Granularidad | Confianza para forecast | Qué falta |
|---|---|---|---|---|---|---|
| Sesiones | GA4 (Data API) | **Sin acceso** | GA4 guarda 14 meses de eventos por defecto (retención **UNVERIFIED**, `G2A5` §3); la propiedad tiene datos al menos desde 2026-06 (R1) | día × mercado (ruta) × canal × dispositivo | MEDIA (GA4 sin consentimiento, IAB) | D1/D2 de `G2B1` §D |
| CR (sesión → PS) | Commerce Facts ÷ GA4 | MISSING | Online F360 desde 2026-10-08 | día × mercado | BAJA hasta 3+ meses de datos | Backfill Woo + GA4 |
| AOV | Commerce Facts | LIVE | Desde 2026-10-08 (prod); clon de staging4 jun–sep como **referencia no oficial** (MXN 3,435.83 AOV producto, `G1B` §5) | pedido | ALTA cuando haya volumen | Backfill |
| Spend | Meta / Google Ads | **MISSING (sin acceso)** | UNKNOWN (Meta guarda 37 meses de insights; UNVERIFIED para esta cuenta) | día × campaña × anuncio | ALTA cuando exista | Acceso a Ads |
| CPC / CPM / CTR | Plataformas | MISSING | Ídem | Ídem | ALTA (de la plataforma) | Ídem |
| CAC | Spend ÷ nuevas | MISSING | — | mes × mercado × canal | MEDIA (atribución last-click) | Spend + identidad |
| ROAS / MER | Revenue F360 ÷ Spend | MISSING | — | mes × mercado | MEDIA / ALTA (MER) | Spend |
| Repeat rate / frecuencia | Commerce Facts + identidad | MISSING | — | cohorte mensual | BAJA hasta 12 m de historia | Backfill + D-C3 |
| Churn / retención | Ídem | MISSING | — | cohorte | BAJA | Ídem |
| Tienda física | `offline_sales` (RPC) + `historical_sales` | PARTIAL | RPC: 1 venta; legacy 36 (no contables); 2 bazares | ubicación × día | BAJA hoy | Uso continuo del flujo de vendedora; decisión sobre legacy |
| Mezcla de producto | `commerce_order_lines` canónicas | LIVE | Desde 2026-10-08 | modelo × color × talla | MEDIA | Volumen |
| Intención (favoritos, Avísame) | `05_…` | PARTIAL | Días | modelo × talla | **No es driver de revenue**; solo de producción/reposición | — |
| Precio / descuento | `product_prices`, `discount` | LIVE | — | variante × moneda | ALTA | — |
| Estacionalidad | Woo histórico | MISSING en F360 | En Woo (años) | día | — | Backfill (D-C1) |

**Conclusión:** hoy el forecast solo puede alimentarse de **supuestos** (como el Plan B4) más **AOV** de pocos días. Los drivers de adquisición (sesiones, CR, spend, CAC) están bloqueados por **acceso** (GA4, Meta) y por **historia** (backfill Woo).

---

## 3. Contrato de insumo (PROPUESTA)

Cada insumo que entre al forecast sale de una vista mensual `f360.growth_monthly_facts` (ver `09_…`) con:

| Columna | Regla |
|---|---|
| `month`, `market`, `currency` | Moneda original, nunca convertida |
| `kind` | `ACTUAL` únicamente (los `TARGET` / `SCENARIO` siguen en las tablas del Plan) |
| `revenue_paid_net_product`, `paid_orders`, `units`, `aov_product` | Commerce Facts |
| `sessions` | GA4 (NULL si no hay) |
| `spend` | Ads (NULL si no hay) |
| `new_customers`, `repeat_customers` | NULL hasta que la historia cubra el lookback |
| `coverage_flags` | `{online_from, store_rpc_only, ga4_connected, spend_connected, history_months}` |
| `quality` | Peor calidad de sus insumos |

**Regla:** un mes con `coverage_flags` incompletos **no** se usa para calibrar tasas (CR, CAC, repeat). Se muestra, pero el forecast lo marca como "no calibrable".

---

## 4. Riesgos de doble conteo

| # | Riesgo | Cómo ocurre | Regla |
|---|---|---|---|
| DC1 | Revenue por árbol A + árbol B completos | Las nuevas del árbol A también son "clientas activas" en B | A aporta solo nuevas; B solo recurrentes |
| DC2 | Online + loyalty | `transactions.amount` (web) duplica pedidos Woo | `transactions` nunca es dinero (`02_…` §3) |
| DC3 | Históricos + pedidos | Un bazar cargado en `historical_sales` y además sus ventas registradas por RPC | Regla de `f360_exec_dashboard`: históricos solo en periodos que cubren; validar con su suite antes de reusar |
| DC4 | GA4 `purchase` + Commerce Facts | Sumar revenue de GA4 | Prohibido |
| DC5 | Meta conversiones + F360 | Usar compras de Meta para CAC | Prohibido (DQ-01) |
| DC6 | Pedido de link de pago + pedido fallido original | El rescate crea un **pedido nuevo**; el original queda `pending`/`failed` | Solo cuenta el pagado; el original no es venta |
| DC7 | Monedas | Sumar MXN + COP | Prohibido sin D-FX |
| DC8 | Tienda que cumple pedido online | Venta online surtida desde una tienda ("Envíos en línea") | Es **una** venta online (`commerce_woo_orders`); el movimiento de inventario no es otra venta (`20261012001100` encabezado) |
| DC9 | Sobre pedido | Venta pagada sin stock y luego producción | Una venta; la producción no es venta |
| DC10 | Plan vs actual | Guardar escenarios con números actuales copiados | `ACTUAL` solo desde la vista; Plan guarda supuestos |

---

## 5. Recomendación para el forecast de 18 meses

1. **Ahora:** forecast por **supuestos explícitos** (Plan B4 extendido a mensual), con cada supuesto etiquetado `ASSUMPTION` y su dueño.
2. **Al tener backfill Woo (D-C1):** calibrar AOV, estacionalidad, mezcla de mercado y repeat con historia real (24 m).
3. **Al tener GA4 API:** calibrar sesiones y CR por mercado.
4. **Al tener gasto:** calibrar CAC / MER y abrir el árbol de adquisición.
5. Cada mes el forecast compara `ACTUAL` vs `FORECAST` vs `TARGET` sin sobrescribir nada (bitácora como `growth_plan_changes`).
