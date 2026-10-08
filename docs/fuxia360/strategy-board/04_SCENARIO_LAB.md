# 04 · Scenario Lab

> Spec. Laboratorio de simulación. **Nunca** modifica BUDGET ni FORECAST sin aprobación explícita.

## 1. Qué existe hoy (reusar)

- `f360.growth_scenarios` (`supabase/migrations/20260929000100_f360_b4_growth_plan.sql:19-26`): una fila por `(plan_year, kind)` con `kind IN ('conservador','base','agresivo')` e `inputs jsonb` validado por `f360.validate_growth_inputs`. Prod: **0 filas**.
- `f360.growth_plans` (North Star anual; prod 2027 = MXN 15,000,000), `f360.growth_plan_changes` (append-only).
- Matemática pura `admin-web/src/lib/growth-model.ts` (revenue = clientas activas × pedidos por clienta × AOV; brechas, splits por canal/categoría/región) con pruebas `admin-web/test/growth-model.test.ts`.
- UI `/growth` (operator+ en pantalla; edición owner, `can_edit = r.role = 'owner'`, `20261008000100_f360_g1_commerce_facts.sql:512-527`).

**Limitaciones para el Lab:** solo 3 escenarios fijos por año, sin CUSTOM, sin duplicar/archivar, sin horizonte mensual, sin outputs de GP/EBITDA/caja/inventario, y legible por `operator` (Strategy exige owner-allowlist).

**Propuesta:** el Lab vive en `f360_board` (nuevo) y **importa** (copia con trazabilidad `imported_from = growth_scenarios:<year>:<kind>`) los escenarios B4 como punto de partida. `growth_scenarios` sigue siendo de Growth (no se borra ni se mueve). Decisión D8: ¿B4 se congela como "vista operativa" y el Lab es la herramienta de dirección?

## 2. Tipos de escenario

| Tipo | Uso |
|---|---|
| `CONSERVATIVE` | Piso prudente |
| `BASE` | Lo esperado |
| `AGGRESSIVE` | Techo con ejecución fuerte |
| `CUSTOM` | Cualquier otra hipótesis (nueva tienda, nueva categoría, país) |

Cada escenario tiene: `name`, `kind`, `horizon` (meses, default 18 o 60 para plan), `base_ref` (forecast_version o budget_version del que parte — opcional), `status` (`DRAFT`, `SAVED`, `ARCHIVED`), `created_by`, `notes`.

## 3. Inputs

Por escenario, por mes (o anual con estacionalidad), por dimensión cuando aplique:

| Input | Unidad | De dónde se siembra | Hoy |
|---|---|---|---|
| traffic (sesiones) | sesiones/mes | Growth | MISSING → tecleado |
| CR | % | Growth / G1 | MISSING → tecleado |
| AOV | moneda | G1 (`ticket`, `aov_product`) | EXISTS (pocos datos) |
| marketing spend | moneda | Growth / cierre | MISSING |
| CAC | moneda | derivado | MISSING |
| gross margin | % | costo (D3) | MISSING → supuesto explícito |
| repeat rate | % | CRM/G1 | PARTIAL |
| inventory turns | veces/año | ledger + costo | PARTIAL (pares sí, costo no) |
| new store | toggle + apertura (mes), ramp-up, ticket, transacciones, capex, OPEX fijo | dueños | supuesto |
| new category | toggle + lanzamiento, % mix, margen, inventario inicial | dueños | supuesto |
| new country | toggle + mercado, moneda, canal | dueños | supuesto |

Cada input tiene `source` (`ACTUAL_SEED`, `GROWTH_FACT`, `ASSUMPTION`) y, si es supuesto, `rationale` obligatorio. La UI marca visiblemente los `ASSUMPTION`.

## 4. Outputs (calculados en servidor)

revenue, orders, customers (nuevas/recurrentes), gross profit, EBITDA, cash requirement, inventory requirement (unidades y monto si hay costo) — por mes y totales por año, en moneda original + consolidado opcional con `fx_rates`.

Reglas de cálculo = las de `03_FORECAST_MODEL.md` §3 (mismos métodos y la misma prevención de doble conteo). Un output cuyo input crítico falta se devuelve `null` con motivo (principio ya usado en `growth-model.ts`: "missing inputs give null (never a guessed value)").

## 5. Acciones

| Acción | Efecto | Auditoría |
|---|---|---|
| SAVE | guarda inputs; recalcula outputs; incrementa `revision` | fila en `scenario_revisions` (inputs completos + hash) |
| COMPARE | 2–4 escenarios lado a lado (y vs BUDGET/FORECAST vigente) | lectura (access log) |
| DUPLICATE | copia con `duplicated_from` | revisión inicial |
| ARCHIVE | `status = ARCHIVED`, solo lectura; no se borra | revisión |
| PROMOTE (opcional) | **propone** convertir el escenario en nueva versión de BUDGET o FORECAST | crea `decision` en estado `PROPOSED` (`08_BOARD_GOVERNANCE.md`); la versión se crea solo cuando la decisión pasa a `APPROVED` por quien defina D5 |

**Aislamiento:** las tablas del Lab no tienen FK de escritura hacia `budget_*`/`forecast_*`; ninguna RPC del Lab escribe en ellas. PROMOTE solo crea una propuesta. Prueba obligatoria: guardar/duplicar/archivar escenarios no cambia ningún hash de budget/forecast.

## 6. RPCs

`f360_board_scenarios_list()`, `f360_board_scenario_get(id)`, `f360_board_scenario_save(id|null, payload, idempotency_key)`, `f360_board_scenario_duplicate(id)`, `f360_board_scenario_archive(id, reason)`, `f360_board_scenario_compare(ids uuid[])`, `f360_board_scenario_propose(id, target 'BUDGET'|'FORECAST', reason)` — todas `require_board_member('FINANCIAL')`.
