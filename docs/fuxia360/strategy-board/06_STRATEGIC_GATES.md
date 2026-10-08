# 06 · Strategic Gates

> Spec. Un gate es una **condición medible** que debe cumplirse (o ser excepcionada con decisión registrada) antes de una apuesta mayor.

## 1. Gates iniciales

| Gate | Pregunta | Métricas candidatas (fuente) |
|---|---|---|
| APPAREL PILOT | ¿Probamos ropa? | repeat rate (cockpit), gross margin (D3), base de clientas activas, caja disponible, capacidad operativa |
| NEW STORE | ¿Abrimos otra tienda? | revenue por tienda vs costo fijo (OPEX por location), payback, ticket y transacciones de tiendas existentes (G1 store), inventario disponible |
| NEW CITY | ¿Otra ciudad en México? | demanda online por estado/ciudad (requiere dato de envío agregado, sin PII — hoy no existe como agregado), desempeño de bazares (`historical_sales` kind=bazaar; prod: 2 bazares) |
| NEW COUNTRY | ¿Otro país (o escalar CO)? | revenue `market=CO` (G1; COP aparte), costo logístico, márgenes por moneda, entidad legal |
| NEW CATEGORY | ¿Accesorios u otra categoría? | % de clientas recurrentes, AOV, margen, inventario capital requerido |
| CAPITAL RAISE | ¿Levantar capital? | runway (caja ÷ quema mensual — requiere cierre), cumplimiento de plan, forecast accuracy |
| MAJOR INVENTORY EXPANSION | ¿Compra/producción grande? | sell-through, rotación, unidades a producir (cadena de inventario `03`), caja |

Los umbrales **no se proponen aquí con cifras**: los fijan Carolina y Mario al activar cada gate. Este documento no inventa thresholds.

## 2. Campos (`strategic_gates`)

| Campo | Tipo | Notas |
|---|---|---|
| id | uuid | |
| name | text | uno de los anteriores o nuevo |
| description | text | |
| status | enum | `LOCKED`, `ELIGIBLE`, `UNDER_REVIEW`, `APPROVED`, `REJECTED`, `DEFERRED` |
| required_metrics | jsonb[] → tabla `gate_requirements` | `{metric_key, comparator, threshold, currency?, window, source}` — `metric_key` debe existir en el catálogo de KPIs del cockpit |
| thresholds | (en `gate_requirements`) | |
| evidence | → `gate_evaluations` + documentos | snapshot de valores medidos al evaluar, con `sources[]` |
| decision | text | resumen; la decisión formal vive en el Decision Log |
| decision_date | date | |
| approved_by | uuid[] | miembros del board |
| decision_id | uuid | FK a `decisions` |
| related_plan_year | int | vínculo al plan 5 años |
| notes | text | |

## 3. Máquina de estados

```
LOCKED ──(evaluación automática: todos los requisitos cumplidos)──► ELIGIBLE
LOCKED/ELIGIBLE ──(un dueño abre revisión)──► UNDER_REVIEW
UNDER_REVIEW ──(decisión APPROVED en Decision Log)──► APPROVED
UNDER_REVIEW ──(decisión REJECTED)──► REJECTED
UNDER_REVIEW ──(decisión DEFERRED + fecha de revisión)──► DEFERRED ──(fecha)──► LOCKED|ELIGIBLE
```

- `ELIGIBLE` lo calcula el servidor (`f360_board_gate_evaluate`) con valores ACTUAL; **nunca** con FORECAST ni SCENARIO (o con FORECAST solo si el requisito lo declara explícitamente `basis='forecast'`).
- Aprobar un gate con requisitos **no cumplidos** es posible solo como **excepción**: la decisión debe llevar `override_reason` y lo aprueban ambos dueños (D5).
- Cada evaluación se guarda en `gate_evaluations` (append-only): valores, umbrales, resultado, `sources[]`, versión de datos (cierre usado).
- Una métrica `MISSING` (p. ej. margen hoy) deja el requisito en `UNKNOWN`, nunca en "cumplido".

## 4. RPCs

`f360_board_gates_list()`, `f360_board_gate_get(id)`, `f360_board_gate_define(…)` (DRAFT de requisitos), `f360_board_gate_evaluate(id)`, `f360_board_gate_open_review(id)`, `f360_board_gate_decide(id, decision_id)` — scope `BOARD`.
