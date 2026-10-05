# G2-B2 · Identidad canónica de producto y variante + Measurement V1.1 sobre esa identidad

**Fecha:** 2026-10-04.

**Decisión de Mario (regla permanente de Fuxia 360, no solo de Analytics):** la identidad maestra es la de Fuxia 360. Los IDs de Woo son externos, del canal. La regla quedó en `INVENTORY_MODEL.md` §1.1, que es la fuente de verdad arquitectónica.

**Reemplaza:** G2-B1 §C (que proponía el padre Woo como `item_id`).

**Estado:** solo diseño y auditoría de solo lectura (staging + código).
- **Sin migraciones.**
- **Sin cambios en producción** (aparte de P1, ya aplicado).

---

## A. Auditoría del esquema: ¿podemos representar la relación hoy?

**Sí, casi completa.** Lo que existe (verificado en migraciones + staging, solo lectura):

| Pieza requerida | Objeto actual | Estado en staging |
|---|---|---|
| `canonical_product_id` | `f360.products.id` + `code` (único, inmutable tras publicar: `codes_locked_at`, trigger `guard_locked_codes`) | 60 productos, 11 con código bloqueado |
| `canonical_variant_id` | `f360.product_variants.id` (único por color + talla) | 870 variantes |
| `canonical_sku` | `f360.product_variants.sku` = `f360.variant_sku()` → **`F360-{MODELO}-{COLOR}-{TALLA}`** (único; bloqueado tras publicar) | **870 de 870 con SKU canónico, 870 distintos** |
| SKU de modelo en el canal | Woo padre publicado con `F360-{MODELO}` (`mapping.ts`: `parentSku`) | — |
| `sales_channel_id` | `f360.sales_targets.id` (`key`, `fulfillment_location_id`, `is_production`) | `woo_staging4` activo |
| Woo ↔ canónico **vigente** | `f360.woo_product_links (target, product_id ↔ woo_product_id)`, `f360.woo_variant_links (target, variant_id ↔ woo_variation_id, origin = f360_published \| legacy_adopted, woo_product_id)` | 7 productos, 90 variaciones `f360_published` |
| Woo ↔ canónico **histórico** | `f360.retired_woo_links (target, woo_variation_id → variant_id, retired_at, reason)` | 234 variaciones retiradas al unir modelos |
| Decisión humana (homologación) | `f360.legacy_woo_map (target, woo_variation_id → confirmed_variant_id, status, decided_by…)` + guard: un vínculo legacy **solo** se crea desde una fila `confirmado` (`woo_variant_link_guard`) | 678 confirmadas (678 variantes distintas) · 12 `requiere_revision` · 102 `sin_correspondencia` |
| Uno a muchos en el tiempo | Una variante con variación vigente + retiradas | 90 variantes ya tienen más de un ID de Woo (vigente + retirado), **sin perder identidad** |

---

## B. Gaps: dónde un ID de Woo todavía actúa como identidad (o falta algo)

