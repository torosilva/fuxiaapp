# Fuxia 360 · Measurement Contract V1 (`mc_version = "1.0"`)

**Estado:** diseño aprobado para G2-A, 2026-10-04. **Nada desplegado:** sin `dataLayer` en staging4, sin GTM, GA4, Meta ni Clarity.

**Fuente única de verdad** de la instrumentación de comportamiento del sitio:
- **CRO genera** los eventos (fragmentos del storefront).
- **Growth los consume.**
- `cro/08_ANALYTICS.md` conserva el bloqueo de GTM y apunta aquí. Su tabla anterior queda **reemplazada** (mapeo en §9).
- Cualquier evento nuevo se agrega **aquí primero**, con un cambio de versión.

---

## 1. BEHAVIOR EVENT ≠ COMMERCE FACT

| | BEHAVIOR EVENT (este contrato) | COMMERCE FACT (G1, `f360.commerce_orders`) |
|---|---|---|
| Qué es | Una acción observada en el navegador | La venta real registrada por Woo o por la tienda |
| Fuente | `dataLayer` → GA4 (futuro) | Webhook, poll y backfill de Woo; `offline_sales` |
| Confiabilidad | Muestreo, bloqueadores, consentimiento, navegadores in-app | Completa para lo que registra Woo o la tienda |
| Revenue / pedidos | **Nunca** | **Siempre** |
| Atribución | Sesión de GA4 (futuro): `platform_reported` | Woo first-party order attribution (`first_party_observed`) |

**Reglas:**
1. **`purchase` del navegador NO es la verdad de revenue ni de pedidos.** Commerce Facts manda. El `purchase` de navegador solo sirve para **medir la cobertura de la medición**: cuántos pedidos `countable` de F360 tienen un `purchase` observado.
2. Ningún tablero suma `value` de eventos como "ventas".
3. Las métricas de funnel (vistas → selección → carrito → checkout) son de comportamiento. La compra final del funnel se toma de Commerce Facts cuando se cruza por día, mercado y producto, **en agregado y nunca por persona**.

---

## 2. Principios

- **Nombres:**
  - Eventos estándar de GA4 con su nombre GA4 (`view_item`, `add_to_cart`…).
  - Eventos propios de Fuxia con prefijo **`f360_`** en el `dataLayer` (`f360_select_color`). Así no chocan con GA4 ni con plugins.
  - El catálogo usa el nombre canónico sin prefijo (`select_color`); el nombre en el cable lleva prefijo.
- **Un `push` por acción del usuario.** Sin reintentos automáticos que dupliquen.
- **Allowed PII = NONE**, en todos los eventos y parámetros:
  - nada de nombre, correo, teléfono, dirección, IP, user agent crudo, texto libre de la clienta (mensajes, notas) ni códigos de cupón (pueden contener nombres; G1 tampoco los guarda);
  - términos de búsqueda solo **saneados** (§5.3).
- **Sin datos de pago:** solo el ID de la pasarela (`payment_type = woo-mercado-pago-custom`), nunca datos de tarjeta.
- **Taxonomía de producto genérica:**
  - `item_category` = `f360.categories.category_key`;
  - talla y calce son **opcionales** y solo aplican a calzado (accesorios no los llevan; D-G1-08).
- **No se emiten eventos de features que no existen:** estado `RESERVED` en §4.
- **Consentimiento:** el `push` al `dataLayer` es local. **Ningún destino** (GA4, Meta, Clarity) recibe nada hasta resolver LEGAL_REVIEW_REQUIRED (§8).

---

## 3. Sobre común (todos los eventos)

| Parámetro | Requerido | Valor | Fuente / regla |
|---|---|---|---|
| `event` | ✓ | Nombre en el cable (§4) | — |
| `mc_version` | ✓ | `"1.0"` | Constante del contrato |
| `event_id` | ✓ | UUID v4 por `push` | Deduplicación (§6) |
| `page_view_id` | ✓ | UUID v4 por carga de página | Eventos "una vez por página" |
| `market` | ✓ | `MX` / `CO` / `ROW` / `UNKNOWN` | Prefijo de la ruta: `/mx/` → MX, `/co/` → CO, otro → ROW. **Misma regla que `session_entry_path` en Commerce Facts** |
| `currency` | ✓ (eventos con precio) | `MXN` / `COP` / `USD` | Moneda con la que Woo muestra la página. Nunca convertida |
| `page_type` | ✓ | `home` / `plp` / `pdp` / `cart` / `checkout` / `thankyou` / `other` | Plantilla Bricks / ruta |
| `browser_context` | ✓ | `instagram_iab` / `facebook_iab` / `standard` | **Contexto del navegador**, no la fuente del tráfico (§7). Lo detecta CRO-IAB con las mismas reglas que `browserClass()` de G1 (`_shared/f360-woo/commerce.ts`) |
| `os_class` | opcional | `ios` / `android` / `macos` / `windows` / `other` | Misma regla |

