# Fuxia 360 — Modelo de producto, inventario y canales (fuente de verdad)

Decisión arquitectónica fijada por Mario el 2026-09-30. Todo lo nuevo de Fuxia 360 se construye sobre este modelo.

```
PRODUCT → VARIANT → INVENTORY BY LOCATION → SALES CHANNEL
```

## 1 · Reglas

1. El producto o modelo **no** es inventario.
2. El color **no** es producto.
3. La variante comercial es producto + color + talla.
4. La variante tiene una identidad y un SKU estables, sin importar dónde esté físicamente.
5. El inventario siempre pertenece a variante + ubicación.
6. Mover inventario cambia la ubicación, nunca la identidad de la variante.
7. "En camino" es una ubicación de sistema que no se puede vender.
8. Un canal de venta no posee inventario: tiene una ubicación de origen (`source_location`) explícita.
9. Woo publica disponibilidad únicamente desde esa ubicación. El stock de otras tiendas o bodegas no se suma automáticamente.
10. El orden (`sort`), el orden en pantalla o el nombre de una ubicación nunca determinan autoridad.
11. Fuxia 360 es la autoridad del inventario. Woo es un canal.
12. El precio pertenece a producto + mercado, no al inventario ni a la ubicación.
13. En V1, todas las variantes de un modelo comparten precio dentro de cada mercado.
14. Debe poder extenderse a `variant → lot → physical_pair` sin cambiar SKU, variante, balances ni mapeos de Woo. Esa extensión **no** está implementada.

## 1.1 · Identidad canónica de producto y variante (regla permanente, Mario 2026-10-04)

**Fuente de verdad conceptual:** `PRODUCT → COMMERCIAL VARIANT → INVENTORY BY LOCATION → SALES CHANNEL`.

| Nivel | Identidad maestra en Fuxia 360 | Formato | Ejemplo | Dónde vive |
|---|---|---|---|---|
| Producto (modelo) | `canonical_product_id` = `f360.products.id` + código `products.code` | Código inmutable tras publicar (`codes_locked_at`) | `MACARENA` | `f360.products` |
| Variante comercial (modelo + color + talla) | `canonical_variant_id` = `f360.product_variants.id` + **`canonical_sku`** | **`F360-{MODELO}-{COLOR}-{TALLA}`** (`f360.variant_sku`), único y bloqueado tras publicar | `F360-MACARENA-NUDE-37` | `f360.product_variants.sku` |
| Inventario | variante × ubicación | — | — | `f360.inventory_balances` |
| Canal | `sales_channel_id` = `f360.sales_targets.id` | — | `woo_staging4` | `f360.sales_targets` |

**Reglas:**
1. **La identidad de una variante comercial NO depende de ningún ID de WooCommerce.**
   - `woo_product_id`, `woo_variation_id` y el SKU de Woo son **identificadores externos del canal**, nunca la identidad maestra.
2. **El SKU canónico identifica la misma variante en todo Fuxia 360:** inventario, transferencias, ventas físicas, WooCommerce (cuando F360 publica), Commerce Facts, Customer 360, Growth, Analytics y campañas cuando corresponda.
3. **Productos F360 nuevos o unidos:** F360 publica en Woo el padre con SKU `F360-{MODELO}` y cada variación con su SKU canónico (`mapping.ts`: `parentSku`, `v.sku`). El SKU en Woo **es** el canónico. La ingesta lo verifica (`sku_mismatch`).
4. **Legacy (los 129 productos Woo anteriores):** **no** se modifican masivamente sus SKUs ni sus IDs.
   - Durante la transición **coexisten** la identidad legacy de Woo y la canónica de F360.
   - La correspondencia la establece **solo** la homologación confirmada por Carolina (`f360.legacy_woo_map.status = 'confirmado'` → `confirmed_variant_id`).
5. **Mapping canal ↔ canónico (uno a muchos en el tiempo):** una variante canónica puede tener, por canal, una variación Woo vigente y otras históricas (productos por color retirados al unir).
   - Vigente: `f360.woo_variant_links` / `woo_product_links`.
   - Histórico: `f360.retired_woo_links`.
   - Decisión humana: `f360.legacy_woo_map`.
   - **Ningún hecho** (venta, movimiento, pedido) se re-identifica por un ID de Woo sin pasar por ese mapping.
