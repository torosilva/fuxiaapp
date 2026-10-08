# 03 · Forecast Model — Rolling 18 meses

> Spec. Ningún número de este documento es un dato: los ejemplos son fórmulas, no cifras.

## 1. Definiciones

| Serie | Qué es | Mutabilidad |
|---|---|---|
| **ACTUAL** | Hechos (G1 + históricos + cierre mensual). Mes abierto = `ACTUAL_PROVISIONAL` | Se recalcula hasta el cierre; al cerrar se congela snapshot |
| **BUDGET** | Plan anual aprobado (versión). Mensualizado | Inmutable una vez `APPROVED`; cambios = nueva versión (`REFORECAST`/`REBUDGET`) con motivo |
| **FORECAST** | Proyección rolling de 18 meses desde el mes en curso | Versionado; cada publicación crea `forecast_version` nueva; las publicadas se congelan en snapshot (`11_FORECAST_ACCURACY.md`) |

**Regla de mes cerrado:** cuando un mes pasa a `CLOSED` en el cierre mensual, en todas las vistas el FORECAST de ese mes **se reemplaza por ACTUAL** (la versión de forecast conserva su valor original en el snapshot para medir precisión). La ventana se desplaza: siempre 18 meses hacia adelante desde el primer mes abierto.

Ejemplo de ventana a 2026-10-08: oct-2026 (provisional) … mar-2028.

## 2. Dimensiones (nombres REALES)

| Dimensión | Valores hoy | Fuente |
|---|---|---|
| company | Fuxia Ballerinas (única) | — (decisión D7 si hay entidades MX/CO separadas) |
| market | `MX`, `CO`, `ROW`, `UNKNOWN` | `f360.commerce_woo_orders.market` CHECK (`20261008000100_f360_g1_commerce_facts.sql:49`) |
| country | MX, CO (derivado de market; tiendas = MX) | G1; tiendas MX "by construction" (`:409-410`) |
| currency | MXN, COP, USD | `f360.currencies` (`20261005000100_f360_currency_prices.sql:10-27`; prod: MXN, COP, USD) |
| channel | `online` (Woo target `woo_production`, "Tienda en línea"), `store` (venta F360 en tienda), `historical_summary` (resúmenes pre-F360) | `commerce_orders.channel`; `f360.sales_targets` (prod: `woo_production` prod=true **active=false**; `woo_staging4` test) |
| store / location | `Tienda Polanco`, `Amsterdam 264`, `La Noria`, `San Jeronimo lidice` (store), `Torreon` (**bazaar**), `Bodega CDMX` (warehouse, no vendible), `En camino` (transit) | `f360.locations` en prod 2026-10-08 |
| category | `ballerinas`, `sandalia-plana`, `sandalia-alta`, `botas` | `f360.categories` en prod; `commerce_order_lines.category_key` |

**No inventar canales.** Hallazgos:

- **Cali (Colombia)** — **Decidido (Mario 2026-10-08):** para este ejercicio Cali es **solo la casa matriz** (Colombia), operada por su suegra. **No** es ubicación de Fuxia 360 ni canal de venta del cockpit/forecast; no se crea en `f360.locations` ni se pronostica como tienda. Las ventas legacy del canal "Cali" quedan fuera de los actuals de Fuxia 360. La relación con la casa matriz (p. ej. pares pedidos a Colombia) se trata como origen/proveedor, no como canal. Contexto: no existe en `f360.locations`; solo como `public.channels` legacy ("Cali"). Tampoco Monterrey, Guadalajara, Contreras (legacy `public.channels`, con ventas legacy en `offline_sales`). El forecast no tendrá esas tiendas como dimensión hasta que existan como ubicación F360 (Track C) — mientras tanto, si Mario quiere forecast de Colombia retail, se modela como **escenario** "nueva tienda/país" (`04_SCENARIO_LAB.md`).
- Accesorios/apparel no existen como categoría: solo vía escenario "nueva categoría".

Granularidad mínima: mes × market × channel × location (si store) × category. Los niveles superiores son sumas **dentro de una moneda**.

## 3. Drivers (driver-based)

Cada línea de forecast declara su **método** y sus **drivers**; el método decide qué se suma.

