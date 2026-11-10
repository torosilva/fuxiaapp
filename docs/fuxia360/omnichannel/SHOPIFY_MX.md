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

**Cómo quedó (20261109000100):**
- **Copia del catálogo:** `f360.shopify_products` / `f360.shopify_variants`, cargada con `scripts/f360/shopify_catalog.mjs`.
- **La liga va en `f360.woo_variant_links`**, la misma que leen pedidos e inventario.
- **Ids internos cortos:** los ids de Shopify (50958118649926) no caben en las columnas de 32 bits que vienen de Woo, y ampliarlas obliga a rehacer la cadena de vistas de ventas en producción. Por eso cada producto y variante de Shopify recibe un `link_id`, y `public.f360_shopify_localize` cambia los ids antes de ingerir el pedido.
- **Ids que se quedan como los de Shopify:** pedido, línea, reembolso y clienta, porque ya son bigint.
- **Guardia de la liga:** en Shopify exige que la variante exista en la copia del catálogo, en vez de la homologación hecha a mano.
  - Cada liga automática hereda una liga que ya hizo una persona o el publicador.
  - Origen `legacy_adopted`: se compara por id, no por SKU.
- **Staging, con el catálogo real:** 1,026 de 1,278 ligadas, 0 con otro color o talla, ningún par ligado dos veces.
- **Las 252 pendientes** (42 colores: Mafalda Studs, Stud Point, Croc, Knotty…): sus variaciones Woo viejas no guardaban color (solo "Medida"). Se resolvieron con una 3.ª regla (`20261109000200`): **nombre del modelo** (la agencia usó los nombres de Fuxia 360 como título en Shopify; exactamente un producto activo con ese nombre) + color + talla. Prueba de solo lectura en prod: 252/252 únicas, sin choques. Staging: 1278/1278.
- **Límite conocido:** si un producto Shopify no tiene **ninguna** talla ligada, su venta se registra como "legacy" y no se descuenta, igual que pasa en Woo. Por eso hay que cerrar los pendientes.

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
- **Respaldo:** sondeo cada 15 min por GraphQL (`orders(query:"updated_at:>…")`), igual que `commerce_poll`. **Pendiente**; por ahora solo webhooks, que Shopify reintenta hasta 48 h.
- **Cambios de base:**
  - `sales_targets.kind` acepta `'shopify'`;
  - la liga de variantes por tienda acepta la tabla nueva;
  - `orders_since_id` = pedido de corte, para que el `#1001` de prueba nunca mueva inventario.
- **Pedidos de prueba:** Shopify los marca con `test: true` y se ignoran sin registrar nada.
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

## 6. Hilo en Shopify (2026-11-09, listo para publicar)
- **Ubicación:** extensión de tema de la app Fuxia 360 (`shopify-app/extensions/fuxia-tienda`, app embed "Hilo · Fuxia 360"). Vive en la app, así que un cambio de tema no lo borra.
- **Base:** port de `tools/storefront/f360-hilo-global.html`. Producto, color y talla salen del formulario de Shopify (`[name=id]` + `/products.json`). Las tarjetas y los modelos salen de `/products.json`: los títulos de Shopify son los nombres de Fuxia 360 (79 de 81).
- **Tallas:** las de la tienda (35–40).
- **Los dos servicios rechazaban a mx.fuxiaballerinas.com:**
  - Hilo en Railway: CORS 400. Rama `shopify-mx-cors` del repo fuxia-chatbot, una línea → `main`.
  - `f360-store-reserve`: 403. `F360_RESERVE_ORIGINS` + mx en `deploy_prod_function.sh`.
- **Publicar:** `cd shopify-app && npx -y @shopify/cli@4.9.4 app deploy` (pide la sesión de Shopify de Mario). Después, encender el app embed en el editor del tema y apagar el asistente IA de Shopify ("Z9fdqc 0Z AI", `<shopify-chat>` del tema Horizon).
- **2026-11-09, EN VIVO:**
  - versión `fuxia-360-2` publicada por Mario;
  - app embed "Hilo · Fuxia 360" encendido en el tema Horizon y guardado;
  - CORS de Railway (`main` 2e3e808) y `f360-store-reserve` con el origen mx.
- **Bug encontrado en vivo:** en las tarjetas de "Lo más vendido", `catalogo` chocaba de nombre. Arreglado en `7e99a15`; falta un `app deploy` más.
- **El botón "Shop with AI" / "Comprar con IA" NO era de Shopify:** era el app embed **"Clarity Agents JS"** de Microsoft Clarity (`#ads-agent-host`, scripts de `adsagentclient…azurefd.net`).
  - Apagado el 2026-11-09.
  - "Clarity JS" (la medición) sigue encendido.
  - Verificado en la tienda pública: sin agente, con Clarity y con Hilo.