6. **Columnas dormidas que duplican identidad:** `f360.products.wc_product_id` y `f360.product_variants.wc_variation_id`. **No se usan**; están marcadas para retiro (N3). Nada nuevo debe escribirlas ni leerlas.
7. **Woo no es la fuente de verdad** de identidad ni de inventario. **Commerce Facts** es la de ventas y dinero. **GA4** no es fuente financiera.

Diseño de detalle, gaps y migración mínima: `growth/G2B2_CANONICAL_IDENTITY.md`.

## 2 · Auditoría del modelo actual (2026-09-30, staging)

| Concepto | Fuente de verdad actual | ¿Cumple? | Problema | Cambio necesario |
|---|---|---|---|---|
| Producto | `f360.products` (`20260925010000…inventory_core.sql:28`); `code` único (`p21:48`) | ✅ | — | — |
| Color | `f360.product_colors`, hijo de producto, único por (producto, nombre) (`inventory_core:42`) | ✅ | Los 129 productos del Woo actual son "un producto por color" (p. ej. *Suecos cucarrones azul*). Es el catálogo heredado; Fuxia 360 no lo usa como modelo. | Ninguno ahora; no se tocan los 129. |
| Variante | `f360.product_variants`, único (color, talla) (`inventory_core:61`) | ✅ | — | — |
| SKU | `product_variants.sku` único, generado `F360-<modelo>-<color>-<talla>` (`p21:55`), bloqueado al publicar (`p21:80`). Staging: 0 de 30 variantes sin SKU. | ✅ | La columna admite NULL a nivel de tabla, aunque el flujo siempre lo genera. | Opcional, más adelante: `SET NOT NULL`. |
| Ubicaciones | `f360.locations`, con `type`, `ledger_authority` (legacy/f360) y `sellable` (`c1_locations_roles:23-24`) | ✅ | — | — |
| Inventario | `inventory_balances`, llave primaria (variant_id, location_id), `on_hand ≥ 0` (`inventory_core:123`) | ✅ | — | — |
| Eventos / movimientos | Un solo registro de solo agregar: `inventory_events` + `inventory_movements`, con variante, desde y hacia (`inventory_core:93,110`) | ✅ | — | — |
| Transferencias | TRANSFER origen → "En camino" → destino. La variante no cambia (`transfers.sql:8-11`). | ✅ | — | — |
| En camino | Una sola ubicación `type='transit'`. Una restricción impide venderla (`transfers.sql:22-26`). | ✅ | — | — |
| Canal de venta | `f360.sales_targets.fulfillment_location_id` (= source_location), obligatorio (`p22:17`). Staging: `woo_staging4 → Bodega CDMX`. | ✅ con nota | **N1.** Un canal es el sitio Woo completo (/mx, /co y resto del mundo), así que un pedido de Colombia también descuenta de Bodega CDMX. **N2.** Antes, nada impedía configurar "En camino" como origen. | N1: sin cambios (decisión de Mario, 2026-10-01; ver §2.1). N2: **aplicado** (ver §2.2). |
| Stock enviado a Woo | `f360.online_ats(variant, fulfillment_location)` = `on_hand` de esa ubicación únicamente (`p22:131`). La cola se llena solo con cambios de esa ubicación (`p23a:99`). | ✅ | No se suman otras tiendas ni "En camino". | — |
| `online_location()` | El origen del canal activo, ordenado por `is_production` y `created_at` (`c3_cutover…:176`). Reemplazó la versión anterior, que elegía por `sort` (`p21:133-135`). | ✅ | — | — |
| Vínculos Woo | `woo_product_links` (producto ↔ producto Woo) y `woo_variant_links` (variante ↔ variación Woo), por canal (`p22:40,53`) | ✅ con nota | **N3.** Las columnas `products.wc_product_id` y `product_variants.wc_variation_id` siguen existiendo sin uso (documentado en `p22:13`); son una identidad duplicada dormida. | Retirarlas en una migración futura, aprobada aparte. |
| Pedidos Woo | `f360_ingest_woo_order` descuenta variante (vía `woo_variant_links`) en `fulfillment_location_id` (`p23a:247-259`) | ✅ | — | — |
| C3 | El corte de una tienda pasa su inventario legacy a variante + ubicación con conteo verificado (`OPENING_PHYSICAL_COUNT`); la autoridad cambia por ubicación (`c3_cutover…`) | ✅ | — | — |
| Venta en tienda | Rama F360: variante en la ubicación del turno del vendedor. Precio del maestro de producto, nunca del cliente (`c3_cutover…:478+`, líneas 57 y 102). | ✅ | La rama legacy (tiendas sin corte) sigue usando `channel_inventory` por texto. Es lo esperado hasta el corte de cada tienda. | Ninguno (migración legacy fuera de alcance). |
| Precio por mercado | MXN: `products.regular_price` / `sale_price`. Otras monedas: `f360.product_prices` (producto, moneda) (`currency_prices.sql:3,28`). | ✅ con nota | **N4.** La llave es la moneda, no el mercado. Hoy es 1 a 1: MXN = México, COP = Colombia, USD = resto del mundo. Dos mercados con la misma moneda no se distinguirían. | Ninguno en V1. Si aparece un mercado con moneda compartida, agregar `market`. |
| Precio vs. inventario | Ninguna tabla de precio tiene ubicación ni variante | ✅ | — | — |
| Lote / par físico | No existe | ✅ preparado | Los movimientos y balances usan variante + ubicación. Un `lot_id` opcional en movimientos más una tabla de pares se pueden agregar sin cambiar SKU, balances ni vínculos Woo. | Ninguno ahora. |

