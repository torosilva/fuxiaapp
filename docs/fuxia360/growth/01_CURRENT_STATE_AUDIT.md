# 01 · Auditoría del estado actual de Growth

**Fecha:** 2026-10-08. **Método:** lectura del repo (rama `fuxia-360`), consultas de solo lectura a producción con `scripts/f360/prod_read.sh` (envuelve cada consulta en `BEGIN READ ONLY`; solo conteos, esquemas y rangos de fechas, **sin PII**), `curl` del HTML público de `https://fuxiaballerinas.com/mx/` y los documentos previos de `growth/`. Nada se modificó.

**Estados:**
- **LIVE**: existe y funciona en producción (proyecto Supabase `tgzg…`, target `woo_production`).
- **PARTIAL**: existe en producción con huecos materiales.
- **STAGING**: solo en staging (`faltx…` / staging4).
- **PLANNED**: diseñado en un documento, no construido.
- **MISSING**: no existe ni está diseñado.
- **UNKNOWN**: no verificable con el acceso actual.

---

## Foto de producción (2026-10-08 ~18:00 UTC, conteos exactos)

| Objeto | Filas | Rango / nota |
|---|---|---|
| `f360.commerce_woo_orders` | **1** | Pedido 5351, creado 2026-10-08 14:14 UTC; `paid → cancelled` → `status_class = reversed`, `data_quality = PARTIAL (paid_value_unknown)`. **0 pedidos contables** |
| `f360.commerce_woo_order_lines` | 1 | — |
| `f360.commerce_woo_attribution` | 1 | `source_type = typein`, `utm_source = (direct)`, Chrome, Mobile. **Confirma que Woo Order Attribution está activo en producción** |
| `f360.commerce_woo_refunds` | 0 | — |
| `f360.commerce_woo_status_log` | 1 | — |
| `f360.commerce_sync_runs` / `commerce_sync_state` | **0 / 0** | El poll de 15 min nunca corrió en producción (ver §C.3) |
| `f360.order_shipping` | 0 | Tabla creada hoy (`20261013000500`); solo pedidos pagados |
| `f360.woo_orders` (inventario) | 0 | Las 2 entregas `order.updated` del pedido 5351 quedaron `before_cutover` |
| `f360.woo_webhook_deliveries` | 4 | 2 `before_cutover`, 2 `rejected_signature` con topic vacío (pruebas de smoke; ver commit `cbfc5fe`) |
| `f360.sales_targets` | 2 | `woo_production`: `is_production = true`, **`active = false`**, `orders_mode = on`, `orders_since_id = 5351`, `stock_sync_mode = off`, `catalog_mode = on`. `woo_staging4`: inactivo |
| `public.offline_sales` | 37 | 2026-05-18 → 2026-10-08 (mayo 2, septiembre 33, octubre 2). **Solo 1 con `created_by_rpc`** → solo 1 entra a `commerce_orders` |
| `f360.historical_sales` | 2 | Dos bazares (MXN), resúmenes de Carolina |
| `public.transactions` (loyalty) | 45 | MXN; web 19, tienda 23, app 3; 2026-01-12 → 2026-10-08 |
| `public.unmatched_orders` | 43 | MXN 33, COP 9, USD 1; 2026-08-08 → **2026-09-12** (no hay filas posteriores; causa UNKNOWN) |
| `public.customers` / `loyalty_cards` | 63 / 61 | Teléfono 63, correo 41, `auth_user_id` 41, `wc_customer_id` 40, ciudad 1; `source` ∈ {admin, app, store} |
| `f360.customer_consent_events` | 22 | Todos `privacy_notice` / `requested`. **0 eventos de marketing** |
| `f360.favorite_events` | 22 | 2026-10-07; `favorite_added` 11, `favorite_removed` 6, `favorite_add_to_cart` 5; todo `mx`. Producto resuelto 22/22, variante 5/22 |
| `f360.anon_visitors` | 5 | 0 fusionados con clienta |
| `f360.storefront_searches` | 8 | 2026-10-07 → 2026-10-08 |
| `f360.stock_intents` (Avísame) | 0 | — |
| `f360.customer_cases` | 1 | `a_la_medida`, `web_pdp` |
| `f360.growth_plans` / `growth_scenarios` / `reported_figures` | 1 / 0 / 0 | — |
| `public.push_campaigns` / `public.wishlists` | 0 / 0 | Legacy sin uso |
| Columnas de gasto / impresiones / `gclid` / `fbclid` | **0** | Búsqueda en `information_schema` de `f360` y `public` |
| Secretos en Vault | 0 | `vault.secrets` vacío |
| `f360.user_roles` | 2 `owner` | — |

