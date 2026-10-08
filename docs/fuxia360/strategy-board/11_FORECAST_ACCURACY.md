# 11 · Forecast Accuracy

> Spec. Mide qué tan bien pronostican Carolina y Mario, para calibrar el forecast y dar credibilidad ante un inversionista.

## 1. Snapshots inmutables

- Cada `forecast_version` publicada genera `forecast_snapshots` (`id`, `forecast_version_id`, `taken_at`, `kind` = `PUBLISH` | `SCHEDULED_MONTHLY`, `content_hash`) y `forecast_snapshot_lines` (mes objetivo × dimensiones × métrica × valor × moneda × método).
- Además, un snapshot programado el día 1 de cada mes de la versión vigente (cron, mismo patrón que los jobs existentes `f360-commerce-poll`, `f360-reservations-expire`… listados en `cron.job` de prod), para que siempre haya foto aunque nadie publique.
- Append-only: `f360.reject_audit_change()` en ambas tablas (patrón existente). Nada de UPDATE/DELETE, ni por la RPC.

## 2. Horizontes

Para cada mes objetivo M ya **cerrado** (cierre mensual `CLOSED`), se busca el último snapshot tomado **antes de** M − 30, M − 60 y M − 90 días (aprox. 1, 2 y 3 meses de anticipación).

| Horizonte | Snapshot usado |
|---|---|
| 30d | último snapshot con `taken_at ≤ inicio(M) − 30 días` |
| 60d | `≤ inicio(M) − 60 días` |
| 90d | `≤ inicio(M) − 90 días` |

Si no existe snapshot para un horizonte, la celda dice "sin snapshot" (no se interpola).

## 3. Métricas

Por métrica (revenue, orders, AOV, …), dimensión y horizonte:

| Medida | Fórmula |
|---|---|
| Absolute error | \|F − A\| |
| % error (APE) | \|F − A\| ÷ \|A\| (indefinido si A = 0 → se muestra "n/a") |
| Bias | (F − A) ÷ \|A\| con signo; promedio en el periodo → + sobre-pronóstico, − sub-pronóstico |
| WAPE (agregado) | Σ\|F − A\| ÷ Σ\|A\| — preferido sobre MAPE para series pequeñas |
| forecast_version | id + nombre de la versión que originó F |

A = ACTUAL del **cierre** (snapshot de cierre, `02_CEO_COCKPIT.md` §3), no el ACTUAL vivo, para que la medición no cambie si G1 recibe un reembolso tardío; la diferencia se muestra aparte.

Moneda: error calculado en moneda original; no se mezclan monedas.

## 4. Implementación

Vista/función de solo lectura `f360_board.forecast_accuracy` calculada desde snapshots + cierres (no se guarda el resultado; es determinístico). RPC `f360_board_forecast_accuracy(p_from, p_to, p_metric, p_horizon)` — scope `FINANCIAL`.

## 5. Realidad de datos

El primer mes con cierre posible es octubre 2026, y el primer horizonte de 90d con snapshot real sería ~enero 2027 (si el primer snapshot se toma en oct-2026). La pantalla debe explicarlo en vez de mostrar tablas vacías sin contexto.
