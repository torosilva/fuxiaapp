# CRO · Medición (D-CRO-05)

## BLOQUEO: NEED_GTM_ACCESS · GTM-W2PZG3L5

- Producción carga **GTM-W2PZG3L5**, **Meta Pixel** y **Microsoft Clarity**. staging4 no carga ninguno.
- Mario resuelve con Carolina y Adrián quién tiene acceso al contenedor.
- **Hasta tener acceso:**
  - No se crean eventos.
  - No se toca producción.
  - No se agrega GTM a staging.

**Con acceso, en este orden:**
1. Tags.
2. Triggers.
3. Variables.
4. Eventos GA4 existentes (ecommerce: `view_item`, `add_to_cart`, `begin_checkout`, `purchase`, ¿vía plugin o GTM?).
5. Meta (Pixel/CAPI).
6. Ecommerce `dataLayer`.
7. Duplicados.
8. Consentimiento.
9. Cómo crear staging: Environment de GTM o contenedor aparte.

## Contrato de `dataLayer` (SOLO DISEÑO)

**Principios:**
- Nombres **GA4 estándar** cuando existan. Eventos propios con prefijo `f360_` solo si GA4 no tiene uno equivalente.
- **Sin datos personales:** nada de teléfono, correo, nombre ni dirección.
- Un solo `push` por acción.

| Evento | Cuándo | Parámetros |
|---|---|---|
| `view_item` *(GA4)* | PDP cargada | `items[{item_id: woo_product_id, item_name, item_category, price, currency}]` |
| `f360_select_color` | Clic en un color | `item_id`, `color` |
| `f360_select_size` | Clic en una talla | `item_id`, `color`, `size_store`, `size_mx`, `state` (`inmediata` / `5_7_dias` / `agotado`) |
| `f360_fit_guide_open` | Abre la guía de tallas | `item_id` |
| `f360_gold_reserve_click` | "Fuxia Gold: te las apartamos" | `item_id`, `size_store` |
| `f360_hilo_open` | "¡Pregúntale a Hilo!" | `item_id` |
| `f360_made_to_order_selected` | Elige una talla en estado 5–7 días | `item_id`, `size_store` |
| `add_to_cart` *(GA4)* | Añadir al carrito | `items[...]` (Woo/GTM puede ya enviarlo: **verificar antes**) |
| `begin_checkout` / `purchase` *(GA4)* | Checkout / gracias | Probablemente ya existen: **verificar** |
| `f360_review_open` / `f360_review_submit` | Reseñas | `item_id` |
| `f360_back_in_stock_request` | Avísame (futuro) | `item_id`, `size_store` |
| `search` *(GA4)* | Búsqueda en Tienda | `search_term` (ya se guarda también en `storefront_searches`) |
| `f360_filter_use` | Filtro en Tienda | `filter` (`categoria` / `color` / `talla` / `inmediata`), `value` |
| `f360_sticky_atc_click` | Barra fija de compra (futuro) | `item_id` |

**Customer 360:** el embudo VIEW → INTENT → ATC → CHECKOUT → PURCHASE se reconstruye en GA4. Del lado de F360 se guardan solo señales agregadas sin identidad (búsquedas, solicitudes a la medida e intenciones con consentimiento, ver `07_INTENT_CRM.md`).
