# G0 — Growth Intelligence: auditoría y arquitectura

**Fecha:** 2026-10-04. **Rama:** `fuxia-360`.

**Alcance.** Es una auditoría:
- Sin código, migraciones ni despliegue.
- No se tocaron producción, GTM, Meta ni Clarity.
- No se llamó a ninguna API externa.

**Fuentes revisadas:**
- `docs/fuxia360/` completo, en especial `growth/`, `cro/`, `ops/BITACORA_2026-10-02_04.md` e `INVENTORY_MODEL.md`.
- `supabase/migrations/` hasta `20261007002400`.
- El esquema vivo de producción: `docs/fuxia360/audit/live/schema.sql`, solo estructura.
- `fuxia-native/supabase/functions/*`, `fuxia-native/app/*`, `admin-web/src/*`, `tools/storefront/*`, `wordpress/`.
- `docs/fuxia360/audit/live/staging4/*`: respuestas REST capturadas de staging4.

**Etiquetas de cada afirmación:**
- **HECHO**: verificado en el repo, con cita.
- **SEÑAL**: patrón observado.
- **HIPÓTESIS**: algo que hay que verificar.
- **RECOMENDACIÓN**: propuesta.

---

## Resumen en 10 líneas

1. **HECHO.** El repo **no tiene ninguna instrumentación de medición**: ni GTM, GA4, `dataLayer`, Meta Pixel/CAPI ni Clarity. Tampoco parsea UTMs. Lo único que mide es el término de búsqueda de la Tienda (`f360.storefront_searches`).
2. **HECHO.** Producción carga GTM-W2PZG3L5, Meta Pixel y Clarity (observado en el HTML, `cro/08_ANALYTICS.md:5`). **Nadie del proyecto ha auditado el contenedor**: está bloqueado por `NEED_GTM_ACCESS`. staging4 no carga nada.
3. **HECHO.** **F360 no guarda revenue en línea.** `f360.woo_orders` y `woo_order_lines` no tienen totales ni precios: se minimizó a propósito en P2.3A (`_shared/f360-woo/orders.ts:39-53`). El revenue en línea completo solo vive en Woo.
4. **HECHO.** El modelo de ventas único (`f360.sales_facts`) ya existe, pero solo con `channel='store'`. El canal en línea es un marcador `available:false` (`20261004000400…:4,14,54-55`). Además, F360 **no está en producción**.
5. **HECHO.** **No existe atribución ni UTMs** en ninguna tabla o función.
   **HIPÓTESIS fuerte:** WooCommerce 11.1.2 trae **Order Attribution**; staging4 expone `woocommerce/order-attribution` en su REST (`audit/live/staging4/root.json`). Si está activo en producción, cada pedido ya trae su fuente y UTMs. Sería la forma más barata de tener atribución V1, pero no se ha verificado.
6. **HECHO.** Customer 360 está **diseñado, no construido**. Lo bloquean las decisiones D-C1…D-C5 (`growth/CUSTOMER_360_MODEL.md` §3). No hay AOV, LTV, recompra ni cohortes calculados en ningún lado.
7. **HECHO.** El Plan 2027 existe (B4) y solo guarda **supuestos**:
   - Los $15M son un default de la UI, no un dato guardado.
   - "Actual" está fijo en "Sin datos confiables todavía".
   - No usa tráfico, conversión ni tiendas.
8. **HECHO.** "`search_log`" **no es una tabla**: es el nombre de una acción.
   - La tabla real es `f360.storefront_searches`, con solo término, país y fecha.
   - No guarda si hubo resultados, ni sesión, ni la compra posterior.
   - Solo existe en staging.
9. **HECHO.** **No existe ningún campo de consentimiento de marketing.** Aun así, en producción **ya se envían** mensajes de lifecycle sin ese modelo: push masivo por nivel o inactividad, y WhatsApp y correo de bienvenida.
10. **HECHO.** Un `seller` tiene el mismo rango que un `viewer`, así que **puede leer el Plan 2027 completo**, incluidas las cifras de revenue reportadas (`c1_locations_roles.sql:18-19`, `b4_growth_plan.sql:89`).

---

## A. Inventario de lo existente