**Resultado:** no hay ninguna violación que obligue a cambiar algo antes de continuar P2.3B.

Decisiones de Mario (2026-10-01):
- **N1** se documenta (§2.1), sin cambios.
- **N2** se aplica (§2.2).
- **N3** y **N4** no se modifican por ahora.

### 2.1 · Mercado ≠ ubicación de origen (N1)

- **Mercado:** dónde y en qué moneda se vende (México MXN · Colombia COP · resto del mundo USD). Define el **precio**: producto + mercado.
- **Ubicación de origen** (`fulfillment_location_id`): de dónde salen los pares que vende un canal. Define el **stock publicado**.
- Hoy un solo canal (el sitio Woo) atiende los tres mercados desde **Bodega CDMX**. Un pedido de /co/ descuenta de Bodega CDMX. Es correcto mientras Colombia no tenga inventario propio.
- Si Colombia obtiene inventario propio, se separa en un canal propio con su propia ubicación de origen. El modelo ya lo admite (un canal = una ubicación de origen explícita), sin cambiar SKU, variantes ni balances.

### 2.2 · N2: un canal nunca publica desde una ubicación de sistema

Migración `20261006000200_f360_n2_fulfillment_location_guard.sql` (reversión en `supabase/rollbacks/…`; prueba en `supabase/staging/f360_n2_tests.sql`, 7 revisiones). Aplicada en staging el 2026-10-01.
- **Qué hace:** un trigger rechaza que la ubicación de origen de un canal sea de tipo `transit` ("En camino"), al crear el canal o al cambiarlo.
- **Prueba antes de aplicar:** la base de datos aceptaba "En camino" (2 FAIL; todo revertido). **Después:** 7 de 7 PASS. Suite completa: 12 archivos, **425 de 425**.
- **Alcance:** solo ubicaciones de sistema. **No** usa `sellable = false`, porque ese campo significa "se puede vender en tienda" y Bodega CDMX, el origen de Woo, es `sellable = false` a propósito.
- Una ubicación que ya es origen tampoco puede convertirse después en `transit` (índice de una sola ubicación de tránsito).

## 3 · Diagramas (staging)

**Canal en línea**

```
Macarena                              f360.products
 └─ Nude / 37                         f360.product_variants   SKU F360-MACARENA-NUDE-37
     └─ Bodega CDMX = 4               f360.inventory_balances (variant, Bodega CDMX)
         └─ Woo (staging4)            f360.sales_targets woo_staging4
              fulfillment_location = Bodega CDMX
              variación Woo 3624      f360.woo_variant_links
              stock publicado = online_ats(Nude 37, Bodega CDMX) = 4
              precio: MX 2,800 MXN · CO 420,000 COP · USD pendiente   (producto + mercado)
```

**Al mismo tiempo, tienda física**

```
Macarena
 └─ Nude / 37                         la misma variante, el mismo SKU
     └─ Tienda X = 2                  f360.inventory_balances (variant, Tienda X)   ledger_authority = f360 (después de C3)
         └─ POS Tienda X              turno del vendedor ligado a Tienda X → f360_record_store_sale
              descuenta solo Tienda X; precio del maestro (2,800 MXN)
              NO cambia lo que Woo publica (Woo solo lee Bodega CDMX)
```

**Movimiento entre las dos**

```
Bodega CDMX −1 → En camino +1 → Tienda X +1
```

El SKU es el mismo en todo el trayecto. "En camino" nunca se vende.

## 4 · Hallazgos operativos de P2.3B (2026-09-30)

