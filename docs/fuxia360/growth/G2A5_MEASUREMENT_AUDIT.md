# G2-A.5 · Auditoría real de la medición existente (PRODUCCIÓN, solo lectura)

**Fecha:** 2026-10-04.

**Método:** Claude in Chrome, en la sesión de Mario, solo lectura. No se modificó, guardó ni publicó nada.
- **GA4:** propiedad `Fuxia Ballerinas - Web`.
- **wp-admin de producción:** lista de plugins, ajustes de GTM4WP y Meta for WooCommerce (vista).
- **GTM:** el usuario de Google de la sesión **no tiene acceso** a ninguna cuenta de GTM. El contenedor se auditó desde su **versión publicada pública** (`gtm.js?id=GTM-W2PZG3L5`, descargado con `curl`, sin ejecutar JavaScript).
- **HTML de producción** (`/mx/`, `/co/`), con `curl`. Las descargas quedaron en `~/Documents/fuxia-g2a5/`, fuera del repo.

**No se hizo:**
- **No** se creó ninguna exploración en GA4 (se habría guardado en la cuenta).
- **No** se usó Preview / Tag Assistant.
- **No** se consultaron Meta Events Manager ni la documentación de Meta.

**Etiquetas:**
- **HECHO**: observado.
- **HIPÓTESIS**: inferido y por verificar.
- **UNVERIFIED**: no comprobable con este acceso.

---

## 1. Arquitectura actual de la medición (producción)

```
                       WordPress / WooCommerce 11.1.2 (fuxiaballerinas.com)
 ┌───────────────────────────────────────────────────────────────────────────────────────────┐
 │ GTM4WP 2.0.5 ──► dataLayer (eventos GA4 de ecommerce + pagePostAuthor/pagePostType/cart)    │
 │      └─► carga GTM-W2PZG3L5 (versión publicada 8)                                          │
 │             ├─ Google tag G-8C1244627P            (en gtm.init)            ──► GA4         │
 │             ├─ GA4 Event {{Event}}                (view_item|add_to_cart|begin_checkout|purchase) ──► GA4 │
 │             ├─ Meta Pixel 951926154215387 PageView (en gtm.js)             ──► Meta        │
 │             └─ Meta Pixel {{Event}} GA4→Meta      (mismos 4 eventos; CAPI opt-in en el template) ──► Meta │
 │ Meta for WooCommerce 3.7.6 ──► fbevents.js + MISMO pixel 951926154215387 (PageView, eventos)│
 │                          └─► servidor: Conversions API (_meta_event_id / _meta_purchase_tracked_server) │
 │ Microsoft Clarity 0.10.35 (plugin WP) ──► clarity.ms (fuera de GTM)                         │
 │ Google for WooCommerce 3.9.5 (activo; emisor GA4 / Ads no confirmado)                         │
 │ WooCommerce Order Attribution (sourcebuster sbjs_*) ──► meta del pedido (Commerce Facts G1) │
 │ Cart Abandonment Recovery 2.1.3 (activo)                                                    │
 └───────────────────────────────────────────────────────────────────────────────────────────┘
 Consentimiento: SIN banner ni CMP. El plugin de Meta llama fbq('consent','grant') por sí mismo;
 el template de GTM tiene consent=true. No hay Consent Mode.
```

---

## 2. GTM: contenedor `GTM-W2PZG3L5`, versión publicada **8**

| # | Tag | Tipo | Disparador | Configuración clave |
|---|---|---|---|---|
| T1 | Google tag | `googtag` | `gtm.init` (todas las páginas) | `G-8C1244627P` |
| T2 | GA4 Event | `gaawe` | Evento ∈ `view_item\|add_to_cart\|begin_checkout\|purchase` | Nombre = `{{Event}}`; ecommerce desde el `dataLayer`; *user properties* y *EUID* activos |
| T3 | Meta Pixel (plantilla `cvt_5RM3Q`, Facebook Pixel) | Custom template | `gtm.js` (todas las páginas) | `PageView`, pixel `951926154215387`, `consent: true`, sin advanced matching |
| T4 | Meta Pixel (misma plantilla) | Custom template | Mismos 4 eventos que T2 | Nombre = `{{Event}}`, **`useGA4Ecommerce: true`**, **`optInMetaCAPI: true`**, `consent: true` |

