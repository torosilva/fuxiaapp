# 05 · Five-Year Plan (2027–2031)

> Spec. **TODOS los montos de este documento son METAS DE DIRECCIÓN (TARGETS) en estado DRAFT.**
> **No son forecast, no son resultados, no son compromisos con terceros.**

## 1. Metas iniciales (DRAFT — management targets)

| Año | Revenue target (MXN) | Tema estratégico | Estado |
|---|---|---|---|
| 2027 | 15,000,000 | Scale Footwear México | DRAFT target |
| 2028 | 25,000,000 | Fashion Footwear + Accessories | DRAFT target |
| 2029 | 40,000,000 | Fashion Brand | DRAFT target |
| 2030 | 60,000,000 | Lifestyle | DRAFT target |
| 2031 | 85,000,000 | Fashion Company | DRAFT target |

Consistencia con el repositorio: `f360.growth_plans` en prod tiene **2027 north_star = 15,000,000 MXN** (prod_read 2026-10-08; tabla en `supabase/migrations/20260929000100_f360_b4_growth_plan.sql:10-17`). Para no crear dos fuentes de verdad (CLAUDE.md regla 11): el revenue target 2027 del plan **referencia** `growth_plans.plan_year=2027` y la UI muestra una alerta si difieren. Decisión D8: o `growth_plans` se vuelve la vista operativa del año en curso derivada del plan aprobado, o el plan lee de `growth_plans` para el año corriente. No ambos editables de forma independiente.

No hay datos ACTUAL anuales verificados (prod: `reported_figures` = 0 filas) contra los cuales comparar la trayectoria; la UI debe mostrar "sin año base verificado" hasta que haya un FY cerrado o una cifra `reported_figures` en estado `verificada`.

## 2. Versionado

`plan_versions`: `id`, `name` ("Plan 5 años v1"), `status` (`DRAFT` → `PROPOSED` → `APPROVED` → `SUPERSEDED`), `approved_by[]`, `approved_at`, `supersedes_id`, `decision_id` (link al Decision Log), `notes`.

- Solo una versión `APPROVED` vigente a la vez.
- Editar una aprobada = duplicar a DRAFT nueva; la aprobación de la nueva marca la anterior `SUPERSEDED` (no se modifica su contenido).
- Cada guardado de DRAFT escribe `plan_revisions` (payload completo + hash).

## 3. Campos por año (`plan_years`)

| Campo | Tipo | Nota |
|---|---|---|
| year | int | 2027–2031 |
| theme | text | "Scale Footwear México", … |
| revenue_target | numeric + currency | MXN por defecto |
| gross_margin_target | % | sin costo hoy → sin línea base |
| ebitda_target | numeric o % | |
| customer_target | int | clientas activas (definición del cockpit) |
| repeat_target | % | |
| ecommerce_target | numeric o % del revenue | |
| store_target | numeric o % + número de tiendas | |
| category_targets | jsonb `{category_key|new_category_label: amount|pct}` | categorías nuevas como etiqueta hasta que existan en `f360.categories` |
| market_targets | jsonb `{MX, CO, ROW}` | |
| capital_requirement | numeric + currency | vínculo a `07_CAPITAL_OWNERSHIP.md` (uso de fondos), no a cap table |
| initiatives | → `plan_initiatives` | |
| gates | → `strategic_gates` (`06`) | un año puede depender de gates (p. ej. 2028 Accessories requiere gate NEW CATEGORY aprobado) |
| assumptions | text | obligatorio si hay supuestos materiales |

`plan_initiatives`: `id`, `plan_version_id`, `year`, `title`, `description`, `owner` (Carolina/Mario), `category` (mismo catálogo de capital deployment: Growth/Inventory/Content/Technology/Operations/Working Capital/Store Expansion/Other), `capex/opex estimado`, `gate_id`, `status` (`IDEA`, `PLANNED`, `IN_PROGRESS`, `DONE`, `DROPPED`).

## 4. Relación con forecast y escenarios

- El plan **no** genera forecast. El Scenario Lab puede crear un escenario de 60 meses "camino al plan" para ver qué drivers serían necesarios (clientas, AOV, tiendas), reutilizando la lógica "lo que se necesita" de `growth-model.ts` (`ordersNeeded`, `customersNeeded`, `aovRequired`).
- El cockpit muestra para el año en curso: ACTUAL YTD + FORECAST resto vs **TARGET** del plan y vs **BUDGET** — tres cosas distintas, con su etiqueta.

## 5. Visualización

Línea de 2027–2031 con TARGET (punteada, rótulo "Meta DRAFT"), ACTUAL de años cerrados (sólida) y FORECAST FY en curso. Nunca un área sombreada continua que mezcle meta y realidad.

## 6. RPCs

`f360_board_plan_list()`, `f360_board_plan_get(version_id)`, `f360_board_plan_save_draft(…)`, `f360_board_plan_duplicate(id)`, `f360_board_plan_propose(id)` (crea decisión), `f360_board_plan_approve(id)` (solo vía decisión aprobada) — `require_board_member('BOARD')` para aprobar, `'FINANCIAL'` para editar draft.
