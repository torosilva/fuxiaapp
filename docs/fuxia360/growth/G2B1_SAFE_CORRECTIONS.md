# G2-B1 · Correcciones seguras + diseño (Measurement V1.1)

**Fecha:** 2026-10-04.

**Único cambio en producción:** **P1**, autorizado por Mario.

**Todo lo demás es diseño o lectura:**
- sin GTM publish;
- sin cambios de configuración en GA4;
- sin cambios en Meta;
- sin "reliable purchase";
- sin Clarity ni Campaign 360.

**Regla vigente:**
- Commerce Facts = verdad financiera.
- GA4 = comportamiento y adquisición, reconciliado contra Commerce Facts.
- Meta ≠ verdad de ventas.

---

## A. P1 aplicado: correo del autor fuera del `dataLayer` (PRODUCCIÓN)

| Paso | Detalle |
|---|---|
| Cambio | wp-admin → Ajustes → Google Tag Manager → **Variables de página → Datos de la entrada → "Nombre del autor del post" = desactivado** → *Guardar cambios* (mensaje "Ajustes guardados.") |
| Caché | Barra superior → **Purgar caché de SG** |
| Hora | 2026-10-04, sesión de Mario (Claude in Chrome) |

**Verificación pública** (`curl`, sin JavaScript, antes y después):

| Página | `pagePostAuthor` antes | Después | Otras claves del `dataLayer` | Snippet GTM / scripts GTM4WP / datos de producto / Meta / Clarity |
|---|---|---|---|---|
| `/mx/` | **presente (correo)** | **ausente** | `cartContent`, `pagePostType`, totales: **iguales** | 2 / 3 / 9 / 5 / sí: **iguales** |
| `/mx/tienda/` | ausente | ausente | iguales | 2 / 3 / 32 / 5 / sí: iguales |
| `/mx/producto/…` | **presente (correo)** | **ausente** | `productType`, `productIsVariable`, ratings…: **iguales** | 2 / 3 / 5 / 5 / sí: iguales |
| `/co/` | — | ausente | iguales | iguales |

**Resultados:**
- **Correos restantes en el HTML:** solo el de contacto público `@fuxiaballerinas.com`.
- **Constantes de GTM4WP** (`gtm4wp_currency`, `product_per_impression`, etc.): idénticas antes y después.
- **Regresión:** ningún tag consumía `pagePostAuthor` (GTM v8 solo usa variables integradas). Los scripts y datos de ecommerce que alimentan `view_item_list`, `view_item`, `add_to_cart`, `begin_checkout` y `purchase` no cambiaron.
- **No se ejecutó Preview de GTM** ni se generaron eventos de prueba.
- **Rollback:** volver a activar la opción y purgar la caché.

**Pendiente opcional (raíz):** el "nombre para mostrar" de la cuenta de WordPress de la agencia es un correo. Cambiarlo evita que aparezca en otros lugares (feeds, páginas de autor). No se hizo.

---

## B. P2: allowlist exacta de eventos para GA4 (DISEÑO, no publicado)

| | BEFORE (GTM v8) | AFTER (propuesto) |
|---|---|---|
| Trigger usado por **T2 (GA4 Event)** | Evento personalizado, *Event name* **matches RegEx** `view_item\|add_to_cart\|begin_checkout\|purchase` (sin anclas: "contiene") | **Trigger nuevo** "CE · GA4 ecommerce V1.1": evento personalizado, *Event name* **matches RegEx** `^(view_item_list\|view_item\|add_to_cart\|begin_checkout\|purchase)$` (anclado, lista exacta) |
| Eventos que llegan a GA4 | `view_item_list` (**por accidente**), `view_item`, `add_to_cart`, `begin_checkout`, `purchase` | **Los mismos cinco, ahora a propósito.** No se agrega ni se quita ninguno en P2, para no mover las series. Los demás (`select_item`, `view_cart`, `add_shipping_info`, `add_payment_info`) se agregan en una unidad posterior, ya decidida |
| Trigger usado por **T4 (Meta)** | El mismo regex ambiguo | **Sin cambios en P2** (decisión: no tocar Meta). Queda con el trigger viejo hasta G2-META-1 |

**Procedimiento** (requiere permiso **Editar** para preparar y **Publicar** para publicar; Mario hoy no tiene acceso al contenedor):
1. Workspace nuevo "G2-B P2 GA4 allowlist".
2. Crear el trigger AFTER. En T2, reemplazar el trigger viejo por el nuevo. **No editar T4.**
3. **Preview** (Tag Assistant) en una sesión: listar, abrir una ficha, agregar al carrito, llegar al checkout. Verificar que T2 dispara en exactamente esos 5 eventos y que T4 no cambió.
4. *Submit* → crear versión "v9 · G2-B P2". **Publicar solo con aprobación de Mario.**

