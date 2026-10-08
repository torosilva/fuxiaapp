# Fuxia 360 → Strategy & Board — Master Spec

> **Fase:** DISCOVERY / AUDIT / SPEC. Nada de este documento está implementado. No hay migraciones, RPCs, rutas ni datos.
> **Fecha de auditoría:** 2026-10-08 · rama `fuxia-360` · producción leída SOLO con `scripts/f360/prod_read.sh` (READ ONLY, conteos/rangos, sin PII).
> **Acceso del módulo:** exclusivamente **Carolina** y **Mario** (los dos dueños). Ver `01_ACCESS_MODEL.md`.

## 1. Propósito

Strategy & Board es la capa de **dirección** de Fuxia 360: compara lo que pasó (ACTUAL) contra lo que se planeó (BUDGET) y lo que se espera (FORECAST), modela escenarios, gobierna decisiones estratégicas (gates, consejo, capital) y prepara material para inversionistas.

**Regla de oro (no negociable):** Strategy **consume hechos** producidos en otros módulos (Commerce Facts G1, inventario, CRM, Growth) o capturados en un **cierre mensual auditado**. **Nunca inventa** ingresos, ROAS, CAC, ventas, inventario ni márgenes. Si un dato no existe, la pantalla dice `MISSING` y explica de dónde vendría; no muestra un número estimado disfrazado de real.

Clases de número que el módulo distingue siempre (etiqueta visible en cada cifra):

| Clase | Significado | Quién lo produce |
|---|---|---|
| `ACTUAL` | Hecho medido o cierre mensual aprobado | G1 Commerce Facts, ledger de inventario, CRM, cierre mensual |
| `ACTUAL_PROVISIONAL` | Mes en curso, aún no cerrado | Mismas fuentes, sin cierre |
| `REPORTED` | Cifra reportada por una persona, no verificada | `f360.reported_figures` (existe, ver §4) |
| `BUDGET` | Presupuesto aprobado (versión) | Dueños |
| `FORECAST` | Proyección rolling 18 meses (versión) | Modelo + ajustes de dueños |
| `SCENARIO` | Simulación; nunca afecta budget/forecast sin aprobación | Scenario Lab |
| `TARGET` | Meta de dirección (plan a 5 años) | Dueños |
| `INDICATIVE` | Valuación indicativa de gestión | Valuation Tracker |

## 2. Navegación y orden de dependencias

```
Fuxia 360 → Estrategia (solo Carolina y Mario)
 1  CEO Cockpit ............ 02_CEO_COCKPIT.md
 2  Forecast (18 meses) .... 03_FORECAST_MODEL.md
 3  Scenario Lab ........... 04_SCENARIO_LAB.md
 4  Plan a 5 años .......... 05_FIVE_YEAR_PLAN.md
 5  Strategic Gates ........ 06_STRATEGIC_GATES.md
 6  Capital & Ownership .... 07_CAPITAL_OWNERSHIP.md
 7  Board (consejo) ........ 08_BOARD_GOVERNANCE.md
 8  Investor Room .......... 09_INVESTOR_ROOM.md
 9  Valuation Tracker ...... 10_VALUATION_TRACKER.md
10  Forecast Accuracy ...... 11_FORECAST_ACCURACY.md
11  AI Board Analyst ....... 12_AI_BOARD_ANALYST.md (solo spec)
```

Transversales: `01_ACCESS_MODEL.md`, `13_DATA_MODEL.md`, `14_SECURITY_MODEL.md`, `15_IMPLEMENTATION_PLAN.md`.

### Grafo de dependencias

```
SB0 Access + Data Foundation (allowlist, access log, monthly close, FX, periods)
  └─► 1 CEO Cockpit (ACTUAL + cierre)          ◄── G1 Commerce Facts, ledger, CRM, Growth spend (docs/fuxia360/growth/00–09)
        └─► BUDGET versions ──► VARIANCE
        └─► 2 Forecast 18M ──► 10 Forecast Accuracy (snapshots inmutables)
              └─► 3 Scenario Lab (copia aislada de drivers)
                    └─► 4 Five-Year Plan (TARGETS) ──► 5 Strategic Gates (métricas del Cockpit)
6 Capital & Ownership (independiente de datos comerciales; depende de SB0)
  └─► 9 Valuation Tracker (necesita ownership formal para cualquier cálculo por socio — hoy NO existe)
7 Board + Decision Log ◄── usa 1,2,4,5,6 como contenido del board pack
8 Investor Room ◄── documentos de 4,6,7,9 (curados, sin PII, sin secretos)
11 AI Board Analyst ◄── lee TODO lo anterior por las mismas RPCs owner-only (último)
```