| Área | Qué existe hoy | Dónde | Ambiente |
|---|---|---|---|
| **Customer 360** | Modelo propuesto (perfiles, identificadores con confianza, decisiones de enlace, `commerce_orders`). **No construido.** Pantalla `/clientes` estática con campos, 12 segmentos (definiciones) y 5 decisiones pendientes | `growth/CUSTOMER_360_MODEL.md`; `admin-web/src/app/(app)/clientes/page.tsx:2-37`; `src/lib/data-audit.ts:24-58` | Solo documento + UI estática |
| Vista 360 de la clienta (app) | Perfil, puntos, nivel, últimas 30 `transactions`, referidas, tickets. Sin total gastado, AOV ni LTV. `app/admin/_layout.tsx` **no tiene control de rol** | `fuxia-native/app/admin/customer/[id].tsx:93-148` | Producción (app) |
| **Growth** | Pestaña "Inteligencia comercial": 6 tarjetas "Sin datos suficientes" y la tabla de preguntas con su estado (confiable / parcial / no disponible) | `admin-web/src/app/(app)/growth/page.tsx:8,26-33`; `src/lib/data-audit.ts:9-22` | Staging |
| **Campañas** | **Nada de campañas de pauta.** Solo `public.push_campaigns` (push; tabla sin quien la escriba ni la lea) y `public.broadcasts` (registro del push masivo) | `live/schema.sql:404-416, 609-622`; `functions/admin-broadcast-push/index.ts:138,179` | Producción |
| **Plan 2027** | B4: `growth_plans` (north_star), `growth_scenarios` (3 escenarios con supuestos), `growth_plan_changes` (bitácora), `reported_figures` (cifras con estado de verificación). Fórmula: clientas × frecuencia × AOV, más mezclas en % | `migrations/20260929000100_f360_b4_growth_plan.sql:10-163`; `admin-web/src/lib/growth-model.ts:38-55`; `PlanEditor.tsx:9,61,85` | Staging |
| **GA4** | Nada en el repo. En producción, desconocido (posiblemente vía GTM o "Google for WooCommerce") | `cro/08_ANALYTICS.md:30-45` (solo diseño) | — |
| **GTM** | GTM-W2PZG3L5 en producción, **sin auditar**. En staging4 está desactivado | `cro/08_ANALYTICS.md:3-21`; `audit/P2_3B_STAGING4_PREFLIGHT.md:96` | Producción |
| **Meta** | Pixel en producción (`connect.facebook.net`). "Facebook for WooCommerce" figura en el stack de producción. CAPI desconocido | `cro/CRO_PRODUCT_EXPERIENCE_V1_AUDIT.md:22`; `admin/WOO_PUBLISHING_V1_PLAN.md:21` | Producción |
| **Clarity** | Cargado en producción. Sin ID de proyecto registrado, sin uso de API, sin `clarity("set")` | Solo en docs | Producción |
| **UTMs** | **No existen** en código, BD ni funciones | — | — |
| **Sesiones** | No hay sesiones de analítica. `session_id` solo existe como **turno de vendedora** | `20261001000100_f360_s02_seller_sessions.sql` | — |
| **Atribución** | **No existe.** "Referral" = programa de referidas de loyalty | `live/schema.sql:656-667` | — |
| **Búsqueda** | `f360.storefront_searches(term, country, at)` + `f360_top_searches` ("Más buscados", ≥ 3 en 30 días). La escribe la Edge `f360-store-reserve` (acción `search_log`) desde `f360-tienda.html:260` | `migrations/20261007002300…:6-34` | Staging |
| **Ventas** | Tiendas: `f360.sales_facts` sobre `offline_sales` con `created_by_rpc`; `/ventas` (owner/operator). En línea: `woo_orders`/`woo_order_lines` **sin dinero**. Loyalty: `transactions` (monto, solo socias) + `unmatched_orders` | `20261004000400…`; `20260928000100…:107-130`; `woocommerce-webhook/index.ts:283-327` | Mixto |
| **Revenue** | Total por canal: **no disponible**. Tiendas: suma de `sales_facts` (staging). En línea: solo Woo. Cifras de Mario (2025 ≈ $5.5M, 2026 ≈ $6M): **no verificadas**, no cargadas | `growth/DATA_AUDIT.md` §1-2 | — |
| **AOV** | `avg_ticket` = suma / número de ventas en tienda (`20261004000400…:39`). En la app: suma de `offline_sales.total` del día (`dashboard-today.tsx:156-164`). En el Plan: supuesto escrito a mano | — | Parcial |
| **CAC / CPA / ROAS** | **No existen** (no hay gasto) | — | — |
| **LTV / cohortes / recompra / frecuencia** | **No existen** | — | — |
| **Funnel** | Solo diseño del contrato `dataLayer` en CRO-8 (`view_item` → `f360_select_color` → `f360_select_size` → `add_to_cart` → `begin_checkout` → `purchase`) | `cro/08_ANALYTICS.md:23-47` | Diseño |
| **Forecast** | No existe. El Plan dice explícitamente "objetivo, no pronóstico" | `PlanEditor.tsx:9` | — |
| Más vendidas / Nuevas | `f360_storefront_catalog`. Vendidas = unidades de 60 días (tiendas + líneas Woo) **+ `legacy_woo_map.sold_90d`**. Nuevas = 45 días o `new_override`. Solo unidades, sin dinero | `migrations/20261007002200…:4-60`; `f360-store-reserve/handler.ts:54-65` | Staging |
| Inventario certificado | CRO-5a: `f360.variant_inventory_certified`, `f360.online_scarcity_reliable`, `f360_inventory_certification()`. **Hoy ninguna ubicación está certificada** | `cro/06_INVENTORY_CONVERSION.md` §1; `migrations/20261007002400…` | Staging |
| IAB (Instagram/Facebook) | Protocolo de diagnóstico y diseño de telemetría (`f360.storefront_tech_events`). **Nada implementado**; no hay detección por User-Agent en el código | `cro/05_MOBILE_IAB.md` | Diseño |
| Lifecycle | Ver §A.1 | — | — |

### A.1 Lifecycle / CRM

