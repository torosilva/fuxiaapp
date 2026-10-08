# 13 · Data Model (propuesto — SIN migraciones)

> Propuesta. Ningún objeto existe. Antes de implementarse, cada tabla pasa por CLAUDE.md regla 4 (revisar migraciones y referencias) y por la revisión de Mario.

## 0. Esquema y convenciones comunes

**Esquema nuevo `f360_board`**, mismo patrón que `f360` (`supabase/migrations/20260925010000_f360_admin_v1_inventory_core.sql:14-16,144-145,397`):

```sql
CREATE SCHEMA f360_board;
REVOKE ALL ON SCHEMA f360_board FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA f360_board TO service_role;          -- solo migraciones/mantenimiento
-- cada tabla: ENABLE ROW LEVEL SECURITY sin políticas (deny-all como 2ª barrera)
REVOKE ALL ON ALL TABLES/FUNCTIONS IN SCHEMA f360_board FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA f360_board REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
```

Por qué un esquema aparte y no `f360`: (1) las funciones SECURITY DEFINER del F360 operativo pueden leer cualquier cosa de `f360`; separarlo hace explícito y grep-able qué toca datos de dirección; (2) `REVOKE … IN SCHEMA f360_board` y default privileges propios; (3) un rollback del módulo = `DROP SCHEMA f360_board CASCADE` + funciones `public.f360_board_*`, sin tocar F360.

**Superficie cliente:** únicamente `public.f360_board_*` (`SECURITY DEFINER`, `SET search_path = pg_catalog, pg_temp`, nombres totalmente calificados, `REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated`), primera instrucción `f360_board.require_board_member(<scope>)`.

**Valores por defecto de los atributos (salvo que la tabla diga otra cosa):**
- RLS MODEL: RLS ON, sin políticas; sin grants a `anon/authenticated`.
- READ AUTHORITY: miembros del board con el scope indicado, vía RPC.
- WRITE AUTHORITY: miembros del board vía RPC con `idempotency_key`; nunca service role desde app/edge.
- RETENTION: indefinida (volumen bajo; registros de gobierno).
- AUDIT: `created_at/created_by` (uid) + `created_by_name` (de `f360.user_roles.display_name`, no del cliente); tablas `*_events`/`*_revisions` append-only con `f360.reject_audit_change()`.
- Dinero: `numeric(14,2)` + `currency text REFERENCES f360.currencies(code)` (existe: `20261005000100_f360_currency_prices.sql:10`).
- Periodos: `period_month date CHECK (period_month = date_trunc('month', period_month))`.

## 1. Acceso

### board_members
- PURPOSE: allowlist de Strategy (Carolina, Mario).
- SOURCE OF TRUTH: esta tabla (decisión de dueños vía migración).
- PK: `auth_user_id uuid` → `auth.users(id)` ON DELETE CASCADE.
- COLUMNS: `display_name`, `scopes text[]` (CHECK ⊆ {OPERATIONAL, FINANCIAL, BOARD, CAP_TABLE, VALUATION, INVESTOR_ROOM}), `active`, `granted_at`, `granted_by_name`, `note`.
- RLS/READ: solo `require_board_member` (definer) la lee; `f360_board_me()` devuelve la fila propia.
- WRITE: **solo migración** (como `f360.customer_pii_viewers`, `20261010000100…:83-93`). Sin RPC.
- AUDIT: trigger → `board_member_changes` (append-only).
- EXISTING: `f360.customer_pii_viewers` (mismo patrón, propósito distinto: PII ≠ finanzas). `f360.user_roles` (se exige además `role='owner'`). No se reutiliza `customer_pii_viewers` para no acoplar dos permisos.

### board_member_changes · access_log
- PURPOSE: historia de altas/bajas; log de cada llamada a `f360_board_*` (allowed/denied).
- PK: `id bigint identity`.
- COLUMNS (access_log): `at`, `auth_user_id`, `rpc`, `scope`, `outcome`, `object_ref`, `params_hash`, `actor_kind` (`human`/`ai_analyst`).
- RETENTION: indefinida.
- AUDIT: append-only.
- EXISTING: `f360.access_changes` (`20260930000100…:43-53`) cubre roles/asignaciones operativas; se podría escribir ahí `what='board_member'`, pero se prefiere tabla propia para que el log sensible no sea legible por quien lea `access_changes`. Denegaciones: patrón `20261001000200_f360_s02_persist_denials.sql`.

## 2. Cierre mensual y finanzas manuales

### fiscal_periods
- PURPOSE: estado del mes (`OPEN`, `IN_REVIEW`, `CLOSED`) y versión de cierre.
- PK: `(period_month, entity_key)`; `entity_key` default `'fuxia'` (D7).
- COLUMNS: `status`, `close_version int`, `closed_at`, `closed_by uuid[]`, `exception_note` (cierre sin fuente fresca).
- WRITE: FINANCIAL; cerrar requiere D5.
- AUDIT: `fiscal_period_events` append-only.
- EXISTING: ninguna.