| # | Lugar | Problema | Severidad |
|---|---|---|---|
| B1 | `f360.products.wc_product_id`, `f360.product_variants.wc_variation_id` | Columnas **dormidas** que duplican identidad (N3). Hoy 0 filas con valor | Bajo; retirar |
| B2 | **Vista `f360.commerce_order_lines` (G1)** | Expone `sku` = **SKU de la línea en Woo** (en legacy: SKU del padre heredado), **no** el canónico. Resuelve `variant_id` en vivo, pero **no muestra `canonical_sku`**. En staging, 103 de 103 líneas resueltas tienen SKU Woo ≠ canónico | **Medio:** Growth podría agrupar por el SKU equivocado |
| B3 | **No hay una vista única de mapping** | La correspondencia está repartida en 3 tablas (`woo_variant_links`, `retired_woo_links`, `legacy_woo_map`). Cada consumidor repite el `COALESCE` (G1 lo hace en `commerce_order_lines`) | Medio |
| B4 | No se guarda el **SKU observado en Woo** por variación vinculada | El mapping pide `woocommerce_sku`. Para `f360_published` es igual al canónico (lo verifica `sku_mismatch`). Para legacy es el SKU del padre (no identifica variante) | Bajo: dato de canal, no identidad |
| B5 | **App y loyalty (esquema `public`)** | `purchase_items.wc_product_id`, `wishlists(customer_id, wc_product_id)`, `product_image_overrides(wc_product_id)`, `offline_sale_items` legacy con SKU de texto: la app usa el ID de Woo como identidad de producto | Medio para Customer 360. Se resuelve vía mapping, sin migrar datos |
| B6 | **GA4** (GTM4WP) | `item_id` = ID padre Woo (listas, ficha) / ID de variación Woo (carrito → compra) | Alto para Measurement (§F) |
| B7 | **Meta (catálogo + eventos)** | `content_ids` / `retailer_id` del plugin = SKU de Woo o `wc_post_id`; catálogo de 218 productos sincronizado por el plugin | Medio (G2-META) |
| B8 | Fragmentos de la tienda (`f360_storefront_catalog`, `f360-store-reserve`) | Indexan por IDs de Woo **como llave de canal** y traducen a variante (correcto) | OK (es lo que deben hacer) |
| B9 | Ingesta de pedidos (`f360_ingest_woo_order`) | Resuelve por `woo_variation_id` → `variant_id` y guarda la **variante canónica** en `woo_order_lines` | OK |

**Conclusión:** **no hace falta una tabla nueva de identidad.** Faltan:
- una **vista de mapping** (B3);
- exponer el **`canonical_sku`** en Commerce Facts (B2);
- opcionalmente, el SKU observado (B4).

---

## C. Mapping actual (cómo se resuelve hoy una variación Woo → variante canónica)

```
woo_variation_id (de un pedido, evento o catálogo) + target (canal)
  1. f360.woo_variant_links      (vigente; origin f360_published | legacy_adopted)
  2. f360.retired_woo_links      (histórico: producto por color unido a un modelo)
  3. f360.legacy_woo_map         (status='confirmado' → confirmed_variant_id; decisión de Carolina)
  → canonical_variant_id → product_variants.sku = canonical_sku → product_id → products.code
  sin match → UNRESOLVED (nunca se adivina por nombre, color o talla)
```

---

## D. Propuesta de identidad canónica (sin tabla nueva)

1. **Vista `f360.channel_variant_identity`** (B3), una fila por `(sales_channel_id, woo_variation_id)`:
   - `canonical_variant_id`, `canonical_sku`, `canonical_product_id`, `product_code`;
   - `woo_product_id`, `woo_sku_observed` (si existe);
   - `link_state` (`current` / `retired` / `homologated_only`);
   - `source` (`woo_variant_links` / `retired_woo_links` / `legacy_woo_map`);
   - `valid_from`, `valid_to` (de `linked_at` / `retired_at`).
   
   Es la **única** puerta para traducir canal ↔ canónico (Commerce Facts, Growth, reconciliación GA4, Customer 360).
2. **Commerce Facts** (`commerce_order_lines`): agregar `canonical_sku` y `product_code` (de la vista). El `sku` de Woo queda como `channel_sku`.
3. **Opcional:** `woo_variant_links.woo_sku_observed`, llenado por el publicador y el reconciliador. Solo como dato de canal.
4. **Retiro de B1** (columnas dormidas), en una migración aparte y aprobada.

---

## E. Tratamiento legacy (los 129 productos Woo; sin cambios masivos)

