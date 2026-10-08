# Growth 360 · Documento maestro

**Fecha:** 2026-10-08. **Rama:** `fuxia-360`. **Fase:** DISCOVERY / AUDIT / SPEC. Sin código, sin migraciones, sin deploy, sin cambios en Woo, GTM, GA4 ni Meta.

**Contexto.** El 2026-10-05 se congeló GA4 / GTM / Meta / CRO / storefront para enfocarse en ventas de vendedoras. Mario reabre Growth con esta auditoría. Este paquete (00–09) **reconcilia** el trabajo previo (G0, G1, G1-B, G2, G2-A, G2-A.5, G2-B, G2-B1, G2-B2, `DATA_AUDIT.md`, `CUSTOMER_360_MODEL.md`, `FAVORITOS_V1.md`, `cro/08_ANALYTICS.md`) con lo que **existe hoy en producción** (lectura de solo lectura vía `scripts/f360/prod_read.sh`, 2026-10-08 ~18:00 UTC). No lo reemplaza: cuando un documento previo ya decidió algo, aquí se cita.

| Documento | Para qué |
|---|---|
| `00_GROWTH_MASTER.md` | Principios, cadena objetivo, las 15 preguntas |
| `01_CURRENT_STATE_AUDIT.md` | Qué existe (A–F), con LIVE / PARTIAL / STAGING / PLANNED / MISSING / UNKNOWN |
| `02_MEASUREMENT_TRUTH.md` | Jerarquía de fuentes y definiciones (venta pagada, revenue, moneda, nueva vs recurrente) |
| `03_GROWTH_COCKPIT.md` | Los 10 KPIs con fuente, fórmula, refresco, confianza y límites |
| `04_FUNNEL_ATTRIBUTION.md` | Funnel y atribución |
| `05_PRODUCT_INTENT.md` | Capa unificada de intención por producto |
| `06_EXPERIMENTS.md` | Registro de experimentos |
| `07_GROWTH_FORECAST_INPUTS.md` | Qué hechos de Growth alimentan el forecast de 18 meses |
| `08_GROWTH_GAP_ANALYSIS.md` | Matriz de gaps priorizada |
| `09_GROWTH_IMPLEMENTATION_PLAN.md` | Sprints G0–G4 y objetos propuestos (sin migraciones) |

---

## 1. Principios (no negociables)

1. **Growth produce HECHOS, no opiniones ni estimaciones disfrazadas.** Cada número dice su fuente, su periodo, su cobertura y su calidad. Si falta un insumo, la pantalla dice **DATA INCOMPLETE** (o "Sin datos suficientes", como ya hace `admin-web/src/app/(app)/growth/page.tsx:32-38`), nunca 0.
2. **El pedido pagado es la verdad financiera.** Fuente: Commerce Facts (`f360.commerce_orders`, migración `20261008000100_f360_g1_commerce_facts.sql`, vista corregida en `20261008000200`). Solo cuentan `status_class = 'countable'` (`processing` / `completed` / `refunded`; función `f360.commerce_status_class`, `20261008000100:180-188`). Regla ya fijada por Mario el 2026-10-04 (`G2B_MEASUREMENT_CORRECTION_PLAN.md` §0).
3. **GA4 es comportamiento** (sesiones, funnel, adquisición). Nunca revenue ni pedidos. Se reconcilia contra Commerce Facts por `transaction_id = woo_order_id` (`G2B_MEASUREMENT_CORRECTION_PLAN.md` §3).
4. **Meta es plataforma publicitaria.** Su "Purchase" está en conflicto (DQ-01: Meta for WooCommerce manda Purchase por CAPI al **crear** el pedido, antes del pago; `G2B1_SAFE_CORRECTIONS.md` §E.2). Su gasto, impresiones y clics son la verdad **del gasto**, no de la venta.
5. **Nunca se suman monedas.** MXN, COP y USD se reportan separados; no hay tabla de tipo de cambio (verificado: `f360.currencies` no tiene columna de tasa). Cualquier consolidación requiere una regla FX aprobada (D-G1-03).
6. **Una sola fuente de verdad por hecho** (CLAUDE.md regla 11). Antes de crear una tabla se reutiliza: Commerce Facts, `order_shipping`, `favorite_events`, `stock_intents`, `customer_cases`, `storefront_searches`, identidad canónica (`channel_variant_identity`).
7. **Identidad maestra = Fuxia 360.** Producto y variante se agregan por `canonical_sku` / `product_code` (`G2B2_CANONICAL_IDENTITY.md`, `INVENTORY_MODEL.md` §1.1), nunca por IDs de Woo.
8. **Privacidad primero.** Growth trabaja en agregado. La PII (nombre, teléfono, correo, dirección) solo vive en tablas de service role (`f360.order_shipping`, `public.customers`) y se lee por funciones de PII-viewer, nunca en los tableros de Growth.
9. **Sin modelos predictivos** en esta fase. Forecast = drivers explícitos (`07_…`).
10. **Fuxia no opera con reembolsos, opera con cambios** (`G1B_COMMERCE_FACTS_IMPLEMENTATION.md` §8). Un reembolso en Woo es una excepción técnica.