**Objeto `items[]`** (eventos de producto, formato GA4 + extensiones Fuxia):

| Campo | Requerido | Valor | Vínculo con Commerce Facts |
|---|---|---|---|
| `item_id` | ✓ | **ID de producto Woo** (texto) | `commerce_order_lines.woo_product_id` |
| `item_name` | ✓ | Nombre del modelo | — |
| `item_variant` | cuando hay color y talla | **ID de variación Woo** | `commerce_order_lines.woo_variation_id` → `variant_id` (resolución de G1) |
| `item_category` | ✓ | `category_key` F360 (`ballerinas`…) | `commerce_order_lines.category_key` |
| `item_brand` | ✓ | `"Fuxia"` | — |
| `price` | ✓ | Precio unitario mostrado por Woo (moneda de la página) | Comparable con `unit_net`, **no** igual (cupones y reglas) |
| `quantity` | ✓ en carrito y compra | entero | — |
| `sku` | opcional | SKU Woo | `commerce_order_lines.sku` |
| `f360_variant_id` | opcional | UUID F360, si el fragmento lo conoce | `commerce_order_lines.variant_id` |
| `f360_color` | opcional | Nombre del color | — |
| `f360_size_store`, `f360_size_mx` | opcional, **solo calzado** | Talla de tienda / talla MX (= tienda − 13) | — |
| `index` | en listas | Posición 0-based | — |

---

## 4. Catálogo de eventos V1

**Estado del feature en el sitio (2026-10-04, staging4):**
- **EXISTS:** el elemento existe hoy; el evento se puede emitir.
- **RESERVED:** el nombre está reservado; **no se emite** hasta que el feature exista.
- **VERIFY-GTM:** puede que GTM o un plugin de producción ya lo envíe; se decide un solo emisor en G2-B.

### 4.1 Funnel (GA4 estándar)

| Canónico → cable | Significado de negocio | Trigger exacto | Requeridos (además del sobre) | Opcionales | Emisor / estado | Commerce Facts | Dedup |
|---|---|---|---|---|---|---|---|
| `view_item_list` → `view_item_list` | La clienta ve un listado de modelos | El listado se pinta (Tienda, categoría, búsqueda, carrusel). **Una vez por listado y página**, con los items visibles al pintar (máx. 20) | `item_list_id` (`tienda`, `categoria:<slug>`, `busqueda`, `mas_vendidas`, `nuevas`, `tambien_te_pueden_gustar`), `items[]` (con `index`) | `item_list_name` | `f360-tienda.html` · EXISTS | — | `page_view_id` + `item_list_id` |
| `select_item` → `select_item` | Elige un modelo de un listado | Clic en la tarjeta o el link del modelo **antes** de navegar | `item_list_id`, `items[1]` con `index` | — | `f360-tienda.html` · EXISTS | — | `event_id` |
| `view_item` → `view_item` | Ve la ficha de un modelo | Ficha cargada. **Una vez por página** | `items[1]` (a nivel producto: sin `item_variant`), `value` = precio mostrado | — | Fragmento PDP · EXISTS · **VERIFY-GTM** | Demanda por modelo (agregado) | `page_view_id` |
| `select_color` → `f360_select_color` | Elige un color | Clic de la clienta en un color. **No** la preselección automática | `items[1]` con `f360_color` | `availability_state` | `f360-selector-color` / `tallas-y-color` · EXISTS | Demanda por color | `event_id` |
| `select_size` → `f360_select_size` | Elige una talla | Clic de la clienta en una talla con la variación resuelta (`found_variation`) | `items[1]` con `item_variant`, `f360_size_store`, `delivery_state` (`inmediata` / `5_7_dias` / `agotado`) | `f360_size_mx`, `sku` | Fragmento PDP · EXISTS | `woo_variation_id` → variante (G1) | `event_id` |
| `view_fit_guide` → `f360_view_fit_guide` | Consulta cómo le queda | Clic en "Guía de tallas" (hoy abre una imagen) | `items[1]` (producto) | — | Ficha / Bricks · EXISTS | — | `event_id` |
| `add_to_cart` → `add_to_cart` | Agrega al carrito | **Confirmación** de Woo de que se agregó (evento `added_to_cart` / fragmentos actualizados), no el clic | `items[1]` con `item_variant` y `quantity`, `value` | `add_source` (`pdp_button` / `sticky_atc`), `delivery_state` | Fragmento PDP · EXISTS · **VERIFY-GTM** | Intención por variante (agregado) | `event_id` |
| `view_cart` → `view_cart` | Revisa el carrito | Página de carrito cargada | `items[]`, `value` | — | Woo / Bricks · EXISTS · **VERIFY-GTM** | — | `page_view_id` |
| `begin_checkout` → `begin_checkout` | Empieza a pagar | Página de checkout cargada | `items[]`, `value` | — | Woo (checkout de bloques) · EXISTS · **VERIFY-GTM** | — | `page_view_id` |
| `add_shipping_info` → `add_shipping_info` | Confirma el envío | La clienta elige o confirma un método de envío en el checkout | `shipping_tier` (`flat_rate` / `free_shipping`…), `value` | — | Woo · EXISTS · **VERIFY-GTM** | `shipping_total` (agregado) | `event_id` |
| `add_payment_info` → `add_payment_info` | Elige cómo pagar | Selecciona la pasarela | `payment_type` = ID de pasarela | — | Woo · EXISTS · **VERIFY-GTM** | `payment_category` (G1) | `event_id` |
| `purchase` → `purchase` | **Señal** de compra en el navegador | Página "pedido recibido" cargada, **una sola vez por pedido** | `transaction_id` = **ID del pedido Woo**, `items[]`, `value` (total mostrado), `shipping`, `tax` | `coupon_count` (**nunca** el código) | Woo / GTM · EXISTS · **VERIFY-GTM** | **Solo reconciliación:** `commerce_orders` con `woo_order_id = transaction_id`. Revenue y pedidos siempre de Commerce Facts | **`transaction_id`** (además de `event_id`) |