**Rollback:** *Versions* → v8 → *Publish*.

**Efecto esperado en GA4:** ninguno en conteos. Es una refactorización que vuelve explícito lo que hoy pasa por accidente.

---

## C. Contrato de identidad ecommerce (GA4) · LEGACY vs F360

> **REEMPLAZADA (2026-10-04)** por la decisión de identidad canónica de Mario: `item_id` = **SKU canónico F360** cuando la variante está determinada. Ver `G2B2_CANONICAL_IDENTITY.md` e `INVENTORY_MODEL.md` §1.1. Lo de abajo queda solo como referencia del estado actual de GTM4WP (§C.1).

### C.1 Lo que pasa hoy (código de GTM4WP 2.0.5, `ProductData.php` + `gtm4wp-woocommerce.js`)

| Evento | `item_id` hoy | `item_variant` hoy |
|---|---|---|
| `view_item_list`, `select_item` | ID del producto **padre** Woo | — |
| `view_item` (carga de la ficha) | ID del producto **padre** | — |
| `view_item` (al elegir talla o color, `found_variation`) | **ID de la variación** (+ `item_group_id` = padre) | Atributos en texto (`"37,Azul"`) |
| `add_to_cart`, `view_cart`, `begin_checkout`, `purchase` | **ID de la variación** (+ `item_group_id`) | Atributos en texto |

**Problemas:**
1. El `item_id` **cambia de nivel** dentro del funnel (padre → variación).
2. Las variaciones **legacy no tienen SKU propio** (heredan el del padre, D1 H1), así que la opción "usar SKU" de GTM4WP **colapsaría** todas las tallas en un solo ID. **No usarla.**

### C.2 Propuesta V1.1

**Una identidad por nivel, estable en todo el funnel:**

| Campo | Regla V1.1 | Legacy (129 productos, sin SKU por variante) | F360 (publicados o unidos) |
|---|---|---|---|
| `item_id` | **Identidad de PRODUCTO (modelo)**, igual en todos los eventos | **ID del producto padre Woo**, el mismo que ya usan hoy listados y fichas | **ID del producto padre Woo** del producto F360 publicado (`woo_product_links`) |
| `item_variant` | **Identidad de VARIANTE (color + talla)**, en todo evento donde la variante es conocida | `woo_var:<ID de variación>` | **SKU F360** (`F360-<MODELO>-<COLOR>-<TALLA>`) |
| `item_name` | Nombre del modelo | Nombre del producto Woo | Nombre del modelo F360 |
| `item_category` | Categoría | Primera categoría Woo (como hoy) | Ídem. Mapeo a `category_key` de F360 en el análisis |
| `price` | Precio **unitario** en la moneda de la página | Listas y fichas: precio mostrado. Carrito y checkout: precio de la línea. `purchase`: total de la línea ÷ cantidad (neto, igual que `unit_net` de Commerce Facts) | Ídem |
| `currency` | Moneda del mercado | `gtm4wp_currency` (MXN en `/mx/`, COP en `/co/`) | Ídem |
| Parámetros extra | `f360_color`, `f360_size_store` (calzado), `item_group_id` se conserva | Desde los atributos | Ídem |

**Por evento:**

| Evento | `item_id` | `item_variant` |
|---|---|---|
| `view_item_list` / `select_item` | producto | — (no hay variante) |
| `view_item` | producto. **Solo en la carga** (la selección de variante es `f360_select_size`, de CRO) | — |
| `add_to_cart` / `view_cart` / `begin_checkout` / `purchase` | **producto** (de `item_group_id`) | **variante** (SKU F360 o `woo_var:<id>`) |

**Resultado:** la misma variante se sigue de `add_to_cart` a `purchase` por `item_variant`, y el mismo modelo de la lista a la compra por `item_id`.

### C.3 ¿El SKU F360 como identificador futuro?

- **Sí, para la VARIANTE:** es estable, comercial, igual en tienda física y en línea, y sobrevive a la recreación o unión de productos Woo.
- **No todavía como `item_id`:**
  - **Legacy** no tiene SKU por variante.
  - Cambiar `item_id` rompe la continuidad del histórico de GA4.
  - A nivel **producto**, F360 tiene `products.code`, pero el navegador no lo conoce.
- **Transición en tres fases:**