- La reconciliación remota (función `f360-woo-sync` en Supabase staging) devolvió **18 de 18 en coincidencia**.
- **Pedido de prueba #3654** (Macarena Nude 37, $2,800 MXN, pagado, creado por la API): el stock en Woo bajó de 4 a 3. En Fuxia 360, Bodega CDMX sigue en 4.
- El webhook **no llegó en 12 minutos**. WP-Cron está desactivado en staging4 y no hay cron real activo, así que Action Scheduler no entrega los webhooks.
- **Corregido el mismo día.** Mario creó un cron real en SiteGround, cada minuto y solo para staging4:
  `php /home/u2262-72gcmsiaboij/www/staging4.fuxiaballerinas.com/public_html/wp-cron.php`.
  Unos 2 minutos después:
  - `order.created` → **applied**;
  - `order.updated` → **duplicate**;
  - Bodega CDMX Nude 37 pasó de 4 a 3, con **un** SALE "Tienda en línea · Pedido #3654" (`woo_order:woo_staging4:3654`).
- **Reenvío.** Se volvió a guardar el pedido y llegó un nuevo `order.updated` (versión nueva del pedido). Bodega siguió en 3 y sigue habiendo 1 SALE: no hubo doble descuento.
- **Reconciliación posterior:** 18 revisadas, 18 coinciden, 0 diferencias, 0 faltantes. Woo en 3 y Fuxia 360 en 3.
- **Envío automático de existencias.** Mario aprobó la migración `20261006000100_f360_woo_stock_schedule.sql` y se aplicó en staging. En el vault de staging quedaron `f360_sync_url` y `f360_sync_secret`; el job `f360-woo-stock-push` corre cada minuto.
  - Prueba: `scripts/f360/p23b_stock_auto_check.mjs`, con la transferencia real `b9224276`: Bodega → En camino, y luego regreso al origen.
  - Salió 1 par de Bodega (3 → 2): Woo mostró **2 en 56 s**, sin llamada manual. El par en "En camino" **no** se publicó.
  - Regresó a Bodega (2 → 3): Woo mostró **3 en 62 s**.

### 4.1 · Acceptance del pedido #3654: BEFORE / AFTER (staging4 → Fuxia 360 staging)

| Medición | BEFORE (antes del pedido) | AFTER |
|---|---|---|
| Woo, Macarena Nude 37 (variación 3624) | 4 | 3 (lo descuenta Woo al pagar) |
| Fuxia 360, Bodega CDMX Nude 37 | 4 | **3** |
| Ventas SALE `woo_order:woo_staging4:3654` | 0 | **1** ("Tienda en línea · Pedido #3654") |
| Movimientos de ese evento | 0 | **1** (F360-MACARENA-NUDE-37, Bodega CDMX → fuera, ×1) |
| Entregas registradas del pedido | 0 | 4 |
| Reconciliación | 18 de 18 | **18 de 18**, 0 diferencias (corrida `83f663ce`) |

Entregas del pedido, en orden:
1. `6f42cc7a…`, order.created → **applied**. La primera entrega llegó por el cron real de SiteGround (cada minuto, solo staging4); ya no depende de wp-admin.
2. `63a983a0…`, order.updated (misma versión) → **duplicate**.
3. `f201440e…`, order.updated (pedido re-guardado, versión nueva) → applied, pero **sin** nuevo descuento: Bodega siguió en 3.
4. Reenvío de la **misma** entrega `6f42cc7a…` (mismo ID, firma válida, sin crear pedido) → **duplicate_delivery**. Bodega 3, 1 venta, 1 movimiento.

Control: la misma entrega con firma inválida → **401**, rechazada.

No se creó otro pedido ni se corrigió stock a mano. Macarena sigue privada.

**Configuración del envío automático** (migración `20261006000100`, verificada después de aplicar):
- Lo aplicado es idéntico al archivo revisado: 5 de 5 sentencias.
- pg_net 0.20.4 y pg_cron 1.6.4.
- `f360.woo_sync_tick()` es SECURITY DEFINER, sin ejecución para `anon` ni `authenticated`.
- El job `f360-woo-stock-push` (`* * * * *`) está activo; corridas `succeeded` y respuestas HTTP 200.

**Vault:** `f360_sync_url` y `f360_sync_secret` se guardaron en staging al aplicar la migración, antes de que Mario pidiera una autorización separada para esos valores. Se reportó; quedan disponibles para borrarse si Mario lo pide.