### 4.2 Features Fuxia

| Canónico → cable | Significado | Trigger exacto | Requeridos | Opcionales | Emisor / estado | Dedup |
|---|---|---|---|---|---|---|
| `sticky_atc_view` → `f360_sticky_atc_view` | La barra fija de compra aparece | `stickyCompra()` la muestra por **primera vez** en la página (≤ 900 px y botón real fuera de pantalla) | `items[1]` (producto) | — | `f360-entrega-inmediata.html` · EXISTS (CRO-4) | `page_view_id` |
| `sticky_atc_click` → `f360_sticky_atc_click` | Toca la barra fija | Tap en el botón del sticky | `sticky_state` (`elegir_color` / `elegir_talla` / `no_disponible` / `anadir`) | `items[1]` | CRO-4 · EXISTS. **Reemplaza** `sticky_atc_scroll_to_selector` de `cro/04` (= estados `elegir_*`) | `event_id` |
| `review_view` → `f360_review_view` | Ve reseñas reales | El bloque de reseñas (ivole) entra en pantalla **y es visible**, es decir, con ≥ 1 reseña. Con 0 reseñas está oculto y no se emite | `items[1]`, `review_count` | `rating_avg` | Fragmento PDP · EXISTS (hoy sin reseñas → no se emite) | `page_view_id` |
| `review_photo_view` → `f360_review_photo_view` | Abre una foto de reseña | Abre una foto en el visor de ivole | `items[1]` | — | **RESERVED** (sin reseñas con foto; hay que verificar el DOM de ivole) | `event_id` |
| `back_in_stock_intent` → `f360_back_in_stock_intent` | Quiere que le avisen | Envío del formulario "Avísame" | `items[1]` con `item_variant` | — | **RESERVED**: el feature no existe (no autorizado; necesita consentimiento) | `event_id` |
| `hilo_open` → `f360_hilo_open` | Abre a Hilo | Se abre el panel de Hilo (botón global o "¡Pregúntale a Hilo!" en la ficha) | `entry_point` (`global_button` / `pdp_a_la_medida` / `cambios`) | `items[1]` si está en una ficha | `f360-hilo-global.html`, fragmento PDP · EXISTS | `event_id` |
| `hilo_message` → `f360_hilo_message` | Le escribe a Hilo | La clienta envía un mensaje. **Nunca el texto** | `entry_point`, `message_index` (1, 2, 3…) | `items[1]` | `f360-hilo-global.html` · EXISTS | `event_id` |
| `store_availability_view` → `f360_store_availability_view` | Ve en qué tiendas puede probárselas hoy | El recuadro "¿Prefieres probártelas? Están hoy en {tiendas}" se muestra para la variante elegida | `items[1]` con `item_variant`, `store_count` | `stores` (nombres de tienda) | `f360-entrega-inmediata.html` · EXISTS | `page_view_id` + `item_variant` |
| `search` → `search` (GA4) | Busca en la Tienda | Se registra un término (sugerencia elegida, Enter o cambio). Mismo momento en que hoy se llama `search_log` | `search_term` **saneado** (§5.3) | `results_count` (cuando exista) | `f360-tienda.html` · EXISTS | `event_id` |
| `filter_use` → `f360_filter_use` | Filtra la Tienda | Aplica un filtro | `filter` (`categoria` / `color` / `talla` / `inmediata`), `value` | — | `f360-tienda.html` · EXISTS | `event_id` |
| `gold_reserve_click` → `f360_gold_reserve_click` | Pide que se lo aparten (Gold) | Clic en "te las apartamos" | `items[1]` con `item_variant` | — | Fragmento PDP · EXISTS | `event_id` |
| `made_to_order_selected` → `f360_made_to_order_selected` | Elige una talla de 5 a 7 días | `select_size` con `delivery_state = 5_7_dias` | — | — | **No es un evento aparte**: se deriva de `f360_select_size`. Se elimina para no duplicar | — |
| `review_submit` → `f360_review_submit` | Publica una reseña | Envío exitoso del formulario de ivole | `items[1]` | `rating` | ivole · EXISTS (verificar el hook) | `event_id` |