---

## A. Tráfico / sesión

| Capacidad | Estado | Evidencia |
|---|---|---|
| GA4 (propiedad 519011849, `G-8C1244627P`) | **LIVE (sin acceso API)** | `G2A5_MEASUREMENT_AUDIT.md` §3. Un solo stream web para `/mx/`, `/co/` y raíz. Zona horaria **Tijuana** (conflicto con CDMX, A4). Moneda MXN (GA4 convierte COP/USD con su propia tasa) |
| GTM `GTM-W2PZG3L5` (v8) | LIVE | Presente en el HTML de `/mx/` hoy (curl, 2 apariciones). Tags: Google tag, GA4 Event (regex no anclada), Meta Pixel ×2 (`G2A5` §2). **Sin acceso al contenedor** (A11) |
| GTM4WP 2.0.5 como emisor de `dataLayer` | LIVE | 27 apariciones de `gtm4wp` en el HTML. `pagePostAuthor` ya no aparece (P1, `G2B1` §A) |
| Source / medium / campaign por **sesión** | LIVE en GA4 · **UNKNOWN** para F360 | Solo visible en la UI de GA4; F360 no tiene Data API. `gcloud` no está instalado y no existe `~/.config/gcloud` (verificado 2026-10-08) |
| Source / medium / campaign por **pedido** | LIVE (desde 2026-10-08) | `f360.commerce_woo_attribution` (`20261008000100`), llenado por `orderAttribution()` en `fuxia-native/supabase/functions/_shared/f360-woo/commerce.ts:26-44`: `source_type`, `utm_*` (opacos), `referrer_host`, `session_entry_path` (solo path), `session_start_at`, `session_pages`, `session_count`, `device_type`, `browser_class`, `os_class` |
| Landing page | PARTIAL | `session_entry_path` solo para pedidos; GA4 para sesiones |
| País | PARTIAL | Pedido: `billing_country` + `market` (por moneda). Sesión: GA4 (sin API). Búsqueda: `storefront_searches.country` |
| Dispositivo / navegador / in-app (IAB) | PARTIAL | Pedido: `device_type`, `browser_class` ∈ {`instagram_iab`, `facebook_iab`, `safari`, `chrome`, `edge`, `firefox`, `other`} (`commerce.ts:13-18`; el user agent crudo no se guarda). Sesión: GA4 no distingue Instagram de Facebook (`G2B1` §F). Telemetría IAB de CRO (`storefront_tech_events`) = PLANNED (`cro/05_MOBILE_IAB.md`) |
| Contrato `dataLayer` V1 / V1.1 (`mc_version`, `f360_select_*`) | STAGING | `G2_MEASUREMENT_CONTRACT.md`; snippet `tools/measurement/f360-measurement-v11-staging4.php` (sin seguimiento en git, con guard `staging4.`). 0 apariciones de `mc_version` / `f360_select` en el HTML de producción |
| Clarity | LIVE (sin API) | Presente en el HTML; nada sale a F360 |
| Consentimiento / CMP | **MISSING** | Sin banner ni Consent Mode (`G2A5` A6, LEGAL_REVIEW) |

## B. Datos de campañas