---

## 2. Cadena objetivo

```
MARKET (MX / CO / ROW)
  → CHANNEL (paid social, organic social, search, direct, email, referral, store…)
    → CAMPAIGN (utm_campaign / campaign_id de la plataforma)
      → AD / CREATIVE (utm_content / ad_id / creative_id)
        → SESSION (GA4 session; Woo Order Attribution session_*)
          → PRODUCT INTENT (view, search, favorite, Hilo, notify-me, add-to-cart, checkout)
            → ORDER (Woo order / store sale)
              → PAID SALE (Commerce Facts countable)
                → CUSTOMER (public.customers / order_shipping / loyalty)
                  → REPEAT (2.ª compra pagada)
```

**Dónde se rompe hoy (detalle en `01_…` y `08_…`):**

| Eslabón | Estado | Por qué |
|---|---|---|
| MARKET | LIVE (por moneda) | `f360.commerce_market(currency)`; la tienda física asume MXN |
| CHANNEL | PARTIAL | Solo desde Woo Order Attribution del pedido; reglas `channel_rules_v1` diseñadas (G2-A §1), **no construidas** |
| CAMPAIGN | PARTIAL | `utm_campaign` opaco en `commerce_woo_attribution`; sin registro de campañas ni IDs de plataforma |
| AD / CREATIVE | MISSING | Solo `utm_content` si la agencia lo pone; sin `ad_id` / `creative_id` |
| SPEND | **MISSING** | No existe ningún dato de gasto en BD, repo ni credenciales (§01-B) |
| SESSION | PARTIAL / UNKNOWN | GA4 vivo pero **sin acceso por API**; Woo guarda la sesión solo de pedidos |
| PRODUCT INTENT | PARTIAL | Favoritos y búsquedas LIVE; Avísame STAGING; vistas / ATC / checkout solo en GA4 |
| ORDER → PAID SALE | LIVE desde hoy, **sin historia** | Webhook de producción encendido el 2026-10-08 con corte en el pedido 5351; sin poll ni backfill |
| CUSTOMER | PARTIAL | `customers` (63), `order_shipping` (0 aún), loyalty; sin identidad unificada para pedidos de invitada |
| REPEAT | MISSING | Requiere historial + identidad |

---

## 3. Las 15 preguntas que Growth debe contestar

Estados: **SÍ** (contestable hoy con confianza) · **PARCIAL** (contestable con límites declarados) · **NO**.