- **Variables:** solo built-in (`Event`, URL, Host, Path, Referrer). Sin variables propias.
- **No hay:** Custom HTML, Clarity, tags de Google Ads, Consent Mode, Conversion Linker, etiquetas de WooCommerce propias.
- **No auditable sin acceso al contenedor:** cambios sin publicar en el workspace, quién publicó y cuándo, nombres legibles de tags y triggers (el `gtm.js` publicado no los incluye).

---

## 3. GA4: propiedad **519011849** (`Fuxia Ballerinas - Web`, cuenta `Default Account for Firebase`)

| Elemento | Valor | Observación |
|---|---|---|
| Measurement ID | **`G-8C1244627P`** | Coincide con T1 y T2 |
| Data streams | 1 web: `https://fuxiaballerinas.com` (stream 14799733291), con tráfico en las últimas 48 h | Un solo stream para `/mx/`, `/co/` y la raíz |
| Zona horaria | **(GMT−07:00) Tijuana** | ⚠ **Conflicto:** el negocio y Commerce Facts usan America/Mexico_City (GMT−6). Los días de GA4 no cortan igual |
| Moneda | Peso mexicano | GA4 convierte COP y USD a MXN con su propio tipo de cambio; no es comparable con G1 (D-G1-03) |
| Medición mejorada | Activa: vistas, scroll, clics de salida y 4 más | Produce `form_start` / `form_submit` (más de 14 mil en R1), probablemente de buscadores y filtros |
| Ocultar datos | Correo: **activo**; parámetros de URL: inactivos | Bien |
| Key events | `purchase` (activo). `close_convert_lead` y `qualify_lead` (sin datos) | — |
| Etiquetas de sitio conectadas | 0 | — |
| Cross-domain, unwanted referrals, retención, vínculos | **UNVERIFIED** (la UI no abrió esos paneles en esta sesión) | Pendiente: ¿están excluidas las pasarelas (Mercado Pago, ePayco, PayPal) como referrals? |

**Eventos recibidos** (informe Eventos):

| Evento | R1: 12 jun – 24 sep 2026 | R2: 6 sep – 3 oct 2026 |
|---|---|---|
| `view_item_list` | 197,678 | 38,966 |
| `page_view` | 141,626 | 24,091 |
| `user_engagement` | 92,741 | 14,054 |
| `session_start` | 70,507 | 12,291 |
| `first_visit` | 56,586 | 9,210 |
| `view_item` | 27,519 | 4,019 |
| `scroll` | 22,837 | 2,646 |
| `form_submit` / `form_start` | 14,207 / 12,754 | 1,938 / 1,540 |
| `add_to_cart` | 3,604 | 313 |
| `begin_checkout` | 563 | 77 |
| `click` | 93 | 19 |
| **`purchase`** | **29 (revenue GA4 $98,422.48, convertido a MXN)** | **1 (revenue $0)** |
| `view_search_results` | 7 | — |

**No llegan:** `select_item`, `view_cart`, `add_shipping_info`, `add_payment_info`, `search` ni ningún evento `f360_*`.

---

## 4. Matriz: medición real contra el Measurement Contract V1

Abreviaturas de emisor:
- **G4W** = GTM4WP;
- **T2 / T4** = tags de GTM (§2);
- **M4W** = Meta for WooCommerce.