### monthly_close_entries
- PURPOSE: montos que **no existen** en otro lado: COGS (si no hay costo unitario), OPEX por categoría, marketing spend (hasta que Growth lo publique), caja por cuenta.
- SOURCE OF TRUTH: esta tabla para esos rubros; **nunca** para ventas (ventas = G1/historical_sales).
- PK: `id uuid`; único activo por `(period_month, entity_key, account_key, dimension_key)`.
- COLUMNS: `account_key` (CHECK en catálogo `close_accounts`: `cogs`, `opex_rent`, `opex_payroll`, `opex_tech`, `opex_logistics`, `opex_other`, `marketing_spend_<channel>`, `cash_<account>`), `amount`, `currency`, `source` (texto: "estado de cuenta BBVA sep", "factura proveedor"), `evidence_document_id`, `status` (`active`, `voided`), `void_reason`, `close_version`.
- WRITE: FINANCIAL; corrección = void + nuevo (patrón `f360.historical_sales`, `20261010000200…:11-36`).
- AUDIT: `monthly_close_log` append-only (como `historical_sales_log`, `:42`).
- EXISTING: `f360.reported_figures` (`20260929000100…`) solo admite `metric='revenue_annual'` y es "reportado, no verificado" → no sirve para cierre; se mantiene para su propósito.

### close_actual_snapshots
- PURPOSE: foto congelada de ACTUAL de ventas (desde G1) al cerrar el mes.
- PK: `(period_month, entity_key, close_version)`.
- COLUMNS: `payload jsonb` (KPIs por dimensión), `sources jsonb`, `content_hash`, `taken_at`.
- AUDIT: append-only.
- EXISTING: ninguna (G1 es vivo, no versionado por mes).

### product_cost_versions (condicional, D3)
- PURPOSE: costo unitario por modelo (y opcional variante) con vigencia, para COGS calculado y valor de inventario a costo.
- SOURCE OF TRUTH: aquí **o** en `f360` core si el Core implementa `cost` (`docs/fuxia360/03_DATA_MODEL.md:26`). **Nunca en ambos.**
- PK: `id`; único `(product_id, valid_from)`.
- FK: `product_id → f360.products(id)`.
- COLUMNS: `unit_cost`, `currency`, `valid_from`, `source`, `entered_by`.
- READ: FINANCIAL (el costo no debe ser visible a operator/seller → argumento para que viva en `f360_board`).
- AUDIT: append-only de versiones.

### fx_rates
- PURPOSE: tipos de cambio explícitos para vistas consolidadas.
- PK: `(rate_date, from_ccy, to_ccy, source)`.
- COLUMNS: `rate numeric(18,8)`, `source` (Banxico FIX, BanRep TRM, manual), `entered_by`.
- AUDIT: append-only (corrección = nueva fila con `supersedes`).
- EXISTING: `f360.price_suggestions` (sugerencias MXN→COP de precios) **no** es TC; no reutilizar.

## 3. Budget y Forecast

### budget_versions / budget_lines
- PURPOSE: presupuesto anual mensualizado.
- PK: `budget_versions.id`; `budget_lines (version_id, period_month, metric_key, dim_market, dim_channel, dim_location_id, dim_category_key, currency)`.
- FK: `dim_location_id → f360.locations(id)`, `dim_category_key → f360.categories(key)`, `currency → f360.currencies`.
- COLUMNS: version `fiscal_year`, `status` (`DRAFT`, `APPROVED`, `SUPERSEDED`), `decision_id`; line `amount`, `note`.
- WRITE: DRAFT editable; `APPROVED` congelado por trigger (solo vía decisión aprobada).
- EXISTING: `f360.growth_plans` (un número anual) — se usa como referencia del total anual 2027, no como budget mensual.

### forecast_versions / forecast_lines / forecast_drivers
- PURPOSE: rolling 18M versionado y driver-based.
- PK: versions `id`; lines como budget + `method`, `role` (`total`|`decomposition`); drivers `(line_id, driver_key)`.
- COLUMNS: version `window_start`, `status` (`DRAFT`, `PUBLISHED`, `SUPERSEDED`), `based_on_close_version`; driver `value`, `source` (`ACTUAL_SEED`, `GROWTH_FACT`, `ASSUMPTION`), `rationale`.
- WRITE: FINANCIAL; publicar recalcula en servidor.
- AUDIT: publicación → snapshot.

### forecast_snapshots / forecast_snapshot_lines
- PURPOSE: memoria inmutable para Forecast Accuracy.
- AUDIT: append-only estricto. RETENTION: indefinida.