---

## 5. Reglas de parámetros

1. **Moneda:** `currency` y `price` / `value` en la moneda que muestra Woo. Nunca se convierten. Un evento en COP no se suma con uno en MXN.
2. **Mercado:** solo por prefijo de ruta (§3). El geo-cookie de país no se envía.
3. **`search_term` saneado:**
   - minúsculas;
   - 3 a 60 caracteres;
   - se **descarta** el evento si el término contiene un correo, una secuencia de 7 o más dígitos (teléfonos) o `@`.
   
   Misma longitud que `f360.storefront_searches`.
4. **Talla:** `f360_size_mx = f360_size_store − 13` (decisión 6 de la bitácora). Solo para la categoría calzado.
5. **Nada de texto libre:** ni mensajes de Hilo, ni notas, ni motivos.

---

## 6. Deduplicación

- **`event_id`** (UUID por `push`): futuros destinos server-side lo usan para deduplicar contra el navegador. **No se activa en G2.**
- **Una vez por página** (`page_view_id`): `view_item`, `view_cart`, `begin_checkout`, `sticky_atc_view`, `review_view`, `store_availability_view`, y `view_item_list` por `item_list_id`.
- **`purchase`:** `transaction_id` = ID de pedido Woo. La página de gracias guarda en `sessionStorage` (con `try/catch`) los pedidos ya reportados, para no repetirlo si se recarga.
- **Un solo emisor por evento.** Si G2-B encuentra que GTM o un plugin ya envían un evento `VERIFY-GTM`, se apaga uno de los dos. Nunca conviven.

---

## 7. Fuente del tráfico ≠ contexto del navegador

| Dimensión | Pregunta | Dónde vive | Ejemplos |
|---|---|---|---|
| **Fuente / canal** | ¿De dónde vino? | Commerce Facts: `commerce_woo_attribution` (Woo first-party) + clasificación V1 (`G2A_MEASUREMENT_FOUNDATION.md` §1). Eventos: sesión de GA4 (futuro) | `PAID_SOCIAL` / instagram, `ORGANIC_SOCIAL` / instagram, `DIRECT` |
| **Contexto del navegador** | ¿En qué navegador compró? | Commerce Facts: `browser_class` / `os_class`. Eventos: `browser_context` / `os_class` | `instagram_iab`, `facebook_iab`, `safari`, `chrome` |

**Nunca se infiere una de la otra:**
- un anuncio de Instagram puede abrirse en Safari;
- una visita directa puede ocurrir dentro del navegador de Instagram (link copiado en un DM).

**Ejemplo con los 81 pedidos de staging4** (muestra pequeña, solo para ilustrar):

| Canal / plataforma | Instagram IAB | Safari | Chrome | Facebook IAB |
|---|---|---|---|---|
| PAID_SOCIAL / instagram | 16 | 3 | 1 | — |
| ORGANIC_SOCIAL / instagram | 17 | 2 | 2 | — |
| PAID_SOCIAL / facebook | — | — | — | 3 |
| ORGANIC_SOCIAL / facebook | — | — | — | 1 |

La **detección** del IAB y su diagnóstico son de **CRO-IAB**. Growth solo consume la dimensión.

---

## 8. Consentimiento (LEGAL_REVIEW_REQUIRED, abierto)