| Evento | ¿Existe hoy? | Emisor | Trigger real | Parámetros | ¿Duplicado? | Calidad | Contrato V1 | Acción propuesta |
|---|---|---|---|---|---|---|---|---|
| `view_item_list` | **Sí**, a GA4 | G4W → `dataLayer`. **Cómo llega a GA4: HIPÓTESIS H-1** (T2 no lo incluye en su regex) | Listados (10 productos por impresión, `gtm4wp_product_per_impression`) | Items GA4 de GTM4WP (`item_id` = ID de producto Woo; `use_sku_instead = 0`) | **Posible** (emisor desconocido; pico de 3.2k el 8 de septiembre) | PARTIAL | `view_item_list` | **Verificar H-1.** Adoptar GTM4WP como emisor único |
| `select_item` | No | — | — | — | — | — | `select_item` | GTM4WP lo soporta: habilitar en el emisor único (G2-B) |
| `view_item` | **Sí** (GA4 + Meta) | G4W → T2 y T4. **Además M4W** (navegador, HIPÓTESIS) | Ficha | Items G4W | **Sí, en Meta:** T4 + M4W con el mismo pixel | GA4 OK · Meta CONFLICTED | `view_item` | Un solo emisor para Meta |
| `select_color` / `select_size` / `view_fit_guide` | No | — | — | — | — | — | `f360_*` | CRO las emite (fragmentos) según V1, cuando se autorice |
| `add_to_cart` | **Sí** (GA4 + Meta) | G4W → T2 y T4 (+ M4W, HIPÓTESIS) | Ajax add-to-cart de Woo | Items G4W | **Sí, en Meta** | GA4 OK · Meta CONFLICTED | `add_to_cart` | Verificar que el sticky (CRO-4), que hace `click()` en el botón real, **no** genere un segundo evento: debería generar uno solo vía G4W |
| `view_cart` | No | — | — | — | — | — | `view_cart` | Habilitar en G4W |
| `begin_checkout` | **Sí** (GA4 + Meta) | G4W → T2 y T4 (+ M4W, HIPÓTESIS) | Página de checkout (bloques: `gtm4wp-woocommerce-blocks.js`) | Items G4W | **Sí, en Meta** | OK / CONFLICTED | `begin_checkout` | — |
| `add_shipping_info` / `add_payment_info` | No | — | — | — | — | — | Iguales | Habilitar en G4W y agregarlos a la regex de T2 |
| **`purchase`** | **Sí, muy subcontado en GA4** | G4W → T2 (GA4) y T4 (Meta). **M4W servidor (CAPI) + M4W navegador (HIPÓTESIS)** | **G4W:** la página "pedido recibido" **y** el pedido llegó por primera vez a Procesando / Completado / **En espera**, **y** tiene < 30 min. "Seguimiento fiable" **apagado**. **M4W servidor:** al crear el pedido en el checkout, **antes del pago** (§6) | `transaction_id` = número de pedido Woo (sin prefijo); `value` **incluye envío e impuestos**; ¿cupón? (UNVERIFIED) | **Sí, en Meta (hasta 3 caminos)** | GA4: PARTIAL (≤ 54% de cobertura) · Meta: **CONFLICTED (DQ-01)** | `purchase`, **solo reconciliación** | §7. Commerce Facts sigue siendo la verdad |
| `search` | No (`view_search_results` 7) | Medición mejorada | — | — | — | — | `search` | CRO según V1 (saneado) |
| `form_start` / `form_submit` | Sí (ruido) | Medición mejorada | Cualquier formulario | — | — | Ruido | No está en V1 | Evaluar desactivar *form interactions* (decisión de Mario) |
| `f360_*` (sticky, Hilo, reseñas, tiendas, Gold, filtros) | No | — | — | — | — | — | `f360_*` | CRO, cuando se autorice |
| `PageView` (Meta) | Sí | **T3 + M4W**, mismo pixel | Cada página | — | **Sí, doble** | CONFLICTED | Fuera de V1 (Meta) | Un solo emisor |

---

## 5. Duplicados

