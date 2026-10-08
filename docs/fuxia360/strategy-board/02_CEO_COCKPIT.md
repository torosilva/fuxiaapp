# 02 · CEO Cockpit

> Spec. La pantalla de dirección: **ACTUAL vs BUDGET vs FORECAST vs VARIANCE**, por **MTD / QTD / YTD / FY**.
> Fuente de verdad comercial: G1 Commerce Facts. El cockpit **no recalcula** ventas por su cuenta y **no inventa** lo que falta.

## 1. Estructura de la pantalla

Para cada KPI y cada periodo:

| Columna | Significado | Fuente |
|---|---|---|
| ACTUAL | Hecho (mes cerrado) o provisional (mes abierto, marcado) | §3 |
| BUDGET | Versión de presupuesto **aprobada** vigente | `f360_board.budget_versions/lines` (nuevo) |
| FORECAST | Versión vigente del forecast rolling (cerrados = actual) | `03_FORECAST_MODEL.md` |
| VARIANCE | ACTUAL − BUDGET (abs y %), ACTUAL − FORECAST, FORECAST(FY) − BUDGET(FY) | calculado en la RPC |
| Calidad | `VERIFIED / PARTIAL / UNVERIFIED / MISSING` + motivo | heredado de G1 (`data_quality`) y del cierre |

Periodos (zona `America/Mexico_City`, igual que `f360_exec_dashboard`, `20261010000300_f360_exec_dashboard.sql:20-21`): MTD, QTD, YTD, FY (año fiscal = calendario **hasta que Mario confirme**, decisión D6). FY combina ACTUAL de meses cerrados + FORECAST de meses restantes ("FY outlook").

Moneda: titular MXN. COP y USD **aparte**, nunca sumados sin TC (regla G1 D-G1-03; `20261008000100_f360_g1_commerce_facts.sql:9`). Vista "consolidado MXN" solo con `f360_board.fx_rates` explícito y rótulo "consolidado a TC <fuente, fecha>".

## 2. Estado REAL de cada KPI (auditado 2026-10-08)

Leyenda: **EXISTS** = dato medido y accesible hoy; **PARTIAL** = existe con huecos conocidos; **MISSING** = no existe en ninguna tabla.