| Capacidad | Estado | Dónde | ¿Envía de verdad? | ¿Revisa consentimiento? |
|---|---|---|---|---|
| Push masivo por segmento (todas / bronze / silver / gold / inactivas 30 días) | EXISTS | `admin-broadcast-push/index.ts:37-179` | **Sí** (Expo) | **No** |
| Bienvenida en la primera compra (WhatsApp + correo) | EXISTS | `woocommerce-webhook/index.ts:117-169, 343-347` | **Sí** (Twilio/Resend, si hay llaves) | **No** |
| Push de puntos / subida de nivel | EXISTS | `woocommerce-webhook/index.ts:348-363` | Sí | No (transaccional) |
| Cumpleaños | LEGACY / PARTIAL | RPC `award_birthday_points` y tabla `birthday_rewards` (baseline `:55,392`); **nadie la invoca**. La función `birthday-push` está desplegada y **no está en el repo** (`audit/LIVE_RECONCILIATION.md` §1) | Desconocido | Desconocido |
| Avisos transaccionales (apartados) | EXISTS | `f360.push_outbox` + `f360-push` | Sí (vendedoras) | N/A |
| Leads "a la medida" | EXISTS | `f360.custom_requests` (`20261007001800…`) | No (WhatsApp manual) | — |
| Avísame cuando llegue / carrito abandonado / win-back / VIP / cross-sell | MISSING | — | — | — |
| Consentimiento de marketing | **MISSING (blocker)** | No existe en el esquema vivo ni en las migraciones | — | — |

---

## B. Matriz de capacidades

Estados:
- **EXISTS**: existe.
- **PARTIAL**: existe en parte.
- **MISSING**: no existe.
- **CONFLICT**: contradice otra regla o decisión.
- **BLOCKED**: no se puede avanzar sin algo externo.
- **LEGACY**: viene del sistema anterior.

Esfuerzo: S / M / L.