| Fase | `item_id` | `item_variant` | Cuándo |
|---|---|---|---|
| **V1.1 (ahora)** | ID padre Woo (todos) | SKU F360 o `woo_var:<id>` | P2-bis (abajo) |
| **V1.2** | Igual | Igual, + `f360_variant_id` cuando el fragmento lo conozca | Con CRO |
| **V2 (futuro)** | `F360-<MODELO>` (código de producto F360) | SKU F360 | Cuando el catálogo completo sea F360 (consolidación terminada). **Con versión de contrato y fecha de corte** |

**Histórico:**
- No se reescribe GA4.
- La reconciliación en F360 traduce los IDs viejos: variación → padre por `commerce_woo_order_lines`, y legacy → variante F360 por `legacy_woo_map` / `retired_woo_links`.
- Los análisis que crucen la fecha de corte usan la tabla de traducción, nunca un join directo.

**Implementación (P2-bis, diseño):** una **variable JavaScript personalizada en GTM** que, solo para T2, reescribe los items:
- `item_id := item_group_id || item_id`;
- `item_variant := (sku empieza con "F360-") ? sku : "woo_var:" + <id de variación>`.

**No se toca GTM4WP ni los 129 productos.** Requiere decisión (abajo).

---

## D. Data API: instrucciones para Mario (sin crear nada todavía)

**Dos caminos.** Recomiendo **D1** para la reconciliación completa ya, y **D2** cuando sea programada.

### D1. Una sola vez, con tu propio usuario (no requiere administrador de GA4)

Tu usuario ya ve la propiedad 519011849. Con permiso de lectura, la Data API funciona con el usuario.
1. **Google Cloud:**
   - entra a https://console.cloud.google.com con tu cuenta;
   - **crea un proyecto** (selector de proyectos → *Nuevo proyecto* → nombre `fuxia360-analytics`) o usa uno existente de Fuxia.
2. **Habilitar la API:** *APIs y servicios → Biblioteca* → busca **"Google Analytics Data API"** → *Habilitar* (en ese proyecto).
3. **Instalar `gcloud` en tu Mac**, si no lo tienes.
4. **Autenticarte** (escríbelo tú en la terminal con el prefijo `!`, porque abre el navegador):
   ```
   ! gcloud auth application-default login --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/analytics.readonly"
   ! gcloud auth application-default set-quota-project fuxia360-analytics
   ```
   - La credencial queda en `~/.config/gcloud/` de tu Mac, **fuera del repo**.
   - **Nunca la copies al chat.**
5. **Avísame.** Corro la reconciliación de solo lectura, que no guarda nada de GA4 en el repo, para **todo el periodo disponible** (desde que existe la propiedad).

### D2. Programada (service account): requiere un **Administrador** de la propiedad GA4

Tu usuario no puede: la gestión de accesos de GA4 te redirige.
1. Mismo proyecto y API habilitada (D1, pasos 1 y 2).
2. *IAM y administración → Cuentas de servicio → Crear*: nombre `ga4-reader`. **Sin roles de Google Cloud.**
3. En la cuenta de servicio: *Claves → Agregar clave → JSON*. Se descarga un archivo.
   - **No** lo mandes por chat ni lo subas a ningún lado.
4. El **Administrador de GA4**: Admin → *Gestión de acceso de la propiedad* → "+" → correo de la cuenta de servicio (`ga4-reader@…iam.gserviceaccount.com`) → rol **Lector** → Agregar. Según Google, el lector ve datos "vía la UI o las APIs".
5. Guardarla como secreto **solo en Supabase staging** (escríbelo tú):
   ```
   ! supabase secrets set --project-ref faltxpkaicwpnlqaxrdu GA4_PROPERTY_ID=519011849 GA4_SA_KEY_JSON="$(cat ~/Downloads/<archivo>.json)"
   ```
   Después **borra el archivo** descargado.
6. **Rollback:** quitar el usuario en GA4 y borrar la clave en Google Cloud.

---

## E. G2-META-0: auditoría de solo lectura

**Fuentes:**
- código público de **Meta for WooCommerce 3.7.6** (`downloads.wordpress.org`);
- plantilla de Meta en GTM v8 (`gtm.js`);
- documentación oficial de Meta (deduplicación).

**Events Manager:** tu usuario de Facebook **no tiene acceso** al pixel `951926154215387` ("No hay orígenes de datos"). No se pudo leer el método de conexión ni el % deduplicado: hace falta ese acceso.

### E.1 Quién envía qué y cuándo