| Capacidad | Estado | Evidencia |
|---|---|---|
| Meta Pixel `951926154215387` | LIVE (CONFLICTED) | Doble emisor GTM + Meta for WooCommerce; Purchase por CAPI al crear el pedido (DQ-01, `G2B1` §E) |
| Meta Ads: gasto, impresiones, clics, CPC, CPM, `campaign_id` / `ad_id` / `creative_id` | **MISSING / sin acceso** | 0 columnas en BD; 0 referencias a Marketing API en el código (`grep` de `graph.facebook.com`, `act_`, `ads_insights`, `META_ACCESS_TOKEN` sin resultados fuera de docs); el usuario de Mario **no tiene acceso** a Events Manager del pixel (`G2B1` §E). Acceso a Ads Manager: **UNKNOWN** |
| Google Ads | **MISSING / UNKNOWN** | GTM v8 no tiene tags de Google Ads (`G2A5` §2). "Google for WooCommerce 3.9.5" activo, emisor no confirmado (A8). Si existe cuenta con gasto: UNKNOWN |
| UTMs en pedidos | LIVE (texto opaco) | `commerce_woo_attribution.utm_*`. En staging4 (clon jun–sep): `utm_campaign` 28%, `utm_content` 58% (`G1B` §9) |
| Gobierno de UTMs | PLANNED | `G2A_MEASUREMENT_FOUNDATION.md` §2 |
| Registro de campañas (Campaign 360) | MISSING | G0 #6; aplazado por Mario (`G1B` §13) |
| Campañas propias (push / broadcast) | LEGACY | `public.push_campaigns` 0 filas; `admin-broadcast-push` envía sin revisar consentimiento (`G0` §A.1) |

**Conclusión B: NO hay ningún dato de gasto accesible hoy.** No se asume que exista; hay que pedir acceso (ver `08_…`, decisiones).

## C. Commerce

| Capacidad | Estado | Evidencia |
|---|---|---|
| Hechos de pedido Woo (estado, `created_via`, `business_origin`, `paid_at`, `ever_paid`, moneda, componentes de dinero, foto de lo pagado, método y categoría de pago, `woo_customer_id`, país, mercado) | **LIVE desde 2026-10-08** | `f360.commerce_woo_orders`; escritura única `public.f360_capture_order_economics` (service role), llamada desde `f360-woo-orders/handler.ts:47` |
| Líneas (cantidad, subtotal, total, impuestos, `list_price_hint`) + identidad canónica | LIVE | `commerce_woo_order_lines`; vista `f360.commerce_order_lines` con `canonical_sku`, `canonical_product_key`, `identity_link_state` (`20261008000300`) |
| Descuentos | LIVE | `discount_total`, `coupon_count` (los códigos de cupón no se guardan, por diseño) |
| Reembolsos | LIVE (excepción técnica) | `commerce_woo_refunds`; 0 filas. Fuxia opera con cambios (`G1B` §8) |
| Atribución por pedido | LIVE | Ver A |
| Clienta del pedido | PARTIAL | `commerce_orders.loyalty_customer_id` (vía `transactions`) y `customer_link_status` (`20261008000200:16-17`); `order_shipping.customer_id` desde hoy |
| Dirección de envío (PII) | LIVE desde hoy | `f360.order_shipping` (`20261013000500`), solo `processing`/`completed` (`:67`), service role only |
| Ventas de tienda | PARTIAL | `commerce_orders` incluye solo `offline_sales` con `created_by_rpc` (`20261008000100:440-444`): **1 de 37** en producción. Las 36 legacy no cuentan |
| Resúmenes históricos | LIVE | `f360.historical_sales_active` (2 bazares), sumados en el tablero solo en MXN (`20261010000300:44-49`) |
| **Historial de pedidos Woo previo al corte** | **MISSING** | `orders_since_id = 5351`; no hay backfill en producción. El script `scripts/f360/g1_commerce_backfill.mjs` existe pero solo se corrió en staging4 (`G1B` §4) |
| **Poll de recuperación (15 min)** | **MISSING en producción** | Tres causas independientes: (1) `f360.commerce_poll_tick` sale si no hay `f360_sync_url`/`f360_sync_secret` en Vault (`20261008000100:533-535`) y Vault está vacío; (2) la acción `commerce_poll` de `f360-woo-sync/handler.ts:59-60` responde *skipped* si `stock_sync_mode ≠ on` (producción = `off`); (3) el cron corre (15 ejecuciones `succeeded` hoy) pero es no-op. Consecuencia: **un webhook perdido = un pedido perdido** |
| Salud de la fuente | **PARTIAL (ciega en prod)** | `f360.commerce_source_health` filtra `WHERE t.active AND NOT t.is_production` (`20261008000100:455`): producción **nunca aparece**; el tablero recibe `sources = []` |
| Pedidos por link de pago | PARTIAL | `f360-store-reserve` crea pedidos con `created_via = 'f360_pay_link'` (`handler.ts:164`); `f360.commerce_business_origin` no lo conoce → `business_origin = 'unknown'` → `PARTIAL origin_unknown` (`20261008000100:164-168`). Al crearse por REST, **no traen Woo Order Attribution** |
| Moneda / FX | LIVE (sin FX) | `currency_original` por fila; sin tabla de tipo de cambio |
| Resumen técnico | LIVE | `public.f360_commerce_summary` (operator+), `f360_exec_dashboard` (operator+) |

