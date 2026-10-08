# 09 · Plan de implementación de Growth

**Fecha:** 2026-10-08. **Estado:** PROPUESTA para revisión. **No se implementa nada** hasta la aprobación explícita de Mario (CLAUDE.md). **Sin migraciones** en este documento: los objetos se describen, no se crean.

**Nota de nombres:** los documentos previos usan G0 (auditoría), G1 (Commerce Facts) y G2 (Measurement) como **fases**. Para no confundir, los sprints de este plan se llaman **S-G0 … S-G4**.

**Reglas transversales (CLAUDE.md):** rama de trabajo (nunca `main`); dry-run antes de cada `db push`; staging primero, después producción con su pase; cada migración con rollback ensayado; cada RPC con `require_role` y sin PII; ningún valor privilegiado viene del cliente; push tras cada commit.

---

## Resumen

| Sprint | Objetivo | Depende de | Complejidad |
|---|---|---|---|
| **S-G0 Measurement Truth** | Que la venta pagada online en producción sea completa, fresca y con historia | D-C1 (backfill), carga de Vault en prod | M |
| **S-G1 Growth Cockpit** | Cockpit con Revenue, Pedidos, AOV, canal; DATA INCOMPLETE donde falte | S-G0 | M |
| **S-G2 Funnel / Campaign Performance** | Gasto, GA4 y ROAS / CAC / MER / CR | Acceso Meta Ads y GA4 | L |
| **S-G3 Product Intent** | Capa unificada de intención por modelo / color / talla / mercado | S-G0; GA4 opcional | M |
| **S-G4 Experiments** | Registro de experimentos con veredicto por venta pagada | S-G1 (S-G2 para ROAS) | S-M |

---

## S-G0 · Measurement Truth

| Campo | Contenido |
|---|---|
| **Objetivo** | Commerce Facts de producción completo (sin huecos), fresco (salud visible), con historia, y con reglas de exclusión y origen claras |
| **Alcance** | (1) Poll de producción: `commerce_poll` gobernado por `orders_mode` en lugar de `stock_sync_mode` (`f360-woo-sync/handler.ts:59-60`); secretos `f360_sync_url` / `f360_sync_secret` en Vault de prod (el tick sale si faltan, `20261008000100:533-535`). (2) `commerce_source_health` incluye targets con `orders_mode = 'on'` (hoy `WHERE t.active AND NOT t.is_production`, `:455`). (3) Backfill histórico de Woo **solo economía + atribución** (D-C1), con `via='backfill'`, sin inventario y sin `order_shipping` salvo D-C2. (4) `f360_pay_link` → origen `storefront_rescue`. (5) Lista de exclusiones auditada. (6) Corregir textos desactualizados de `/growth` (`page.tsx:33`, `lib/data-audit.ts:9-22`). (7) Rate limit + saneo de `search_log` (S1/S2) |
| **Dependencias** | D-C1 aprobada; acceso REST de lectura a Woo producción (ya existe para el webhook); ventana de backfill acordada (PROPUESTA 24 meses) |
| **Impacto en esquema** | `CREATE OR REPLACE VIEW f360.commerce_source_health`; `CREATE OR REPLACE FUNCTION f360.commerce_business_origin` (+1 valor; requiere ampliar el CHECK de `commerce_woo_orders.business_origin`); tabla nueva `f360.commerce_exclusions`; vista `commerce_orders` filtra exclusiones (o columna `excluded`) |
| **Impacto frontend** | `/growth` texto y `GROWTH_QUESTIONS` actualizados; `CommerceFacts.tsx` muestra producción en frescura |
| **Impacto backend** | `f360-woo-sync` (gate del poll); script de backfill parametrizado para producción con guardas (`is_production`, dry-run, conteo antes/después, idempotente); `f360-store-reserve` (`search_log` con límite por IP-hash) |
| **Seguridad** | Backfill con service role desde la máquina de Mario (patrón `scripts/s00a/run.sh`), nunca en el cliente; la lista blanca de `orderEconomics` no cambia (sin PII); exclusiones solo por owner, con motivo y autor del JWT |
| **Pruebas** | Node: gate del poll por `orders_mode`; SQL: salud incluye prod, `storefront_rescue`, exclusiones, CHECK ampliado; backfill dos veces = `unchanged` (repetir el ensayo de `G1B` §4 sobre una **copia local de prod**); `f360_g1_commerce_tests.sql` sigue 47/47; inventario intacto (`woo_orders`, `inventory_events` sin cambios) |
| **Criterios de aceptación** | (a) `commerce_sync_runs` con corridas `ok` cada 15 min en prod; (b) frescura de `woo_production` = VERIFIED en `/growth?vista=commerce` y `/tablero`; (c) pedidos de Woo en el rango acordado = filas en `commerce_woo_orders` (conteo cruzado con Woo admin, diferencia 0); (d) 0 cambios en tablas de inventario y en `order_shipping` por el backfill; (e) pedidos de link de pago con origen `storefront_rescue` |
| **Rollback** | Vista y funciones: `.down.sql` que restaura la definición previa; backfill: filas con `first_captured_via='backfill'` se pueden borrar por llave (las tablas de G1 no tienen dependientes de inventario); poll: volver el gate (un deploy) o `cron.unschedule` |
| **Complejidad** | M |