| Evento | GA4 | Meta |
|---|---|---|
| `view_item` | Un emisor (T2) | **Duplicado probable:** T4 + M4W (mismo pixel `951926154215387`) |
| `add_to_cart` | Un emisor | **Duplicado probable** |
| `begin_checkout` | Un emisor | **Duplicado probable** |
| `purchase` | Un emisor (T2), **subcontado** | **Hasta 3 caminos:** T4 (navegador, en la página de gracias), M4W navegador (HIPÓTESIS) y **M4W servidor CAPI** (al crear el pedido). La deduplicación de Meta usa `event_id`: M4W comparte el suyo (`_meta_event_id`) entre navegador y servidor; **T4 no lo comparte**, así que **no se deduplica** contra M4W (HIPÓTESIS fuerte) |
| `PageView` | — | **Doble:** T3 + M4W |
| `view_item_list` | Emisor desconocido (H-1) | — |

---

## 6. DQ-01: por qué Meta "recibe" compras de pedidos nunca pagados

**Hechos:**
1. Las metas `_meta_event_id` y `_meta_purchase_tracked_server` (73 pedidos de la muestra de G1) son de **Meta for WooCommerce** (activo, v3.7.6). Es el único componente server-side de Meta en el sitio: GTM es solo de navegador.
2. Los 23 pedidos marcados que **nunca se pagaron** siguieron la ruta "Pendiente de pago" → "Cancelado" por límite de tiempo, o → "Fallido" por rechazo de Mercado Pago. **Nunca** pasaron por Procesando ni Completado.
3. GTM4WP **excluye** Pendiente, Fallido y Cancelado para `purchase`. El camino GTM (T4) **no** pudo enviar compra por esos 23.

**Conclusión:** la compra de los 23 pedidos no pagados la envió **Meta for WooCommerce por servidor (Conversions API) en el momento de crear el pedido en el checkout**, antes de que la pasarela confirme el pago. Así, toda clienta que llega a pagar a Mercado Pago, ePayco o PayPal y no termina se cuenta como compra en Meta.
- **El hook exacto del plugin** (p. ej., `woocommerce_checkout_order_processed` frente a `thankyou`) es **UNVERIFIED**. Requiere leer el código de la 3.7.6 o ver Events Manager, y quedó fuera de alcance por la regla de no consultar Meta.

**Impacto:** las compras y el ROAS de Meta están **inflados** por (a) pedidos no pagados y (b) posibles duplicados entre T4 y Meta for WooCommerce. Además, el catálogo de Meta se sincroniza desde Meta for WooCommerce (218 productos).

**No se modificó nada.** La corrección es una decisión aparte (G2-B / auditoría de Meta).

---

## 7. ¿Cuándo se dispara `purchase`?

| Mecanismo | ¿Envía purchase? | Destino | Momento |
|---|---|---|---|
| Al **crear el pedido** (checkout) | **Sí** | Meta (CAPI, Meta for WooCommerce) | Antes del pago |
| Al abrir la **página de gracias** | **Sí** | GA4 (T2) y Meta (T4) vía GTM4WP. Meta for WooCommerce en el navegador: HIPÓTESIS | Solo si el estado ∈ {Procesando, Completado, **En espera**}, la primera vez, en menos de 30 min |
| **Al pagar** (webhook de la pasarela) | **No directamente.** Ningún emisor escucha el pago real; GTM4WP depende de que la clienta vuelva a la página de gracias | — | — |
| Por **cambio de estado** en el servidor | Solo en el sentido de que GTM4WP revisa el estado al ver la página | — | — |
| Por plugin | Sí: GTM4WP y Meta for WooCommerce | — | — |
| Por GTM | Sí: T2 y T4 | — | — |

**Respuesta: más de un mecanismo.**
- **GA4:** un emisor, condicionado a que la clienta vuelva a la página de gracias.
- **Meta:** dos o tres emisores, uno de ellos antes del pago.

---

## 8. GA4 `purchase` frente a Commerce Facts (R1, 12 jun – 24 sep 2026)