| Elemento | ¿Depende del consentimiento? | Estado |
|---|---|---|
| Hacer `push` al `dataLayer` (local, no sale del navegador) | No por sí mismo | Diseñado. **No desplegado** |
| Enviar eventos a **GA4** | **Sí** | Bloqueado (legal + GTM) |
| **Meta Pixel / CAPI** | **Sí** | Fuera de alcance. DQ-01 abierto |
| **Clarity** (grabaciones) | **Sí** | Fuera de alcance |
| Google Consent Mode | Lo define legal | No activar |
| Telemetría técnica propia (CRO-IAB, `storefront_tech_events`) | Por definir (¿interés legítimo?) | Diseño CRO, sin aprobar |
| **Cookies `sbjs_*` de Woo Order Attribution** (ya activas en producción) | **Pregunta legal nueva** | Las usa Commerce Facts V1. Woo dice ser compatible con WP Consent API. Legal debe confirmar |
| Commerce Facts (dinero del pedido, sin PII) | No para la operación; el uso analítico lo confirma legal | Implementado (staging) |
| Avísame / carrito abandonado / lifecycle | **Sí** (consentimiento de marketing) | No existe |

---

## 9. Migración desde `cro/08_ANALYTICS.md` (tabla anterior, nunca implementada)

| Nombre anterior | V1 |
|---|---|
| `view_item` | `view_item` (igual; se precisa trigger y dedup) |
| `f360_select_color` / `f360_select_size` | Iguales, con parámetros V1 |
| `f360_fit_guide_open` | → `f360_view_fit_guide` |
| `f360_gold_reserve_click` | Igual |
| `f360_hilo_open` | Igual, + `entry_point` |
| `f360_made_to_order_selected` | **Eliminado**: se deriva de `f360_select_size` con `delivery_state = 5_7_dias` |
| `add_to_cart`, `begin_checkout`, `purchase` | Iguales, con trigger, dedup y regla de Commerce Facts |
| `f360_review_open` | → `f360_review_view` |
| `f360_review_submit` | Igual |
| `f360_back_in_stock_request` | → `f360_back_in_stock_intent` (RESERVED) |
| `search`, `f360_filter_use` | Iguales, + saneamiento |
| `f360_sticky_atc_click` | Igual, + `sticky_state`. `cro/04` `sticky_atc_scroll_to_selector` → estados `elegir_*` |
| *(nuevos)* | `view_item_list`, `select_item`, `view_cart`, `add_shipping_info`, `add_payment_info`, `f360_sticky_atc_view`, `f360_review_photo_view` (RESERVED), `f360_hilo_message`, `f360_store_availability_view` |

---

## 10. Ejemplos de `dataLayer` (diseño; no desplegados)

```js
// Ficha /mx/, la clienta elige talla MX 24 (tienda 37) de Macarena Nude, entrega inmediata, dentro de Instagram.
// IDs ILUSTRATIVOS: no son datos reales.
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({ ecommerce: null });   // limpiar el objeto ecommerce anterior (práctica GA4)
window.dataLayer.push({
  event: 'f360_select_size', mc_version: '1.0', event_id: crypto.randomUUID(), page_view_id: PAGE_VIEW_ID,
  market: 'MX', currency: 'MXN', page_type: 'pdp', browser_context: 'instagram_iab', os_class: 'ios',
  delivery_state: 'inmediata',
  ecommerce: { items: [{ item_id: '3601', item_name: 'Macarena', item_variant: '3624', item_category: 'ballerinas', item_brand: 'Fuxia',
                         price: 2800, f360_color: 'Nude', f360_size_store: '37', f360_size_mx: '24' }] },
});

// Página de gracias: SEÑAL de compra (Commerce Facts sigue siendo la verdad)
window.dataLayer.push({ ecommerce: null });
window.dataLayer.push({
  event: 'purchase', mc_version: '1.0', event_id: crypto.randomUUID(), page_view_id: PAGE_VIEW_ID,
  market: 'MX', currency: 'MXN', page_type: 'thankyou', browser_context: 'standard', coupon_count: 0,
  ecommerce: { transaction_id: '3654', value: 2800, shipping: 0, tax: 0, items: [/* … */] },
});
```

---

## 11. Versionado

- **Cambio compatible** (parámetro opcional nuevo, evento nuevo): `1.x`.
- **Cambio que rompe** (renombre, parámetro requerido nuevo, cambio de significado): `2.0`.
- Cada `push` lleva `mc_version`, para que los reportes separen versiones.
- **Historial:** `1.0`, 2026-10-04 (G2-A), reemplaza la tabla de `cro/08_ANALYTICS.md`.