| Método | Fórmula | Aplica a | Fuente de drivers |
|---|---|---|---|
| `ECOM_FUNNEL` | sesiones × CR × AOV | channel=online | Sesiones/CR: Growth (`docs/fuxia360/growth/00–09`) — hoy **MISSING** (Growth congelado). AOV: G1 |
| `PAID_ACQ` | nuevas_clientas_pagadas = spend ÷ CAC; revenue_pagado = spend × ROAS | sub-componente de online | Spend/CAC/ROAS: Growth o cierre mensual — hoy MISSING |
| `RETAIL_TX` | transacciones × AOV | channel=store, por location | Transacciones/AOV: G1 store (`commerce_orders` channel=store; en prod 1 venta) + `historical_sales` (monto y pares, **sin** número de tickets) |
| `CUSTOMER_BASE` | clientas_activas × frecuencia × AOV | vista total (cross-check) | CRM + G1. Es la lógica de B4 (`admin-web/src/lib/growth-model.ts:1-2`) |
| `MANUAL` | monto por mes con nota obligatoria | cualquier línea sin drivers | Dueños |
| `INVENTORY_CHAIN` | demanda (unidades) → disponible requerido → producción → caja | derivado, no revenue | `inventory_balances`, `made_to_order`, costo (D3) |

### 3.1 Solapamientos (no doble conteo)

1. **`PAID_ACQ` está DENTRO de `ECOM_FUNNEL`**: las sesiones pagadas son parte de las sesiones totales. Regla: online revenue = `ECOM_FUNNEL` **o** (`PAID_ACQ` + orgánico/directo explícito), nunca ambos. El modelo guarda `method` por línea y la suma de revenue ignora líneas marcadas `role='decomposition'`.
2. **`spend ÷ CAC` y `spend × ROAS` son dos lecturas del mismo dinero**: CAC da clientas, ROAS da revenue. Se usa uno como driver y el otro como **chequeo** (revenue_pagado ÷ nuevas_pagadas debe ≈ AOV × pedidos por clienta nueva). Si discrepan > umbral, alerta "drivers inconsistentes".
3. **`CUSTOMER_BASE` vs canales**: es una vista alternativa del total (clientas × frecuencia × AOV ya incluye online y tienda). Nunca se suma a `ECOM_FUNNEL` + `RETAIL_TX`; se muestra como "triangulación" con su diferencia.
4. **Históricos vs tienda F360**: `historical_sales` ya rechaza periodos con ventas RPC en la misma ubicación (`20261010000200_f360_historical_sales.sql:6-7`). El forecast hereda esa garantía al usar ACTUAL de G1 + históricos tal como los suma el panel ejecutivo.
5. **Reservas / sobre pedido / links de pago**: son pipeline, no revenue; solo afectan ACTUAL cuando se pagan (G1 `status_class`). El forecast puede usarlos como señal de corto plazo, no como monto.

### 3.2 Cadena de inventario

```
unidades demandadas (forecast revenue ÷ precio medio por categoría)
 − inventario disponible (inventory_balances, excluye transit y no vendible)
 − producción ya comprometida (made_to_order pendiente/en_proceso)
 = unidades a producir
 × costo unitario (D3: hoy MISSING)
 = requerimiento de caja para inventario (por mes de pago según lead time)
```

Sin costo, la cadena se detiene en **unidades a producir** (útil igual para Carolina) y la caja queda `MISSING`.

## 4. Construcción de una versión

1. Semilla automática: últimos N meses de ACTUAL disponibles (hoy muy pocos: G1 en prod inicia 2026-10-08; históricos 2 bazares de sep/oct 2026) → la mayoría de líneas arranca en `MANUAL` o con drivers tecleados. La UI debe mostrar "base histórica insuficiente" por línea.
2. Ajustes del dueño sobre drivers (no sobre el resultado, salvo `MANUAL`).
3. `PUBLISH` → versión inmutable + snapshot (11).
4. Comparar contra BUDGET y contra la versión anterior.

## 5. Moneda

Cada línea en su moneda original. El forecast de Colombia (COP) no se convierte salvo en la vista consolidada con `fx_rates` (fuente+fecha) — nunca TC "del día" implícito.

## 6. Cálculos: dónde viven

- Matemática pura en TypeScript (patrón `admin-web/src/lib/growth-model.ts` + `admin-web/test/growth-model.test.ts`) para la UI de edición **y** la misma fórmula en SQL para la versión publicada (fuente única = SQL al publicar; TS solo previsualiza). Prueba de igualdad TS↔SQL con fixtures.
- La RPC `f360_board_forecast_publish` recalcula en servidor; nunca acepta totales calculados por el cliente (CLAUDE.md regla 6).

## 7. Riesgos

- Base histórica casi vacía en prod → forecast dominado por juicio. Mitigación: etiqueta de método por línea + Forecast Accuracy desde el día 1.
- Online de prod sin salud visible (`commerce_source_health` excluye producción) → ACTUAL online puede estar incompleto sin aviso.