## D. Identidad de clienta

| Capacidad | Estado | Evidencia |
|---|---|---|
| Anónimo (`anon_id`) | LIVE (solo favoritos) | `f360.anon_visitors` (5), uuid del navegador `f360_anon_v1`; `customer_id` / `merged_at` sin uso (V2) (`FAVORITOS_V1.md` §3) |
| Identificada: teléfono / correo | LIVE | `public.customers` (63; teléfono 63, correo 41). OTP WhatsApp (`otp_verifications`) |
| Pedido en línea → clienta | PARTIAL | Loyalty (`woocommerce-webhook` → `transactions` / `unmatched_orders`) y, desde hoy, `order_shipping` (teléfono/correo → `customer_id` si ya existe; **no crea clientas**, `20261013000500` encabezado) |
| Consentimiento | PARTIAL | `f360.consent_purposes`: `privacy_notice`, `marketing_whatsapp`, `marketing_email`, `stock_notification`. Eventos: 22 `privacy_notice`/`requested`; 0 de marketing |
| País | LIVE | `customers.country` (63/63) |
| Compras por clienta | PARTIAL | `f360.customer_purchases` (`20261010000100_f360_crm_c1_customer_profile.sql:328-339`) lee `offline_sales` + `transactions`/`purchase_items` (loyalty), **no** Commerce Facts → segunda fuente de verdad para historial por clienta |
| Loyalty (puntos, nivel) | LIVE | Sistema legacy |
| Favoritos por clienta | STAGING / PLANNED | V2 (fusión anon → clienta) no construido |
| Resolución de identidad (invitada ↔ clienta) | PLANNED | `CUSTOMER_360_MODEL.md`; decisiones D-C1…D-C5 abiertas (`lib/data-audit.ts:52-58`) |

## E. Intención de producto

Columnas: ¿capturado? · dónde · relación con PRODUCTO (modelo) / VARIANTE (color+talla) / PAÍS / UBICACIÓN / CLIENTA / ANÓNIMO / SESIÓN / CAMPAÑA / TIMESTAMP.