Orden de construcción recomendado (= sprints en `15_IMPLEMENTATION_PLAN.md`): SB0 → SB1 → SB2 → SB3 → SB4 → SB5 → SB6 → SB7; AI Analyst después de SB7 y fuera de este plan.

## 3. Realidad del repositorio que condiciona el diseño (resumen de la auditoría)

Detalle y citas en `14_SECURITY_MODEL.md` y `02_CEO_COCKPIT.md`.

1. **Modelo de roles**: `f360.user_roles` con `owner/operator/seller/viewer` (`supabase/migrations/20260925010000_f360_admin_v1_inventory_core.sql:19-25`, ampliado en `20260930000100_f360_c1_locations_roles.sql:15-19`). `role_rank` da **seller = viewer = 1**, así que `require_role('viewer')` deja pasar vendedoras. En producción hoy hay 2 filas en `user_roles`, ambas `owner`: "Carolina" y "Mario Silva" (prod_read 2026-10-08). **Pero "owner" ≠ "Carolina y Mario"** por diseño: en staging existe "Adrián" como owner técnico y la migración de PII lo excluye explícitamente (`20261010000100_f360_crm_c1_customer_profile.sql:90`). Strategy necesita su **propia allowlist** (patrón de `f360.customer_pii_viewers`), no `require_role('owner')`.
2. **Hechos financieros que existen**: ventas en línea (Woo) y en tienda vía `f360.commerce_orders` / `commerce_order_lines` (G1, `20261008000100_f360_g1_commerce_facts.sql:371-446`), resúmenes históricos (`f360.historical_sales`, `20261010000200`), clientas (`public.customers`), inventario en pares (`f360.inventory_balances`). **No existe** en ninguna tabla de `public`/`f360`: costo de producto, COGS, OPEX, caja, gasto de marketing, presupuesto (búsqueda en `information_schema.columns` en prod, 2026-10-08: cero columnas `%cost%|%cogs%|%margin%|%spend%|%budget%|%expense%|%opex%|%cash%`).
3. **Volumen real en producción hoy es mínimo**: 1 pedido Woo capturado (2026-10-08, estado `reversed`), 1 venta de tienda vía RPC F360, 36 ventas legacy de `public.offline_sales` fuera de Commerce Facts, 2 resúmenes históricos de bazar, 61 clientas, 631 pares en inventario. El Cockpit nacerá casi vacío y debe decirlo, no rellenarlo.
4. **Planeación existente reutilizable**: `f360.growth_plans` (North Star anual; prod: **2027 = MXN 15,000,000**), `f360.growth_scenarios` (conservador/base/agresivo, 0 filas en prod), `f360.growth_plan_changes` (append-only), `f360.reported_figures` (0 filas) — `20260929000100_f360_b4_growth_plan.sql`. Matemática pura en `admin-web/src/lib/growth-model.ts` con prueba `admin-web/test/growth-model.test.ts`.
5. **Panel ejecutivo existente**: `public.f360_exec_dashboard` (`20261010000300_f360_exec_dashboard.sql`) + `admin-web/src/app/(app)/tablero/`. Es **operator+**, no owner-only; su "valor de inventario" es **precio de venta × pares**, no costo (`:137-138`).
6. **Infra de auditoría**: `f360.reject_audit_change()` (append-only) usada en `access_changes`, `growth_plan_changes`, `commerce_woo_status_log`, etc.; patrón "void + nuevo" en `historical_sales`.
7. **No hay**: bucket privado de Storage (los 3 buckets de prod — `avatars`, `tryon-temp`, `product-images` — son públicos), generación de PDF en servidor (solo `window.print()` en `conteo/hoja/PrintButton.tsx` y CSV por Blob en `conteo/ConteoClient.tsx:146`), integración LLM en código (`hilo-chat` es una base de conocimiento por palabras clave, `fuxia-native/supabase/functions/hilo-chat/index.ts`), tabla de tipos de cambio.

