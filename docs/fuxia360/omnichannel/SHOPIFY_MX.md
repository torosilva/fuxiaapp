# Shopify México ↔ Fuxia 360

> **Estado (2026-11-09):** conexión de solo lectura probada. Nada escribe todavía en Fuxia 360 ni en Shopify.
> **Decisiones de Mario:**
> - 2026-11-09: inventario **real y automático** en Shopify. Antes de encenderlo se muestra cuántas tallas quedarían agotadas.
> - 2026-11-09: Colombia sigue en WooCommerce.

## 1. Qué pasó
La agencia migró **solo México** de WooCommerce a Shopify. Las fechas son aproximadas: la tienda Shopify tiene su primer pedido el 8 de noviembre, y el último pedido Woo de México en Fuxia 360 es del 7 de noviembre.
- `fuxiaballerinas.com/` y `/mx/*` redirigen a **mx.fuxiaballerinas.com**:
  - tienda `z9fdqc-0z.myshopify.com`;
  - tema Horizon 4.4.0;
  - MXN.
- `/co/` sigue en WooCommerce. También redirige `/mx/wp-json/…`, así que **toda llamada a la API Woo de México se rompió**.
- Catálogo en Shopify:
  - 79 productos y 1,278 variantes, todas con Color + Talla y fotos;
  - **"Inventory not tracked"**: todas las tallas aparecen disponibles;
  - los SKU son nuevos, inventados por la agencia (`BALLERINAS-RESORTE-TACHES-TAUPE-35`): **no coinciden** ni con Fuxia 360 (`F360-…`) ni con Woo.
- Clientas: **1** en Shopify, la de prueba. La base no se migró; sigue en Fuxia 360 y en Woo.
- Pedidos: solo `#1001` (pedido de prueba, `test: true`). Se numeran desde 1001; Woo iba en #6149.
- Pagos: Shopify Payments, con depósito a HSBC ****4567 (Mario lo confirma). Incluye:
  - tarjetas;
  - Apple Pay;
  - Google Pay;
  - Shop Pay;
  - **Meses sin Intereses**.

  PayPal aparece en el checkout pero con "Setup incomplete": pedir a la agencia que lo quite. Mercado Pago ya no está.
- Una sola ubicación en Shopify: `gid://shopify/Location/97074643014` ("sur 69 149 101").
- Velocidad (Lighthouse móvil, una corrida). Inicio: 79 vs 60–63 de Woo CO. Ficha de producto: 66 vs 67.

## 2. Acceso
- App **"Fuxia 360"** en el Dev Dashboard (org 245924007, app 445479976961, versión `fuxia-360-1`), instalada en la tienda.
- **Scopes:** `read_orders`, `read_products`, `read_inventory`/`write_inventory`, `read_locations`, `read_customers`.
- **Credenciales:** solo en la Mac de Mario y en los secretos de Supabase, nunca en el repo.
  - `~/.fuxia-shopify.client_id`
  - `~/.fuxia-shopify.secret` (`shpss_…`, chmod 600)
- **Token:** grant `client_credentials` → `POST https://z9fdqc-0z.myshopify.com/admin/oauth/access_token`. Dura 24 h y se pide de nuevo; no se guarda.
- **API:** GraphQL Admin `2026-10`.
- **Webhooks:** se firman con el mismo client secret (HMAC-SHA256 base64, header `X-Shopify-Hmac-Sha256`).

## 3. Ligar el catálogo (sin trabajo manual de Carolina)
El handle de Shopify es igual al slug del producto Woo: **78 de 79** (falta `botas-comb`). Con eso:
1. **Por producto:** handle Shopify → producto Woo (`woo_product_links` / `products.wc_product_id`) → producto Fuxia 360. Dentro del producto se busca la variante por nombre de color (sin acentos) + talla.
   - Prueba de solo lectura en prod, 2026-11-09: **1,008 de 1,278 únicas, 0 ambiguas**.
2. **Las 270 restantes** son productos Woo viejos aún no unificados. Camino: variación Woo con color explícito → `retired_woo_links` / `legacy_woo_map` confirmado (la homologación de Carolina).
   - Las variaciones Woo **sin atributo de color** (p. ej. `sandalias-tiras-amarrar`) no sirven para esto: casarían Negro y Verde con la misma variación.
3. **Lo que no se resuelva** va a la pantalla de Homologación como pendiente. Nunca se adivina.