| | Commerce Facts (G1, verdad) | GA4 |
|---|---|---|
| Pedidos pagados (`countable`) | **54** (MXN 36 · COP 17 · USD 1) | **29** `purchase` (28 usuarios) |
| Pedidos no pagados | 27 (23 cancelados + 4 fallidos) + 1 pagado → cancelado | No los cuenta (bien) |
| Revenue | Por moneda: MXN 124,090 · COP 8,126,300 · USD 465 (total de pedidos) | $98,422.48 convertido a MXN por GA4. **No es comparable** sin FX (D-G1-03) |

**Cobertura de GA4: a lo más 29 / 54 = 54%.**
- Es un techo. Si alguno de los 29 fuera de un estado "En espera" que no se pagó, la cobertura real sería menor.
- La comparación pedido por pedido (`transaction_id` ↔ `woo_order_id`) **no se hizo**: la dimensión solo está en Explorations y crear una se habría guardado en la cuenta. Queda para la Data API (G2-B).

**Causas probables del subconteo (HIPÓTESIS, ordenadas):**
1. Pasarelas externas: la clienta paga en Mercado Pago, ePayco o PayPal y **no vuelve** a la página de gracias ("Seguimiento fiable" apagado).
2. El pago se confirma después y la ventana de 30 minutos se vence.
3. 49% de las compras ocurren dentro del navegador de Instagram o Facebook (G1), donde el regreso de la pasarela y las cookies son frágiles (CRO-IAB).
4. Bloqueadores o consentimiento (no hay banner, así que es poco probable).

**R2 (últimos 28 días):** GA4 registra **1** `purchase` con revenue 0. Producción sí tiene ventas en ese periodo, aunque F360 no tiene pedidos de producción posteriores al 24 de septiembre para cruzar. **SEÑAL de deterioro reciente** de la medición de compras; verificar con la Data API.

---

## 9. Huecos y conflictos

| # | Tipo | Hallazgo |
|---|---|---|
| A1 | **CONFLICT** | Mismo pixel de Meta cargado por GTM (T3/T4) y por Meta for WooCommerce → eventos dobles |
| A2 | **CONFLICT (DQ-01)** | Meta for WooCommerce envía Purchase por CAPI antes del pago |
| A3 | **GAP** | GA4 `purchase` ≤ 54% de los pedidos reales (R1) y casi 0 en R2 |
| A4 | **CONFLICT** | Zona horaria de GA4 = Tijuana; la del negocio y Commerce Facts es CDMX |
| A5 | **PRIVACIDAD** | GTM4WP publica en el `dataLayer` de **todas las páginas** el **correo del autor de la página** (`pagePostAuthor`, cuenta de la agencia). Está en el HTML público; GA4 no lo recibe salvo que un tag lo lea (T2 no lo lee). Se corrige desactivando "autor" en *Variables de página* de GTM4WP |
| A6 | **LEGAL_REVIEW** | No hay banner ni CMP. Meta for WooCommerce hace `fbq('consent','grant')` automáticamente. GA4, Meta y Clarity corren sin consentimiento |
| A7 | **CORRECCIÓN A G0** | **Sí existe** recuperación de carrito abandonado en producción (*Cart Abandonment Recovery* 2.1.3 activo). G0 decía MISSING. Probablemente envía correos sin un modelo de consentimiento de marketing (LEGAL_REVIEW) |
| A8 | **UNKNOWN (H-1)** | Cómo llega `view_item_list` a GA4 sin estar en la regex de T2. Candidatos: Google for WooCommerce 3.9.5 (activo) u otro camino. Verificar con Tag Assistant / Preview **en staging** o leyendo la config de GTM4WP y Google for WooCommerce |
| A9 | **GAP** | No se miden `select_item`, `view_cart`, `add_shipping_info` ni `add_payment_info`, aunque GTM4WP los puede generar |
| A10 | **NOISE** | `form_start` / `form_submit` (medición mejorada) inflan los eventos |
| A11 | **ACCESO** | El usuario de la sesión no tiene acceso a GTM: no se pudieron ver los nombres, el workspace ni el historial de publicación |
| A12 | **UNVERIFIED** | Si `purchase` de GTM4WP manda códigos de cupón (posible PII). El contrato lo prohíbe |
| A13 | **DATA QUALITY** | GTM4WP cuenta "En espera" como compra (pagos no confirmados). Commerce Facts no |