## 7. Después
- **Bienvenida 10% + captura de correo/celular:** cupón BIENVENIDA10 en Shopify + popup propio; los datos van a la ficha de la clienta en Fuxia 360.
- **Fuxia Kids (juegos)**, **Favoritos**, link del **Club Fuxia**.
- **Clientas (2026-11-09, HECHO):** `scripts/f360/wp_clientas_a_shopify.sh` → `~/fuxia360-respaldos/shopify_clientas_mx.csv` → Shopify Customers → Import (sobrescribir existentes). **313 importadas, 0 fallidas.**
  - 213 con "acepta correos" (popup Woo, "Sin spam…"); 100 sin permiso (compradoras y carritos); SMS = no; 49 con celular.
  - Solo México: 137 leads de Colombia se quedan en Woo. Sin dirección (claves de estado Woo ≠ Shopify; siguen en Fuxia 360).
- **Cupón BIENVENIDA10 (2026-11-09, HECHO):** creado en Shopify con las reglas Woo (10%, un uso por clienta, sin mínimo, no combina).
- **Popup y correos (2026-11-09, EN VIVO), nativos** (Mario: "no custom si Shopify ya lo hace"):
  - **Shopify Forms**, formulario "Bienvenida 10%" (id 1244541): el texto del popup Woo; aparece a los 25 s o al intentar salir (escritorio), igual que el de Woo; correo obligatorio y WhatsApp opcional. Sin recuadro recordatorio (teaser = Never): tapaba "Descarga la app" y a Mario no le gustó.
    - Permiso **solo de correo**: SMS y WhatsApp apagados, porque el WhatsApp de Woo daba puntos, no permiso de publicidad.
    - Al enviar muestra **BIENVENIDA10**; etiqueta `popup-bienvenida`.
    - Se quitó "+50 puntos Club Fuxia": Forms no puede darlos.
    - App embed "Forms" encendido en el tema.
  - **Shopify Messaging**, automatización "Recupera el pedido abandonado" (correo "Completa tu pedido", en español): **activa por defecto**. Mario autorizó los permisos.
- **Favoritos y el arreglo de Hilo (2026-11-09, EN VIVO):** `app deploy` corrido por Mario y app embed "Favoritos · Fuxia 360" encendido. Verificado en la tienda: corazones en tarjetas y header, y Hilo «Lo más vendido» con tarjetas.
- **Lo que se rompió con la redirección y hay que mover a Shopify:**
  - `f360-store-reserve` (link de pago MX);
  - `my-orders`, `link-orders` y `backfill-orders`;
  - la app (`WooCommerceService.ts`, catálogo MX);
  - `importFromStoreAction` en el admin.
- **Medición:**
  - el pixel de Meta sí está en Shopify (web pixels);
  - GA4 y la compra por servidor dependen de cómo lo dejó la agencia;
  - comparar 4 semanas Shopify vs las 4 anteriores en Woo cuando ya entren los pedidos.
- **Ficha de producto (2026-11-09, EN VIVO):** el link "Más opciones de pago" medía 11.7 px. Se subió a 15 px con el **Custom CSS nativo** de la sección "Product information" del tema (`.shopify-payment-button__more-options`). El botón de Shop Pay sigue igual.
- **Tallas Kids (2026-11-09).** La guía oficial de Mario: 24 16.0 · 25 16.5 · 26 17.2 · 27 17.9 · 28 18.6 · 29 19.2 · 30 19.9 · 31 20.6 · 32 21.3 · 33 21.9 cm.
  - **Antes:** Mini cucarrones y Mini Twin Studs tenían 25–33 + 35–40, y Mini Paula solo 35–40, en Fuxia 360, Shopify y Woo. La tabla de cm del tema decía 25 = 15.5 cm.
  - **Shopify (EN VIVO):** los tres quedaron con 24–33. Las variantes se editaron en el admin: $1,900, sin control de inventario, todas comprables.
  - **Tabla de cm:** está en el bloque Custom Liquid `custom_liquid_ajMTkt` del template de producto, rama `product.type == 'Kids'`. Ahí se corrigieron los valores. Respaldo del bloque original: `~/fuxia360-respaldos/shopify_custom_liquid_tallas_20261109.txt`.
  - **Fuxia 360:** `supabase/pase/20261109_kids_tallas.sql`, con dry-run OK.
    - Agrega 24–33 con una variante por color.
    - Borra 35–40 solo si no tienen ninguna historia; sus ligas a Woo y Shopify se borran con ellas.
  - **Liga Shopify:** `supabase/pase/20261109_kids_tallas_shopify.sql` va después. Recarga el catálogo (1,264 variantes) y liga las 100 tallas Kids.
  - **Woo CO:** botón **Publicar** de cada modelo en Fuxia 360. El publicador oculta 35–40 (privadas, nunca las borra) y crea las nuevas.
  - **Hilo:** su KB solo trae la tabla de adulta. Falta un artículo Kids (`fuxia-chatbot` `kb/seed.json` + `scripts/ingest_kb.py`).
    - Ojo: la regla CRO-6 convierte "24 MX → 37", y 24 ahora también es talla Kids.
