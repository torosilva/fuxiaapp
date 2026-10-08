# S-G0 · Measurement Truth — Entrega (STAGING)

**Fecha:** 2026-10-08. **Rama:** `fuxia-360`. **Alcance autorizado por Mario (2026-10-08):** implementar SOLO en staging (`faltx…`). **Producción: nada** (ni migraciones, ni datos, ni deploys, ni Woo, ni RLS). Producción solo se leyó con `scripts/f360/prod_read.sh` (agregados, sin PII) y la API REST de Woo de producción solo con GET de agregados (sin guardar datos de clientas).

Specs implementadas: `00_GROWTH_MASTER.md`, `02_MEASUREMENT_TRUTH.md`, `03_GROWTH_COCKPIT.md`, `07_GROWTH_FORECAST_INPUTS.md`, `08_GROWTH_GAP_ANALYSIS.md` (#1, #2, #3, #5, #8, #30), `09_GROWTH_IMPLEMENTATION_PLAN.md` §S-G0.

---

## 1. Qué se construyó

| # | Decisión | Implementación | Dónde |
|---|---|---|---|
| D1 | Historial Woo 24 meses | Importación idempotente `commerceHistoryImport` (ids primero, pedido completo solo si falta / está desactualizado), `p_via='backfill'` → `capture_source = woo_history_import`, `imported_at = first_captured_at`; respeta el corte (`orders_since_id`): ids posteriores son tiempo real; nunca relabela un pedido de webhook; nunca toca inventario ni `order_shipping` (PII, D-C2 abierta); dry-run | `_shared/f360-woo/commerce.ts`, `scripts/f360/sg0_woo_history_import.mjs` (solo staging4) |
| D2 | Conciliación (P0) | `commerceReconcile`: lista stubs de Woo (`_fields=id,status,date_modified_gmt`), `f360_commerce_reconcile_diff` (missing / outdated / before_cutover_missing / current), recupera por la ÚNICA ruta de captura (`p_via='poll'` → `woo_reconciliation_recovered`), log en `commerce_sync_runs` (`kind='reconcile'`, stats: `woo_seen, current, detected_missing, recovered, detected_outdated, refreshed, before_cutover_missing, errors, error_order_ids, mode`). El gate pasa de `stock_sync_mode` a `orders_mode` (`f360-woo-sync/handler.ts`). `commerce_poll` (cron) ahora ejecuta la conciliación; `commerce_reconcile` + `lookback_hours` = revisión profunda (solo owner/operator). Primera corrida en prod empieza en la creación del pedido de corte − 1 día | `20261014000100`, `f360-woo-sync/handler.ts` |
| D3 | Gasto | Tablas append-only `marketing_spend_imports` / `marketing_spend_rows`, vista efectiva `marketing_spend_daily` (la importación aceptada más nueva por plataforma × cuenta × día; anular devuelve la anterior). RPC `f360_marketing_spend_upload` (owner; valida cada fila en el servidor; archivo con 1 error = rechazado completo y el intento queda auditado; mismo contenido = `duplicate`). Upload CSV en `/growth?vista=medicion` (owner). API = arquitectura (§5), sin credenciales | `20261014000200`, `admin-web/src/lib/spend-csv.ts`, `SpendUpload.tsx` |
| D4 | GA4 | Registro de fuente + `measurement_runs` (log para el conector). Estados NOT_CONFIGURED / CONFIGURED / HEALTHY / STALE / ERROR. GA4 `purchase` nunca es venta pagada | `20261014000600` |
| D5 | Costo de producto | `f360.product_cost_versions` versionado (producto, variante opcional, mercado opcional, monto, moneda, vigencia, fuente, notas, creado por, aprobado por). Proponer = owner/operator; aprobar/rechazar = owner. Aprobar cierra la versión anterior (`effective_to`); nada más se modifica nunca (trigger); no se borra; no se permite reescribir hacia atrás | `20261014000400` |
| D6 | Definiciones de revenue | Vista `f360.measurement_sales` (§3) | `20261014000600` |
| D7 | Moneda | `f360.fx_rates` (mensual, base MXN, propuesto → aprobado por owner, anulación con motivo; inmutable). `f360.fx_rate_for` → NULL sin tasa aprobada → consolidado = DATA_INCOMPLETE | `20261014000300` |
| D8 | Ventas legacy | `f360.legacy_store_sale_imports`: registro auditado (no copia) de que una venta `offline_sales.created_by_rpc=false` entra al historial como `LEGACY_IMPORT`; validación por venta; `needs_review` no cuenta. Owner, dry-run, idempotente, append-only. **No cambia** `commerce_orders`, `f360_commerce_summary` ni `f360_exec_dashboard` | `20261014000500` |
| D9 | Cali | Nada creado (sin tienda, sin datos) | — |
| — | MEASUREMENT HEALTH | `f360_measurement_health()` y `f360_measurement_truth(from,to)` (operator+), `f360_measurement_sales_list`, `f360_measurement_source_set` (owner). UI: pestaña **Medición** en `/growth` | `20261014000600`, `admin-web` |
| D14 | Avísame + identidad GA4 | **No hecho** (prioridad baja; sin tiempo tras lo requerido) | — |

## 2. Esquema (todo aditivo; staging)

| Migración | Objetos | Rollback |
|---|---|---|
| `20261014000100_f360_sg0_order_reconciliation` | `f360.sg0_order_target`, `f360.sg0_orders_path_on`, CHECK `commerce_sync_runs.kind` + `reconcile`, `f360_commerce_reconcile_begin`, `f360_commerce_reconcile_diff` (service role), `commerce_source_health` (incluye prod si `orders_mode='on'`), `f360_channel_mode` (+`orders_mode`, `orders_since_id`) | `supabase/rollbacks/20261014000100_…down.sql` |
| `…0200_f360_sg0_marketing_spend` | 2 tablas, vista, guard, RPCs upload / void / imports | `…0200….down.sql` (tablas solo si vacías) |
| `…0300_f360_sg0_fx_rates` | tabla, guard, `fx_rate_for`, RPCs propose / approve / void / list | `…0300….down.sql` |
| `…0400_f360_sg0_product_cost` | tabla, guard, vista `product_cost_effective`, RPCs propose / decide / history | `…0400….down.sql` |
| `…0500_f360_sg0_legacy_store_sales` | registro, `legacy_sale_check`, RPC import | `…0500….down.sql` |
| `…0600_f360_sg0_measurement_truth` | `measurement_sources` (8 filas de configuración, sin credenciales), `measurement_runs`, vista `measurement_sales`, health / truth / list / source_set | `…0600….down.sql` |

Compatibilidad: las migraciones leen `orders_mode` / `orders_since_id` con `to_jsonb(t)`, así que funcionan con y sin `20261012001100` (staging no la tiene; producción sí). Ensayadas con su rollback en `BEGIN … ROLLBACK` antes de aplicarse.

## 3. D6 · Definiciones de revenue (sin un "revenue" ambiguo)

Por venta, en **moneda original**, en `f360.measurement_sales`:

| Campo | Definición |
|---|---|
| `gross_merchandise_value` | Σ `line.subtotal` (precio después de reglas de precio tipo WDR, antes de cupones), sin envío ni impuestos |
| `discounts` | Cupones = Σ(subtotal − total) = `discount_total`. Las rebajas directas (WDR / precio de oferta) ya están dentro del subtotal: no se reconstruyen (`list_price_hint` es secundario, nunca revenue) |
| `product_net` | Σ `line.total` (después de cupones, sin envío, sin impuestos) |
| `product_net_before_tax` | `product_net` **solo si** Woo separó impuestos; si no, NULL |
| `tax_iva`, `iva_treatment` | `total_tax`. En producción Woo tiene impuestos desactivados (`total_tax = 0` en los 84 pedidos, lectura 2026-10-08) → `included_not_separated`. **No se calcula IVA** (supuesto no probado) |
| `shipping_charged` | `shipping_total` (aparte; nunca en ROAS/MER) |
| `refunds` / `refunds_product` | Reembolsos Woo (positivos); sin detalle de línea → se asume producto y la venta queda PARTIAL |
| `net_product_revenue` | `product_net − refunds_product` (≥ 0) — **base de ROAS / MER** cuando la venta es pagada |
| `total_collected` | `order_total − refunds` |

Reglas: solo cuentan ventas `is_paid_sale` (`processing` / `completed` / `refunded`, venta de tienda por RPC, legacy `imported`). `cancelled` (nunca pagado) y `paid→cancelled` (`reversed`) no cuentan; reembolso total = pedido pagado con revenue 0; reembolso parcial = resta solo el producto reembolsado. Cambios (Fuxia opera con cambios) no alteran la venta original. **La historia no se recalcula**: son vistas sobre los hechos capturados.

## 4. Pruebas

| # | Prueba | Resultado | Archivo |
|---|---|---|---|
| 9 | Conciliación idempotente | PASS (Node + SQL) | `_shared/f360-woo/test/reconcile.test.ts`; `supabase/staging/test_sg0_reconciliation.sql` |
| 10 | Importación histórica idempotente | PASS (Node + SQL + corrida real staging4: 90 vistos, 90 al día, 0 importados, inventario intacto) | ídem + `scripts/f360/sg0_woo_history_import.mjs` |
| 11 | No se puede duplicar un pedido Woo | PASS | ídem |
| 12 | Cancelado no es revenue pagado | PASS | `supabase/staging/test_sg0_measurement.sql` |
| 13 | Reembolso total / parcial / sin detalle | PASS | ídem |
| 14 | COP/USD nunca sumados con MXN | PASS | ídem |
| 15 | FX faltante → DATA_INCOMPLETE | PASS | ídem |
| 16 | Sin gasto: CAC/ROAS/MER ≠ 0 (null + DATA_INCOMPLETE) | PASS | ídem |
| 17 | Legacy queda LEGACY_IMPORT | PASS | ídem |
| 18 | Versiones de costo conservan historia | PASS | ídem |
| 20 | Flujo de venta de vendedora sigue funcionando | PASS: `test_store_sale_customer.sql` (con `20261013000100/200` dentro de la misma transacción deshecha: "all checks passed") + `f360_s02_tests.sql` 28/28 | — |

Suites: `test_sg0_reconciliation.sql` 31/31, `test_sg0_measurement.sql` 45/45; existentes con S-G0 aplicado: `f360_g1_commerce_tests` 47/47, `f360_exec_dashboard_tests` 17/17, `f360_g2_identity_tests` 18/18, `f360_historical_sales_tests` 26/26, `f360_s02_tests` 28/28, `f360_pay_links_tests` 9/9. Node: f360-woo 63/63 (51 previas + 12 nuevas; sin `contract.local`), f360-whatsapp 5/5, admin-web 15/15 (`spend-csv` nuevo). `tsc --noEmit` y eslint limpios en lo tocado.

## 5. Arquitectura de conectores (sin credenciales; no bloquea S-G0)

- **GA4 Data API** (D4): Edge Function `f360-growth-sync` (o acción en `f360-woo-sync`), service account de solo lectura (`analytics.readonly`) en secretos de Supabase; diario D+1 con re-lectura de 3 días; escribe agregados (sesiones / funnel por día × mercado por ruta × canal × dispositivo) y un renglón en `measurement_runs`. Estado: NOT_CONFIGURED → (owner marca CONFIGURED) → HEALTHY / STALE (> 36 h) / ERROR. GA4 `purchase` solo mide cobertura, nunca revenue.
- **Meta Marketing API / Google Ads API** (D3): token `ads_read` / developer token de solo lectura en secretos; `insights` diario por anuncio, re-importa 7 días; escribe una importación `source='api'` en las mismas tablas (la API nunca usa el RPC del owner) + `measurement_runs`. El "Purchase" / ROAS de Meta nunca se usa (DQ-01).
- **Fallback CSV** (implementado): owner, validado, auditado, idempotente.

## 6. Decisiones abiertas

**De negocio (bloquean números, no código):** (1) ¿Hay gasto en Google Ads? y confirmar Meta (`f360_measurement_source_set(... p_spend_expected)`), hoy UNKNOWN → MER bloqueado a propósito. (2) Tasas FX mensuales aprobadas COP/USD y su fuente (Banxico FIX?). (3) ¿Precios Woo/tienda incluyen IVA? (contadora/Carolina). (4) Ventas legacy en periodos de bazar con resumen histórico de Carolina: cuál cuenta (hoy `needs_review`). (5) Ubicación de los 4 canales legacy (`locations.legacy_channel_id` vacío en prod → `location_unresolved`). (6) D-C2: PII histórica en el import (hoy NO se importa). (7) Entidades legales / Cali (D9): pendiente Carolina. (8) Revenue para ROAS/MER = net product (aplicado como indicó Mario; confirmar para tienda). (9) ¿Acceso de lectura a Meta Ads / export diario? 
**G2B1 §G (8):** ninguna bloquea S-G0 (son GTM / GA4 / Meta pixel). Bloquean S-G2: #5 (Data API), #7 (acceso Meta). #6 (zona horaria GA4) afecta cortes por día de GA4, no a F360.

## 7. Plan de activación en PRODUCCIÓN (no ejecutado; aprueba Mario)

Pre-requisitos: aprobación explícita de Mario de este documento; ventana sin pedidos en curso preferible.
1. **Rama / pase**: el pase de producción usa `scripts/f360/prod_sql.sh` (dry-run primero: `--dry-run` con cada `supabase/staging/test_sg0_*.sql` contra prod en transacción deshecha; deben dar `ENSAYO OK`). Los tests usan los usuarios sintéticos de staging: para prod se ensaya solo la migración + `select f360.sg0_source_health()`.
2. **Migraciones en orden** `20261014000100` → `0600`, cada una en una transacción con su fila en `supabase_migrations.schema_migrations` (sin `db push`, para no arrastrar migraciones de otras sesiones). Verificar después: `select * from f360.commerce_source_health` muestra `woo_production` (UNVERIFIED hasta la 1.ª corrida).
3. **Deploy** de `f360-woo-sync` a prod (`scripts/f360/deploy_prod_function.sh f360-woo-sync`, `--no-verify-jwt`), con secretos ya existentes `WOO_*`, `F360_SYNC_SECRET`, `WOO_TARGET_KEY=woo_production`. Confirmar: `stock_sync_mode='off'` sigue igual (el deploy no empuja stock: el gate de stock no cambió).
4. **Vault de prod** (hoy vacío): `vault.create_secret('<url de f360-woo-sync prod>', 'f360_sync_url')` y `vault.create_secret('<F360_SYNC_SECRET>', 'f360_sync_secret')` — lo hace Mario (o con él presente) desde el SQL editor; nunca en chat ni repo. **Ojo:** el mismo `f360_sync_url` también lo usaría `f360.sync_tick` (empuje de stock cada minuto) si su cron existe en prod: verificar `select jobname from cron.job` antes; con `stock_sync_mode='off'` el handler responde "stock apagado", sin efecto en Woo.
5. **Cron**: `f360-commerce-poll` ya existe en prod (cada 15 min, hoy no-op). Al cargar Vault empieza a llamar `commerce_poll` → conciliación. Primera corrida: desde la creación del pedido 5351 − 1 día.
6. **Verificar 1 h**: `f360_measurement_health()` → `order_reconciliation` HEALTHY; `commerce_sync_runs` con `kind='reconcile' ok` cada 15 min; `detected_missing` = `recovered`; inventario (`woo_orders`, `inventory_events`) sin cambios por la conciliación (solo economía).
7. **Historial (D1)**: pase separado, con su propio OK. Script de producción a revisar (variante de `sg0_woo_history_import.mjs` con guardas `is_production`, dry-run obligatorio, conteo antes/después). Producción tiene **84 pedidos Woo en total** (2026-06-12 → 2026-10-08; 48 MXN, 31 COP, 5 USD): dry-run → importar → re-correr (debe dar 0) → cruce con Woo admin (diferencia 0). Efecto conocido: `/tablero` y `f360_commerce_summary` mostrarán ventas desde junio (es el objetivo de D-C1).
8. **Legacy (D8)**: owner corre `f360_legacy_store_sales_import(true)` (dry), revisa `issues` (overlap con bazares de Carolina, ubicación sin resolver), y solo con su OK `(false)`.
9. **admin-web**: deploy normal (`scripts/f360/deploy_prod_admin.sh`) con la pestaña Medición.
Aprueba: **Mario** (todo); Carolina para D8 (legacy) y tasas FX/costos.

## 8. Rollback de producción

- Conciliación: volver a desplegar el `f360-woo-sync` anterior (commit previo) **o** `select cron.unschedule('f360-commerce-poll')` **o** borrar los 2 secretos de Vault (tick vuelve a no-op). Los pedidos recuperados son hechos reales de Woo: se conservan.
- Migraciones: `supabase/rollbacks/20261014000600 → 0100 .down.sql` en orden inverso (las tablas con datos — gasto, FX, costos, registro legacy — se conservan salvo OK explícito de Mario).
- Historial: filas `first_captured_via='backfill'` borrables por llave (`commerce_woo_orders` → cascada a líneas/atribución/reembolsos; no hay dependientes de inventario) — solo con OK de Mario.
- admin-web: redeploy del commit anterior.

## 9. Datos que siguen faltando

Gasto (0 filas; sin acceso), GA4 (sin API), tasas FX (0 aprobadas → consolidado DATA_INCOMPLETE), costos de producto (0), historial Woo de producción (pendiente pase), identidad / nuevas vs recurrentes (S-G1), reglas de canal para ROAS (S-G1), ubicación de canales legacy.

## 10. Nota de entorno

Staging **no tiene** las migraciones de producción `20261012001100` (orders_production) ni `20261013000100…0700`. No se aplicaron (el intento de aplicar `20261012001100` fue denegado por permisos; quedan como decisión de Mario). Por eso las migraciones S-G0 leen `orders_mode` sin referenciar la columna. La prueba 20 corrió `20261013000100/200` solo dentro de una transacción deshecha.
