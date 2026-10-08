# 04 · Funnel y atribución

**Fecha:** 2026-10-08. **Estado:** especificación; reconcilia `G2_MEASUREMENT_CONTRACT.md`, `G2A_MEASUREMENT_FOUNDATION.md` §1–3 (`channel_rules_v1`, gobierno UTM, salud de fuentes) y `G2B_MEASUREMENT_CORRECTION_PLAN.md` §3–4 (reconciliación GA4). **Nada construido en producción** salvo Woo Order Attribution por pedido.

---

## 1. Dos modelos que no se mezclan

| | **Funnel de comportamiento** | **Atribución de la venta pagada** |
|---|---|---|
| Pregunta | ¿Dónde se cae la clienta? | ¿Qué canal/campaña trajo esta venta pagada? |
| Unidad | Sesión / evento (agregado por día × mercado × dispositivo) | Pedido pagado |
| Fuente | GA4 (vía Data API) + señales F360 (favoritos, búsquedas) | Commerce Facts + `commerce_woo_attribution` |
| Paso final | Pedido **pagado** de Commerce Facts (nunca `purchase` de GA4) | — |
| Unión entre ambos | Solo **agregada** por día × mercado (× dispositivo/navegador). Nunca por persona | — |

**Por qué no se unen por sesión:** no existe llave común. GA4 tiene `client_id` / `session_id` propios; Woo Order Attribution guarda su propia sesión (sourcebuster `sbjs_*`); F360 tiene `anon_id` solo para favoritos. Unirlos exigiría escribir el `client_id` de GA4 en el pedido (meta de Woo) — **posible a futuro (PROPUESTA F-5), no hoy**, y requiere consentimiento.

---

## 2. Funnel objetivo

| Paso | Evento | Fuente | Estado hoy | Observación |
|---|---|---|---|---|
| 1 Sesión | `session_start` | GA4 | LIVE en GA4, sin API | 70,507 en R1 (12 jun – 24 sep) (`G2A5` §3) |
| 2 Lista | `view_item_list` | GA4 (GTM4WP, lotes de 10) | LIVE, inflado | No usar como "vistas de lista" sin dividir entre 10 (`G2B` §2) |
| 3 Ficha | `view_item` | GA4 | LIVE, **duplicado** en `found_variation` | V1.1: un `view_item` por carga (STAGING) |
| 3b Selección | `f360_select_color` / `f360_select_size` | dataLayer V1.1 | STAGING | — |
| 3c Intención F360 | favorito, búsqueda, Avísame, Hilo | F360 | LIVE / STAGING | Ver `05_…` |
| 4 Carrito | `add_to_cart` | GA4 | LIVE | 3,604 en R1 |
| 5 Ver carrito | `view_cart` | GA4 | **No se reenvía** (T2) | P2 de `G2B1` §B (allowlist), pendiente |
| 6 Checkout | `begin_checkout` | GA4 | LIVE | 563 en R1. El checkout de bloques sigue siendo Woo (CRO `f360-compra` solo presentación) |
| 7 Envío / pago | `add_shipping_info` / `add_payment_info` | GA4 | No se reenvían | P2 |
| 8 Pedido creado | Woo `pending` | Commerce Facts | LIVE | `status_class = pending_payment` |
| 9 **Pedido pagado** | Woo `processing`/`completed` | **Commerce Facts** | LIVE desde 2026-10-08 | Paso final del funnel |
| 10 Recompra | 2.ª PS | Commerce Facts + identidad | MISSING | — |

**Tasas del funnel (PROPUESTA de definición):**
- `PDP rate` = sesiones con `view_item` ÷ sesiones.
- `ATC rate` = sesiones con `add_to_cart` ÷ sesiones con `view_item`.
- `Checkout rate` = sesiones con `begin_checkout` ÷ sesiones con `add_to_cart`.
- `Pay rate` = **PS (Commerce Facts)** ÷ sesiones con `begin_checkout` → `CROSS_SOURCE`.
- `Pending→Paid` = PS ÷ pedidos creados (Commerce Facts puro; mide fricción de pasarela: Mercado Pago, ePayco, PayPal). **Contestable hoy** con datos de producción en cuanto se acumulen pedidos (en staging4: 54 pagados de 82 creados, `G1B` §5).

**Cortes:** mercado, dispositivo, `browser_context` (Instagram IAB / Facebook IAB / estándar). Para pagados, el navegador sale de `commerce_woo_attribution.browser_class` (fuente base, `G2B1` §F); para GA4, `browser` va en columna paralela (`in_app_unknown`), nunca mezclado.

---

## 3. Atribución V1 (vigente)