| Evento Meta | GTM T3/T4 (navegador, plantilla "Facebook Pixel" 2.0.8) | Meta for Woo, navegador | Meta for Woo, servidor (CAPI) | `event_id` |
|---|---|---|---|---|
| PageView | T3 en `gtm.js` (cada página) | `inject_page_view_event` | Sí (`send_api_event(…, false)`) | Plugin: compartido navegador/servidor. **GTM: sin `eventID`** |
| ViewContent | T4 con `view_item` **y `view_item_list`** (regex ambiguo; cómo lo traduce la plantilla: UNVERIFIED) | `woocommerce_after_single_product` | Sí | Ídem |
| AddToCart | T4 con `add_to_cart` | `woocommerce_add_to_cart` | Sí | Ídem |
| InitiateCheckout | T4 con `begin_checkout` | `woocommerce_after_checkout_form` / checkout de bloques | Sí | Ídem |
| **Purchase** | T4 con `purchase` de GTM4WP: página de gracias, estado ∈ Procesando / Completado / En espera, menos de 30 min | `woocommerce_thankyou` | **`woocommerce_new_order` (10), `woocommerce_process_shop_order_meta` (20), `woocommerce_checkout_update_order_meta` (30)** | Plugin: `_meta_event_id` en el pedido, **compartido**. GTM: sin `eventID` |
| ViewCategory, Search, Lead | — | Sí | Sí | Plugin |

### E.2 Purchase: ¿al crear el pedido o al confirmar el pago? (código, `inject_purchase_event`)

- **Estados válidos:** `processing`, `completed`, `on-hold` **y `pending`**.
- Al crear el pedido en el checkout, Woo lo deja en **`pending`** (pendiente de pago) **antes** de redirigir a Mercado Pago, ePayco o PayPal.
- El hook `woocommerce_new_order` / `checkout_update_order_meta` entra en ese momento, **envía la CAPI** y marca `_meta_purchase_tracked_server`. No vuelve a enviarla aunque el pedido después falle o se cancele.
- **Conclusión (HECHO, por código + datos G1): Purchase server = ORDER CREATED, no PAYMENT CONFIRMED.** Esto explica **DQ-01** (23 pedidos nunca pagados con la marca de servidor).
- El Purchase de navegador del plugin solo ocurre si la clienta ve la página de gracias, y lleva el **mismo `event_id`** que el de servidor.

### E.3 Deduplicación

- **Doc oficial de Meta:** se deduplica cuando **coinciden `event_id` y `event_name`**. Los eventos **sin** `event_id` **no se pueden deduplicar**.
- **Plugin:** navegador y servidor comparten `event_id`, así que se deduplican entre sí.
- **GTM T3/T4:** la plantilla solo manda `eventID` si se configura (`eventId`); en v8 **no está configurado**. Resultado: PageView, ViewContent, AddToCart, InitiateCheckout y Purchase de GTM **no se deduplican** contra los del plugin. **Doble conteo probable** (HIPÓTESIS fuerte; confirmar en Events Manager).
- **`optInMetaCAPI: true` en T4:** la plantilla llama `fbq('set','optinMetaEnabledCapi', pixel)` y carga un *param builder* de Meta. Es la opción de **integración de Conversions API administrada por Meta**. Si eso reenvía por servidor los eventos de GTM es **UNVERIFIED** (no hay documentación oficial clara; solo issues públicos en GitHub de Meta).

### E.4 Qué debería sobrevivir (propuesta para G2-META-1, no aplicada)

| Opción | Descripción | Requisito para "Purchase = pago confirmado" |
|---|---|---|
| **M-A (recomendada, preliminar)** | **Meta for WooCommerce como emisor único** (navegador + CAPI con `event_id` compartido; maneja catálogo, advanced matching y deduplicación propia). **Quitar el pixel de GTM** (T3/T4) | El plugin envía Purchase en `pending`. Hace falta que **no** envíe hasta el pago: ajuste o filtro en el plugin (**UNVERIFIED** si existe un filtro público para los estados válidos), o un snippet que lo retrase. Verificar en el código antes |
| M-B | GTM como emisor único (pixel + CAPI propia) | Hay que **desactivar el pixel del plugin** sin perder la sincronización del catálogo, y construir CAPI con `event_id` y el disparador de pago. Más trabajo |
| M-C | Dejar ambos con `event_id` común | Frágil: GTM no conoce el `_meta_event_id` del pedido |

**Antes de decidir:** acceso a Events Manager (método de conexión, % deduplicado) y confirmar en el código si existe un filtro para los estados válidos del Purchase.

---

## F. Reconciliación GA4 ↔ Commerce Facts con `browser_context`