---

## S-G1 · Growth Cockpit

| Campo | Contenido |
|---|---|
| **Objetivo** | Una pantalla honesta con los 10 KPIs de `03_…`: valores reales donde hay fuente; DATA INCOMPLETE donde no |
| **Alcance** | Vista de canal `channel_rules_v1`; RPC agregado del cockpit; vista mensual de hechos; UI en `/growth` (pestaña principal); filtros periodo / mercado / canal / campaña (UTM) / producto |
| **Dependencias** | S-G0 |
| **Impacto en esquema** | Función `f360.classify_channel_v1(...)` IMMUTABLE; vista `f360.growth_order_channel`; vista `f360.growth_monthly_facts`; RPC `public.f360_growth_cockpit` |
| **Impacto frontend** | `admin-web/src/app/(app)/growth/page.tsx` + componente nuevo `GrowthCockpit.tsx`; `lib/f360.ts` tipo y llamada; tarjetas con estado DATA INCOMPLETE; reemplaza `DataStatusTable` como vista principal (la tabla queda como "Qué falta") |
| **Impacto backend** | Ninguno fuera de SQL |
| **Seguridad** | `require_role('operator')`; sin PII; sin filas por pedido; `REVOKE … FROM anon` |
| **Pruebas** | SQL: una prueba por regla de canal (R0…R9 y alias, con los 82 casos de staging4 como fixture sintético); KPIs con datos faltantes devuelven `status=DATA_INCOMPLETE` y `value=null`; separación por moneda; permisos (seller/viewer/anon rechazados). Playwright: `/growth` en `smoke-readonly.spec.ts` |
| **Criterios de aceptación** | (a) Ningún KPI muestra 0 cuando falta su insumo; (b) Revenue/Pedidos/AOV del cockpit = `f360_commerce_summary` para el mismo periodo; (c) suma por canal = total; (d) Carolina entiende cada tarjeta sin explicación (prueba de lectura con ella) |
| **Rollback** | Quitar la pestaña (deploy) y `DROP` de vistas/RPC nuevas (nada depende de ellas) |
| **Complejidad** | M |

---

## S-G2 · Funnel / Campaign Performance