| # | Capability | Status | Source of truth hoy | Implementación actual | Datos disponibles | Calidad | Qué falta | Owner objetivo | Dependencias | Riesgo | Prio | Esf. |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Revenue en línea | PARTIAL | **Woo** (producción) | F360 ingiere pedidos sin dinero (`woo_orders` / `woo_order_lines`) | Unidades por variante (staging4) | Confiable en unidades, **nula en dinero** | Total, subtotal, descuento, envío y precio por línea en F360 (no es PII). `sales_facts` con `channel='online'` | F360 Core | Enmendar la minimización de P2.3A (decisión). Regla de moneda | Doble conteo con `transactions` | **P0** | M |
| 2 | Revenue en tiendas | PARTIAL / LEGACY | `offline_sales` | `sales_facts` (solo `created_by_rpc`, staging). En producción el flujo legacy permite **INSERT/UPDATE anónimo** (P0-4) | Ventas registradas en la app | **No confiable en producción** (precio y total los pone el cliente; anon puede escribir) | S0.3 / C3 en producción | F360 Core | A2 + S0.3 en producción | Alto | P0 (fuera de G) | — |
| 3 | Revenue total / por canal | MISSING | — | — | — | — | #1 + #2 + regla de moneda | Growth (consume) | #1, #2 | Sumar MXN + COP + USD | P0 | S |
| 4 | Historial de pedidos Woo | BLOCKED | Woo | `backfill-orders` (loyalty, desplegada, **llamable con anon key**, P0-8) | Todo el historial en Woo | Alta en Woo | Lectura aprobada del historial | Customer 360 | **D-C1, D-G1** | PII | P1 | M |
| 5 | Atribución de pedidos (fuente / UTM) | MISSING | — | — | **HIPÓTESIS:** metadatos `_wc_order_attribution_*` en cada pedido Woo | Desconocida | Verificar si está activa; leer una lista blanca de campos (sin PII) | Growth (attribution) | Verificación en staging4 y producción | Bajo | **P0** | S |
| 6 | Registro de campañas | MISSING | Probablemente Meta Ads Manager / hojas (sin verificar) | — | — | — | Campaign 360 mínimo (UTM ↔ campaña ↔ mercado ↔ productos) | Campaign 360 | Saber dónde viven hoy las campañas (pregunta) | Duplicar Meta | P1 | M |
| 7 | Gasto (spend) | MISSING | Plataformas | — | — | — | Importación con fuente y fecha (CSV primero) | Campaign 360 | #6 | Mostrar el ROAS de Meta como verdad | P1 | M |
| 8 | Eventos de comportamiento (funnel) | BLOCKED | GA4 (sin auditar) | Contrato `dataLayer` en diseño (CRO-8) | Desconocidos | Desconocida | Auditoría GTM, entorno staging, `dataLayer` | Measurement (CRO genera) | **NEED_GTM_ACCESS** | Duplicar eventos GA4 | P1 | M |
| 9 | Sesión / fuente de tráfico | BLOCKED | GA4 | — | — | — | Leer GA4 (Data API) o exportar | Measurement | #8, credenciales | — | P2 | M |
| 10 | Dimensión IAB / navegador | MISSING (diseño CRO) | — | Telemetría diseñada (`storefront_tech_events`) | — | — | Que CRO-IAB la implemente; Growth la consume | CRO-IAB | Aprobación de CRO-IAB | — | P1 | S (para G) |
| 11 | Señales Clarity | BLOCKED | Clarity | Nada | — | — | Ver §H | Measurement / Growth | Verificación externa + acceso | Inventar una API | P2 | ? |
| 12 | Búsqueda | PARTIAL | `f360.storefront_searches` | Término + país + fecha | Términos (staging) | Confiable en volumen; **sin resultado ni conversión** | `results_count` por búsqueda; enlace a sesión o pedido | F360 (CRO) | Decisión: ¿se enriquece la tabla existente? | Poco volumen hoy | P2 | S |
| 13 | Customer 360 (identidad) | BLOCKED | `customers` + `auth.users` | Modelo propuesto | Socias de loyalty | Parcial | Construir B1 | Customer 360 | **D-C1…D-C5** | Fusiones erróneas | P1 | L |
| 14 | AOV | PARTIAL | — | Ticket promedio en tienda; supuesto en el Plan | Tiendas (staging) | Parcial | AOV por canal con revenue real | Growth | #1, #2 | — | P1 | S |
| 15 | Nuevas vs recurrentes / frecuencia / LTV / cohortes | MISSING | — | — | — | — | Identidad + historial | Customer 360 → Growth | #4, #13 | Métricas falsas | P1 | M |
| 16 | CAC / CPA / ROAS | MISSING | — | — | — | — | Gasto + pedidos atribuidos + nuevas clientas | Growth | #5, #7, #15 | Mezclar ROAS de plataforma y de F360 | P2 | S |
| 17 | Plan 2027 vs real | PARTIAL | `f360.growth_plans` | Supuestos y objetivo | Objetivo editable | Confiable como objetivo | Actual, run rate y gap con revenue real | Growth | #3 | — | P1 | S |
| 18 | Drivers del Plan (tráfico, conversión, tiendas) | CONFLICT | — | El modelo usa clientas × frecuencia × AOV | — | — | Decidir el modelo de drivers | Growth | #8, #9 | Romper el plan guardado | P2 | M |
| 19 | Merchandising (más vendidas / nuevas) | EXISTS (staging) | `f360_storefront_catalog` | Unidades + `sold_90d` legacy | Unidades | Parcial (mezcla legacy) | Exponer a Growth sin duplicar | F360 | — | — | P2 | S |
| 20 | Inventario × Growth | EXISTS (guard) | CRO-5a | `online_scarcity_reliable`, `f360_inventory_certification` | Booleano por variante / ubicación | Hoy todo **no certificado** | Mapear certificado a la etiqueta de calidad de Growth | F360 | Track D (conteos) | Concluir sobre escasez | P1 | S |
| 21 | Categoría (calzado vs accesorios) | MISSING | `f360.categories` (solo 4 de calzado) | — | — | — | Categoría "accesorios"; talla y calce opcionales por categoría | F360 Core | **D-G2** | Asumir que todo es calzado | P1 | S |
| 22 | Consentimiento de marketing | MISSING | — | — | — | — | Modelo de consentimiento | CRM / C360 | Legal + decisión | **Envíos actuales sin consentimiento** | **P0** (para activación) | M |
| 23 | Permisos de Growth | CONFLICT | `f360.role_rank` | seller = viewer = 1; el Plan pide viewer | — | — | Restringir Growth a owner / operator (o rol nuevo tras revisar C1) | F360 Core | Decisión | Fuga de revenue o gasto a vendedoras | **P0** | S |
| 24 | Calidad del dato | PARTIAL | `data-audit.ts` | Estados confiable / parcial / no disponible (estáticos) | — | — | Estado calculado por fuente (última sincronización, cobertura) | Growth | — | Precisión falsa | P1 | S |
| 25 | War Room | MISSING | — | Pestaña Growth con estados honestos | — | — | Evolucionar `/growth`, no crear otro dashboard | Growth | #1, #3, #17 | Otro Looker | P1 | M |
| 26 | Demand / Buying | MISSING (futuro) | — | — | — | — | — | Growth / Producción | Todo lo anterior | — | FUTURE | L |

---

## C. Flujo de datos actual

```
CLIENTA (Instagram / Google / directo)
   │  clic con o sin UTM
   ▼
SITIO WOO (producción)  ── GTM-W2PZG3L5 ──► GA4?      (sin auditar)
   │                    ── Meta Pixel ────► Meta      (sin auditar; ¿CAPI?)
   │                    ── Clarity ───────► Clarity   (grabaciones; nada sale de ahí)
   │                    ── ¿Order Attribution de Woo? ─► meta del pedido   (HIPÓTESIS)
   │  búsqueda en Tienda (solo staging4) ─► f360.storefront_searches (término, país)
   ▼
PEDIDO WOO (producción)  ← fuente completa: dinero, líneas, dirección, cupones
   │
   ├─ webhook loyalty (producción) ─► transactions + purchase_items   (solo socias, con monto)
   │                                └► unmatched_orders               (no socias, con monto)
   │
   └─ webhook F360 (solo staging4) ─► f360.woo_orders / woo_order_lines
                                      (sin dinero, sin clienta) ─► inventario (SALE)

TIENDA FÍSICA
   ├─ producción: app legacy ─► offline_sales (precio del cliente; anon puede escribir)
   └─ staging: RPC F360 ──────► offline_sales (created_by_rpc) ─► f360.sales_facts

QUÉ SE PIERDE HOY
  • La fuente de tráfico NO llega a ningún lado que F360 lea.
  • El gasto vive solo en Meta (y Google, si lo hay).
  • El comportamiento (vistas, talla, ATC) vive solo en GA4 / Clarity, sin auditar.
  • F360 no ve el dinero de los pedidos en línea.
  • Las búsquedas no registran si hubo resultados.

QUÉ PUEDE ATRIBUIRSE HOY DE VERDAD
  • Nada a campañas.
  • Unidades en línea por variante (staging4) y ventas de tienda por ubicación (staging).
```