## 4. Principios de diseño

1. **Reusar antes de crear** (CLAUDE.md regla 11): ACTUAL de ventas = G1; North Star 2027 = `growth_plans`; cifras reportadas = `reported_figures`. Nada se copia; Strategy lee por vistas/RPCs.
2. **Un esquema aparte** `f360_board` sin `USAGE` para `anon`/`authenticated`; la única superficie cliente son `public.f360_board_*` SECURITY DEFINER que empiezan con `f360_board.require_board_member(<scope>)` y registran el acceso.
3. **Autorización en servidor/DB**, nunca solo ocultando navegación. La UI oculta además, pero eso es cortesía.
4. **Append-only + versionado** para todo lo que se decide: decisiones, cierres, budgets aprobados, snapshots de forecast, cap table formal.
5. **Moneda original siempre**; consolidación MXN solo con tipo de cambio explícito (fuente + fecha) y etiqueta "consolidado a TC …". Mismo principio que G1 D-G1-03.
6. **Sin PII de clientas** en ningún objeto de Strategy (solo agregados). Sin secretos técnicos en Investor Room.
7. **Operación simple** (regla 15): Carolina debe poder hacer un cierre mensual con un formulario de ~10 campos, no con hojas técnicas.

## 5. Fuera de alcance

- Contabilidad general (libro mayor, CFDI, impuestos). Strategy recibe **totales mensuales cerrados**, no asientos.
- Medición de Growth (GA4/GTM/Meta/sesiones/experimentos): la define el agente hermano en `docs/fuxia360/growth/00–09`. Strategy solo consume sus hechos publicados (sesiones, gasto, CAC, ROAS) cuando existan. Nota: Growth está congelado desde 2026-10-05 (GA4/GTM/Meta/CRO), así que sesiones y gasto seguirán `MISSING` en el corto plazo.
- Acceso de inversionistas externos, agencias, vendedoras, tiendas, staff o clientas: **prohibido** en esta fase.
- Asesoría legal/fiscal; los campos de cap table no se llenan con supuestos legales.

## 6. Contradicciones documento ↔ repositorio detectadas (CLAUDE.md regla 14)

| # | Documento dice | Repositorio/producción muestra | Impacto |
|---|---|---|---|
| C1 | `docs/fuxia360/03_DATA_MODEL.md:26` lista `cost` en producto; `00_MASTER_SPEC.md:140` "enter/confirm cost" | `f360.products` no tiene columna de costo (columnas reales en prod: id, name, slug, category, status, tier, image_path, wc_product_id, …, regular_price, sale_price, category_key, make_to_order, new_override, store_rank) | Gross Profit/Margin/COGS = MISSING. Decisión D3 en `15_IMPLEMENTATION_PLAN.md` |
| C2 | La tarea menciona Cali (Colombia, casa matriz y tienda) | `f360.locations` en prod NO tiene Cali; `Cali` existe solo como `public.channels` legacy | **Resuelto 2026-10-08:** Cali = casa matriz operada por la suegra de Mario; fuera de ubicaciones/canales de Fuxia 360 |
| C3 | Nombres de tiendas: "San Jerónimo", "Torreón" | Prod: `San Jeronimo lidice` (store), `Torreon` (**bazaar**), `Tienda Polanco` | Usar los nombres reales de `f360.locations.name`, con alias visual solo si Carolina lo decide |
| C4 | Panel ejecutivo "valor de inventario" | Es precio de venta × pares (`20261010000300…:137-138`) | Strategy no puede llamarlo "Inventory Value" (a costo) |
| C5 | Commerce Facts "freshness" | `f360.commerce_source_health` filtra `NOT t.is_production` (`20261008000100…:455`, confirmado con `pg_get_viewdef` en prod) → la salud del canal de producción es invisible; `commerce_sync_state` vacío en prod; `woo_production.active = false` | ACTUAL en línea de prod sin señal de completitud. Ver riesgo R2 |