| Elemento | Definición |
|---|---|
| Modelo | **Woo first-party order attribution, last-click de sesión** (`provenance = first_party_observed`, `model = woo_order_attribution_last_click_session`, `G1B` §1) |
| Ventana | La sesión de sourcebuster (30 min de inactividad). **No** hay ventana de días: si la clienta vio un anuncio el lunes y compra el jueves entrando directo, la venta es `typein` |
| Cobertura | Solo pedidos creados por el checkout (`store-api`/`checkout`). Pedidos por API, admin o **link de pago** (`f360_pay_link`) no traen atribución |
| Valores | `utm_*` opacos, sin normalizar. Alias en la vista de canal |
| Inmutabilidad | La primera captura gana (`G1B` §6, "Atribución: inmutable") |

**Clasificación de canal:** `channel_rules_v1` (G2-A §1.2: R0 `no_attribution` → UNKNOWN, R1 email, … paid social, organic social, organic search, referral, direct, `utm_noncompliant`). Validada en solo lectura sobre staging4 (`G2A` §1.3: paid social 23, organic social 22, direct 20, organic search 14, email 1, referral 1, unknown 1). **Se implementa como vista** (`f360.growth_order_channel`, ver `09_…`), nunca como columnas en los hechos; versionable (`channel_rules_version`).

---

## 4. Atribución de campaña / creativo

| Nivel | Llave hoy | Llave objetivo | Dependencia |
|---|---|---|---|
| Plataforma | `utm_source` + `referrer_host` | `platform` (vista) | `channel_rules_v1` |
| Campaña | `utm_campaign` (en el histórico de staging4 es un número = `utm_id`, `G2A` §2 nota 3) | `utm_id` = `campaign_id` de la plataforma | Gobierno UTM aplicado por la agencia + import de gasto con `campaign_id` |
| Adset / audiencia | `utm_term` | `adset_id` | Ídem |
| Anuncio / creativo | `utm_content` | `ad_id` / `creative_id` | Ídem + registro de creativos (`06_…`) |

**Regla:** un UTM que no cumple la convención no se corrige; se marca `utm_noncompliant` y se reporta su porcentaje (KPI de higiene).

**Join con gasto (PROPUESTA):** `marketing_spend_daily.campaign_id = commerce_woo_attribution.utm_id` (o `utm_campaign` si es numérico). La tasa de match (`attributed_revenue_matched_to_spend %`) es un KPI de calidad. Lo que no hace match va a "Paid social · campaña sin identificar".

---

## 5. Atribución reportada por plataformas

| Fuente | Uso permitido | Uso prohibido |
|---|---|---|
| Meta (Ads Manager, Pixel/CAPI) | Mostrar "conversiones reportadas por Meta" **al lado**, con etiqueta "no verificado (DQ-01)"; comparar tendencia | Usar como ventas, revenue, ROAS oficial, CAC |
| GA4 (atribución data-driven) | Contexto multi-touch de sesiones | Revenue |
| F360 first-party | ROAS / CAC oficiales (last-click) | Presentarla como multi-touch |

**Brecha de atribución (KPI de honestidad):** `PS con utm paid_social` vs `compras reportadas por Meta` en el mismo periodo. Una diferencia grande no se "arregla": se explica (view-through, otros dispositivos, DQ-01).

---

## 6. Reconciliación GA4 ↔ Commerce Facts (reutiliza `G2B` §4)

Sin cambios de diseño: `f360.ga4_purchase_snapshots` + vista `f360.ga4_purchase_reconciliation` (FULL OUTER JOIN `transaction_id = woo_order_id`), salidas: cobertura, pagados ausentes en GA4, GA4 sin hecho pagado, duplicados, discrepancia de revenue (solo MXN), por `browser_context`. **Bloqueado** por acceso a la Data API (D1/D2 de `G2B1` §D; `gcloud` no instalado al 2026-10-08).

---

## 7. Propuestas de mejora de atribución (no aplicadas)

| # | Propuesta | Valor | Riesgo / requisito |
|---|---|---|---|
| F-1 | Mapear `created_via = f360_pay_link` a origen `storefront_rescue` y copiar la atribución del pedido fallido original (el link nace de un checkout fallido, `f360-store-reserve/handler.ts:164-168`, meta `_f360_pay_link_case`) | Los rescates no se pierden como "unknown" | Requiere saber qué pedido falló; si no se puede, `no_attribution` explícito |
| F-2 | Exponer `browser_class` y `device_type` en la vista de canal | Corte IAB de ROAS/CR | Ninguno |
| F-3 | Ventana de clic de 7 días (cookie first-party propia con último UTM pagado) | Recupera ventas con retorno directo | Requiere snippet en producción y **consentimiento** (LEGAL_REVIEW) |
| F-4 | Guardar `fbclid` / `gclid` como **presencia** (booleano), no el valor | Distinguir paid sin UTM | Bajo |
| F-5 | Guardar el `client_id` de GA4 en el pedido (meta Woo) | Unión sesión ↔ pedido; habilita Measurement Protocol sin duplicar (`G2B` §3 R3) | Consentimiento; cambio en Woo |
