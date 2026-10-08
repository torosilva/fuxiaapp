# 08 · Análisis de gaps de Growth

**Fecha:** 2026-10-08. **Base:** `01_CURRENT_STATE_AUDIT.md` (evidencia y citas). Prioridad: **P0** bloquea cualquier número confiable · **P1** necesario para el cockpit · **P2** valor alto, no bloqueante · **P3** después.

| # | CAPABILITY | STATUS | CURRENT SOURCE | CONFIDENCE | GAP | BLOCKER | PROPOSED SOLUTION | PRIORITY |
|---|---|---|---|---|---|---|---|---|
| 1 | Captura de pedidos online en tiempo real | LIVE | `f360-woo-orders` → `f360_capture_order_economics` | ALTA | Solo webhook; un webhook perdido no se recupera | Poll no corre en prod (Vault vacío + gate `stock_sync_mode` en `f360-woo-sync/handler.ts:59-60`) | Desacoplar `commerce_poll` del modo de stock (usar `orders_mode`), cargar secretos de Vault de prod para el tick | **P0** |
| 2 | Salud / frescura de la fuente online | PARTIAL | `f360.commerce_source_health` | — | Excluye producción (`20261008000100:455`); el tablero recibe `sources=[]` | Definición de la vista | Redefinir con `orders_mode='on'` en vez de `active AND NOT is_production` | **P0** |
| 3 | Historial de pedidos Woo (antes del corte 5351) | MISSING | Solo en Woo | — | Sin historia: no hay nuevas/recurrentes, estacionalidad ni AOV histórico | **Decisión D-C1** | Backfill de solo lectura con `g1_commerce_backfill.mjs` (`via=backfill`), **sin** inventario ni `order_shipping` (PII) salvo decisión D-C2 | **P0** |
| 4 | Clasificación del pedido 5351 y futuros pedidos de prueba | PARTIAL | `payment_category='test'`, `is_test` | MEDIA | No hay forma de excluir un pedido real de prueba sin borrarlo | — | `f360.commerce_exclusions` (lista auditada) | P1 |
| 5 | Ventas de tienda en Commerce Facts | PARTIAL | `offline_sales` con `created_by_rpc` (1 de 37) | ALTA en lo capturado | 36 ventas legacy no cuentan | Decisión de negocio | Decidir: (a) contarlas como `legacy_store` con calidad PARTIAL, o (b) dejarlas fuera y declararlo | P1 |
| 6 | Pedidos por link de pago | PARTIAL | `created_via='f360_pay_link'` | MEDIA | `origin_unknown`; sin atribución | — | Mapear a `storefront_rescue`; heredar atribución del pedido fallido si es posible (`04_…` F-1) | P1 |
| 7 | Vista de canal (`channel_rules_v1`) | PLANNED | `G2A` §1 | — | No construida | — | Vista `f360.growth_order_channel` + función inmutable + pruebas por regla | **P1** |
| 8 | Gasto publicitario (Meta) | **MISSING** | — | — | Sin spend, impresiones, clics, IDs | **Acceso a Meta Ads** (Ads Manager / Marketing API, o export) | Import diario a `f360.marketing_spend_daily` (CSV primero, API después) | **P0 para CAC/ROAS/MER** |
| 9 | Gasto Google Ads | **UNKNOWN** | — | — | No se sabe si hay cuenta con gasto | Pregunta a Mario | Ídem 8 si existe | P2 |
| 10 | Sesiones y funnel GA4 en F360 | MISSING | GA4 UI | — | Sin Data API | `gcloud` / service account; admin de GA4 (`G2B1` §D) | D1 (lectura manual) → D2 (job) a `f360.ga4_daily_sessions` y `ga4_item_daily` | **P1** |
| 11 | Reconciliación GA4 ↔ Commerce Facts | PLANNED | `G2B` §4 | — | Cobertura de `purchase` desconocida en prod (≤ 54% en R1, casi 0 en R2) | Ídem 10 | `ga4_purchase_snapshots` + vista de reconciliación | P1 |
| 12 | Zona horaria GA4 | CONFLICT | GA4 Tijuana | — | Días no alineados con CDMX | Rol Editor en GA4 + decisión P4 | Cambiar a CDMX (solo futuro) | P2 |
| 13 | Meta: emisor único y Purchase al pagar | CONFLICT (DQ-01) | GTM + Meta for WooCommerce | BAJA | Duplicados y compras no pagadas en Meta | Acceso a Events Manager + decisión M-A/M-B | G2-META-1 (`G2B1` §E.4) | P1 (para optimización de Meta, no para la verdad de F360) |
| 14 | Allowlist GA4 (P2) y eventos faltantes (`view_cart`, `add_shipping_info`, `add_payment_info`) | PLANNED | `G2B1` §B | — | Funnel incompleto en GA4 | Acceso GTM | Publicar allowlist anclada | P2 |
| 15 | Identidad canónica en GA4 (V1.1) | STAGING | `tools/measurement/f360-measurement-v11-staging4.php` | — | GA4 de prod usa IDs Woo | Prueba ATC v2 + purchase en staging4; aprobación | Snippet en prod tras completar `G2B2` §G2-B2.2 | P2 |
| 16 | Nueva vs recurrente | MISSING | — | — | Sin regla ni historia | D-C1, D-C3 | Clave de clienta (`02_…` §2.7) + vista `f360.growth_customer_orders` | **P1** |
| 17 | Historial por clienta en CRM | PARTIAL | `f360.customer_purchases` (loyalty + tienda) | MEDIA | Segunda fuente de verdad (no usa Commerce Facts) | — | Reapuntar a Commerce Facts + `order_shipping.customer_id` cuando Growth lo apruebe (cambio de CRM, decisión aparte) | P2 |
| 18 | Geografía (ciudad / estado) | LIVE desde hoy | `f360.order_shipping` | ALTA en pagados nuevos | 0 filas; sin historia; PII | D-C2 (retención) | Vista agregada por estado/ciudad sin PII (`f360_growth_geo`) | P2 |
| 19 | Retención de PII de `order_shipping` | MISSING | — | — | Sin política | Decisión legal | Política (p. ej. 24 m tras el último pedido) + job | P1 (gobierno) |
| 20 | Consentimiento de medición / marketing | MISSING / PARTIAL | `consent_purposes` (4), 0 eventos de marketing | — | Medición sin CMP; CRM sin opt-in | LEGAL_REVIEW | CMP + Consent Mode; opt-in de marketing en Club Fuxia | **P0 legal** (para activar CRM/medición extendida) |
| 21 | Favoritos | LIVE | `favorite_events` | ALTA | Sin pruebas SQL; sin fusión con clienta | — | Suite SQL; V2 fusión | P2 |
| 22 | Búsquedas | LIVE | `storefront_searches` | MEDIA | Sin rate limit (S1), posible PII (S2), sin `results_count`, sin mapeo a modelo | — | Rate limit + saneo + `results_count` + diccionario | P1 (seguridad) / P2 |
| 23 | Avísame en producción | STAGING | `stock_intents` | — | Snippet solo en staging4 | Aprobación de CRO-5 en prod (y congelamiento del storefront) | Publicar snippet; prueba como clienta (`tools/qa/tienda-como-clienta.mjs`) | P2 |
| 24 | Hilo como señal de intención | PARTIAL | `customer_cases` (texto) | BAJA | Producto/talla en texto libre; solo escalaciones | Export de HiloLabs UNKNOWN | Resolver a canónico en el intake; pedir a HiloLabs eventos agregados | P3 |
| 25 | Vistas / ATC / checkout por producto | MISSING en F360 | GA4 | — | — | Ídem 10 | `ga4_item_daily` | P2 |
| 26 | Capa unificada de intención | PLANNED | `05_…` | — | — | 21–25 | Vista `product_intent_events` + RPC | P2 |
| 27 | Cockpit de Growth | MISSING | `/growth` estático | — | Texto desactualizado (`page.tsx:33`, `data-audit.ts`) | 1, 2, 7 | RPC `f360_growth_cockpit` + UI con DATA INCOMPLETE | **P1** |
| 28 | Registro de experimentos | MISSING | — | — | — | — | `growth_experiments` (`06_…`) | P2 |
| 29 | Registro de campañas (Campaign 360) | MISSING | — | — | No hay catálogo campaña ↔ UTM ↔ mercado ↔ producto | Aplazado por Mario (`G1B` §13) | Mínimo: `f360.marketing_campaigns` poblado por el import de gasto | P2 |
| 30 | Tipo de cambio | MISSING | — | — | No se puede consolidar MXN + COP + USD | Decisión D-FX | `f360.fx_rates` mensual aprobada | P2 |
| 31 | Forecast 18 meses | MISSING | Plan B4 (supuestos) | — | Sin drivers de adquisición | 3, 8, 10 | `growth_monthly_facts` (`07_…`) | P2 |
| 32 | IAB / navegador por sesión | PARTIAL | `browser_class` del pedido | ALTA en pagados | Sin denominador de sesiones IAB | Ídem 10 + CRO-IAB | Telemetría `storefront_tech_events` (CRO) o GA4 | P3 |
| 33 | Pruebas de Growth | PARTIAL | Node 51/51 PASS; SQL G1/G2 | — | Sin pruebas SQL de favoritos; Playwright bloqueado por entorno | — | Agregar suites antes de cada sprint | P1 |
| 34 | `unmatched_orders` se detuvo el 2026-09-12 | UNKNOWN | Loyalty | — | Puede indicar que el webhook de loyalty dejó de registrar no-socias | — | Revisar `woocommerce-webhook` (fuera de Growth; reportar a Loyalty) | P2 |
| 35 | Acceso de vendedoras a reportes agregados | PARTIAL | `require_role('viewer')` en `f360_stock_demand` / `f360_favorites_report` | — | seller = viewer (rango 1) | — | Subir a `operator` si se decide que es información comercial | P3 |

---

## Bloqueadores externos (no se resuelven con código)

| Bloqueador | Dueño | Desbloquea |
|---|---|---|
| Acceso a Meta Ads (gasto) y Events Manager | Mario / agencia | 8, 13, CAC, ROAS, MER |
| ¿Hay cuenta de Google Ads con gasto? | Mario | 9 |
| Data API de GA4 (`gcloud` + permiso; admin para service account) | Mario / admin GA4 | 10, 11, 25, CR |
| Acceso a GTM (Editar / Publicar) | Agencia | 14, 15 |
| D-C1 (leer historial Woo), D-C2 (PII y retención), D-C3 (unir invitadas) | Mario | 3, 16, 18, 19 |
| LEGAL_REVIEW de consentimiento | Mario / legal | 20, F-3, F-5 |
| Descongelar storefront (2026-10-05) para Avísame y V1.1 | Mario | 15, 23 |