| Campo | Contenido |
|---|---|
| **Objetivo** | Gasto, sesiones y funnel en F360 para calcular CAC, ROAS, MER y CR con fuente declarada |
| **Alcance** | (1) Import de gasto Meta (CSV de Ads Manager primero; Marketing API `insights` después) a `marketing_spend_daily` + catálogo `marketing_campaigns`; (2) GA4 Data API → `ga4_daily_sessions`, `ga4_purchase_snapshots`; (3) reconciliación GA4 ↔ Commerce Facts (`G2B` §4); (4) `measurement_source_health` (G2-A §3); (5) funnel agregado por día × mercado × dispositivo |
| **Dependencias** | **Acceso a Meta Ads** (y Google Ads si existe); **GA4 Data API** (D1 o D2 de `G2B1` §D); decisión D-FX si la cuenta publicitaria no está en la moneda del mercado |
| **Impacto en esquema** | Tablas: `marketing_spend_daily`, `marketing_campaigns`, `ga4_daily_sessions`, `ga4_purchase_snapshots`, `measurement_runs`; vistas: `ga4_purchase_reconciliation`, `measurement_source_health`, `growth_funnel_daily` |
| **Impacto frontend** | Cockpit: CAC / ROAS / MER / CR dejan de ser DATA INCOMPLETE cuando su fuente está conectada; pestaña "Campañas" (tabla campaña → gasto → PS atribuidas → ROAS F360 vs ROAS reportado) ; pestaña "Funnel" |
| **Impacto backend** | Job programado (Edge `f360-growth-sync` nueva **o** acción en `f360-woo-sync`) con secretos en Supabase; upload de CSV por owner con validación en el servidor |
| **Seguridad** | Tokens de Meta / llaves de GA4 **solo** como secretos de Supabase (nunca en repo, chat ni cliente); permisos de solo lectura (`ads_read`, `analytics.readonly`); import CSV: el servidor valida columnas, moneda y fechas; nada de PII entra (insights son agregados) |
| **Pruebas** | Node: parser de CSV y de `insights` (fixtures), idempotencia por `(platform, account, date, ad_id)`; SQL: reconciliación con casos (pagado sin GA4, GA4 sin pagado, duplicado, MXN vs COP); ROAS = DATA INCOMPLETE si falta un día de gasto |
| **Criterios de aceptación** | (a) Gasto del mes en F360 = gasto en Ads Manager (diferencia 0 en la moneda de la cuenta); (b) cobertura GA4 `purchase` calculada para prod; (c) ROAS F360 y ROAS de Meta lado a lado con etiquetas; (d) re-import de 7 días no duplica |
| **Rollback** | Desactivar el job; `DROP` de tablas nuevas (sin dependencias de inventario ni commerce); revocar tokens en Meta / Google |
| **Complejidad** | L |

---

## S-G3 · Product Intent

| Campo | Contenido |
|---|---|
| **Objetivo** | Saber por modelo / color / talla / mercado cuánta intención hay, cuánta se convierte y cuánta no tiene inventario |
| **Alcance** | Vista `product_intent_events`; RPC `f360_product_intent_report`; resolución canónica en `f360-hilo-intake` (talla MX → canónica); `results_count` y diccionario en búsquedas; GA4 por item (`ga4_item_daily`) si S-G2 está; Avísame en producción si se descongela el storefront |
| **Dependencias** | S-G0; S-G2 (opcional, para VIEW/ATC/CHECKOUT de GA4); aprobación de Avísame en prod |
| **Impacto en esquema** | Vista `product_intent_events`; columnas nuevas en `customer_cases` (`product_id`, `variant_id`, nullable, aditivas); `storefront_searches.results_count` (nullable, aditiva); tabla `search_term_map`; tabla `ga4_item_daily` |
| **Impacto frontend** | Página `/demanda` evoluciona a "Demanda e intención" (no otra página): bloque por modelo con la línea "guardaron / piden aviso / preguntaron / vendidas / disponibles"; `/favoritos` se mantiene |
| **Impacto backend** | `f360-hilo-intake` (resolver producto), `f360-store-reserve` (`results_count`) |
| **Seguridad** | Solo agregados; `subject_ref` nunca sale del servidor; reporte a operator+ (hoy `f360_stock_demand` y `f360_favorites_report` aceptan viewer — decidir) |
| **Pruebas** | SQL: cada fuente aparece una vez por evento; normalización `mx`→`MX`; talla MX 25 → 38; legacy sin homologar = `legacy`; favoritos activos = último evento; suite SQL **nueva para favoritos** (hoy no existe) |
| **Criterios de aceptación** | (a) Para `F360-PAULA-NEGRO-38` el reporte cuadra contra cada tabla de origen; (b) sin PII en la respuesta; (c) Carolina lo lee sin ayuda |
| **Rollback** | `DROP VIEW`/RPC; columnas aditivas nullable se pueden dejar o quitar |
| **Complejidad** | M |

---

## S-G4 · Experiments