- **Bug encontrado el 2026-11-09 por Mario:** "Subir a la tienda" fallaba en Woo con "Este modelo viene del catálogo Woo anterior…" en TODOS los modelos ligados a Shopify.
  - **Causa:** las ligas de Shopify usan origin `legacy_adopted`, y `f360.sync_job_legacy_guard` miraba esas ligas en cualquier tienda.
  - **Arreglo:** `20261109000300`, que filtra por la tienda del trabajo, en el pase `20261109_legacy_guard_por_tienda.sql`, **APLICADO** en producción el 2026-11-09.
  - **Otra lectura sin filtro por tienda:** el aviso de "no se puede archivar" (`20261007000500`). Ahí sí es correcto, porque estar ligado a Shopify también cuenta.
- **Accesibilidad de la ficha (2026-11-09, EN VIVO): Lighthouse móvil pasó de 75 a 92.** Regina Romero tiene 93. Mario pidió hacerlo nosotros, sin pasarlo a la agencia.
  - **Custom CSS de "Product information":** los puntitos del carrusel miden 24 px (`.slideshow-controls__dots .slideshow-control`); el punto visible no cambió.
  - **Custom CSS de "FX · Footer":** el texto legal y el copyright pasaron a crema al 70%, con contraste de unos 7:1. Para los links se redefine la variable `--f-faint` dentro de `.fx-legal`, porque la agencia usa `!important`.
  - **Código del tema.** Cada archivo tiene historial de versiones en el editor de código.
    - `sections/product-information.liquid`: `aria-label` en el botón de la barra que sigue al bajar.
    - `snippets/slideshow-controls.liquid`: los puntitos quedan como `tablist`/`presentation`/`tab`, para que su `aria-selected` sea válido; no se tocó `slideshow.js`.
    - `blocks/` y `sections/product-recommendations.liquid`: `role="img"` en el esqueleto de carga.
  - **Ojo:** si la agencia actualiza el tema Horizon, estos cambios de código pueden perderse y hay que volver a aplicarlos.
  - **Lo que falta:**
    - ~~El botón de Hilo~~: **arreglado** el 2026-11-09. Letra oscura sobre el mismo dorado (`c008b46`); Mario hizo el `app deploy`.
    - Las etiquetas grises y el nombre del recuadro del popup de Shopify Forms. Son de la app de Shopify; no se pueden cambiar.
    - Un `h3` en "Recomendados".
- **Inventario real en Shopify (2026-11-09, EN VIVO).** Mario aprobó los permisos `write_products` y `write_metaobjects` (versión `fuxia-360-9` + pantalla de actualización de acceso).
  - Se cargó con `scripts/f360/shopify_inventario.mjs`: 1,264 tallas rastreadas, "seguir vendiendo sin existencia" en los 79 modelos (todos sobre pedido en Fuxia 360) y cantidades = `f360.online_ats` (343 tallas, 484 pares). Ninguna talla quedó agotada.
  - **Falta la sincronización automática:** cuando Fuxia 360 mueva existencias, Shopify todavía no se actualiza solo. Por ahora se vuelve a correr el script.
- **Menú "Tienda" (2026-11-09, EN VIVO):** submenú Ballerinas / Sandalias planas / Sandalias altas / Botas / Ver todo.
  - El encabezado de la agencia (`sections/fx-encabezado.liquid`) no mostraba submenús en computadora; se le agregó un menú desplegable. Respaldo del archivo original en `~/fuxia360-respaldos/shopify_fx-encabezado_20261109.liquid`.
  - Las colecciones se ordenan por más vendidos.
- **Círculos de color (2026-11-09, EN VIVO): 79/79 productos y 53 colores.**
  - Script: `scripts/f360/shopify_colores.mjs`.
  - Cada color es un metaobjeto `shopify--color-pattern`. El tono sale de `product_colors.hex` de Fuxia 360; 14 estampados y combinados que no tenían tono recibieron uno aproximado.
  - A cada producto se le asignó su categoría de Shopify (Flats, Sandals, Boots, Shoes).
  - La opción Color quedó ligada a `shopify.color-pattern`. Los ids de variante no cambian (verificado).
  - El tema tiene encendido "Swatches" en el bloque del selector de variantes.