---

## 10. Diferencias contra el Measurement Contract V1

1. **Emisor de los eventos GA4 estándar:**
   - Hoy es **GTM4WP**, no los fragmentos de CRO.
   - **Recomendación (cambio a V1.1):** **adoptar GTM4WP como emisor único** de los eventos de ecommerce GA4 estándar (`view_item_list`, `select_item`, `view_item`, `add_to_cart`, `view_cart`, `begin_checkout`, `add_shipping_info`, `add_payment_info`, `purchase`), configurándolo para cumplir V1.
   - CRO emitiría **solo** los `f360_*`.
   - Así se evitan dos instrumentaciones.
2. **`item_id`:** GTM4WP usa el ID de producto Woo (`use_sku_instead = 0`). **Coincide** con V1.
3. **`purchase.value`:** GTM4WP incluye envío e impuestos, igual que V1 (`value` = total). OK.
4. **Estados de `purchase`:** GTM4WP incluye "En espera"; V1 no fija estados porque `purchase` es solo una señal. Documentar en V1.1.
5. **Sobre común de V1** (`mc_version`, `event_id`, `market`, `browser_context`, `page_type`): **no existe** en GTM4WP. Agregarlo requiere una variable o un tag en GTM, o un pequeño script que enriquezca el `dataLayer`, **sin** un segundo emisor de eventos.
6. **Zona horaria:** V1 usa CDMX; GA4 usa Tijuana.
7. **Moneda:** GTM4WP manda la moneda correcta por mercado (MXN en `/mx/`, COP en `/co/`). OK.

---

## 11. Propuesta de G2-B (no implementada; requiere decisión por punto)

**A. Correcciones de configuración** (en producción; cada una necesita autorización explícita y se hace en GTM, GA4 o wp-admin, no en código F360):
1. **Meta (después de una auditoría de Meta / CAPI):**
   - un solo emisor de pixel: o GTM (T3/T4) o Meta for WooCommerce, no ambos;
   - Purchase por servidor **solo cuando el pago está confirmado**.
2. **GA4:** cambiar la zona horaria a Ciudad de México. Solo afecta datos futuros.
3. **GTM4WP:**
   - desactivar `pagePostAuthor`;
   - evaluar "Seguimiento fiable de compras";
   - decidir si "En espera" cuenta;
   - habilitar `select_item`, `view_cart`, `add_shipping_info` y `add_payment_info`, y agregarlos a la regex de T2.
4. **Acceso:** pedir a quien administra GTM acceso de **lectura** para el correo de Mario, o un export JSON del contenedor.

**B. Sin tocar producción (staging / F360):**
1. Contrato **V1.1**: GTM4WP como emisor de los eventos estándar; `f360_*` desde CRO; sobre común vía GTM.
2. Vistas `commerce_channel_v1` y `measurement_source_health` (diseñadas en G2-A), ahora con IDs reales:
   - GA4 `519011849` / `G-8C1244627P`: PARTIAL por cobertura;
   - Meta: CONFLICTED;
   - GTM v8: auditado sin acceso.
3. **Reconciliación GA4 contra Commerce Facts por `transaction_id`** usando la **GA4 Data API**, con una service account de solo lectura (checklist en G2-A §4.2). Métrica: cobertura de `purchase`.
4. Verificar H-1 y A12 con Tag Assistant **en staging4**, que no carga GTM hoy. Requiere decidir el entorno de GTM para staging.

**Bloqueado:** consentimiento (LEGAL_REVIEW), Meta / CAPI (fuera de alcance hasta su auditoría), acceso a GTM (A11).