La liga vive en una tabla nueva `f360.shopify_variant_links`:
- columnas: `shopify_variant_id`, `shopify_inventory_item_id`, `variant_id`, `method`, `confirmed_by`;
- `UNIQUE` por variante Shopify y por variante Fuxia 360 dentro de la tienda.

## 4. Pedidos Shopify → Fuxia 360 (primero)
Se **reusa el camino de pedidos que ya existe**, no se crea uno paralelo. Un pedido Shopify entra como un pedido más de la tienda en línea, con su propio `sales_target` (`shopify_mx`, `kind 'shopify'`). Así funcionan sin tocarlos:
- ventas, tablero, Growth e Inteligencia;
- descuento de inventario (Bodega → tienda → sobre pedido);
- WhatsApp de gracias y puntos del Club;
- cierre de casos de la Bandeja.

- **Edge Function `f360-shopify`:**
  - webhooks `orders/create`, `orders/updated`, `orders/paid`, `orders/cancelled`, `refunds/create`;
  - verifica HMAC y que el dominio sea `z9fdqc-0z.myshopify.com`;
  - traduce el pedido Shopify a la forma que esperan `f360_ingest_woo_order` / `f360_capture_order_economics`:
    - `financial_status` paid/partially_refunded → `processing`; fulfilled → `completed`; voided/cancelled → `cancelled`;
    - `line_items` con la variante Fuxia 360 ya resuelta por `shopify_variant_links`.
- **Respaldo:** sondeo cada 15 min por GraphQL (`orders(query:"updated_at:>…")`), igual que `commerce_poll`.
- **Cambios de base:**
  - `sales_targets.kind` acepta `'shopify'`;
  - la liga de variantes por tienda acepta la tabla nueva;
  - `orders_since_id` = pedido de corte, para que el `#1001` de prueba nunca mueva inventario.
- **Identidad del pedido:** el `id` numérico de Shopify (bigint), único por tienda. El número visible (#1001) se guarda aparte. Nunca choca con los de Woo porque la tienda es otra.
- **Mercado:** MXN → MX, como hoy.

## 5. Inventario Fuxia 360 → Shopify (segundo)
- **Fórmula:** la de Fuxia 360 que ya existe, `f360.online_ats`: Bodega CDMX + lo libre de las tiendas activas, menos apartados Gold, sin bazares.
  - En producción **nunca se encendió para Woo** (`stock_sync_mode='off'`), así que esto es nuevo y lo decidió Mario.
- **Envío:** `inventorySetQuantities` (name `available`) en la ubicación de Shopify. Antes, `inventoryItemUpdate(tracked:true)` por variante.
- **Antes de encender:**
  1. reporte con cuántas tallas quedarían en 0 y cuántas con existencia, por modelo, para que Mario y Carolina lo vean;
  2. activar `tracked` + mandar cantidades en un solo paso por producto;
  3. vigilar los primeros pedidos.
- **Productos sobre pedido** (`make_to_order`): se dejan con "seguir vendiendo sin existencia" (`inventoryPolicy CONTINUE`). Así no se agotan los que se fabrican.
- **Colombia (Woo) y México (Shopify) comparten las mismas existencias.** Cada pedido de una tienda baja el número en Fuxia 360 y se reenvía a la otra en ~1 min. El riesgo de vender doble existe solo en ese minuto.

## 6. Después
- **Hilo:** app embed de la app Fuxia 360 (theme app extension), para que no dependa del código del tema que maneja la agencia.
- **Bienvenida 10% + captura de correo/celular:** cupón BIENVENIDA10 en Shopify + popup propio; los datos van a la ficha de la clienta en Fuxia 360.
- **Fuxia Kids (juegos)**, **Favoritos**, link del **Club Fuxia**.
- **Clientas:** subir la base a Shopify respetando el consentimiento de marketing (pendiente de decisión con la agencia).
- **Lo que se rompió con la redirección y hay que mover a Shopify:**
  - `f360-store-reserve` (link de pago MX);
  - `my-orders`, `link-orders` y `backfill-orders`;
  - la app (`WooCommerceService.ts`, catálogo MX);
  - `importFromStoreAction` en el admin.
- **Medición:**
  - el pixel de Meta sí está en Shopify (web pixels);
  - GA4 y la compra por servidor dependen de cómo lo dejó la agencia;
  - comparar 4 semanas Shopify vs las 4 anteriores en Woo cuando ya entren los pedidos.