| Campo | Contenido |
|---|---|
| **Objetivo** | Que cada prueba de Growth tenga hipótesis, umbrales, resultado y decisión registrados, con veredicto por venta pagada |
| **Alcance** | Tablas `growth_experiments` + `growth_experiment_changes`; RPCs de guardar / transicionar / listar; cálculo de `result` en el servidor; pestaña `/growth?vista=experimentos` |
| **Dependencias** | S-G1 (KPIs); S-G2 para ROAS/CAC |
| **Impacto en esquema** | 2 tablas + 3 RPCs (`06_…` §2) |
| **Impacto frontend** | Lista + formulario + aprobación (owner) |
| **Impacto backend** | Ninguno fuera de SQL |
| **Seguridad** | Escritura operator, aprobación/veredicto owner; actor del JWT; umbrales inmutables desde RUNNING; append-only en la bitácora |
| **Pruebas** | SQL: transiciones válidas/ inválidas; inmutabilidad de umbrales; permisos; `result` calculado igual que el cockpit |
| **Criterios de aceptación** | (a) No se puede pasar a RUNNING sin umbrales; (b) WINNER exige muestra mínima; (c) el resultado no lo escribe el cliente |
| **Rollback** | `DROP` de las 2 tablas y RPCs (sin dependientes) |
| **Complejidad** | S-M |

---

## Objetos propuestos (sin migraciones)

Formato: PURPOSE · SOURCE OF TRUTH · PK · IMPORTANT COLUMNS · FKs · RLS MODEL · WRITE / READ AUTHORITY · RETENTION · AUDIT · EXISTING TABLE THAT MAY ALREADY COVER THIS.

### Reutilizados (no se crean)
| Objeto existente | Uso en Growth |
|---|---|
| `f360.commerce_woo_orders` / `commerce_orders` / `commerce_order_lines` | Venta pagada, revenue, AOV, mezcla de producto |
| `f360.commerce_woo_attribution` | Canal / campaña / creativo / navegador del pedido |
| `f360.order_shipping` | Clave de clienta (hash) y geografía (agregada) |
| `f360.favorite_events`, `anon_visitors` | FAVORITE / ATC desde favoritos |
| `f360.stock_intents` | NOTIFY_ME |
| `f360.customer_cases` | HILO |
| `f360.storefront_searches` | SEARCH |
| `f360.channel_variant_identity` / `channel_product_identity` | Traducción Woo/GA4 → canónico |
| `f360.historical_sales_active` | Totales pre-F360 marcados |
| `f360.growth_plans` / `growth_scenarios` | TARGET / SCENARIO (no ACTUAL) |
| `f360_commerce_summary`, `f360_exec_dashboard`, `f360_favorites_report`, `f360_stock_demand` | Se extienden, no se duplican |

### 1. `f360.growth_order_channel` (VIEW) — S-G1
- **PURPOSE:** canal / plataforma / detalle por pedido online según `channel_rules_v1`.
- **SOURCE OF TRUTH:** `commerce_woo_attribution` (no guarda nada).
- **PK:** `(target_id, woo_order_id)` lógico. **Columnas:** `channel_group`, `platform`, `channel_detail`, `channel_rule_id`, `channel_rules_version`, `utm_campaign_norm`, `utm_content_norm`, `utm_compliant`, `browser_class`, `device_type`.
- **FKs:** lógica a `commerce_woo_orders`. **RLS:** sin grant a `anon`/`authenticated`. **Write:** — . **Read:** RPCs operator+.
- **RETENTION / AUDIT:** las del hecho. **Ya cubre:** nada (diseñado en `G2A` §1 como `commerce_channel_v1`; **este es ese objeto**, renombrado solo si Mario prefiere el nombre de Growth).

### 2. `f360.commerce_exclusions` (TABLE) — S-G0
- **PURPOSE:** excluir de Growth pedidos reales que son pruebas o errores, sin borrar.
- **SOURCE OF TRUTH:** decisión del owner. **PK:** `(target_id, woo_order_id)`. **Columnas:** `reason` (`test`, `duplicate`, `fraud`, `other`), `note`, `decided_by` (JWT), `decided_at`, `revoked_at`.
- **FKs:** `target_id → f360.sales_targets`. **RLS:** service role; escritura por RPC `require_role('owner')`; lectura operator+.
- **RETENTION:** permanente. **AUDIT:** append-only (revocar = nueva marca). **Ya cubre:** `payment_category='test'` y `sales_targets.is_test` cubren solo pruebas evidentes.