| Situación del producto Woo | En Woo (no se toca) | En Fuxia 360 | En GA4 |
|---|---|---|---|
| **Legacy no unido**, con homologación confirmada | Su ID, sus variaciones y su SKU de padre se quedan | `legacy_woo_map` → variante canónica | **`item_id` histórico sin cambios** (IDs de Woo). Se reconcilia offline con la vista D1 |
| **Legacy unido** (consolidado en un modelo F360) | Producto viejo **privado** (nunca borrado); el nuevo producto Woo lo publica F360 con SKU canónico | `retired_woo_links` (viejo) + `woo_variant_links` (nuevo) | Viejo: IDs Woo históricos. Nuevo: **SKU canónico** (§F) |
| Legacy **sin correspondencia** (102) o **requiere revisión** (12) | Sin cambios | UNRESOLVED hasta que Carolina decida | IDs Woo; aparecen como "sin identidad canónica" en los reportes |

**Regla:** el histórico de GA4 **nunca se reescribe**. Cualquier análisis que cruce periodos traduce con la vista D1.

---

## F. Contrato Analytics V1.1 sobre la identidad canónica

### F.1 Identidades por momento del funnel

| Momento | `item_id` | `item_group_id` (custom, a nivel item) | `item_variant` | Regla |
|---|---|---|---|---|
| `view_item_list` | **Modelo:** `F360-{MODELO}` (productos F360) · ID padre Woo (legacy) | igual a `item_id` | — | No hay variante elegida: **no se inventa** |
| `select_item` | Modelo (igual) | igual | — | Ídem |
| **Ficha sin variante elegida** → `view_item` (una vez por carga) | Modelo | igual | — | **Un solo `view_item` por carga** |
| **Ficha con variante elegida** → `f360_select_size` (CRO, no `view_item`) | **`canonical_sku`** (`F360-MACARENA-NUDE-37`) | `F360-MACARENA` | `"Nude / 37"` (texto) | El paso producto → variante es **un evento de intención**, no otra vista. El `view_item` que GTM4WP repite en `found_variation` **se descarta** (no se reenvía) |
| `add_to_cart` | **`canonical_sku`** | `F360-{MODELO}` | texto | Igual en todo el resto del funnel |
| `view_cart` / `begin_checkout` / `purchase` | **`canonical_sku`** | `F360-{MODELO}` | texto | `purchase.transaction_id` = `woo_order_id` (reconciliación con Commerce Facts) |
| **Legacy** (cualquier evento) | **Sin cambios:** padre o variación Woo, como hoy | ID padre Woo | atributos Woo | Se traduce offline (E) |

**Resultado:** para catálogo F360, `F360-MACARENA-NUDE-37` es el mismo `item_id` desde que se elige la talla hasta la compra. El modelo se sigue por `item_group_id`, que se registra como dimensión personalizada a nivel item en GA4.

### F.2 Cómo se implementa sin tocar legacy ni GTM4WP

1. **Un snippet de WordPress** (*Fragmentos de código*, que ya está instalado) en el filtro soportado **`gtm4wp_eec_item_with_source`** de GTM4WP 2.0.5. Se aplica en el servidor a cada item de listados, ficha, carrito, checkout y compra:
   - si el SKU del producto o variación empieza con `F360-` → `item_id` = ese SKU; `item_group_id` = SKU del padre (`F360-{MODELO}`); `identity_scheme` = `f360`;
   - si no → **no cambia nada** (`identity_scheme` = `legacy_woo`).
2. **GTM:** el trigger GA4 (P2, allowlist exacta) + condición "no reenviar `view_item` cuando el item trae `item_group_id` ≠ `item_id`". Así se descarta el `view_item` de `found_variation`, que GTM4WP arma en el navegador con el ID de variación.
3. **CRO:** `f360_select_size` con el `canonical_sku` (los fragmentos ya conocen el SKU de la variación).
4. **GA4:** registrar `item_group_id` e `identity_scheme` como dimensiones personalizadas a nivel item (cambio de configuración; requiere rol Editor).

---

## G. Impacto en la homologación