| Señal | ¿Capturado? | Dónde | Prod | Var | País | Ubic | Clienta | Anon | Sesión | Camp | TS |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `product_view` | **GA4 solamente** (LIVE) | GA4 `view_item` (27,519 en R1, `G2A5` §3); `item_id` = ID Woo, no canónico | GA4 (ID Woo) | Inconsistente (`found_variation`) | GA4 | — | — | GA4 client_id | GA4 | GA4 | ✓ |
| `search` | **LIVE** (F360) | `f360.storefront_searches` vía `f360-store-reserve` acción `search_log` (`handler.ts:55-58`) | ✗ | ✗ | `country` | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| `favorite` | **LIVE** | `f360.favorite_events` (`20261012000800`), plugin `tools/storefront/mu-plugins/produccion/f360-favoritos.php` | ✓ canónico | color/variante si se eligió (5/22) | `market` | ✗ | ✗ (V2) | ✓ | ✗ | ✗ | ✓ |
| `favorite_removed` | LIVE | Igual | ✓ | parcial | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ |
| `favorite_add_to_cart` | LIVE | Igual (`20261012000900`) | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ |
| `hilo_interaction` | **PARTIAL** | Solo escalaciones: `f360.customer_cases` vía `f360-hilo-intake` (`handler.ts:21-27`), producto/color/talla como **texto libre**; la conversación vive en HiloLabs | texto | texto | `country` | ✗ | teléfono/correo (PII) | ✗ | ✗ | ✗ | ✓ |
| `notify_me` (Avísame) | **STAGING** | `f360.stock_intents` (`20261010000700:79-…`) vía `f360-storefront` acción `notify_me`; el snippet solo existe como mu-plugin de staging4 (`tools/storefront/mu-plugins/f360-promesa-avisame-staging4.php`); 0 filas en prod | ✓ | ✓ | ✓ | ✗ | teléfono (PII, consentimiento operativo) | ✗ | ✗ | ✗ | ✓ |
| `add_to_cart` | **GA4 solamente** (+ ATC desde favoritos en F360) | GA4 (3,604 en R1) | GA4 | GA4 (ID variación Woo) | GA4 | — | — | GA4 | GA4 | GA4 | ✓ |
| `checkout_started` | GA4 solamente | GA4 `begin_checkout` (563 en R1) | GA4 | GA4 | GA4 | — | — | GA4 | GA4 | GA4 | ✓ |
| `purchase` | **LIVE (F360, verdad)** + GA4 (señal, ≤ 54%) | `commerce_orders` / `commerce_order_lines` | ✓ canónico | ✓ | `market` | ✓ (tienda / fulfillment) | parcial | ✗ | atribución Woo | `utm_*` | ✓ |
| `repeat_purchase` | **MISSING** | — | — | — | — | — | requiere identidad | — | — | — | — |

**Hallazgo central E:** las señales de intención **viven en silos con llaves distintas**: favoritos (`anon_id` + canónico), búsquedas (solo término + país), Avísame (canónico + teléfono), Hilo (texto), vistas/ATC/checkout (GA4, IDs Woo). **No existe una llave de sesión común** entre F360 y GA4, ni un `anon_id` en el pedido. Unirlas por persona hoy es imposible; por **producto × mercado × día** sí es posible (ver `05_…`).

## F. UI actual de Growth

| Superficie | Estado | Evidencia | Observación |
|---|---|---|---|
| `/growth` "Inteligencia comercial" | LIVE (estático) | `admin-web/src/app/(app)/growth/page.tsx:29-44`; `lib/data-audit.ts:9-22` | Texto y tabla **desactualizados** (dice que la venta en línea no está conectada) |
| `/growth?vista=plan` (Plan 2027) | LIVE | `PlanEditor.tsx`; `f360_growth_plan` (operator+). 1 plan, 0 escenarios en prod | Objetivo, no forecast |
| `/growth?vista=commerce` | LIVE | `CommerceFacts.tsx`; `f360_commerce_summary` | Técnico; muestra frescura de fuentes, que en prod viene vacía (§C) |
| `/tablero` (Centro de control) | LIVE | `tablero/page.tsx`, `ControlCenter.tsx`; `f360_exec_dashboard` (`20261010000300`) | Ventas MXN (online + tienda + históricos), otras monedas aparte, por ubicación, por producto/talla. Sin gasto, sin atribución, sin conversión |
| `/demanda` | LIVE (vacío) | `demanda/page.tsx`; `f360_stock_demand` (`20261010000700:182`) | Avísame + sobre pedido |
| `/favoritos` | LIVE | `favoritos/page.tsx`; `f360_favorites_report` (`20261012000900`) | Por modelo: activos, agregados, quitados, a la bolsa, vendidos |
| `/clientes` y ficha | LIVE | `clientes/page.tsx`, `clientes/[id]` ; `f360_admin_customer` | Historial desde loyalty + tienda, no Commerce Facts |
| Funnel, conversión, CAC, ROAS, MER, LTV, cohortes, experimentos, campañas | **MISSING** | — | — |
| "Más buscados" en la tienda | LIVE | `f360_top_searches` (service role) | Pública: ver seguridad |