---

## D. Flujo de datos objetivo (mínimo)

```
WOO PEDIDO ──(webhook F360 existente, +dinero, +atribución en lista blanca)──► f360.sales_facts (channel online|store)
                                                                               │  (una sola tabla de ventas)
CAMPAIGN 360 (registro pequeño: campaña ↔ utm_campaign ↔ mercado ↔ modelos)   │
GASTO (CSV o API, con fuente y fecha) ────────────────────────────────────────┤
GA4 (agregados diarios: sesiones, vistas, ATC, checkout por fuente/navegador) ─┤  ← tras auditar GTM
CLARITY (agregados de fricción + deep link, si existe una vía legítima) ───────┤  ← tras verificar
CUSTOMER 360 (perfiles + enlace de pedidos) ───────────────────────────────────┤  ← tras D-C1…C5
                                                                               ▼
                         VISTAS DE GROWTH (SQL, sin copiar datos): economía por canal/campaña/producto
                         + etiqueta de fuente y calidad por métrica (confiable / parcial / no disponible / desactualizado)
                                                                               ▼
                         /growth = WAR ROOM (evoluciona la pestaña existente) → HECHO / SEÑAL / HIPÓTESIS / RECOMENDACIÓN
```

**Principios:**
- **No** se crea una tabla de sesiones propia en V1. El comportamiento se lee **agregado** de GA4, y F360 guarda solo el dinero, los pedidos y su atribución.
- **No** se crea un segundo modelo de ventas: se completa `sales_facts`, que ya prevé `channel='online'`.

---

## E. Gap map