- La homologación de Carolina (`legacy_woo_map` confirmado) es **la única** fuente de correspondencia legacy ↔ canónico. Nada lo adivina.
- **Prioridad:** cerrar las **12 en revisión** y decidir las **102 sin correspondencia**, ordenadas por ventas (`sold_90d`). Cada una sin resolver es venta legacy que Growth no puede atribuir a una variante canónica.
- **Ninguna homologación nueva cambia hechos pasados:** la vista D1 la aplica en vivo. Commerce Facts gana resolución sin reescribirse (patrón ya probado en G1).

---

## H. Impacto futuro al reorganizar el catálogo Woo

| Acción futura | Efecto en identidad |
|---|---|
| Unir más modelos (consolidación) | Variación vieja → `retired_woo_links`; nueva → `woo_variant_links` con SKU canónico. **La identidad canónica no cambia.** GA4 pasa de IDs Woo a SKU canónico en la fecha de unión (registrar la fecha) |
| Recrear o republicar un producto Woo (IDs nuevos) | Solo cambia el mapping vigente. SKU canónico igual |
| Nuevo canal (otra tienda Woo, marketplace) | Otro `sales_channel_id` con sus propios vínculos. Mismo SKU canónico |
| Cambiar de motor de ecommerce | Se reemplaza el canal; la identidad F360 sobrevive |
| Meta: catálogo | Cuando el plugin sincronice productos F360, `retailer_id` debería ser el SKU canónico (G2-META) |
| Cambiar nombre o color de un modelo ya publicado | El código y el SKU están **bloqueados** (no cambian); solo cambia el nombre visible |

---

## I. Migraciones y código que serían necesarios (NO hechos)

| # | Pieza | Tipo | Notas |
|---|---|---|---|
| I1 | Vista `f360.channel_variant_identity` (D1) | Migración aditiva (staging) | Sin tabla nueva. Pruebas: vigente, retirado, solo homologado, sin resolver, uno a muchos |
| I2 | `commerce_order_lines` + `canonical_sku`, `product_code`, `channel_sku` | Migración (vista) | Excepción acotada al congelamiento de G1, por ser un bug de identidad (B2). Requiere aprobación |
| I3 | `woo_variant_links.woo_sku_observed` (opcional) | Migración + publicador | Dato de canal |
| I4 | Retiro de `products.wc_product_id` / `product_variants.wc_variation_id` | Migración aparte | Verificar 0 usos antes |
| I5 | Snippet `gtm4wp_eec_item_with_source` | WordPress (producción) | Probar primero en staging4 (sin GTM allí hoy: validar el `dataLayer` con `curl` y la consola) |
| I6 | GTM: allowlist (P2) + descarte del `view_item` de variación | GTM (producción) | Requiere acceso Editar / Publicar |
| I7 | GA4: dimensiones `item_group_id`, `identity_scheme` | Config GA4 | Editor |
| I8 | CRO: `f360_select_size` con `canonical_sku` | Fragmentos | Contrato V1 → V1.1 |
| I9 | Contrato `G2_MEASUREMENT_CONTRACT.md` → **V1.1** | Docs | `item_id` canónico, `item_group_id`, `identity_scheme` |

---

## J. Riesgos y rollback

| Riesgo | Mitigación | Rollback |
|---|---|---|
| Cambio de `item_id` en GA4 parte las series de productos F360 | Solo afecta productos con SKU `F360-` (hoy pocos en producción). Fecha de corte registrada en el contrato. `item_group_id` permite la continuidad por modelo | Desactivar el snippet (I5) |
| Romper el `dataLayer` de GTM4WP con el filtro | Snippet mínimo: solo toca items con SKU `F360-`. Probar en staging4 + `curl` del `dataLayer` | Desactivar el snippet |
| Legacy sin homologar aparece "sin identidad" | Es correcto (no se adivina). Lo ataca la priorización de G | — |
| Vista D1 con ambigüedad (la misma variación Woo en dos vínculos) | Constraints actuales: `UNIQUE (target, woo_variation_id)` en `woo_variant_links`; PK en `retired_woo_links`. La vista prioriza vigente > retirado > homologado. Prueba de unicidad | Borrar la vista |
| Retiro de columnas dormidas (I4) rompe algo escondido | Búsqueda de usos en repo y funciones desplegadas antes | Re-agregar columnas (estaban vacías) |
| Meta / catálogo con IDs distintos a GA4 | Fuera de este paso: G2-META | — |

