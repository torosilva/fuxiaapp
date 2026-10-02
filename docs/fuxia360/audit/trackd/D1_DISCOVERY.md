# Track D · D1 Discovery: catálogo Woo legacy (solo lectura)

**Fecha:** 2026-10-02. **Fuente:** staging4.fuxiaballerinas.com (copia de producción), API `wc/v3`, **solo GET**.
**Script:** `scripts/f360/d1_legacy_discovery.mjs`. Aborta si el host no es staging4. No escribe nada en Woo ni en Supabase.
**Evidencia:**
- `d1_catalog_staging4.json`: catálogo completo (productos y variaciones, todos los estados). Sin clientes, pedidos ni secretos.
- `d1_legacy_variations.csv`: una fila por variación legacy. Es la base de D2 (mapping) y D3 (hoja de conteo).

**Límite:** staging4 es una copia tomada alrededor del 2026-09-24. El producto legacy más reciente se creó el 2026-09-24 (`3597` Suecos cucarrones azul). Lo que se haya creado o cambiado en producción después **no está aquí**. Ver P1 en §4.

## 1 · Universo

| | Productos | Variaciones |
|---|---|---|
| Total en staging4 | 130 | 810 |
| Macarena (F360, privada, staging) | 1 | 18 |
| **Legacy** | **129** | **792** |

- Los 129 legacy son `variable`, `publish`, y están en 4 categorías: ballerinas 84, sandalia-alta 22, sandalia-plana 19, botas 5.
- 128 tienen tallas 35–40.
- Precio regular: 2,800 en 101, 3,000 en 22, 4,200 en 4 y 4,500 en 1. Hay una oferta de 2,800 a 1,680. Ningún producto tiene precios distintos entre sus variaciones.

## 2 · Hallazgos materiales

### H1 · Las variaciones legacy no tienen SKU propio (contradice la premisa "SKU/variation ID legacy")
- **792 de 792** variaciones legacy no tienen SKU propio.
  - Cuando el padre tiene SKU, la API muestra el del padre (`wc/v3` hace *fallback* al padre): son 552.
  - Cuando el padre no tiene SKU, aparece vacío: son 240.
- Solo las 18 de Macarena tienen SKU propio (`F360-…`).
- En consecuencia, **un SKU legacy identifica a un producto Woo (modelo + color), nunca a una talla**. Las 6 tallas de "Paula plata con verde" comparten `BALL-PAULA-PLT`.
- **Lo único que identifica una talla en Woo es el `variation_id`.**
- **Implicación para D2:** el ancla del mapping es `woo_variation_id`. El SKU legacy del padre se conserva **como referencia**, sin cambiarlo, tal como pidió Mario.

### H2 · El SKU legacy no es confiable como identidad
| Clase (por producto) | Productos | Variaciones | Qué significa |
|---|---|---|---|
| `limpio` | 74 | 444 | El SKU padre sigue un patrón legible (`BALL-PAULA-PLT`, `MFL-TCH-NGO`) |
| `sku_de_copia` | 18 | 108 | El SKU viene de duplicar otro producto en Woo y **no describe el producto**. Por ejemplo, `BALL-PAULA-TPE-1` = "Croc", `BALL-PAULA-TPE-1-1-1` = "Loafer suede café" y `SND-PLT-TIR-AMR-1-1-1-1-1-1` = "Peep toe topo". Además, `BALL-PAULA-TPE` = "Ballerinas doradas con broche de piedras", no Paula taupe. |
| `sin_sku` | 34 | 204 | El padre no tiene SKU |
| `multicolor` | 3 | 36 | Ver H3 |

- **Conclusión:** el SKU legacy **no** sirve para deducir modelo ni color. La agrupación modelo/color de D2 la confirma una persona (Carolina), no un algoritmo.
- El SKU legacy se guarda tal cual, aunque sea una copia. No se cambia (decisión 2).

### H3 · Hay 18 variaciones que no identifican un color
- **`129` Mafalda laser caramelo.** El atributo local "Colores" es BEIGE/TALCO, pero sus 6 variaciones son **solo talla** ("cualquier color").
- **`135` ByL puntudo.** `pa_color` tiene 5 colores, pero sus 6 variaciones son **solo talla**.
- **`131` Mules Colectiva.** Tiene 18 variaciones color × talla, que están bien, y además 6 variaciones **solo talla** (398–403).
- Una venta en esas 18 variaciones ambiguas no dice qué color salió, así que **no pueden ligarse a una variante F360** (modelo + color + talla) sin una decisión. Ver P2 en §4.
- Las 18 de color × talla de Mules Colectiva sí se pueden mapear.

