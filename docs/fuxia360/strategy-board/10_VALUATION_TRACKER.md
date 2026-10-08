# 10 · Valuation Tracker

> Spec. **"Indicative management scenario — not an independent valuation."**
> Este rótulo aparece en cada pantalla, cada exportación y cada cifra del módulo, sin excepción.

## 1. Qué es

Un registro de **escenarios indicativos de gestión** para conversar internamente (y preparar conversaciones con inversionistas), no una valuación profesional, ni un precio de acciones, ni la base para asignar porcentajes.

## 2. Escenarios

| Escenario | Intención |
|---|---|
| `CONSERVATIVE` | múltiplo bajo / métrica conservadora |
| `BASE` | central |
| `STRATEGIC` | lo que pagaría un comprador estratégico |

Cada escenario (`valuation_scenarios`): `id`, `name`, `kind`, `as_of`, `method` (`REVENUE_MULTIPLE`, `EBITDA_MULTIPLE`, `GMV_MULTIPLE`, `COMPARABLE_TRANSACTION`, `OTHER`), `metric_key` (del catálogo del cockpit), `metric_basis` (`ACTUAL_LTM`, `ACTUAL_FY`, `FORECAST_NTM`, `PLAN_TARGET`), `metric_value` (leído en servidor con `sources[]`, nunca tecleado si existe en el cockpit), `multiple_id`, `result` (calculado), `currency`, `status` (`DRAFT`, `SAVED`, `ARCHIVED`), `notes`.

Reglas:
- Si la métrica base es `MISSING` (p. ej. EBITDA hoy), el escenario **no calcula** (`result = null`, motivo visible).
- `PLAN_TARGET` como base requiere el rótulo adicional "basado en metas, no en resultados".
- Los escenarios se versionan (`valuation_revisions`, append-only).

## 3. Múltiplos (`valuation_multiples`)

Cada múltiplo **debe** llevar: `value`, `kind` (EV/Revenue, EV/EBITDA…), `source` (publicación, transacción, informe), `source_date`, `reason` (por qué aplica a Fuxia), `entered_by`, `entered_at`. Sin `source`/`source_date`/`reason` la RPC rechaza el guardado. Este documento **no propone múltiplos**.

## 4. Participaciones

**Nunca** calcular el valor de la participación de Mario (ni de nadie) mientras no exista un `ownership_snapshot` **formal y aprobado** (`07_CAPITAL_OWNERSHIP.md` §2.1). Hoy no existe → la sección "por socio" no se muestra. Cuando exista, el cálculo será `result × pct` con ambos rótulos (indicativo + fecha del snapshot de ownership) y sin redondeos atractivos.

## 5. Permisos
Scope `VALUATION`. Oculto en modo presentación. No exportable a Investor Room sin acción explícita de ambos (registrada como evento).

## 6. RPCs
`f360_board_valuation_list()`, `f360_board_valuation_save(…)`, `f360_board_valuation_archive(id)`, `f360_board_multiple_add(…)`, `f360_board_multiples_list()`.
