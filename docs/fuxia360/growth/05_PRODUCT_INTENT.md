# 05 · Product Intent (capa unificada de intención)

**Fecha:** 2026-10-08. **Estado:** especificación. **Sin modelos predictivos:** solo conteo y agregación de hechos observados.

**Antecedentes que se reutilizan:** `FAVORITOS_V1.md` §4 ("Favoritos + Avísame + ATC + Compra → Product Intent"), CRO-5 (`/demanda`, `f360_stock_demand`), identidad canónica G2-B2, `f360_favorites_report` (`20261012000800` / `20261012000900`).

---

## 1. Principio

La intención es una **señal**, no una venta. Se mide para decidir **qué producir, reponer, mover entre ubicaciones, publicar o promover**. Cada señal conserva su tabla de origen (no se copia a una tabla nueva de eventos); la capa unificada es una **vista** que normaliza todas a la misma forma:

```
intent_type | occurred_at (CDMX) | market | channel | product_key (F360-{MODELO}) | color | size_label (canónica)
| canonical_sku (si hay variante) | location_id (si aplica) | subject_kind (anon | customer | none) | subject_ref (hash/uuid, nunca PII)
| source_table | source_id | weight_hint (NULL; no se pondera en V1)
```

---

## 2. Tipos de intención

| intent_type | Tabla de origen (sin copia) | Estado | Resolución canónica | Sujeto | Notas |
|---|---|---|---|---|---|
| `VIEW` | GA4 `view_item` vía Data API → **agregado diario** `f360.ga4_item_daily` (propuesta) | MISSING en F360 | `item_id` Woo → `channel_product_identity` (legacy) o `F360-{MODELO}` (V1.1) | ninguno (agregado) | Solo conteo por día × mercado × modelo; sin `client_id` |
| `SEARCH` | `f360.storefront_searches` | LIVE (8) | **Ninguna**: el término es texto. PROPUESTA: diccionario término → modelo (`f360.search_term_map`, decidido por Carolina) y `results_count` | ninguno | Sanear PII (S2 de `01_…`) |
| `FAVORITE` | `f360.favorite_events` (`favorite_added`) | LIVE (11) | Servidor: `product_id`, `color_id`, `variant_id` (`20261012000800`) | `anon` (`anon_id`) | "Favorito activo" = último evento del visitante sobre el producto es `added` |
| `FAVORITE_REMOVED` | `f360.favorite_events` | LIVE (6) | Ídem | `anon` | Señal negativa; no resta ventas |
| `HILO` | `f360.customer_cases` (escalaciones) | PARTIAL (1) | **Texto libre** (`product_name`, `color`, `size` como "25 MX"). PROPUESTA: resolver en el intake a `product_key` / `canonical_sku` con la misma regla de la tienda (talla MX + 13 = talla canónica, `tools/storefront/f360-favoritos.html:257`) | `customer` si trae teléfono/correo | Solo escalaciones; las conversaciones completas viven en HiloLabs (UNKNOWN si exportables) |
| `NOTIFY_ME` | `f360.stock_intents` | STAGING (0 en prod) | `variant_id`, `canonical_sku`, `product_key`, `color`, `size` (`20261010000700:79-…`) | `customer` / teléfono (consentimiento `stock_notification`) | Requiere el snippet Avísame en producción |
| `ADD_TO_CART` | GA4 `add_to_cart` (agregado diario) + `favorite_events` (`favorite_add_to_cart`, LIVE 5) | PARTIAL | GA4: ID de variación Woo → `channel_variant_identity`; favoritos: canónico | ninguno / `anon` | La columna "A la bolsa desde ♡" ya existe en el reporte |
| `CHECKOUT` | GA4 `begin_checkout` (agregado) + Commerce Facts `pending_payment` / `not_paid` / `cancelled` | PARTIAL | Líneas Woo → canónico (`commerce_order_lines`) | ninguno | El pedido creado y **no pagado** es intención fuerte con variante exacta, ya en F360 |
| `PURCHASE` | `f360.commerce_order_lines` de PS | LIVE | `canonical_sku`, `canonical_product_key`, `identity_link_state` | `customer` cuando esté ligado | Es la referencia contra la que se mide todo |

**Fuera de V1:** vistas de PDP individuales por persona, scroll, tiempo en página, Clarity.

---

## 3. Agregaciones soportadas

| Eje | Llave | Disponible hoy |
|---|---|---|
| Modelo | `product_key` (`F360-{MODELO}`) | Sí (favoritos, compras, Avísame) |
| Color | `f360.product_colors.name` (vía `color_id` / variante) | Parcial (favoritos 5/22 con color) |
| Talla | `product_variants.size_label` (35–40 canónica; MX = canónica − 13 solo en presentación) | Parcial |
| Mercado | `market` (`mx`/`co` en favoritos; `MX`/`CO`/`ROW` en commerce) — **normalizar mayúsculas** | Sí |
| Ubicación | `location_id` (ventas de tienda; inventario disponible por `inventory_balances`) | Solo compras |
| Clienta | `customer_id` | Solo Avísame / Hilo / compras ligadas |
| Anónimo | `anon_id` | Solo favoritos |
| Tiempo | día / semana / mes (CDMX) | Sí |