### 3. `f360.marketing_campaigns` (TABLE) — S-G2
- **PURPOSE:** catálogo mínimo de campañas de plataforma (Campaign 360 mínimo).
- **SOURCE OF TRUTH:** la plataforma (Meta / Google) vía import. **PK:** `(platform, account_id, campaign_id)`. **Columnas:** `name`, `objective`, `status`, `market` (asignado por regla o por owner), `utm_campaign` esperado, `first_seen`, `last_seen`.
- **FKs:** — . **RLS:** service role; lectura operator+. **Write:** job de import. **RETENTION:** permanente. **AUDIT:** `measurement_runs.run_id`. **Ya cubre:** `public.push_campaigns` (push interno, 0 filas) **no** sirve; no reutilizar.

### 4. `f360.marketing_spend_daily` (TABLE) — S-G2
- **PURPOSE:** gasto e insights diarios por anuncio.
- **SOURCE OF TRUTH:** plataforma publicitaria. **PK:** `(platform, account_id, date, campaign_id, adset_id, ad_id)`. **Columnas:** `spend`, `currency`, `impressions`, `clicks`, `link_clicks`, `reach`, `platform_purchases` (etiqueta "reportado, no verificado"), `platform_purchase_value`, `spend_source` (`api` / `csv` / `manual`), `run_id`, `fetched_at`.
- **FKs:** lógica a `marketing_campaigns`. **RLS:** service role; lectura operator+ (D-G1-05: gasto no es para sellers/viewers). **Write:** job / RPC de upload owner con validación en servidor.
- **RETENTION:** permanente (es contable). **AUDIT:** re-import reemplaza por ventana con `run_id` y conserva `measurement_runs`. **Ya cubre:** nada.

### 5. `f360.ga4_daily_sessions` (TABLE) — S-G2
- **PURPOSE:** denominador de conversión y funnel agregado.
- **SOURCE OF TRUTH:** GA4 Data API. **PK:** `(property_id, date, market, channel_group_ga4, device_category)`. **Columnas:** `sessions`, `engaged_sessions`, `users`, `new_users`, `view_item_sessions`, `add_to_cart_sessions`, `begin_checkout_sessions`, `fetched_at`, `run_id`. `market` derivado de `landingPage` (`/mx/`, `/co/`).
- **RLS:** service role; lectura por RPC operator+. **RETENTION:** 25 meses. **AUDIT:** `run_id`. **Ya cubre:** nada.

### 6. `f360.ga4_purchase_snapshots` (TABLE) + `f360.ga4_purchase_reconciliation` (VIEW) — S-G2
- Diseño **sin cambios** de `G2B_MEASUREMENT_CORRECTION_PLAN.md` §4. PK `(property_id, transaction_id, ga4_date)`. Solo para cobertura; **nunca** revenue.

### 7. `f360.measurement_runs` (TABLE) + `f360.measurement_source_health` (VIEW) — S-G2
- **PURPOSE:** bitácora de corridas de import (GA4, Meta, Google) y frescura por fuente (diseñada en `G2A` §3).
- **PK:** `id` bigint. **Columnas:** `source`, `kind`, `window_from`, `window_to`, `started_at`, `finished_at`, `ok`, `stats`, `error`. **RLS:** service role; lectura operator+. **RETENTION:** 24 meses. **Ya cubre:** `commerce_sync_runs` (solo Woo) — **mismo patrón**; se puede generalizar en vez de crear otra si Mario prefiere (decisión técnica en S-G2).

### 8. `f360.growth_customer_orders` (VIEW) — S-G1 (activa cuando haya historia)
- **PURPOSE:** cada PS con su clave de clienta y su número de orden (1 = nueva).
- **SOURCE OF TRUTH:** `commerce_orders` + `order_shipping` + `customers` + `transactions` (solo enlace). **Columnas:** `external_ref`, `paid_at`, `market`, `customer_key` (uuid o **hash** SHA-256 con sal del servidor; nunca el teléfono), `customer_key_source`, `order_seq`, `is_new`, `history_complete` (bool).
- **RLS:** sin grant; RPC operator+ solo devuelve agregados. **RETENTION:** la de las fuentes. **Ya cubre:** `customer_link_status` en `commerce_orders` (solo tipo de enlace, no secuencia).

