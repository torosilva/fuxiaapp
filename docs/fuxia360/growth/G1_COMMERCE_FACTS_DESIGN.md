# G1-A — Commerce Facts: descubrimiento de solo lectura y diseño

**Fecha:** 2026-10-04. **Rama:** `fuxia-360`. **Estado:** aceptado. Implementado en staging como G1-B: ver `G1B_COMMERCE_FACTS_IMPLEMENTATION.md`.

**Desviación de §O en la implementación:** la economía en línea vive en tablas propias (`f360.commerce_woo_*`) y no en `f360.woo_orders`. Si un backfill escribiera en el estado de inventario, un webhook posterior de la misma versión saldría como `duplicate` y no descontaría el par. `sales_facts` no se tocó para no mezclar monedas.

**Cierre de G1-B (decisiones de Mario, 2026-10-04). Reemplazan lo que diga este documento en contra:**
- **Reembolsos = SOPORTE TÉCNICO / EXCEPCIÓN, NO flujo de negocio de Fuxia.**
  - Fuxia opera con **cambios**, no con devoluciones de dinero (bitácora #7).
  - §H, los reembolsos de §E (REFUND, PRODUCT REFUND, NET PRODUCT REVENUE, REFUND RATE) y G1-Q5 quedan como **representación defensiva** de un evento que Woo técnicamente puede enviar.
  - Sin reembolsos de prueba, sin UI, sin más lógica.
  - Ninguna métrica de negocio asume reembolsos; un valor ≠ 0 es una excepción a revisar.
- **Cambios = flujo futuro del negocio (VENTA → CAMBIO opcional).** Registrado como track "COMMERCE EXCHANGES / CAMBIOS" (`G1B_COMMERCE_FACTS_IMPLEMENTATION.md` §8.1). No implementado. Qué pasa con la diferencia de precio es una decisión pendiente.
- **Pagado → cancelado = EXCEPCIÓN DE NEGOCIO / PARTIAL.** No se infiere devolución de dinero desde el estado de Woo ni se trata como revenue perdido (§G).
- **Invariante de deploy JWT:** las funciones Woo se despliegan siempre sin verificación JWT del gateway, y se verifica después de cada deploy (`admin/P2_3B_RUNBOOK.md` §3).
- **Playwright:** TEST ENVIRONMENT BLOCKER (fuentes de Google en el servidor local), no aprobado.

**Alcance:**
- Sin código, sin migraciones y sin despliegue.
- No se tocaron producción, GTM, Meta, CAPI ni plugins.
- No se consultaron Clarity, documentación de Meta ni GA4.

**Fuentes:**
1. **staging4**, con **solo GET** a `wc/v3/orders` y a `wc/v3/orders/{id}/notes` sobre los **82 pedidos** existentes.
   - Los scripts quedaron en el scratchpad de la sesión, fuera del repo.
   - Imprimieron solo conteos, nombres de campo, montos y valores no personales: nada de nombre, correo, teléfono, dirección, IP ni user agent crudo.
   - De las notas se extrajeron solo las frases de **cambio de estado**.
   - `wp/v2/plugins` respondió **401**: la llave no puede listar plugins.
2. Migraciones `supabase/migrations/*` hasta `20261007002400`, `fuxia-native/supabase/functions/*` y la documentación del repo.
3. **Documentación oficial de WooCommerce:**
   - [W1] *Order Attribution Tracking* (woocommerce.com/document/order-attribution-tracking).
   - [W2] *Order statuses* (woocommerce.com/document/managing-orders/order-statuses).
   - [W3] REST API v3, *Orders*: `woocommerce-rest-api-docs/source/includes/wp-api-v3/_orders.md`.
   - [W4] REST API v3, *Order refunds*: `_order-refunds.md`.

**Contexto de los datos:**
- staging4 es un **clon de producción** (`audit/P2_3B_STAGING4_PREFLIGHT.md:92`).
- 81 pedidos reales del checkout (2026-06-12 → 2026-09-24) + 1 pedido de prueba F360 (#3654, `created_via=rest-api`).
- Las metas de Meta y de la pasarela **se escribieron en producción** antes de la clonación. En staging4 Meta, GTM y Clarity están desactivados (`PREFLIGHT.md:96, 212`).
- La muestra es **pequeña**: sirve para entender semántica, no para sacar métricas de negocio.

**Etiquetas:**
- **HECHO**: observado en datos o en código.
- **DOC**: documentación oficial de Woo.
- **UNVERIFIED**: no comprobable con nuestros datos.
- **HIPÓTESIS**: por verificar.
- **PROPUESTA**: diseño.

---

## Hallazgos destacados

### A. ORDER ATTRIBUTION COVERAGE

- **HECHO.** Woo Order Attribution está activo y poblado en **81 de 81 pedidos del checkout (100%)**. Solo falta en el pedido creado por API.
- **Campos siempre poblados:** `source_type`, `utm_source`, `session_entry`, `session_start_time`, `session_pages`, `session_count`, `device_type`, `user_agent`.
- **Campos parciales:**
  - `referrer`: 80%;
  - `utm_medium`: 75%;
  - `utm_content`: 58%;
  - `utm_campaign` / `utm_id` / `utm_term`: **28%**, solo en los 23 pedidos `utm` + `paid`.
- **Campos vacíos:** `utm_source_platform`, `utm_creative_format`, `utm_marketing_tactic` (0%).
- **`utm_campaign`:** son 5 IDs **numéricos** (= `utm_id`) en `ig/paid` (20) y `fb/paid` (3). Se clasifican como **`first_party_observed` / `woo_order_attribution` (último clic de sesión, 30 min) [W1]**. **No** es atribución de Meta ni prueba que tengamos atribución Meta completa: que el número sea un ID de campaña de Meta es una **HIPÓTESIS** que se verificará en G3.

### B. META PURCHASE DATA QUALITY CONFLICT

- **CONFLICT / DATA QUALITY ISSUE.**
- **Qué marcan las metas:** `_meta_purchase_tracked_server = 1` y `_meta_event_id` (UUID) están en **73 pedidos**.
- **El problema:** **23 de esos 73 (31.5%) nunca se pagaron.**
  - 20 `cancelled`: todos pasaron de "Pendiente de pago" a "Cancelado"; 18 de ellos por "pedido sin pagar cancelado, se alcanzó el límite de tiempo".
  - 3 `failed`: "Mercado Pago: el pago fue rechazado".
- **Valor de esos pedidos no pagados (`order.total`):**
  - MXN 26,320;
  - COP 4,676,000;
  - USD 795.
  
  Frente a pagados + estos no pagados, por moneda, son el 17.5%, el 36.5% y el 63%. Muestra pequeña; el valor que realmente recibió Meta es UNVERIFIED.
- **También al revés:** 4 pedidos pagados **no** tienen la marca.
- **Impacto potencial:** si Meta cuenta esos eventos, las compras y el ROAS reportados por Meta están **sobrestimados**. UNVERIFIED: no se consultó Meta.
- **F360 nunca usa `purchase` de Meta como venta.** No se corrige nada (D-G1-09).

### C. COMMERCE MONEY / DISCOUNT SEMANTICS

- **HECHO.** 11 relaciones comprobadas en **82/82** pedidos (§A.2). Las principales:
  - `total = Σline.total + cart_tax + shipping_total + shipping_tax + fees`;
  - `discount_total = Σ coupon_lines.discount = Σ(line.subtotal − line.total)`.
- **El plugin Woo Discount Rules baja el precio ANTES del `subtotal`:** 30 líneas, todas con regla "simple 15%", y `subtotal = discounted_price × qty` en 30/30. Esa rebaja (MXN 13,020 en la muestra) **no está en `discount_total`**, que solo contiene **cupones**. `line.subtotal` **no es precio de lista**.
- **`line.price` es el precio unitario después del cupón:** `price = total/qty` en 82/82, y `price = subtotal/qty` solo en 53/82.
- **Impuesto:** `prices_include_tax = false` y **todo impuesto = 0** en 82/82. Woo no calcula IVA, y eso **no** demuestra que no haya IVA.

---

## A. Hallazgos de solo lectura: dinero en Woo

### A.1 Composición (82 pedidos)

| Dimensión | Valores reales |
|---|---|
| Estado | `completed` 52 · `cancelled` 24 · `failed` 4 · `processing` 2. No hubo `pending`, `on-hold`, `refunded` ni `trash` |
| `date_paid` × estado | completed 52/52 · processing 2/2 · cancelled **1/24** · failed 0/4 |
| Moneda | MXN 47 · COP 30 · USD 5 (`currency_minor_unit 0` en MXN: pesos enteros, `PREFLIGHT.md:34`) |
| Método de pago | Mercado Pago 44 · ePayco 26 · PayPal / PPCP 10 · prueba F360 1 · vacío 1. **`payment_method_title` a veces no coincide con `payment_method`** (p. ej. `ppcp-gateway` con título "Checkout ePayco"): se usa el ID, nunca el título |
| Clienta | invitada 55 (67%) · registrada 27 |
| Descuentos | 29 pedidos con cupón (todos `percent`); 30 líneas con rebaja WDR (25 sin cupón, 5 con cupón) |
| Envío | `free_shipping` 63 · `flat_rate` 16 |
| `fee_lines` / `tax_lines` / `refunds` | 0 / 0 / **0** |
| SKU de líneas | legacy 100 · vacío 7 · `F360-*` 1 |

### A.2 Semántica de cada campo (DOC + relación comprobada)

**No se reconstruye nada sumando campos hasta demostrarlo.** Estas son las relaciones verificadas:

| Campo | DOC [W3] | Relación comprobada en datos | Resultado |
|---|---|---|---|
| `line_items[].subtotal` | "Line subtotal (before discounts)" | `= price × qty` antes del cupón. **Ya incluye la rebaja WDR** (`= discounted_price × qty`, 30/30 líneas WDR) | 82/82 |
| `line_items[].total` | "Line total (after discounts)" | `= subtotal − parte del cupón`; `= price × qty` | 82/82 |
| `line_items[].price` | "Product price" | **= `total / qty`** (después del cupón); `= subtotal / qty` solo 53/82 | El DOC es ambiguo; **los datos mandan**: no es precio de lista |
| `discount_total` | "Total discount amount for the order" | `= Σ coupon_lines.discount` **y** `= Σ(line.subtotal − line.total)` | 82/82 + 82/82 |
| `discount_tax` | "Total discount tax amount" | 0 | 82/82 |
| `cart_tax` | "Sum of line item taxes only" | `= Σ line.total_tax` (= 0) | 82/82 |
| `shipping_total` | "Total shipping amount for the order" | `= Σ shipping_lines.total` | 82/82 |
| `shipping_tax` | "Total shipping tax amount" | `= Σ shipping_lines.total_tax` (= 0) | 82/82 |
| `total_tax` | "Sum of all taxes" | `= cart_tax + shipping_tax` (= 0) | 82/82 |
| `total` | "Grand total" | `= Σ line.total + cart_tax + shipping_total + shipping_tax + Σ fees` | 82/82 |
| `prices_include_tax` | "True the prices included tax during checkout" | `false` en todos; ajuste `woocommerce_prices_include_tax = no`, `tax_display_cart = excl` | 82/82 |
| `date_paid` | "The date the order was paid" | Presente en todo pedido `processing` / `completed` | §A.1 |

**Woo Discount Rules (meta de línea `_advanced_woo_discount_item_total_discount`):**
- Claves: `initial_price`, `discounted_price`, `total_discount_details` (tipo de regla), `apply_as_cart_rule` (siempre `no`), `initial_price_based_on_tax_settings`, `discounted_price_based_on_tax_settings`, `cart_quantity`, `product_id`, `discount_lines`, `cart_discount_details`.
- Única regla observada: `simple_discount` del 15% (54 apariciones).
- `initial_price > discounted_price` en 30/30.

**Ejemplo saneado** (MXN, `completed`, cupón 10% + envío):
- línea: `subtotal 2800`, `total 2520`, `price 2520`;
- `discount_total 280` (= cupón);
- `shipping_total 200`;
- `total_tax 0`;
- **`total 2720` = 2520 + 0 + 200 + 0.**

**Ejemplo WDR:** `initial_price 2800` → `discounted_price 2380` = `subtotal` → cupón 10% → `total 2142`.

**Pedido pagado y luego cancelado (1 caso):** `date_paid` y `date_completed` presentes, `status=cancelled` y **`total = 0`**. El total original **no se conserva** en el pedido. Se trata como excepción de calidad (§G).

### A.3 Metas no estándar encontradas (solo nombres y valores no personales)

| Meta | Pedidos | Qué es | Uso en F360 |
|---|---|---|---|
| `_meta_purchase_tracked_server`, `_meta_event_id` | 73 | Marca de evento Purchase enviado por servidor. **Plugin que la escribe: UNVERIFIED.** El stack de producción incluye "Facebook for WooCommerce" (`admin/WOO_PUBLISHING_V1_PLAN.md:21`), y en staging4 está inactivo (`PREFLIGHT.md:212`); por eso la meta se escribió en producción | **Solo** como evidencia del conflicto (B). **Nunca** como venta |
| `_ivole_cr_consent` | 60 (yes 9 · no 51) | Consentimiento para el **recordatorio de reseña** (ivole) | No es consentimiento de marketing. Se registra para LEGAL_REVIEW (G0 F6). No se usa en G1 |
| `_currency_ratio` | 43 | Ver §L | **No se adopta** como FX |
| `_Mercado_Pago_Payment_IDs`, `_used_gateway`, `is_production_mode` | 37–52 | Pasarela | Conciliación futura; fuera de G1 |
| `_wc_push_notification_sent/_claimed` | 53 / 50 | Push de la app | Lifecycle; no tocar (D-G1-09) |

---

## B. Woo Order Attribution: cobertura real

**DOC [W1]:**
- Modelo de **último clic**, con cookies sourcebuster (`sbjs_*`) y sesión de **30 minutos**.
- "No sirve para seguir visitantes entre sesiones".
- Precedencia: UTM y orgánico reemplazan; directo nunca reemplaza; referral reemplaza solo sin sesión activa.
- Solo existe para pedidos creados con la función activa.
- Compatible con WP Consent API.

**Cobertura sobre los 81 pedidos del checkout (`created_via = store-api`):**

| FIELD | Poblado | Cobertura | EXAMPLE (saneado) | SOURCE | RELIABILITY | USEFUL FOR F360? |
|---|---|---|---|---|---|---|
| `source_type` | 81 | **100%** | `utm` 40 · `typein` 20 · `organic` 14 · `referral` 5 (+ un segundo valor `admin` en 2) | Woo / sourcebuster | Alta (último clic). **2 pedidos tienen la clave duplicada** (`utm`+`admin`, `referral`+`admin`): en ambos, la nota muestra un "cambio de estado mediante edición en lotes" en wp-admin. Regla: primer valor ≠ `admin` | **Sí:** canal V1 |
| `utm_source` | 81 | **100%** | `ig` 38 · `(direct)` 20 · `google` 14 · `fb` 3 · `l.instagram.com` 3 · otros 3 | URL / sourcebuster | Alta. `(direct)` es un valor de Woo, no un UTM | Sí |
| `utm_medium` | 61 | 75% | `paid` 23 · `social` 18 · `organic` 14 · `referral` 6 | URL / sourcebuster | Alta cuando existe | Sí: pagado vs orgánico |
| `utm_campaign` | 23 | **28%** | 5 valores, todos numéricos (`1202…0626`) | URL. Solo en `ig/paid` 20 y `fb/paid` 3 | Alta como texto; que sea **ID de campaña de Meta = HIPÓTESIS** | Sí, como llave candidata para G3. **No** prueba atribución Meta |
| `utm_id` | 23 | 28% | `= utm_campaign` en 23/23 | URL | Alta | Redundante |
| `utm_term` | 23 | 28% | 6 valores numéricos | URL | Media: su significado (¿conjunto de anuncios?) es HIPÓTESIS | Sí (G3) |
| `utm_content` | 47 | 58% | `link_in_bio` 18 · `/` 6 · 11 numéricos distintos | URL | Media | Sí: separa la bio orgánica del anuncio |
| `utm_source_platform` / `creative_format` / `marketing_tactic` | 0 | 0% | — | — | — | No hoy |
| `referrer` | 65 | 80% | hosts: `l.instagram.com` 19 · `instagram.com` 14 · `www.google.com` 14 · el propio sitio 13 · otros | Navegador | Media. **Solo host** (se descartan ruta y query) | Sí |
| `session_entry` | 81 | 100% | `/`, `/mx/tienda/`, `/co/`, `/co/producto/…` | sourcebuster | Alta | **Sí:** landing; prefijo de mercado (`/mx/`, `/co/`) |
| `session_start_time` | 81 | 100% | marca de tiempo | sourcebuster | Alta | Sí |
| `session_pages` | 81 | 100% | 1–70 | sourcebuster | Alta dentro de la sesión | Sí |
| `session_count` | 81 | 100% | `1` 69 · `2` 9 · otros 3 | cookie del dispositivo | Media. **No** es historial de la clienta | Solo como señal |
| `device_type` | 81 | 100% | Mobile 68 · Desktop 13 | Woo (UA) | Alta | Sí |
| `user_agent` | 81 | 100% | clase: instagram-iab 35 · ios-other 21 · desktop 13 · android-other 7 · facebook-iab 5 | Navegador | Alta | **Solo la clase** `iab_class`; el texto crudo nunca se guarda |
| Historial de pedidos de la clienta | — | 0% | — | — | — | Customer 360 (K) |

**Cruces de cobertura:**
- `utm` + `paid` → siempre trae campaign, term e id (23/23).
- `utm` + `social` → nunca trae campaign (18/18; `utm_content = link_in_bio`).
- `typein`, `organic` y `referral` → nunca traen campaign.

**SEÑAL (muestra pequeña):** 40 de 81 pedidos (49%) se pagaron dentro del navegador de Instagram o Facebook. Es insumo para CRO-IAB, que es quien hace la detección. Growth solo consume `iab_class`.

---

## C. Modelo F360 actual

| Objeto | Qué guarda | Dinero | Notas |
|---|---|---|---|
| `f360.woo_orders` (`20260928000100…:107-115`) | `target_id`, `woo_order_id`, `woo_status`, `woo_modified_at`, `currency`, `refund_ids` | No | Una fila por pedido. Control de versión por `woo_modified_at` (`stale` / `duplicate`) |
| `f360.woo_order_lines` (`:119-130` + `001500`) | Línea, SKU, cantidad, `variant_id`, `outcome`, `sale_event_id` | No | **Solo pedidos pagados.** Cada línea se escribe **una vez** porque gobierna el inventario (`20261007002100…:155-160`) |
| `f360.woo_webhook_deliveries` | Entregas y resultado | No | Sirve para medir frescura |
| `f360_ingest_woo_order` (vigente: `20261007002100…:102-251`) | Candado por pedido, deduplicación, inventario, excepciones de cancelación / reembolso (DW4) | — | **Une el registro del pedido con el movimiento de inventario** |
| `minimizeOrder` (`_shared/f360-woo/orders.ts:39-53`) | id, estado, fechas, moneda, reembolsos, líneas (id / sku / qty) | — | Aquí se pierden el dinero y la atribución |
| `public.offline_sales` + `offline_sale_items` (`20261002000300…:12-43`; C3 `:474,584`) | `total`, `payment_method`, `customer_id`, `location_id`, `idempotency_key`; líneas `unit_price`, `line_total`, `price_source`, `variant_id` | **Sí** | Líneas de solo agregar. Sin moneda (MXN implícito), sin descuento, sin devolución (DW4) |
| `f360.store_sale_facts` → `f360.sales_facts` (`20261004000400…`) | Una fila por venta de tienda (`created_by_rpc`) | Sí | Ya prevé `channel='online'` |
| `public.transactions` / `purchase_items` / `unmatched_orders` | Copia del dinero de Woo hecha por loyalty, solo socias | Sí | **No** es fuente de Commerce; solo sirve para enlazar clientas (`wc_order_id`) |
| `f360.sales_targets` | Canal = sitio Woo completo | — | Sin mercado |
| `f360.product_prices` (`20261005000100…`) | Precio de lista por moneda | — | Precio, no FX |
| `f360.reported_figures` (B4) | Cifras reportadas con estado | — | 2025 y 2026 como UNVERIFIED (D-G1-06) |

### C.1 Orígenes de venta (para distinguirlos en el futuro; no se cambia nada)

| Origen | Cómo se reconoce hoy | Visto | Evidencia |
|---|---|---|---|
| **storefront** (checkout de la clienta) | `created_via = store-api` (checkout por bloques). El checkout clásico usaría otro valor (**UNVERIFIED**: no apareció y [W3] no enumera los valores) | 81 | HECHO |
| **api_integration** (sistemas, pruebas F360) | `created_via = rest-api` | 1 (#3654) | HECHO |
| **admin_manual** (pedido creado a mano en wp-admin) | Woo marca `source_type = admin` [W1]. **No apareció ningún pedido creado en admin**; los 2 con `admin` son pedidos del checkout **editados** después (edición en lotes) | 0 | HECHO + DOC |
| **store_pos** (venta en tienda) | No pasa por Woo: `public.offline_sales` (RPC F360) | — | HECHO |
| **app** (Fuxia app) | La app **no crea pedidos Woo**: el proxy solo permite `POST customers` (`woocommerce-proxy/index.ts:32-34`) | 0 | HECHO |
| **unknown** | Ninguna de las anteriores | 1 (`payment_method` vacío; estado por revisar) | HECHO |

**PROPUESTA:** columna derivada `order_origin` ∈ storefront | admin_manual | api_integration | store_pos | unknown.
- Regla: `created_via` primero.
- `source_type = admin` **solo** cuenta como admin_manual si `created_via` también lo indica.
- Una edición posterior **nunca** cambia el origen.

### C.2 Recomendación: **D = A + C, separando economía de inventario**

| Opción | Evaluación |
|---|---|
| A. Meter el dinero en `woo_order_lines` | No: esas líneas son solo de pedidos pagados e inmutables por inventario |
| B. Tabla de hechos que copie todo (incluida la tienda) | No: duplicaría `offline_sales` |
| C. Libro + vistas | Bien para la tienda; insuficiente para la venta en línea |
| **D. (recomendada)** | En línea: ampliar la cabecera `f360.woo_orders` (misma fila y llave) + tablas hijas solo de economía (`woo_order_amount_lines`, `woo_order_refunds`, `order_attribution`). Tienda: sin copia. Vistas unificadas `commerce_orders` y `commerce_order_lines`; `sales_facts` lee de ahí. **Una venta = una fila de origen** |

---

## D. Gaps

1. El dinero y la atribución se pierden en `minimizeOrder`.
2. No hay líneas de pedidos no pagados (aceptable en V1).
3. Reembolsos: solo IDs. **Ningún caso real** para comprobarlos.
4. Sin mercado en `sales_targets`.
5. La tienda no tiene moneda, descuento ni devolución; producción sigue con el flujo legacy.
6. La rebaja WDR es invisible en `discount_total`.
7. Impuesto 0: no hay IVA derivable.
8. 67% invitadas sin vínculo de clienta.
9. Histórico de producción sin conectar (D-C1); atribución solo desde que se activó la función.
10. El ingest une pedido e inventario, así que el backfill no puede reutilizarlo tal cual.
11. Meta CAPI (B) y el pedido cancelado con total en 0: problemas de calidad externos.

---

## E. Definiciones económicas (**commerce**, no contables)

**Reglas generales:**
- **Por moneda original** (§L).
- Grano: línea → pedido.
- Solo cuentan los pedidos `countable` (§G).
- Cada fórmula usa **solo** relaciones comprobadas en §A.2.

| Métrica | Fórmula Woo | Fórmula tienda | Calidad |
|---|---|---|---|
| **ORDER** | 1 por `woo_order_id` countable | 1 por `offline_sales.id` (`created_by_rpc`) | VERIFIED |
| **UNIT** | Σ `line.quantity` | Σ `offline_sale_items.quantity` | VERIFIED |
| **GROSS SALES (GMV)** | Σ `line.subtotal` (después de WDR, antes de cupón, sin impuesto) | Σ `line_total` | VERIFIED. Etiqueta: "ventas brutas después de promociones de precio" |
| *Gross at list* | Σ `initial_price × qty` (WDR) o precio maestro F360 cuando no hay WDR | Σ `unit_price × qty` | **PARTIAL** (depende de un plugin y del maestro) |
| **MARKDOWN** (promoción de precio) | gross at list − gross sales | 0 | PARTIAL |
| **DISCOUNT** (cupón) | `discount_total` (= Σ `coupon_lines.discount` = Σ(`subtotal` − `total`)) | 0 | VERIFIED |
| **PRODUCT REVENUE** | Σ `line.total` = GMV − DISCOUNT | Σ `line_total` | VERIFIED |
| **SHIPPING REVENUE** | `shipping_total` (= Σ `shipping_lines.total`) | 0 | VERIFIED |
| **FEES** | Σ `fee_lines.total` | 0 | VERIFIED (0 hoy) |
| **TAX** | `total_tax` (= `cart_tax` + `shipping_tax`) | no registrado | VERIFIED como dato Woo. **No es IVA** |
| **ORDER TOTAL** | `total` (= PRODUCT REVENUE + `cart_tax` + SHIPPING + `shipping_tax` + FEES) | `offline_sales.total` | VERIFIED |
| **REFUND** | Σ montos de reembolso del pedido | — (DW4) | **UNVERIFIED** (sin casos) |
| **PRODUCT REFUND** | Σ \|`refund_total`\| de líneas de producto [W4] | — | UNVERIFIED |
| **NET PRODUCT REVENUE** | PRODUCT REVENUE − PRODUCT REFUND. Sin detalle por línea: − min(REFUND, PRODUCT REVENUE), marcado PARTIAL | = PRODUCT REVENUE | VERIFIED / PARTIAL |
| **AOV** (principal) | PRODUCT REVENUE ÷ ORDERS | ídem | VERIFIED |
| *AOV total* | ORDER TOTAL ÷ ORDERS | ídem | VERIFIED |
| **DISCOUNT RATE** | DISCOUNT ÷ GROSS SALES | — | VERIFIED |
| **REFUND RATE** | REFUND ÷ ORDER TOTAL | — | UNVERIFIED |

**La tienda, por verificar en G1-B:**
- `offline_sales.total = Σ line_total`;
- `line_total = unit_price × quantity`.

**Commerce ≠ contabilidad.** Falta:
- desglose de IVA (Woo = 0);
- comisiones de pasarela;
- contracargos;
- reconocimiento por entrega frente a pago;
- tipo de cambio;
- ventas físicas fuera de la app.

En la UI: "Ventas de producto", "Total de pedidos", nunca "Ingresos".

---

## F. Normalización online + física (conceptual)

```
COMMERCE ORDER (vista f360.commerce_orders) — una fila por venta, sin copiar la tienda
  source / order_origin   woo: storefront|admin_manual|api_integration|unknown · store_pos
  source_ref              target_key:woo_order_id | offline_sales.id
  channel                 online | store
  market                  MX | CO | ROW (+ market_source)             §L
  location_id             tienda (store) · por línea en online (Bodega o tienda que surtió, vía outcome/shipments)
  created_at, paid_at     paid_at = date_paid (online) · created_at (tienda)
  status_class            §G
  currency                original
  gross_sales, markdown(PARTIAL), discount, product_revenue, shipping_revenue, fees, tax, order_total, refund_total
  payment_method_id, payment_category (card|paypal|cash|transfer|test|unknown)
  attribution             → f360.order_attribution (online)
  customer_link           §K
  data_quality            §M

COMMERCE ORDER LINE (vista f360.commerce_order_lines)
  product_id / variant_id (si se resolvió) · legacy_sku · category_key (taxonomía; nada fijo de zapatos o accesorios, D-G1-08)
  qty · gross (subtotal) · discount · net (total) · tax · list_price_hint + source (PARTIAL)
  inventory_outcome (sold / sobre_pedido / legacy / …) cuando exista
```

`f360.sales_facts` = `commerce_orders WHERE status_class = 'countable'`. **El contrato de la pantalla Ventas no cambia.**

---

## G. Reglas por estado

**DOC [W2]:**
- **Pending payment:** "no payment has been made".
- **Failed:** "no payment has been successfully made".
- **Processing:** "Payment has been received (paid)".
- **Completed:** "fulfilled and is complete".
- **On hold:** "awaiting payment confirmation".
- **Cancelled:** por admin o clienta. Woo "automatically cancels eligible Pending payment orders … after the configured time limit".
- **Refunded:** "fully refunded … after payment".
- **Draft:** checkout temporal.

**HECHO (notas):** los cancelados no pagados siguen exactamente esa ruta: "Pendiente de pago" → "Cancelado" por límite de tiempo.

**Evidencia de pago:**
- `date_paid IS NOT NULL` (en la muestra, 100% consistente con `processing` / `completed`).
- La clase sale de **estado + `date_paid`**.

| Estado | Visto | `status_class` | ¿ORDERS / revenue? |
|---|---|---|---|
| `processing` | 2 | countable | **Sí** |
| `completed` | 52 | countable | **Sí** |
| `refunded` | 0 | countable (bruto) − reembolso | Sí en bruto; se resta en NET (UNVERIFIED) |
| `on-hold` | 0 | pending_payment | No |
| `pending` | 0 | pending_payment | No |
| `checkout-draft` | 0 | not_paid | No |
| `failed` | 4 | not_paid | No |
| `cancelled` sin `date_paid` | 23 | cancelled | No |
| `cancelled` con `date_paid` | 1 (total 0) | **cancelled_after_payment** | No; excepción de calidad visible |
| `trash` | 0 | excluded | No |

**Fechas:** las métricas de venta usan `paid_at`; el funnel usa `created_at`.

**Tienda:** toda venta por RPC es `countable`.

**Meta `purchase` no participa en ninguna regla.**

---

## H. Modelo de reembolsos

**DOC [W4]:**
- Recurso hijo `orders/{id}/refunds` con `amount` ("Total refund amount… takes precedence over line item totals"), `reason`, `refunded_by`, `refunded_payment`, `line_items` (con `refund_total` "excluding taxes"), `api_refund` y `api_restock`.
- En la respuesta, las líneas reembolsadas aparecen con **valores negativos** (`"quantity": -1`, `"total": "-9.00"`).
- En el pedido padre: `refunds[{id, reason, total}]` [W3].

**UNVERIFIED (sin casos en los datos):**
1. El signo de `refunds[].total` en el pedido padre.
2. Si `order.total` cambia tras un reembolso.
3. Qué webhook dispara Woo en un reembolso parcial.
4. Si un reembolso total cambia el estado automáticamente a `refunded` ([W2] dice "fully refunded").

**PROPUESTA:**
- `f360.woo_order_refunds`, una fila por `refund_id`: `amount` en valor absoluto, moneda, fecha, `product_amount`, `shipping_amount` y `line_detail_status`.
- **No se guarda `reason`**: es texto libre y puede contener datos personales.
- Parcial: varias filas. `refund_total` de la cabecera = Σ.
- Sin detalle por línea → `product_refund` PARTIAL.
- Inventario sin cambios: un reembolso **no es** una devolución física (DW4, `20261007002100…:230-246`).
- La tienda no tiene devoluciones (DW4). Un cambio de talla no es un reembolso (bitácora #7).

**Prueba necesaria en G1-B (escritura en staging4, con aprobación):**
- Un reembolso parcial y uno total con **`api_refund=false`** (para no tocar la pasarela) sobre un pedido de prueba.
- Antes, usar `refunds/preview` (Woo 11.1+ [W4]) si basta.

---

## I. Idempotencia

| Evento | Efecto |
|---|---|
| `order.created` | Inserta la cabecera `(target_id, woo_order_id)` (PK existente) con economía y clase |
| `order.updated` | Versión mayor (`date_modified_gmt`) → reemplaza la economía de la cabecera y **sustituye** las líneas de economía en la misma transacción. Igual → `duplicate`. Menor → `stale` (lógica actual sin cambios) |
| Pago | Igual que un update: la clase pasa a `countable`; `paid_at` queda fijo |
| Reembolso total o parcial | Upsert por `refund_id`; se recalcula `refund_total` |
| `cancelled` / `failed` | Cambia la clase; **nunca** se borra la fila |
| Mismo `delivery_id` | `duplicate_delivery` (existente) |
| Atribución | Una fila por pedido. Primer valor ≠ `admin`. **Inmutable** después de la primera captura |
| Tienda | `offline_sales.idempotency_key` (existente) |

**Separación clave:**
- Nueva función interna `f360.capture_order_economics(target, order)`.
- La llama `f360_ingest_woo_order` dentro de la misma transacción y candado.
- El backfill la llama **sola**, sin inventario.

**Nunca hay dos ventas por pedido.**

---

## J. Procedencia de la atribución

| `provenance` | Significado | En G1 |
|---|---|---|
| `first_party_observed` | Observado por nuestro sitio. `model = woo_order_attribution_last_click_session_30m` [W1] | **Sí** (todos los campos de B) |
| `platform_reported` | Lo que reporta una plataforma con su propio modelo (compras y ROAS de Meta) | **No** (G3). Se mostrará en otra columna, nunca mezclado |
| `derived` | Calculado por F360: `channel_group`, `market_from_path`, `iab_class`, la interpretación "ID de campaña Meta" | Solo vistas, con reglas versionadas |
| `unknown` | Sin datos (por API, admin o histórico) | Sí |

**`f360.order_attribution`, una fila por pedido:**
- `provenance`, `model`, `captured_at`;
- en lista blanca: `source_type`, `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term`, `utm_id`, `referrer_host`, `session_entry_path`, `session_start_time`, `session_pages`, `session_count`, `device_type`, `iab_class`.

**Nunca:** user agent crudo, IP ni URL con query.

**`utm_campaign` es un texto observado.** "Es una campaña de Meta" es `derived` / HIPÓTESIS hasta G3.

---

## K. Vínculo con la clienta

| Situación | Commerce Fact | Fuente |
|---|---|---|
| Registrada en Woo | `woo_customer_id` (ID numérico, sin PII) | Pedido |
| Socia de loyalty | Se deriva al consultar: `transactions.wc_order_id → customer_id` (sin copia) | Loyalty |
| Venta de tienda con QR | `offline_sales.customer_id` | Tienda |
| Invitada (67%) | `customer_link_status = guest`; sin identificador en G1 | — |
| No resuelta | `unresolved` | — |

**Customer 360 después:**
- `f360.customer_identifiers (kind, value) → profile_id`.
- `commerce_orders` hace el join al consultar.
- **Los hechos nunca se reescriben.**

**Nueva vs recurrente para invitadas:** necesita un identificador estable (p. ej. hash con sal del correo). Depende de D-C2 / D-C3 y de LEGAL_REVIEW_REQUIRED. **No se guarda en G1.** Hasta entonces, nueva vs recurrente = PARTIAL.

---

## L. Multimoneda y `_currency_ratio`

- Siempre `amount` + `currency` originales en cabecera y líneas.
- **Nunca** MXN + COP + USD sumados (D-G1-03): "Todos los mercados" = tres cifras.
- FX futuro aparte: `f360.fx_rates (base, quote, rate, source, as_of, version)`, y en las vistas `reporting_currency`, `fx_rate`, `fx_source` y `fx_version`. **No en G1.**

**Investigación de `_currency_ratio`:**

| Pregunta | Respuesta |
|---|---|
| ¿Para qué pedidos existe? | **43 pedidos, todos MXN y todos con `_used_gateway = woo-mercado-pago-custom` (43/43).** 0 en COP o USD. Faltan 2 pedidos MXN de Mercado Pago (sin `_used_gateway` tampoco) |
| ¿Qué valor tiene? | **Siempre 1** |
| ¿Qué lo genera? | Coincide al 100% con la meta de Mercado Pago, así que **HIPÓTESIS**: lo escribe el plugin de Mercado Pago. **UNVERIFIED**: no se pudo listar plugins (401) y no se consultó documentación ajena a Woo |
| ¿Representa FX? | **No como tal:** en una tienda MXN cobrando en MXN vale 1. A lo sumo sería la relación moneda de la tienda / moneda de la cuenta de la pasarela |
| ¿Es confiable? | No sirve como FX: es constante y propio de una pasarela |
| ¿Se adopta? | **No** |

**Mercado (derivado):**
1. Moneda: MXN → MX, COP → CO, USD → ROW (1 a 1 hoy, nota N4 de `INVENTORY_MODEL.md`).
2. Verificación con el prefijo de `session_entry` (`/mx/`, `/co/`).
3. `billing.country` (solo el código, D-G1-01).

Si hay conflicto, gana la moneda y la fila se marca PARTIAL.

---

## M. Calidad del dato (reutilizando lo existente)

| Mecanismo existente | Mapeo |
|---|---|
| `admin-web/src/lib/data-audit.ts` (confiable / parcial / no_disponible) | VERIFIED / PARTIAL / "Sin datos" (la ausencia no es un nivel de calidad) |
| `f360.reported_figures.status` | reportada_no_verificada → **UNVERIFIED** · verificada → VERIFIED. 2025 y 2026 = UNVERIFIED (D-G1-06) |
| CRO-5a (`online_scarcity_reliable`, `f360_inventory_certification`) | certificado → VERIFIED · no → UNVERIFIED · mixto → PARTIAL |
| `f360.woo_webhook_deliveries` | Vista `commerce_source_health`: STALE por antigüedad de la última entrega aplicada |
| Excepciones existentes (`f360.open_exception`) | `cancelled_after_payment`, reembolso sin detalle, mercado en conflicto |

**Sin columnas nuevas de estado:** `data_quality` se **calcula** en las vistas.

**ACTUAL / TARGET / FORECAST / SCENARIO nunca comparten tabla:**
- ACTUAL: `commerce_*`;
- TARGET: `growth_plans.north_star` (los $15M solo se guardan ahí y solo como objetivo);
- SCENARIO: `growth_scenarios`;
- FORECAST: no existe.

**Registro de conflictos de calidad externos (documentados, sin corregir):**

| ID | Tipo | Detalle |
|---|---|---|
| DQ-01 | CONFLICT / DATA QUALITY | Meta Purchase marcado en 23 pedidos no pagados (B) |
| DQ-02 | DATA QUALITY | Pedido pagado y cancelado con `total = 0` (monto original perdido) |
| DQ-03 | DATA QUALITY | `payment_method_title` no coincide con `payment_method` en pedidos PPCP |
| DQ-04 | DATA QUALITY | Rebaja WDR fuera de `discount_total` (GMV ≠ lista) |
| DQ-05 | DATA QUALITY | Clave `source_type` duplicada tras edición en lotes (2) |

---

## N. Acceso y seguridad

**D-G1-05:** owner y operator sí; seller y viewer no. **No se cambia ahora.** Lo que habría que modificar:

| Elemento | Hoy | Cambio |
|---|---|---|
| `public.f360_growth_plan` (`b4_growth_plan.sql:89`) | `require_role('viewer')` → seller y viewer leen el Plan y las cifras reportadas | `require_role('operator')` |
| Guardar el Plan | owner | — |
| `f360_list_sales` / `f360_get_sale` | operator | — |
| RPCs nuevas de commerce | — | `require_role('operator')` |
| Tablas nuevas | — | `REVOKE ALL` a anon y authenticated; escritura solo por service_role o funciones definer |
| `admin-web` (`Shell.tsx:6-21`) | Growth y Clientes visibles a todos | `admin: true` + redirección en el servidor (patrón de `ventas/page.tsx:15`) |
| `fuxia-native/app/admin/_layout.tsx` | Sin control de rol | Fuera de G1; se reporta |

**Datos:**
- `minimizeOrder` amplía **solo** una lista blanca.
- Prueba de que no pasan `billing` / `shipping` (salvo `country`), IP, user agent crudo, `customer_note` ni `reason` del reembolso.

**LEGAL_REVIEW_REQUIRED (D-G1-09), sin resolver:**
1. Aviso de privacidad frente a Pixel, GTM y Clarity.
2. Envíos de lifecycle sin consentimiento de marketing (existe `_ivole_cr_consent`, pero solo para reseñas).
3. **staging4 contiene pedidos reales de producción con PII** (clon).
4. DQ-01: Meta recibe eventos de compra de pedidos no pagados.
5. Futuro hash de correo (§K).

---

## O. Cambios de esquema propuestos (G1-B; no creados)

```sql
ALTER TABLE f360.woo_orders ADD
  created_at_woo timestamptz, paid_at timestamptz, completed_at timestamptz, created_via text, order_origin text,
  status_class text CHECK (status_class IN ('countable','pending_payment','not_paid','cancelled','cancelled_after_payment','excluded')),
  market text CHECK (market IN ('MX','CO','ROW')), market_source text, billing_country text CHECK (length(billing_country) = 2),
  prices_include_tax boolean, gross_sales numeric(14,2), discount_total numeric(14,2), product_revenue numeric(14,2),
  cart_tax numeric(14,2), shipping_total numeric(14,2), shipping_tax numeric(14,2), fees_total numeric(14,2),
  total_tax numeric(14,2), order_total numeric(14,2), refund_total numeric(14,2) NOT NULL DEFAULT 0,
  payment_method_id text, payment_category text, woo_customer_id bigint, economics_version timestamptz, economics_captured_at timestamptz;
CREATE TABLE f360.woo_order_amount_lines (target_id, woo_order_id, woo_line_id, woo_product_id, woo_variation_id, sku, variant_id NULL,
  quantity, subtotal, subtotal_tax, total, total_tax, list_price_hint NULL, list_price_source NULL /* 'wdr_initial_price' | 'f360_master' */,
  PRIMARY KEY (target_id, woo_order_id, woo_line_id), FOREIGN KEY (target_id, woo_order_id) REFERENCES f360.woo_orders);
CREATE TABLE f360.woo_order_refunds (target_id, woo_order_id, woo_refund_id, amount, currency, refunded_at,
  product_amount NULL, shipping_amount NULL, line_detail jsonb NULL /* qty/total por línea, sin reason */, PRIMARY KEY (target_id, woo_order_id, woo_refund_id));
CREATE TABLE f360.order_attribution (target_id, woo_order_id, provenance, model, source_type, utm_source, utm_medium, utm_campaign,
  utm_content, utm_term, utm_id, referrer_host, session_entry_path, session_start_time, session_pages, session_count,
  device_type, iab_class, captured_at, PRIMARY KEY (target_id, woo_order_id));
-- Vistas: f360.commerce_orders, f360.commerce_order_lines, f360.commerce_source_health; f360.sales_facts redefinida.
-- Funciones: f360.capture_order_economics(target, order jsonb) (interna); public.f360_commerce_summary(from, to, market) (operator+).
```

**Sin cambios en:** `woo_order_lines`, `inventory_*`, `offline_sales*`, `transactions`, `growth_*` (salvo `require_role`).

**No se guarda ninguna meta de Meta.**

---

## P. Migración y backfill

1. Migración aditiva. Los pedidos ya ingeridos quedan con economía `NULL` ("sin economía").
2. Ingesta: desde el despliegue en staging, cada webhook captura economía y atribución.
3. Backfill de staging4 (82):
   - GET de solo lectura → `capture_order_economics` (sin inventario);
   - idempotente;
   - requiere aprobación (escribe en la base de staging).
4. Producción: fuera de G1. El histórico depende de D-C1 / D-G1. La atribución existe desde que se activó la función: en la muestra, desde 2026-06-12; en producción, **por confirmar**.
5. 2025 y 2026 siguen en `reported_figures` como UNVERIFIED; nunca se convierten en ACTUAL.

---

## Q. Pruebas requeridas (G1-B)

**SQL** (`supabase/staging/f360_g1_commerce_tests.sql`, en transacción que se deshace):
1. **Idempotencia y versiones:** duplicado, versión vieja (`stale`), versión nueva que reemplaza.
2. **Clases:** las 10 filas de §G, incluido `cancelled` + `date_paid` + `total 0`.
3. **Las 11 relaciones de §A.2 como invariantes** sobre un fixture que reproduce los ejemplos (simple, cupón, WDR, WDR + cupón, envío).
4. **Reembolsos:** parcial, total, repetido, mayor que el revenue de producto. Marcar las expectativas como **UNVERIFIED** hasta la prueba real en staging4.
5. **Multimoneda:** el resumen devuelve MXN, COP y USD separados; nunca un total mezclado.
6. **Mercado:** derivación y conflicto.
7. **Atribución:** duplicado `utm` + `admin`; pedido por API → `unknown`; campos fuera de la lista blanca → no se guardan.
8. **Origen:** `store-api` → storefront; `rest-api` → api_integration; `admin` solo editado → sigue storefront.
9. **Inventario intacto:** el backfill no crea `inventory_events` ni `woo_order_lines`; regresión de P2.3A, D2 y 002100.
10. **Tienda:** `commerce_orders` incluye la tienda sin copiarla; `sales_facts` mantiene su contrato (regresión C3.3).
11. **Permisos:** seller, viewer y anon rechazados.

**Node:**
- `minimizeOrder` con un fixture que trae PII → nada de PII en la salida.
- Clasificador `iab_class`.

**Suite completa:** 687 pruebas existentes.

---

## R. Rollback

- `supabase/rollbacks/<ts>_f360_g1_commerce_facts.down.sql`:
  - borra vistas, tablas y columnas nuevas;
  - restaura `f360_ingest_woo_order`, `sales_facts` y `minimizeOrder` a `20261007002100`.
- No toca inventario.
- Ensayo: aplicar → pruebas → rollback → regresión → reaplicar.

---

## S. Riesgos

| Riesgo | Mitigación |
|---|---|
| Doble verdad con `transactions` | Commerce no la usa como fuente de dinero |
| Romper el inventario | `capture_order_economics` separada + regresión completa |
| Leer "Ventas" como ingreso contable | Nombres de commerce; nota fija; sin "Ingresos" |
| Muestra chica (sin reembolsos, `on-hold` ni `pending`) | Comportamientos marcados UNVERIFIED; pruebas reales aprobadas en G1-B |
| Confundir atribución Woo con Meta | `provenance` explícita; columnas separadas en G3 |
| DQ-01 (Meta) | Documentado; F360 no usa `purchase` de Meta; no se corrige |
| WDR invisible | GMV oficial = `subtotal` (VERIFIED); lista = PARTIAL |
| PII en staging4 | LEGAL_REVIEW_REQUIRED; lista blanca estricta |
| Webhook sin entregar (WP-Cron) | `commerce_source_health` → STALE + reconciliador existente |

---

## T. Alcance exacto propuesto para G1-B (solo staging)

**Incluye:**
1. Migración §O + vistas + `sales_facts` con online.
2. `capture_order_economics` invocada desde el ingest, sin cambiar la lógica de inventario.
3. `minimizeOrder` con lista blanca + prueba de no-PII.
4. `f360_commerce_summary` (operator+), por moneda.
5. Permisos D-G1-05 (Plan → operator; Growth y Clientes solo owner y operator).
6. UI mínima:
   - Ventas: canal "En línea" por moneda.
   - Growth: Pedidos, Ventas de producto y AOV con fuente y calidad.
   - Plan 2027: fila **ACTUAL (PARTIAL desde <fecha>)** separada del TARGET.
7. Backfill de los 82 pedidos de staging4 (solo economía).
8. Pruebas, rollback y reporte.

**Aprobaciones específicas necesarias:**
- (a) escritura en la base de staging;
- (b) reembolsos de prueba en staging4 con `api_refund=false`;
- (c) despliegue de la Edge Function en staging.

**No incluye:**
- FX;
- Campaign 360, gasto o Meta API;
- GTM, Clarity o eventos;
- hash de correo;
- lifecycle, privacidad, CAPI o plugins;
- producción e histórico de producción;
- taxonomía de accesorios.

### Decisiones abiertas

| # | Decisión | Recomendación |
|---|---|---|
| G1-Q1 | GMV oficial | `line.subtotal` (después de WDR, antes de cupón) = VERIFIED; "a precio de lista" = PARTIAL secundaria |
| G1-Q2 | AOV principal | Ventas de producto ÷ pedidos (sin envío) |
| G1-Q3 | Umbral de STALE de Woo | 6 h sin entregas aplicadas |
| G1-Q4 | `cancelled_after_payment` | Excluir de ventas; mostrar como excepción |
| G1-Q5 | Detalle de reembolsos | Sí, un `GET /orders/{id}/refunds` por reembolso nuevo |
| G1-Q6 | `order_origin` | Aprobar las 5 clases de §C.1 |