### H4 · Woo no administra stock hoy: "Woo actual" no es un número
- 792 de 792 variaciones legacy tienen `manage_stock = false`, `stock_quantity = null` y `stock_status = instock`. Los padres están igual.
- Por lo tanto, la columna **"Woo actual"** de la tabla de Mario (`Woo actual | Conteo físico | Diferencia | Opening balance F360`) será **"sin control · en stock"** en las 792 filas. Una diferencia numérica contra Woo no existe.
- La referencia útil para detectar diferencias es otra: **las ventas en línea recientes por variación** (pedidos Woo). Ver P4 en §4.
- Esto confirma la decisión 3: Woo no puede ser el opening balance porque no tiene uno.

### H5 · El código actual rechazaría las ventas legacy (bloqueo para el cutover, no para D1–D4)
- `f360_ingest_woo_order` descuenta inventario solo si el SKU de la línea es igual al SKU de la variante F360. Si no coinciden, abre `sku_mismatch` y **no descuenta** (`supabase/migrations/20260928000100_f360_p23a_stock_sync_orders.sql:229-245`, igual en `…000400_fix_delivery_dedupe.sql:72`).
- Un pedido legacy trae el SKU del padre o nada (H1). Por eso, con el código actual, **cada venta de un producto adoptado sería `sku_mismatch`** y Bodega CDMX nunca bajaría.
- **D2 debe proponer un cambio:** para un vínculo legacy, validar contra el SKU que Woo reportaba al momento de ligar, no contra el SKU F360. Va con migración, rollback y pruebas, y requiere aprobación.

### H6 · El envío de stock cambia el comportamiento de venta: regla de negocio por decidir
- El envío automático (`fuxia-native/supabase/functions/_shared/f360-woo/sync.ts:38`) escribe `manage_stock: true, stock_quantity, backorders: 'no'`.
- En un producto legacy adoptado, eso significa que **toda talla con conteo 0 pasa a "Agotado"** en la tienda.
- Hoy todas las tallas legacy siempre se pueden comprar, y Fuxia vende **sobre pedido** (~5–7 días) cuando no hay par (`docs/fuxia360/audit/CURRENT_STATE.md:70`).
- Activar el envío de stock en legacy **quita la venta sobre pedido** de esas tallas. Según la regla 13 de CLAUDE.md, esto no se cambia en silencio. Ver P3 en §4.

### H7 · Otros
- **"Sandalia pelo" (`153`)** usa el atributo local `medidas` en lugar de `pa_medida`. Se puede mapear (es solo talla), pero queda registrado.
- **Ninguna variación legacy tiene GTIN** (`global_unique_id`).
- **El sistema legacy de tiendas** (`public.channel_inventory`) identifica por texto: `product_name`, `color`, `size` y un `sku` opcional (`docs/fuxia360/audit/live/schema.sql:422-434`). No tiene `woo_variation_id`. Track D no lo toca. Las tiendas siguen el flujo C2/C3 de Track C.

## 3 · Lo que D1 no hizo
- No leyó producción (ni Woo ni Supabase).
- No leyó pedidos ni clientes.
- No escribió en Woo ni en Supabase.
- No cambió SKUs.
- No consolidó productos.

## 4 · Pendientes para Mario (bloquean D2 final)

| # | Pregunta | Recomendación |
|---|---|---|
| **P1** | ¿Autorizas un discovery de **solo lectura** del catálogo de **producción**? Sería la Store API pública (lo mismo que ve un visitante, sin llave), o una llave REST de **solo lectura** que crees tú. | Sí, con la Store API pública. Se compara contra staging4 y se reportan las diferencias (productos o variaciones nuevas o borradas). El mapping final se hace sobre producción, no sobre una copia de hace una semana. |
| **P2** | ¿Qué pasa con las 18 variaciones "cualquier color" (129, 135 y 6 de 131)? | Se excluyen del mapping: no se adoptan y Woo las sigue vendiendo sin control como hoy. Carolina dice qué colores existen físicamente, y esos colores se mapean en el cutover cuando Woo tenga variaciones por color. Corregir Woo es un cambio aparte. |
| **P3** | Cuando una talla legacy adoptada tenga 0 en Bodega CDMX, ¿Woo la muestra **Agotada** o la sigue vendiendo **sobre pedido**? | Es tu decisión de negocio. El código actual hace "Agotada" (`backorders: 'no'`). Si debe seguir sobre pedido, el envío necesita una política por variante, y eso es trabajo adicional antes del cutover. |
| **P4** | Para la columna de referencia, ¿autorizas leer **conteos agregados** de ventas Woo por variación (por ejemplo, los últimos 90 días)? Sería sin datos de clientes y solo en staging4 o con P1. | Sí. Como "Woo actual" no existe (H4), es la mejor señal para priorizar recuentos. |