| Prioridad | Brecha |
|---|---|
| **P0** | 1. **Dinero de los pedidos en línea en F360** (#1) y canal online en `sales_facts`. 2. **Verificar Order Attribution de Woo** (#5). 3. **Permisos de Growth** (#23). 4. **Regla de moneda / revenue neto** (decisión). 5. **Consentimiento** (#22), solo como bloqueo de activación; Growth puede detectar sin enviar |
| **P1** | Auditoría GTM (#8) · registro de campañas (#6) · gasto (#7) · Plan 2027 con datos reales (#17) · calidad del dato calculada (#24) · categoría accesorios (#21) · Customer 360 (#13, tras D-C) · AOV por canal (#14) · War Room v1 (#25) · etiqueta de inventario certificado (#20) · dimensión IAB (#10, la hace CRO) |
| **P2** | Sesiones y fuente desde GA4 (#9) · Clarity (#11) · búsqueda con resultados (#12) · CAC / CPA / ROAS (#16) · drivers del Plan (#18) · merchandising en Growth (#19) |
| **FUTURE** | Cohortes avanzadas, forecast, Demand / Buying (#26), lifecycle con envíos |

---

## F. Contradicciones (NO resueltas)

| # | Contradicción | Evidencia |
|---|---|---|
| F1 | El prompt dice "`search_log` YA EXISTE". En realidad es la **acción** de una Edge Function; la tabla es `f360.storefront_searches`, **solo en staging**, sin resultados, sesión ni compra. No puede responder "sin resultado" ni "búsquedas que terminan en compra" | `migrations/20261007002300…:6-11`; `f360-store-reserve/handler.ts:48` |
| F2 | CRO-8 dice que el funnel se reconstruye **en GA4** y que F360 guarda solo señales **sin identidad**. El prompt quiere CAMPAIGN → SESSION → CUSTOMER → ORDER → LTV dentro de F360. Unir sesión con clienta choca con ese principio y con D-C2 | `cro/08_ANALYTICS.md:47` |
| F3 | Calidad del dato: ya existe el vocabulario `confiable / parcial / no_disponible` (`data-audit.ts`). El prompt propone VERIFIED / PARTIAL / UNVERIFIED / STALE. CRO-5a no define estados: expone un **booleano** (`reliable`) y certificado sí/no por ubicación | `admin-web/src/lib/data-audit.ts`; `cro/06_INVENTORY_CONVERSION.md` §1.3 |
| F4 | Plan 2027: el prompt pide drivers de tráfico, conversión, tiendas, accesorios y LTV. El modelo existente es clientas × frecuencia × AOV más mezclas en %. Y los **$15M no están guardados**: son un default de la UI | `growth-model.ts:38-55`; `PlanEditor.tsx:9` |
| F5 | El prompt asume que una vendedora no ve Growth. Hoy `seller` = `viewer` = rango 1: **puede leer el Plan y las cifras de revenue reportadas**. `/clientes` y `/growth` no tienen control de rol en el menú | `c1_locations_roles.sql:18-19`; `b4_growth_plan.sql:89`; `Shell.tsx:6-21` |
| F6 | El prompt dice "no activar automatizaciones hasta resolver el consentimiento". Producción **ya envía** push masivo, WhatsApp y correo de bienvenida sin modelo de consentimiento | `admin-broadcast-push/index.ts`; `woocommerce-webhook/index.ts:117-169` |
| F7 | `wordpress/page-privacy.php:89` dice "No usamos tu información con fines publicitarios" y menciona solo Supabase y Twilio. El sitio de producción carga Meta Pixel, GTM y Clarity. Hay que confirmar si esa página cubre también el sitio web (revisión **legal**) | `wordpress/page-privacy.php:89-103` |
| F8 | "Revenue final debe venir de ventas propias". Hoy F360 **no guarda dinero de pedidos en línea**, por una decisión aprobada en P2.3A, y no está en producción. Las ventas físicas de producción vienen del flujo legacy, que no es confiable | `_shared/f360-woo/orders.ts:39-53`; `LIVE_RECONCILIATION.md` P0-4 |
| F9 | `INVENTORY_MODEL.md` regla 9 sigue diciendo "Woo publica solo desde Bodega CDMX". La decisión 4 de la bitácora (2026-10-03) la reemplazó por "Bodega + tiendas − apartados", y el documento no se actualizó | `INVENTORY_MODEL.md:19,40`; `ops/BITACORA_2026-10-02_04.md` §1 #4; `migrations/20261007002100…` |
| F10 | Más vendidas suma el histórico legacy `sold_90d` (90 días, foto fija) a las ventas F360 de 60 días. Growth no debe leer ese número como "unidades vendidas en 60 días" | `migrations/20261007002200…:4-5,48-56` |
| F11 | `birthday-push` y `send-push` están desplegadas en producción y **no están en el repo**. No se puede auditar qué envían | `audit/LIVE_RECONCILIATION.md` §1 |
| F12 | El prompt pide revenue por mercado. Hay tres monedas (MXN / COP / USD) y no existe una regla de conversión. El Plan solo admite MXN | `20261005000100_f360_currency_prices.sql`; `b4_growth_plan.sql:10-17` |

---

## G. War Room: wireframe conceptual

Evoluciona `/growth`; no es una pantalla nueva aparte. Diseñado para escritorio; en móvil cada bloque se apila. Cada número lleva su fuente y su calidad (●confiable ◐parcial ○no disponible ⌛desactualizado).

```
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│ GROWTH · WAR ROOM          [Hoy] [7D] [30D] [Personalizado]    Mercado: [Todos ▾]  MXN ▾       │
├───────────────────────────────────────────────────────────────────────────────────────────────┤
│ Revenue ●F360     Pedidos ●     E-commerce ●   Tiendas ◐     Conversión ○GA4   AOV ●           │
│ $412,300 ▲8%      143 ▲5%       $301k          $111k         —                 $2,883          │
│ Gasto ○           CPA ○         CAC ○          ROAS F360 ○   ROAS Meta ○(plataf.)  Nuevas ◐   │
├───────────────────────────────┬───────────────────────────────────────────────────────────────┤
│ ¿QUÉ CAMBIÓ?  (HECHO)         │ ¿POR QUÉ?  (SEÑAL → HIPÓTESIS, etiquetadas)                   │
│ • Revenue e-com +12% vs 7D    │ • SEÑAL: Instagram iOS convierte 50% menos que Safari         │
│ • Macarena Nude 37 agotada    │ • HIPÓTESIS: fricción del IAB en checkout (ver Fricción)      │
├───────────────────────────────┴───────────────────────────────────────────────────────────────┤
│ ¿QUÉ HAGO?  (RECOMENDACIÓN, con su evidencia)                                    [Ver evidencia]│
│ 1. No subir pauta a Macarena Nude: inventario no certificado ◐ y 37/38 sin existencia          │
├──────────────┬──────────────┬──────────────┬──────────────┬──────────────┬────────────────────┤
│ Campañas     │ Funnel       │ Productos    │ Clientas     │ Fricción     │ Plan 2027          │
└──────────────┴──────────────┴──────────────┴──────────────┴──────────────┴────────────────────┘
```

Las cifras del ejemplo son ilustrativas, no datos.

**Pestañas:**

| Vista | Qué muestra | Necesita |
|---|---|---|
| **Ejecutivo** | KPIs y los bloques "¿Qué cambió? / ¿Por qué? / ¿Qué hago?" | G1 (revenue) |
| **Campañas** | Tabla por campaña: gasto, sesiones, pedidos, nuevas, revenue F360, ROAS F360 junto al ROAS reportado por Meta (dos columnas, nunca mezcladas) | Atribución + gasto |
| **Funnel** | Sesión → vista → color → talla → ATC → checkout → compra, por navegador o IAB y por mercado | GTM / GA4 + CRO-IAB |
| **Productos** | Modelo / color / talla: tráfico, búsquedas, ATC, ventas, inventario con su etiqueta de certificación y estado MTO. En accesorios no se piden talla ni calce | Varias |
| **Clientas** | Nuevas vs recurrentes, AOV, frecuencia, cohortes y segmentos (solo detección, sin envíos) | Customer 360 |
| **Fricción** | Tarjetas de Clarity por etapa: "$X de valor de carrito asociado a sesiones afectadas", nunca "pérdida". Botón [Abrir en Clarity] | §H |
| **Plan 2027** | Objetivo, real, run rate, gap y drivers requeridos | G1 + Plan existente |

---

## H. Viabilidad de Clarity — DETENIDO para verificación externa

**Lo que tenemos (HECHO):** nada.
- Ni ID de proyecto, ni uso de API, ni `clarity("set")` / `identify` / etiquetas personalizadas.
- Ni consentimiento.
- Solo sabemos que producción carga el script (`cro/CRO_PRODUCT_EXPERIENCE_V1_AUDIT.md:22`).

**No puedo diseñar la integración sin verificar fuera del repo.** Necesito confirmar:
1. **¿Existe una API oficial de exportación de datos de Clarity?** Si existe:
   - ¿Qué métricas da (dead clicks, rage clicks, scroll excesivo, quick backs, errores de JS)?
   - ¿Agrupadas por qué dimensiones (URL, dispositivo, navegador, país, fuente)?
   - ¿Qué rango de fechas y qué límites de uso tiene?
   - ¿Es agregada o por sesión?
   
   **HIPÓTESIS (no verificada):** hay una API de exportación **agregada** con ventana corta y pocas llamadas al día. Si es así, F360 tendría que guardar instantáneas diarias.
2. **¿Se puede ligar una sesión de Clarity con algo nuestro** (etiquetas o identificadores personalizados), sin PII, y **construir un enlace profundo** a grabaciones filtradas?
3. **Términos de uso** sobre guardar datos exportados.
4. **Consentimiento:** ¿qué exige Clarity para sesiones en México y Colombia?
5. **Acceso:** ¿quién administra el proyecto de Clarity de producción (Mario / Adrián / agencia)?

**Autorización que necesito:** revisar la documentación oficial de Microsoft Clarity (WebFetch / WebSearch), sin conectarme a ninguna cuenta.

---

## I. Propuesta de G1 (NO implementada)

### Ajuste al roadmap propuesto

El G1 propuesto, "Measurement Contract", **está bloqueado** por `NEED_GTM_ACCESS`. Además, todas las métricas económicas (AOV, CPA, CAC, ROAS, Plan vs real) necesitan primero **el revenue real**, y hoy F360 no lo tiene.

**RECOMENDACIÓN:**

| Orden | Unidad | Por qué |
|---|---|---|
| G0 | Auditoría | ✅ Este documento |
| **G1** | **Commerce Facts: dinero + atribución de pedidos** | Desbloquea revenue, AOV, Plan vs real y la base de toda atribución. No depende de GTM |
| G2 | Measurement Contract (= CRO-8) | En cuanto haya acceso a GTM. Lo genera CRO; Growth lo consume |
| G3 | Campaign 360 mínimo + gasto (CSV) | Necesita G1 para cruzar `utm_campaign` con pedidos |
| G4 | Funnel + atribución V1 (first / last non-direct / last) | Necesita G1 (pedido) + G2 (sesión) |
| G5 | War Room v1 (evolución de `/growth`) + Plan 2027 con datos reales | Útil desde G1; crece con cada unidad |
| G6 | Customer Economics | **Bloqueada por D-C1…D-C5** |
| G7 | Clarity Intelligence | Tras §H |
| G8 | Merchandising Intelligence | Consume `f360_storefront_catalog`, CRO-5a y búsquedas |
| G9 | Lifecycle Intelligence (detección, sin envíos) | Consentimiento |
| G10 | Forecast / Demand / Buying | Futuro |

### G1 — Commerce Facts (detalle)

**Objetivo.** Que F360 tenga, en staging, el dinero y la fuente de cada pedido en línea en el **mismo** `sales_facts`, sin PII.

| Aspecto | Propuesta |
|---|---|
| **Verificación previa (bloqueante, solo lectura)** | 1. En staging4, leer los `meta_data` de un pedido de prueba para confirmar si llegan `_wc_order_attribution_*`. 2. Confirmar si Order Attribution está activo en producción (Adrián, en wp-admin; sin cambios). |
| **Archivos** | `fuxia-native/supabase/functions/_shared/f360-woo/orders.ts`: `minimizeOrder` conserva totales, precio por línea y **solo** los campos de atribución en lista blanca. `f360-woo-orders/handler.ts`. Admin: `ventas/page.tsx` (canal en línea), `growth/page.tsx` (tarjeta de revenue con fuente), `PlanEditor.tsx` (Actual YTD etiquetado). |
| **Tablas** | `ALTER f360.woo_orders ADD total, subtotal, discount_total, shipping_total, tax_total, currency (ya existe)` · `ALTER f360.woo_order_lines ADD unit_price, line_total` · `CREATE f360.order_attribution (order_ref, source_type, utm_source, utm_medium, utm_campaign, utm_content, utm_term, referrer_host, device_type, session_pages, captured_at)`, sin IP, correo ni URL con query · `sales_facts` con `UNION ALL channel='online'` (ya previsto) · vista `f360.growth_source_status` (fuente, última actualización, cobertura, estado). |
| **Eventos** | Ninguno nuevo en el navegador. Solo se reutilizan los webhooks existentes. |
| **APIs** | Ninguna externa nueva. RPC `f360_growth_summary(range, market)` para owner/operator. |
| **Migraciones** | 1 aditiva + rollback en `supabase/rollbacks/`. |
| **UI** | Ventas: "En línea" deja de decir "pronto". Growth: Revenue / Pedidos / AOV por canal con su fuente. Plan: Actual (parcial: desde que se activa el webhook). |
| **Pruebas** | SQL: idempotencia (misma entrega dos veces), reembolsos, pedido sin atribución, rechazo de campos fuera de la lista blanca, permisos (seller y viewer no leen el resumen), monedas separadas. Node: `minimizeOrder` no deja pasar PII. |
| **Rollback** | Down migration. Los pedidos ya ingeridos conservan sus columnas originales. |
| **Dependencias** | Decisiones 2, 3 y 6 (abajo). No toca Track D, CRO ni C3. |
| **Riesgos** | Doble conteo con `transactions` de loyalty (se resuelve con la llave `wc_order_id`). Revenue histórico (anterior al webhook) sigue **no disponible** hasta D-C1. Mezcla de monedas. |

---

## Reporte final

### 1. Qué descubrí
- La medición existe **solo en producción y fuera del repo**: GTM, Pixel y Clarity, sin auditar.
- F360 tiene buena base operativa, pero **cero dinero en línea y cero atribución**.
- WooCommerce 11.1.2 tiene la extensión Order Attribution registrada en staging4. Es probablemente el atajo para la atribución V1, pero falta verificarlo.

### 2. Qué ya estaba construido
- Plan 2027 (B4, staging).
- Estados honestos de Growth y Clientes.
- El modelo único de ventas (`sales_facts`, tiendas).
- La ingesta de pedidos Woo (unidades).
- Más vendidas y Nuevas.
- Búsquedas de la Tienda.
- Guard de inventario certificado (CRO-5a).
- Push masivo por segmento, bienvenida y puntos (producción).
- Leads "a la medida".

### 3. Qué creíamos construido y no lo está
- `search_log` como tabla.
- Los $15M guardados.
- "Más vendidas = 60 días", que en realidad incluye el legacy de 90.
- Dimensión IAB, que solo está en diseño.
- Customer 360, que solo está en diseño.
- Revenue en línea en F360.
- Un estado PARTIAL / VERIFIED de CRO-5a, que en realidad es un booleano.

### 4. Qué falta
- Atribución.
- Campañas y gasto.
- Eventos.
- Sesiones.
- AOV por canal, LTV y cohortes.
- CAC, CPA y ROAS.
- Consentimiento.
- Categoría de accesorios.
- Permisos de Growth.
- War Room.
- Clarity.

### 5. Datos confiables hoy
- Loyalty (puntos, nivel).
- Unidades en línea de variantes ligadas (staging4).
- Ventas de tienda vía RPC (staging).
- Pedidos en Woo (producción, sin conectar).
- Objetivo del Plan (como objetivo).

### 6. Datos no confiables
- `offline_sales` de producción (anon puede escribir).
- `transactions` como revenue total (solo socias).
- Inventario (nada certificado).
- Cifras de Mario (no verificadas).
- Más vendidas (mezcla legacy).
- Cualquier métrica de GA4, Meta o Clarity (sin auditar).

### 7. Decisiones que necesito

| # | Decisión |
|---|---|
| 1 | ¿Quién tiene acceso a **GTM-W2PZG3L5** y al proyecto de **Clarity**? |
| 2 | ¿F360 puede guardar **totales y precios** de pedidos en línea y **atribución en lista blanca** (sin PII)? Enmienda la minimización de P2.3A. |
| 3 | Definición de **revenue**: ¿bruto o neto de reembolsos? ¿Con o sin IVA y envío? ¿Por moneda o convertido a MXN, y con qué tipo de cambio? |
| 4 | **D-C1…D-C5** (Customer 360) siguen pendientes. Bloquean G6. |
| 5 | Vocabulario de calidad: ¿reutilizo `confiable / parcial / no disponible` y agrego `desactualizado`? |
| 6 | **Permisos:** ¿Growth y Plan solo para owner y operator? ¿O un rol "growth" (requiere revisar C1)? |
| 7 | **D-G2:** definición de accesorios. |
| 8 | Revisión **legal** del aviso de privacidad frente a Pixel, GTM y Clarity, y modelo de consentimiento. |
| 9 | ¿Dónde viven hoy las campañas: Meta Ads Manager, hojas, una agencia? |
| 10 | ¿Autorizas la investigación externa de Clarity (§H)? |

### 8. Roadmap recomendado
G0 → **G1 Commerce Facts** → G2 Measurement (cuando haya acceso a GTM) → G3 Campaign 360 + gasto → G4 Funnel / atribución V1 → G5 War Room + Plan con datos reales → G6 Customer Economics (tras D-C) → G7 Clarity → G8 Merchandising → G9 Lifecycle (detección) → G10 Demand.

### 9. Git status
Ver la respuesta de esta entrega en la terminal. G0 solo agrega este archivo.