## 4. Escenarios y plan

### scenarios / scenario_revisions
- PURPOSE: Scenario Lab.
- COLUMNS: `name`, `kind` (`CONSERVATIVE`, `BASE`, `AGGRESSIVE`, `CUSTOM`), `horizon_months`, `status` (`DRAFT`, `SAVED`, `ARCHIVED`), `base_ref`, `duplicated_from`, `imported_from` (p. ej. `growth_scenarios:2027:base`), `inputs jsonb` (validado), `outputs jsonb` (calculado en servidor), `revision`.
- FK: ninguna hacia budget/forecast (aislamiento).
- EXISTING: `f360.growth_scenarios` (3 fijos por año, operator-legible) — se importa, no se reemplaza.

### plan_versions / plan_years / plan_initiatives / plan_revisions
- PURPOSE: plan 5 años (TARGETS).
- COLUMNS: ver `05_FIVE_YEAR_PLAN.md` §2–3.
- EXISTING: `f360.growth_plans` (North Star 2027 = 15M en prod) — fuente para 2027 o derivada, D8.

## 5. Gates
### strategic_gates / gate_requirements / gate_evaluations
- PURPOSE: ver `06`.
- FK: `gate_evaluations.gate_id`, `strategic_gates.decision_id → decisions`.
- AUDIT: evaluaciones append-only; cambios de status → `gate_events`.

## 6. Capital
### legal_entities · cap_parties · ownership_instruments · ownership_snapshots · capital_rounds · capital_commitments · capital_movements · capital_deployments · capital_documents
- PURPOSE: ver `07`.
- READ/WRITE: scope `CAP_TABLE`; transiciones a `COMMITTED/FUNDED` y `ownership_snapshots` con doble aprobación (D5).
- AUDIT: `capital_movements` y `ownership_snapshots` append-only; montos de commitments no editables tras `COMMITTED` (cambios por movimiento).
- RETENTION: indefinida (registros societarios).
- EXISTING: ninguna.

## 7. Consejo
### board_meetings · board_agenda_items · board_packs · minute_versions · decisions · decision_revisions · decision_events · action_items · action_item_events
- PURPOSE: ver `08`.
- AUDIT: `decisions` con trigger que congela contenido tras `APPROVED/REJECTED`; DELETE rechazado; revisiones/eventos append-only; `board_packs` inmutable tras `ISSUED` (`content_hash`).
- EXISTING: ninguna. (`f360.customer_cases`, `20261007002600`, es atención a clientas — no aplica.)

## 8. Investor Room y valuación
### investor_room_items · investor_room_events
- Storage: bucket privado `board-private` (no existe; los 3 buckets actuales son públicos). D9.
### valuation_scenarios · valuation_revisions · valuation_multiples
- Ver `10`. `valuation_multiples` exige `source`, `source_date`, `reason` NOT NULL.

## 9. AI Analyst (futuro)
### ai_analyst_sessions · ai_analyst_messages
- Ver `12`. RETENTION: 12 meses (D11).

## 10. Vistas de lectura (sobre lo existente, sin copiar)

| Vista / función | Lee | Propósito |
|---|---|---|
| `f360_board.v_sales_actual_monthly` | `f360.commerce_orders` (countable, sin `is_test` cuando hay target prod), `f360.historical_sales_active` | ACTUAL mensual por moneda × market × channel × location × category (mismas reglas que `f360_exec_dashboard`) |
| `f360_board.v_inventory_position` | `f360.inventory_balances`, `f360.locations` (excluye `transit`), `product_cost_versions` | pares; valor a costo solo si D3 |
| `f360_board.v_customer_aggregates` | `public.customers`, `commerce_orders.loyalty_customer_id/woo_customer_id` | nuevas/recurrentes/tasa — **solo conteos** |
| `f360_board.v_growth_facts` | vistas publicadas por Growth (`docs/fuxia360/growth/00–09`) | sesiones, spend, atribución — cuando existan |
| `f360_board.forecast_accuracy` | snapshots + `close_actual_snapshots` | `11` |

Las vistas viven en `f360_board` (sin grants) y solo las consumen funciones definer.

## 11. Catálogo de métricas (`metric_catalog`)
`metric_key` (revenue_net_product, revenue_gross_product, orders, aov, units, new_customers, repeat_customers, repeat_rate, cogs, gross_profit, gross_margin, opex, ebitda, cash, inventory_units, inventory_value_cost, inventory_value_retail, marketing_spend, cac_blended, roas, mer), `definition`, `unit`, `source_kind` (`G1`, `CLOSE`, `DERIVED`, `GROWTH`), `available` (calculado). Lo usan cockpit, gates, valuación y AI analyst — un solo vocabulario.