| # | Pregunta | ¿Hoy? | Fuente hoy | Qué falta |
|---|---|---|---|---|
| Q1 | ¿Cuánto revenue **pagado** generamos por mercado, moneda y canal (online / tienda) en un periodo? | **PARCIAL** | `f360_commerce_summary` / `f360_exec_dashboard` sobre `commerce_orders`. Online: solo desde el corte 2026-10-08 (1 pedido capturado, 0 contables). Tienda: solo ventas `created_by_rpc` (1 de 37 en prod) | Backfill histórico de Woo (D-C1), poll de producción, regla para ventas de tienda legacy |
| Q2 | ¿Cuántos pedidos pagados y cuál es el AOV? | PARCIAL | Igual que Q1 (`aov_product`, `average_order_total`) | Igual que Q1 |
| Q3 | ¿Cuánto gastamos en marketing, por plataforma / campaña / creativo? | **NO** | Ninguna. 0 columnas de spend en `f360` / `public` (consulta `information_schema`, 2026-10-08) | Acceso a Meta Ads (API o export) y, si aplica, Google Ads |
| Q4 | ¿Cuántas clientas **nuevas** vs **recurrentes** compraron? | NO | — | Historial + identidad (D-C1, D-C3) |
| Q5 | ¿Cuál es el CAC por canal / campaña? | NO | — | Q3 + Q4 |
| Q6 | ¿Cuál es el ROAS (por plataforma) y el MER (total)? | NO | — | Q3 + Q1 |
| Q7 | ¿De qué fuente / medio / campaña vino cada venta pagada? | PARCIAL | `commerce_woo_attribution` (Woo Order Attribution, first-party, last-click de sesión). En staging4 la cobertura de pedidos de checkout fue 100% (`G1B` §9) | Vista de canal (`channel_rules_v1`), historia, pedidos por link de pago sin atribución |
| Q8 | ¿Qué anuncio / creativo produce ventas pagadas? | NO | `utm_content` existe como texto opaco; sin taxonomía | Gobierno de UTMs (G2-A §2) aplicado por la agencia + registro de creativos |
| Q9 | ¿Cuál es la tasa de conversión sesión → pedido pagado por mercado / dispositivo / navegador in-app? | NO | GA4 tiene sesiones; F360 tiene pagados. **Sin acceso a GA4 Data API** | Data API (D1/D2 de `G2B1` §D) |
| Q10 | ¿Dónde se cae el funnel (vista → carrito → checkout → pagado)? | NO (en F360) / PARCIAL (en la UI de GA4) | GA4 UI: `view_item`, `add_to_cart`, `begin_checkout` (G2A5 §3); `purchase` subcontado (≤ 54%) | Data API + `purchase` desde Commerce Facts |
| Q11 | ¿Qué modelo / color / talla tiene intención sin venta (demanda insatisfecha)? | PARCIAL | Favoritos (LIVE, 22 eventos), búsquedas (LIVE, 8), `f360_stock_demand` (Avísame: 0 filas en prod, snippet solo en staging4) | Capa unificada (`05_…`), Avísame en producción |
| Q12 | ¿Qué productos adquieren clientas nuevas? | NO | — | Q4 + líneas canónicas |
| Q13 | ¿Cuál es la tasa de recompra y el tiempo a la 2.ª compra? | NO | — | Historial + identidad |
| Q14 | ¿Qué experimento ganó, con qué evidencia, y qué se decidió? | NO | No existe registro de experimentos | `06_EXPERIMENTS.md` |
| Q15 | ¿Qué ciudades / estados generan revenue y dónde crecer? | PARCIAL (desde hoy) | `f360.order_shipping` (CRM C7, migración `20261013000500`): ciudad/estado/CP de pedidos pagados desde hoy (0 filas aún); `customers.address_*` (1 con ciudad) | Acumular datos; vista agregada sin PII; historial |

**Resumen honesto:** hoy Growth puede contestar con confianza **ninguna** de las 15 a nivel negocio completo. Cinco son parciales (Q1, Q2, Q7, Q11, Q15), y se vuelven confiables con dos decisiones (backfill histórico de Woo y poll de producción) más tiempo de acumulación. Las que dependen de **gasto** (Q3, Q5, Q6) están bloqueadas por acceso, no por código.

---

## 4. Qué cambia respecto al trabajo previo

| Documento previo | Lo que sigue vigente | Lo que esta auditoría corrige o actualiza |
|---|---|---|
| G0 (2026-10-04) | Inventario de capacidades y riesgos | "F360 no está en producción": **ya lo está** (opción B). "No existe consentimiento": existe `f360.consent_purposes` (4 propósitos) y `customer_consent_events` (22 `privacy_notice` / `requested`, 0 de marketing). "Sin wishlist": Favoritos LIVE |
| G1 / G1-B | Modelo de Commerce Facts y sus reglas | En producción las tablas existen y el webhook escribe desde 2026-10-08, pero **el poll no corre** (ver `01_…` §C) y no hay backfill |
| G2 / G2-A | Contrato de medición V1, `channel_rules_v1`, gobierno UTM | Nada implementado en producción (`mc_version` y `f360_select_*` ausentes del HTML de `/mx/`, curl 2026-10-08) |
| G2-A.5 / G2-B / G2-B1 | Hallazgos GA4 / GTM / Meta, DQ-01, reconciliación offline (R1) | P1 (`pagePostAuthor`) sigue aplicado (ausente en el HTML hoy). Las 8 decisiones de `G2B1` §G siguen **abiertas**. `gcloud` sigue sin instalar |
| G2-B2 | Identidad canónica; vistas `channel_variant_identity*` | Las vistas **existen en producción**. El snippet V1.1 sigue solo en staging4 |
| `growth/page.tsx` | — | El texto "la venta en línea … todavía no está conectada" (`page.tsx:33`) y `GROWTH_QUESTIONS` (`lib/data-audit.ts:9-22`) quedaron **desactualizados** |