### 9. `f360.growth_monthly_facts` (VIEW) — S-G1
- **PURPOSE:** insumos mensuales `ACTUAL` para el cockpit y el forecast (`07_…` §3). **SOURCE:** vistas anteriores. **RLS:** RPC operator+. **Ya cubre:** `f360_commerce_summary` (sin mes, sin gasto).

### 10. `f360.product_intent_events` (VIEW) + `f360.ga4_item_daily` (TABLE) + `f360.search_term_map` (TABLE) — S-G3
- Ver `05_PRODUCT_INTENT.md` §6. `search_term_map`: PK `term_norm`; columnas `product_id`, `decided_by`, `decided_at`; escritura owner/operator por RPC; ya cubre: nada.

### 11. `f360.growth_experiments` + `f360.growth_experiment_changes` (TABLES) — S-G4
- Ver `06_EXPERIMENTS.md` §2–4. **Ya cubre:** `growth_plan_changes` es el patrón de bitácora a imitar.

### 12. `f360.fx_rates` (TABLE) — solo si se aprueba D-FX
- **PK:** `(month, from_currency, to_currency)`. **Columnas:** `rate`, `source`, `approved_by`, `approved_at`. **Write:** owner. **Uso:** solo vistas `CONVERTED`; la vista por moneda original sigue siendo la principal.

### RPCs propuestas
| RPC | Rol | Devuelve |
|---|---|---|
| `f360_growth_cockpit(p_from, p_to, p_market, p_filters)` | operator | KPIs + breakdowns + fuentes (sin PII) |
| `f360_growth_campaigns(p_from, p_to, p_market)` | operator | Campaña → gasto → PS atribuidas → ROAS F360 / reportado |
| `f360_growth_funnel(p_from, p_to, p_market)` | operator | Funnel agregado |
| `f360_product_intent_report(p_from, p_to, p_market, p_product_key)` | operator | Intención por modelo/color/talla |
| `f360_marketing_spend_upload(p_rows jsonb)` | owner | Valida e importa CSV de gasto |
| `f360_commerce_exclude(p_target, p_order, p_reason, p_note)` | owner | Marca exclusión |
| `f360_experiment_save` / `_transition` / `f360_experiments_list` | operator / owner | `06_…` |

---

## Decisiones que necesita Mario

| # | Decisión | Bloquea |
|---|---|---|
| 1 | **D-C1:** ¿backfill de solo lectura del historial de pedidos Woo a Commerce Facts? ¿Cuántos meses? (propuesta 24) | S-G0, nuevas/recurrentes, forecast |
| 2 | ¿Encender el poll de 15 min en producción (cargar Vault y gate por `orders_mode`)? | S-G0 |
| 3 | **D-C2:** retención de `order_shipping` y si el backfill incluye datos de envío históricos (PII) | Geografía histórica, nuevas/recurrentes |
| 4 | **Acceso a Meta Ads** (Ads Manager con permiso de lectura o export CSV diario) y a Events Manager del pixel | S-G2 |
| 5 | ¿Existe cuenta de **Google Ads** con gasto? | S-G2 |
| 6 | **GA4 Data API:** D1 (instalar `gcloud` y autenticarte) o D2 (admin de GA4 crea la service account) | S-G2, CR, funnel |
| 7 | Ventas de tienda legacy (36 de 37): ¿contarlas como `legacy_store` PARTIAL o dejarlas fuera? | Revenue omnicanal |
| 8 | **D-FX:** ¿consolidar monedas con tasa mensual aprobada o siempre separadas? | MER total, ROAS cross-market |
| 9 | Revenue para ROAS/MER = net product (propuesta) vs total cobrado | S-G1/S-G2 |
| 10 | Descongelar storefront para Avísame y Analytics V1.1 en producción | S-G3, identidad en GA4 |
| 11 | Reportes de intención/demanda: ¿viewer/seller o solo operator+? | S-G3 |
| 12 | Las 8 decisiones abiertas de `G2B1_SAFE_CORRECTIONS.md` §G (GTM, P2, zona horaria, Meta M-A) | Funnel GA4, Meta |
