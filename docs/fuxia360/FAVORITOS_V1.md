# ♡ Favoritos V1 — señal de intención de Fuxia 360

Fecha: 2026-10-06. Aprobado por Mario: Parte 1 + captura anónima, **solo en staging** (staging4 + Supabase `faltx…`). No producción.

## 1. Auditoría previa: ¿ya existía un wishlist?

No existe ninguno, así que no se duplica nada.

- **staging4:** no hay plugin de wishlist entre los activos ni los inactivos (`wp plugin list`). Bricks no trae uno, ningún snippet de WPCode lo hace y el tema hijo tampoco.
- **Producción:** el HTML público de `/mx/`, `/mx/tienda/` y `/co/tienda/` no tiene ninguna marca de wishlist. Sí existe la etiqueta de producto **`favoritos-fuxia`**, una colección curada "Favoritos Fuxia". Es un choque de nombre a vigilar: la clienta ve **"Mis favoritos"** (lo suyo) y la colección sigue siendo "Favoritos Fuxia" (la elige Fuxia).
- **ATC (agregar al carrito):** hoy solo se mide en GA4 (`tools/measurement/f360-measurement-v11-staging4.php`) y no existe en Fuxia 360. En el reporte va en blanco ("—"); nunca se estima.

## 2. Qué hace V1

**Tienda (staging4), en `/mx/` y `/co/`**, en todas las páginas con productos:
- ♡ en cada tarjeta de producto: tienda, categorías, home y relacionados (`li.type-product`).
- ♡ en los carruseles "Más vendidas" y "Nuevas" (`[data-f360-product-id]`).
- ♡ junto al título de la ficha de producto.
- ♡ con contador en el header, justo antes del ícono de cuenta. En producción quedaría `★ Club Fuxia | ♡ 3 | 👤`.
- Panel **"Mis favoritos"**: foto, nombre y precio del país donde está la clienta, con ligas para ver y quitar. Un producto que ya no existe o no se vende dice "Ya no está disponible", con opción de quitarlo.

Cómo funciona por dentro:
- **Sin cuenta:** la lista vive en el dispositivo (`localStorage` `f360_favs_v1`) y se sincroniza entre pestañas.
- `/mx/` y `/co/` comparten la lista, porque son los mismos productos Woo; cada uno muestra su precio.
- **Rendimiento:** al cargar la página no se envía nada. El panel hace una sola consulta a la Store API de Woo al abrirse, y cada ♡ manda un evento en segundo plano (`keepalive`).

**Fuxia 360 (staging)**, migración `20261012000800_f360_favorites_intent.sql`:
- **`f360.anon_visitors`** guarda `anon_id`: un uuid aleatorio que genera el navegador (`f360_anon_v1`). Nunca guarda nombre, teléfono, correo ni IP.
  - Tiene `customer_id` y `merged_at` listos para V2, pero **en V1 no se escriben**.
- **`f360.favorite_events`** es de solo agregar (append-only) y guarda:
  - `favorite_added` / `favorite_removed`;
  - `market` (`mx`/`co`), `channel` (`web`) y el canal de la tienda (`target_id`);
  - `woo_product_id` y `woo_variation_id`;
  - la **identidad canónica**: `product_id`, `color_id` y `variant_id`.
- **La identidad canónica se resuelve en el servidor** con lo que ya existe, sin crear otra identidad de producto:
  - `woo_product_links`, que cubre productos publicados o unidos;
  - `legacy_woo_map`, para los productos viejos homologados;
  - `woo_variant_links` / `legacy_woo_map`, para la variación;
  - si no hay variación, el color por nombre.
- **`f360_favorite_record(p)`:** solo `service_role`; la tienda la llama vía `f360-store-reserve` con la acción `favorite`. Valida evento, mercado, uuid y producto, y limita a 120 eventos por visitante por hora.
- **`f360_favorites_report(target, días)`:** rol viewer o superior, sin PII. Devuelve por modelo: `MODELO | FAVORITOS ACTIVOS | AGREGADOS | QUITADOS | AL CARRITO (—) | VENDIDOS`.
  - **Favoritos activos:** visitantes cuyo último evento sobre ese producto es "agregado".
  - **Vendidos:** pares del modelo en tiendas y en línea dentro del mismo periodo.
- **Panel:** `/favoritos` (Clientas → "Favoritos · intención") solo en staging. En producción el enlace no aparece y la página da 404.

**Fuera de V1, por decisión:** fusión con clientas, WhatsApp, que Hilo lea favoritos, reordenar la tienda, recomendaciones y marketing con favoritos.

## 3. V2: anónimo → clienta de Club Fuxia

Beneficio para la clienta: *"Tus favoritos están contigo en cualquier dispositivo."* Esto le da sentido a tener perfil.

1. Cuando la clienta se identifica (Club Fuxia en web o app, con OTP de WhatsApp), el navegador manda su `anon_id` junto con la sesión.
2. El servidor hace la fusión: `anon_visitors.customer_id = <clienta>`, `merged_at = now()`.
   - Sus eventos pasados quedan ligados por el `anon_id`; **no se copian ni se reescriben**, porque la tabla es append-only.
   - Un mismo `customer_id` puede tener varios `anon_id` (varios dispositivos).
3. Sus favoritos activos se calculan sobre todos sus `anon_id`, y la lista local se reemplaza por la del perfil.
4. Privacidad: solo las dueñas ven a la clienta con sus favoritos (Ficha de clienta), igual que el resto de su PII. El reporte sigue siendo agregado.

## 4. Después: Product Intent

`Favoritos + Avísame (stock intent) + ATC + Compra → Product Intent` por modelo / color / talla / mercado.

- Favoritos y Avísame ya viven en Fuxia 360.
- ATC requiere llevar el evento de medición a Fuxia 360. La columna ya está en el reporte y hoy vale `NULL`.
- La compra ya existe en `woo_order_lines` / `offline_sale_items`.
- Con eso se podrá decidir qué producir o reponer, y alimentar el Orden en la tienda (hoy manual) cuando Mario lo apruebe.

## 5. Piezas

| Pieza | Archivo |
|---|---|
| Snippet de la tienda (fuente única) | `tools/storefront/f360-favoritos.html` |
| Carruseles con id de producto | `tools/storefront/f360-tienda.html` (`data-f360-product-id`) |
| Plugin staging4 (generado) | `scripts/f360/build_staging4_storefront_mu.mjs` → `tools/storefront/mu-plugins/staging4/f360-favoritos-staging4.php` |
| Instalación staging4 | `scripts/f360/deploy_staging4_wp.sh` (respaldo, `php -l` en el servidor, purga) |
| Endpoint | `fuxia-native/supabase/functions/f360-store-reserve` (acción `favorite`) |
| Base de datos | `supabase/migrations/20261012000800_f360_favorites_intent.sql` (+ rollback) |
| Reporte | `admin-web/src/app/(app)/favoritos/page.tsx` |

**Rollback:**
- **Tienda:** borrar `f360-favoritos-staging4.php` de `wp-content/mu-plugins/` en staging4. Las listas de las clientas siguen en su navegador, pero ya no se ven.
- **Base de datos:** `supabase/rollbacks/20261012000800_f360_favorites_intent.down.sql`.