---

## Decisiones para aprobar

1. **I1 + I2** (vista de mapping + `canonical_sku` en Commerce Facts), en staging.
2. **Contrato V1.1** (§F): modelo hasta elegir variante; SKU canónico desde la variante; `view_item` de variación descartado; `item_group_id` = `F360-{MODELO}`.
3. **I5** (snippet en el filtro de GTM4WP): primero en staging4.
4. **Fecha de corte** para GA4 de los productos F360 en producción.
5. **I4** (retiro de columnas dormidas): ¿ahora o después?

---

## Ejecución (2026-10-04)

### G2-B2.1 · Vista de identidad canónica: HECHO en staging

- **Migración** `20261008000300_f360_g2_identity_resolution.sql`, aplicada con `db push --db-url` y dry-run previo. **Rollback** `…000300…down.sql`, ensayado: deja la vista G1 con 19 columnas y al deshacer vuelve a 24.
- **Vistas** sobre las tablas existentes (sin una cuarta fuente de verdad):
  - `f360.channel_variant_identity_all` (todas las relaciones);
  - `f360.channel_variant_identity` (una por canal y variación Woo; prioridad vigente > retirada > homologada);
  - `f360.channel_product_identity` (producto Woo ↔ `F360-{MODELO}`).
- **`f360.commerce_order_lines`:** mismas 19 columnas de G1 + `channel_sku`, `canonical_sku`, `canonical_product_key`, `identity_link_state`, `identity_source`. Hechos, dinero e idempotencia sin cambios.
- `wc_product_id` / `wc_variation_id` marcados **DEPRECATED** (comentario de columna). No se retiraron.
- **Pruebas:** `supabase/staging/f360_g2_identity_tests.sql` **18/18**. Suite completa **768/768** (incluye G1 47/47 después del cambio).
- **Datos (staging):**
  - 768 variaciones Woo resueltas (vigentes 90 · retiradas 234 · homologadas 678; prioridad aplicada);
  - **0 ambiguas**;
  - 90 variantes con varios IDs Woo históricos, todos al mismo SKU canónico;
  - 0 padres legacy ambiguos;
  - 5 líneas de pedido siguen sin resolver (sin homologación: no se adivina).

### G2-B2.2 · Snippet Analytics V1.1 en staging4: **PARCIAL** (faltan `add_to_cart` v2 y `purchase`)

- **Aislamiento (opción b de Mario):** en staging4 se puso la colocación de GTM4WP en "Desactivado" (`gtm-code-placement` = 3, entero) **antes** de activar el plugin (2.0.3, 2026-10-05 01:04 UTC).
  - Se verificó antes y después: no aparecen `GTM-W2PZG3L5`, `gtm.js`, `G-8C1244627P`, Meta ni Clarity. Solo existe el `dataLayer`.
  - **Ningún evento de staging4 llega a GA4 ni a Meta de producción.**
- **Snippet** `tools/measurement/f360-measurement-v11-staging4.php` instalado como mu-plugin con `php -l` OK en el servidor:
  - v1: 2026-10-05 01:17 UTC;
  - v2 (normalizador del `dataLayer` en la página de producto): 2026-10-05 02:05 UTC.
- **Evidencia:** lectura del `dataLayer` en el navegador, staging4, Macarena Nude 37 (variación Woo 3624) + un producto legacy.