**Llave:** `transaction_id` (GA4) = `woo_order_id` = `commerce_orders.woo_order_id` (`external_ref` = `<target>:<id>`).

**`browser_context`, regla de procedencia (no se inventa):**

| Fuente | Cuándo se usa | Mapeo |
|---|---|---|
| **1. Commerce Facts** (`commerce_woo_attribution.browser_class`, user agent del pedido vía Woo Order Attribution) | **Siempre como base**, porque existe aunque GA4 no tenga el pedido | `instagram_iab` → `instagram_iab` · `facebook_iab` → `facebook_iab` · `safari` → `safari` · `chrome` → `chrome` · firefox/edge/otros → `other` · sin atribución → **`UNKNOWN`** |
| 2. GA4 `browser` (Data API) | Solo como columna **paralela** de verificación | GA4 no distingue Instagram de Facebook: sus navegadores in-app se reportan genéricos (p. ej. "Safari (in-app)", "Android Webview"), así que van a `in_app_unknown`, **nunca** a `instagram_iab` |

**Denominador ya medible (staging4, R1, Commerce Facts, pedidos `countable`):**

| `browser_context` | Pagados |
|---|---|
| instagram_iab | 24 (MXN 15 · COP 9) |
| safari | 19 (MXN 15 · COP 4) |
| chrome | 7 |
| facebook_iab | 3 |
| UNKNOWN | 1 (pedido de prueba por API) |
| **Total** | **54** |

**Salidas** (por periodo × mercado × `browser_context`):
- `paid_orders`;
- `ga4_purchase_found` (≥ 1 `transaction_id`);
- **coverage %**;
- `ga4_duplicates` (`ecommercePurchases` > 1);
- `ga4_without_paid_fact` (no pagado, cancelado o inexistente en F360);
- `revenue_delta_mxn` (solo pedidos MXN; sin FX).

**La pregunta clave** ("¿el déficit se concentra en Instagram y Facebook IAB?") se responde con `coverage %` por `browser_context`.

**Implementación:**
- tras D1, un script de solo lectura (Data API → tabla temporal en memoria → reporte agregado sin PII);
- tras D2, tabla `f360.ga4_purchase_snapshots` + vista en staging (§4 del plan G2-B).

---

## G. Decisiones que necesito de Mario

| # | Decisión |
|---|---|
| 1 | **Acceso a GTM:** que el administrador del contenedor te dé **Editar** (preparar P2) y quien publique tenga **Publicar**. O que la agencia aplique P2 con este diseño |
| 2 | **P2:** ¿aprobar la allowlist V1.1, sin agregar eventos todavía? |
| 3 | **Identidad V1.1:** ¿aprobar `item_id` = producto padre Woo + `item_variant` = SKU F360 / `woo_var:<id>`, implementado con una variable de GTM (P2-bis)? |
| 4 | **`view_item` en `found_variation`:** ¿se deja de enviar a GA4 (lo cubre `f360_select_size` de CRO)? |
| 5 | **Data API:** ¿D1 ahora (tu usuario + `gcloud`)? ¿Y quién es el administrador de GA4 para D2? |
| 6 | **Zona horaria (P4):** confirmada con la doc oficial (solo datos futuros; posible *flat spot*; la zona vieja un rato; máximo una vez al día; **Editor o superior**). ¿Aprobar y quién lo hace (tu rol actual probablemente no alcanza)? |
| 7 | **Meta:** dame acceso de lectura al pixel `951926154215387` en Business Manager para cerrar G2-META-0. Y confirmar si seguimos la línea M-A (plugin como emisor único) |
| 8 | **Raíz de P1:** ¿cambiar el nombre visible de la cuenta de WordPress de la agencia? |

---

## H. Git

- Este documento, sin commit.
- Producción: **solo P1** (ajuste de WordPress, sin código).

**Fuentes:**
- [Google Analytics Help: Add a property / time zone](https://support.google.com/analytics/answer/9744165)
- [GTM user permissions](https://support.google.com/tagmanager/answer/6107011)
- [GA4 transaction ID dedup](https://support.google.com/analytics/answer/12313109)
- [Meta: Using the Conversions API / deduplication](https://developers.facebook.com/documentation/ads-commerce/conversions-api/using-the-api)
- [Meta Pixel reference](https://developers.facebook.com/docs/meta-pixel/reference)
- Código: Meta for WooCommerce 3.7.6 (`facebook-commerce-events-tracker.php`: `inject_purchase_event`, hooks en las líneas 297-300) y GTM4WP 2.0.5 (`ProductData.php`).