**Cruces útiles (todos agregados, sin PII):**
1. **Intención sin inventario:** intención (FAVORITE + NOTIFY_ME + CHECKOUT no pagado) donde `inventory_balances` disponible = 0 → alimenta `/demanda` y Producción (sobre pedido).
2. **Intención sin conversión:** FAVORITE/ADD_TO_CART alto y PURCHASE bajo → revisar precio, foto, talla, disponibilidad.
3. **Conversión por intención:** `PURCHASE ÷ FAVORITE` por modelo (tasa, no causalidad).
4. **Mercado:** intención en CO de un modelo sin precio COP (ver incidente `f360-guardia-precio-pais.php`).

---

## 4. Ejemplo: **Paula · Negro · MX 25**

Identidad (verificada en producción, solo lectura): producto `PAULA` ("Paula"); color "Negro"; tallas canónicas 35–40. **MX 25 = talla canónica 38** (regla de la tienda: MX = canónica − 13). SKU canónico: **`F360-PAULA-NEGRO-38`**. (Existe también `PAULA-GAMUZA`, que es otro modelo.)

Vista objetivo para un periodo (cifras **ilustrativas de forma, no datos reales**; los valores reales hoy son 0 o muy pocos):

| intent_type | Mercado | Conteo | Sujetos distintos | Fuente | Calidad |
|---|---|---|---|---|---|
| VIEW (modelo PAULA) | MX | *n* | — | GA4 Data API | DATA INCOMPLETE hasta tener API |
| SEARCH "paula" | MX | *n* | — | `storefront_searches` (match por diccionario) | PARTIAL |
| FAVORITE (color Negro, talla 38) | MX | *n* | *n anon* | `favorite_events` | VERIFIED |
| HILO ("Paula negro 25 MX") | MX | *n* | *n clientas* | `customer_cases` (resuelto a 38) | PARTIAL (texto) |
| NOTIFY_ME `F360-PAULA-NEGRO-38` | MX | *n* | *n* | `stock_intents` | VERIFIED cuando esté en prod |
| ADD_TO_CART | MX | *n* | — | GA4 + favoritos | PARTIAL |
| CHECKOUT no pagado | MX | *n* | — | Commerce Facts | VERIFIED |
| PURCHASE | MX | *n pares* | *n clientas* | Commerce Facts | VERIFIED |
| Disponible hoy | — | *n pares por ubicación* | — | `inventory_balances` | — |

**Lectura para Carolina (UX simple):** "Paula Negro talla 25: 12 la guardaron en favoritos, 3 piden aviso, 2 preguntaron a Hilo, 4 se vendieron, quedan 0 en Bodega y 1 en Polanco." Ningún nombre ni teléfono.

---

## 5. Llaves y normalización (requisitos)

| Problema | Regla |
|---|---|
| Mercado `mx` vs `MX` | Mayúsculas en la vista |
| Talla MX vs canónica | Siempre `size_label` canónica en la capa; la MX se calcula solo para mostrar en MX |
| Producto legacy sin homologar | `product_key = 'legacy'` + `identity_link_state = unresolved`; **nunca** se adivina por nombre (`G2B2` §C) |
| Favorito sin color/talla | Cuenta a nivel modelo; no se reparte entre tallas |
| Intención repetida de la misma persona | Contar eventos **y** sujetos distintos; el reporte principal usa sujetos distintos |
| Intención de prueba (equipo) | `TEST_PHONES` ya existe en `f360-store-reserve`; PROPUESTA: `anon_id` de prueba marcados |

---

## 6. Objeto propuesto (sin migración)

`f360.product_intent_events` — **VISTA** (UNION ALL de las tablas de §2; GA4 entra solo como agregado diario):
- **PURPOSE:** una forma común para contar intención por producto.
- **SOURCE OF TRUTH:** las tablas de origen (no guarda nada).
- **RLS / acceso:** la vista **no** se expone; se lee con `public.f360_product_intent_report(p_from, p_to, p_market, p_product_key)` (`require_role('operator')`), que devuelve solo agregados sin `subject_ref`.
- **Retención:** la de cada tabla de origen.
- **Existente que ya cubre parte:** `f360_favorites_report` (por modelo) y `f360_stock_demand` (Avísame + sobre pedido). El reporte nuevo **extiende** esos dos; no los reemplaza hasta que Mario lo apruebe.

`f360.ga4_item_daily` — **TABLA** (propuesta, G3):
- **PURPOSE:** conteos diarios de `view_item`, `add_to_cart`, `begin_checkout` por `item_id` y mercado desde la GA4 Data API.
- **PK:** `(ga4_property_id, date, market, event_name, item_id)`. **Columnas:** `item_id`, `identity_scheme`, `resolved_product_key`, `resolved_canonical_sku`, `event_count`, `fetched_at`, `run_id`.
- **Escritura:** service role (job). **Lectura:** por RPC. **Retención:** 25 meses (alineado con GA4). **Auditoría:** `run_id` → `f360.measurement_runs` (propuesta).