| KPI | Estado | Fuente real / motivo | Cómo incorporarlo |
|---|---|---|---|
| Revenue (titular) | **PARTIAL** | `f360.commerce_orders.net_product` (`status_class='countable'`), en moneda original (`20261008000100…:371-421`) + `f360.historical_sales_active` (resúmenes MXN de tiendas/bazares antes de F360). Huecos: (a) 36 de 37 filas de `public.offline_sales` en prod son legacy (`created_by_rpc=false`; Guadalajara 28, Tienda Polanco 6, Monterrey 1, Contreras 1) y **no entran** a Commerce Facts (filtro `WHERE s.created_by_rpc`, `:418`); (b) en prod solo 1 pedido Woo capturado (2026-10-08) y `commerce_sync_state` vacío; (c) salud del canal de producción invisible (`:455`) | Reusar la definición del panel ejecutivo (`net_product` MXN + históricos). Decidir si se cargan ventas legacy como `historical_sales` (Carolina, flujo existente "Ventas pasadas") — **no** copiar `offline_sales` |
| Gross Revenue | **PARTIAL** | `product_gross` (= `items_subtotal`, antes de cupones) en Woo; en tienda = `line_total` (sin descuentos registrados) | Mostrar como "venta bruta de producto". Mismos huecos que Revenue |
| Net Revenue | **PARTIAL** | `net_product` = producto − cupones − reembolsos de producto. **No es neto de IVA**: Woo tiene `prices_include_tax=false` y `total_tax=0` (prod y G1 §89 `docs/fuxia360/growth/G1_COMMERCE_FACTS_DESIGN.md`), y la tienda no guarda impuesto | Decisión D4: definir "Net Revenue" (¿÷1.16?). Hasta entonces el cockpit dice "venta neta de producto (precio cobrado, IVA no separado)" |
| Gross Profit | **MISSING** | Sin costo de producto en ninguna tabla | Requiere COGS (abajo) |
| Gross Margin | **MISSING** | Igual | Igual |
| COGS | **MISSING** | `f360.products` no tiene costo (contradicción con `docs/fuxia360/03_DATA_MODEL.md:26`) | Opción A (preferida a largo plazo): costo unitario por modelo con vigencia (`f360_board.product_cost_versions`, o en core si el Core lo adopta — decisión D3) × unidades de `commerce_order_lines` → COGS calculado. Opción B (rápida, SB0): COGS mensual como **entrada de cierre** con evidencia |
| OPEX | **MISSING** | Nada | Entrada de cierre mensual por categoría (renta, nómina, marketing no pagado, tecnología, logística, otros) |
| EBITDA | **MISSING** | Depende de GP y OPEX | Derivado: Gross Profit − OPEX (solo si ambos del mismo mes están cerrados; si no, `MISSING`) |
| Cash | **MISSING** | Nada | Entrada de cierre: saldo de caja/bancos al cierre por moneda + evidencia (estado de cuenta en bucket privado) |
| Inventory Value | **PARTIAL** (pares) / **MISSING** (a costo) | `f360.inventory_balances` (prod: 526 filas, 631 pares). El panel actual valúa a **precio de venta** (`20261010000300…:137-138`) | Mostrar "Inventario a precio de venta (no es costo)" con esa etiqueta; a costo solo con D3. Excluir `En camino` (transit) igual que el heatmap del panel |
| Marketing Spend | **MISSING** | `G0_GROWTH_INTELLIGENCE_AUDIT.md:111` "Gasto (spend) MISSING"; Growth congelado | Fuente primaria: hechos de gasto que publique Growth (`docs/fuxia360/growth/00–09`). Mientras no exista: entrada de cierre `marketing_spend` por canal con fuente; cuando Growth publique, el cierre pasa a ser **reconciliación** (no segunda fuente) |
| CAC | **MISSING** | Spend + nuevas clientas atribuidas (G0 #16) | Calculado: spend del periodo ÷ nuevas clientas del periodo. Etiqueta "blended CAC". Paid CAC solo cuando Growth publique atribución |
| ROAS | **MISSING** | G0 #16; prohibido usar el ROAS de Meta como verdad (G0 #7) | Revenue atribuido (G1 first-party `commerce_woo_attribution`) ÷ spend pagado, cuando ambos existan |
| MER | **MISSING** | Requiere spend | Revenue total ÷ marketing spend total (no necesita atribución; primer KPI de eficiencia disponible tras cargar spend) |
| AOV | **EXISTS** (con huecos de Revenue) | `ticket` = venta MXN ÷ pedidos MXN (`20261010000300…:63`); G1 `aov_product` en `f360_commerce_summary` | Reusar; por canal |
| Orders | **EXISTS** | `count(*)` countable en `commerce_orders` | Reusar; separar online/tienda; históricos no tienen número de pedidos (solo monto y pares) → marcar |
| New Customers | **PARTIAL** | `public.customers.created_at` (61 clientas en prod) = altas al programa, no "primera compra". Pedidos invitados Woo sin identidad (`customer_link_status='guest'`) | Definir "nueva" = primera compra identificada en `commerce_orders.loyalty_customer_id`/`woo_customer_id`; mostrar % de pedidos no identificados |
| Repeat Customers | **PARTIAL** | Igual: depende de identidad; `store_identified_pct` ya existe en el panel | Contar clientas con ≥2 pedidos countable identificados en ventana |
| Repeat Rate | **PARTIAL** | Derivado | repeat ÷ clientas compradoras identificadas; con denominador explícito |

**Conclusión:** hoy el cockpit puede mostrar con honestidad Revenue/Gross/Net de producto (con huecos), Orders, AOV, pares e inventario en pares; **todo lo de rentabilidad, caja y eficiencia de marketing requiere el cierre mensual** (SB0/SB1).

## 3. El cierre mensual (fuente para lo que no existe)

Pantalla "Cierre de <mes>" (Carolina o Mario), un formulario corto:

| Campo | Tipo | Obligatorio | Evidencia |
|---|---|---|---|
| COGS del mes (si no hay costo por modelo) | monto + moneda | sí para cerrar GP | archivo/nota |
| OPEX por categoría (6–8 renglones) | montos | sí para EBITDA | archivo/nota |
| Gasto de marketing por canal (Meta, Google, influencers, otros) | montos | opcional | captura/CSV de la plataforma |
| Caja al cierre por cuenta/moneda | montos | opcional | estado de cuenta |
| Ventas fuera de F360 no capturadas (si las hay) | se registran en `historical_sales` (flujo existente), **no aquí** | — | — |
| Comentario de cierre | texto | no | — |

Reglas:

- Estados del periodo: `OPEN → IN_REVIEW → CLOSED`; reabrir = nueva **versión** con motivo (append-only), nunca editar en sitio. Patrón "void + nuevo" de `f360.historical_sales` (`20261010000200_f360_historical_sales.sql:1-9`).
- Al cerrar, se congela un **snapshot de ACTUAL** del mes (revenue/orders/AOV leídos de G1 en ese instante + las entradas). Si G1 cambia después (reembolso tardío), el cockpit muestra "ACTUAL actualizado difiere del cierre en $X" — no reescribe el cierre.
- Cierre requiere que `commerce_source_health` del canal de producción esté `VERIFIED` (hoy no se puede: ver `00_MASTER_SPEC.md` C5) o una **excepción explícita** registrada.
- Quién aprueba: decisión D5 (una persona prepara, la otra aprueba vs cualquiera).

## 4. RPC propuesta

`public.f360_board_cockpit(p_period text, p_as_of date, p_currency text DEFAULT 'MXN', p_dims jsonb DEFAULT '{}')` → jsonb

- `require_board_member('FINANCIAL')` + access log.
- Lee: `f360.commerce_orders`/`commerce_order_lines` (mismas reglas que `f360_exec_dashboard`: countable, `paid_at`, excluir `sales_targets.is_test` en una base con target de producción, `:22,40-43`), `f360.historical_sales_active`, `f360.inventory_balances`, `public.customers` (solo conteos), `f360_board.monthly_close_*`, `budget_*`, `forecast_*`, `fx_rates`.
- Devuelve por KPI: `{actual, actual_class, budget, forecast, var_abs, var_pct, quality, quality_reasons[], sources[]}` — `sources[]` cita tabla/vista y versión para que el AI Analyst y la UI puedan mostrar "de dónde sale".
- No devuelve PII. No devuelve filas, solo agregados.

**No** se modifica `f360_exec_dashboard` (sigue siendo el panel operator del día a día). Se extrae la lógica común a una función interna `f360.commerce_period_totals(d0, d1, …)` solo si ambos la usarían — decisión de implementación en SB1 con pruebas de igualdad contra el panel actual.

## 5. UX

- Una fila por KPI, cuatro columnas grandes, chip de calidad. Click → "¿de dónde sale?" (fuentes + motivo de PARTIAL/MISSING).
- `MISSING` en gris con la acción concreta ("Captura el COGS de septiembre en Cierre").
- Selector de periodo MTD/QTD/YTD/FY y de corte (fecha). Modo presentación.
- Nada se edita desde el cockpit; solo enlaza a Cierre, Budget y Forecast.

## 6. Dependencias con Growth

Strategy consume, cuando existan, los hechos definidos en `docs/fuxia360/growth/00–09` (agente hermano): sesiones, tasa de conversión, gasto por canal, nuevas clientas atribuidas, CAC/ROAS de Growth. Contrato: Growth publica **vistas/RPCs owner/operator**; Strategy las lee desde funciones `f360_board_*` (SECURITY DEFINER) sin duplicar tablas. Si Growth y el cierre mensual traen gasto para el mismo mes, **gana Growth** y el cierre muestra la diferencia como reconciliación.