| Evento | Estado | Evidencia / falta |
|---|---|---|
| `view_item_list` / productos relacionados legacy | **VERIFIED** | Conservan el ID de Woo y `identity_scheme = legacy_woo`; sin cambios |
| `view_item` de la página de producto (servidor) | **VERIFIED** | `item_id = F360-MACARENA` |
| `f360_select_size` | **VERIFIED** | `item_id = F360-MACARENA-NUDE-37`, `item_group_id = F360-MACARENA`, `mc_version = 1.1` |
| `view_item` de GTM4WP en `found_variation` (JS, ID de Woo, ×2) | **UNVERIFIED (descarte)** | Existe tal como se esperaba. La regla GTM V1.1 `item_group_id ≠ item_id` → descartar todavía no se construye (no hay GTM en staging4) |
| `add_to_cart` desde la página de producto | **UNVERIFIED** | Con v1 salió **mal** (`item_id = 3624`). Falta verificar la v2: la automatización de colores y tallas no registra la selección y se detuvo por instrucción de Mario |
| `view_cart` | **VERIFIED** | `F360-MACARENA-NUDE-37`; legacy 316 sin cambios |
| `begin_checkout` | **VERIFIED** | `F360-MACARENA-NUDE-37` |
| `add_shipping_info` / `add_payment_info` | **VERIFIED** | `F360-MACARENA-NUDE-37` |
| `purchase` (página de gracias) | **UNVERIFIED** | No se hizo compra con el snippet v2 |
| `remove_from_cart`, `select_item` | no probados | Fuera de alcance de esta prueba |

- **Pedidos reales de staging #4111 y #4114** (Instagram Android, Mercado Pago, 2026-10-04): **no sirven como evidencia de eventos V1.1.**
  - #4111 se creó a las 00:56 UTC, **antes** de activar GTM4WP.
  - #4114 se creó a las 01:54 UTC, con la **v1** (sin el normalizador de la página de producto).
  - staging4 no envía el `dataLayer` a ningún destino, así que esas sesiones **no dejan registro** de eventos.
- **Sí sirven para B2.1:** en Commerce Facts ambas líneas se resuelven con identidad canónica `current`.
  - #4111 → `F360-BOTAS-LARGAS-CAFE-36`.
  - #4114 → `F360-MAFALDA-TACHES-GAMUZA-CAFE-37`.
- **Falta (prueba manual, otro día).** Desde un navegador real en staging4, con el snippet v2:
  1. abrir un producto F360 → elegir color y talla → Añadir: leer `add_to_cart` (esperado: `item_id` = SKU canónico, `item_group_id = F360-{MODELO}`);
  2. comprar con Mercado Pago de prueba (Mario teclea la tarjeta, nombre `APRO`) → leer `purchase` en la página de gracias (mismo `item_id` que en `add_to_cart`, `view_cart` y `begin_checkout`; `transaction_id` = número de pedido).
- **Rollback de staging4:**
  - `rm wp-content/mu-plugins/f360-measurement-v11-staging4.php && wp sg purge`;
  - `wp plugin deactivate duracelltomi-google-tag-manager`.
- **No se tocó:** checkout, Mercado Pago, CRO, inventario, producción, GTM, GA4 ni Meta.

### G2-B2.3 · Data API D1: **PENDIENTE (requiere instalar gcloud)**

- `gcloud` **no está instalado** en el Mac. No hay credenciales ADC.
- **Pasos de Mario:**
  1. Instalar Google Cloud SDK: `! brew install --cask google-cloud-sdk`.
  2. Seguir D1 de `G2B1_SAFE_CORRECTIONS.md` §D (proyecto, habilitar la API, `gcloud auth application-default login` con el scope `analytics.readonly`, `set-quota-project`).
- La credencial queda solo en `~/.config/gcloud/`.
- Después: reconciliación de solo lectura `transactionId` ↔ Commerce Facts (82 pedidos del clon, 54 pagados), con cobertura por `browser_context`.