## Seguridad (hallazgos)

| # | Hallazgo | Severidad | Evidencia |
|---|---|---|---|
| S1 | `search_log` no tiene límite de frecuencia y "Más buscados" se muestra en la tienda: se puede **envenenar** la lista pública con términos arbitrarios | Media | `f360-store-reserve/handler.ts:55-58`; `f360_log_search` (`20261007002300:14-20`) solo exige ≥ 3 caracteres |
| S2 | El término de búsqueda es texto libre de la clienta y puede contener PII (teléfono, correo); se guarda sin sanear | Baja-Media | Mismo; contradice el principio "términos solo saneados" de `G2_MEASUREMENT_CONTRACT.md` §2 |
| S3 | Límite de favoritos por `anon_id` (120/h), pero el `anon_id` lo genera el cliente: rotándolo no hay tope global | Baja | `20261012000800:62` |
| S4 | `f360_stock_demand` y `f360_favorites_report` exigen `viewer`; `seller = viewer = 1` en `f360.role_rank` (verificado en prod). Datos agregados sin PII; la página sí exige `canWrite` | Baja | `20261010000700:184`; `20261012000900:57`; `demanda/page.tsx:11` |
| S5 | `order_shipping` guarda PII de pedidos: correcto en service role, sin política de retención definida | Media (gobierno) | `20261013000500` |
| S6 | Medición sin consentimiento (GA4, Meta, Clarity) y Cart Abandonment Recovery activo | Alta (legal) | `G2A5` A6, A7 |
| S7 | Commerce Facts, `order_shipping`, `favorite_events`: tablas sin acceso para `anon`/`authenticated`, lectura solo por RPC con rol | OK | `20261008000100:543-556`; `20261013000500`; `20261012000800:22-23,42-43,120-123` |

## Pruebas existentes relevantes (inventario)

| Suite | Contenido | Estado |
|---|---|---|
| `fuxia-native/supabase/functions/_shared/f360-woo/test/{commerce,sync,content,publisher}.test.ts` | Economía, atribución, `browserClass`, refund detail, firma, minimización, `orderShipping` | **Corridas hoy: 51/51 PASS** (`node --test`, sin red) |
| `…/test/contract.local.test.ts` | Contrato contra Woo real | No corrida (usa red) |
| `fuxia-native/supabase/functions/f360-store-reserve/test/handler.test.ts` | Incluye `favorite` y `search_log` (11 coincidencias) | No corrida (fuera del alcance pedido) |
| `fuxia-native/supabase/functions/f360-storefront/test`, `f360-hilo-intake/test` | Avísame, Hilo | No corridas |
| `supabase/staging/f360_g1_commerce_tests.sql` (47), `f360_g2_identity_tests.sql` (18), `f360_exec_dashboard_tests.sql`, `f360_cro5_cro6_tests.sql`, `f360_b4_tests.sql`, `f360_pay_links_tests.sql`, `test_order_shipping.sql`, `f360_historical_sales_tests.sql` | Ensayos SQL en transacción deshecha | No corridos (escriben en una BD) |
| **Favoritos** | **No hay** archivo de pruebas SQL para `f360_favorite_record` / `f360_favorites_report` | Gap |
| `admin-web/test/growth-model.test.ts` | Modelo del Plan | No corrida |
| `admin-web/e2e/b-growth.spec.ts`, `smoke-readonly.spec.ts` (`/growth`, `?vista=plan`, `?vista=commerce`) | Playwright | No corridos; G1-B registró bloqueo de entorno (`G1B` §6) |
