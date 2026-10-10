# G2-B · Measurement Correction & Reconciliation: plan (sin cambios en producción)

**Fecha:** 2026-10-04.

**Base:** `G2A5_MEASUREMENT_AUDIT.md` (aprobado) + investigación de solo lectura:
- código público de GTM4WP 2.0.5;
- ajustes de GTM4WP en wp-admin (vista);
- HTML de producción (`curl`, sin JavaScript);
- documentación oficial de Google (fuentes al final).

**Nada se modificó:** sin GTM publish, cambios de configuración en GA4, Meta, Clarity ni Campaign 360.

---

## 0. Regla fijada (Mario, 2026-10-04)

| Sistema | Rol | Nunca es |
|---|---|---|
| **Commerce Facts** (G1) | **Verdad de ventas y revenue** | — |
| GA4 | Comportamiento, funnel, adquisición | Verdad financiera |
| Meta | Plataforma publicitaria, señal de atribución | Verdad financiera |
| Clarity | Comportamiento cualitativo | Verdad de nada cuantitativo |

**Revenue, Orders, AOV, CPA, ROAS y LTV** siempre se reconcilian contra Commerce Facts.

---

## 1. Arquitectura objetivo: Measurement V1.1

```
Woo (tienda) ──► GTM4WP 2.0.5 (EMISOR ÚNICO de ecommerce GA4 estándar) ──► dataLayer
                  └── CRO fragments: SOLO f360_* (contrato V1) ─────────────► dataLayer
dataLayer ──► GTM-W2PZG3L5
               ├─ Google tag G-8C1244627P
               ├─ GA4 Event: lista EXPLÍCITA y ANCLADA de eventos (^(view_item_list|select_item|…|purchase)$)
               └─ Meta: lo decide G2-META-0 (GTM o Meta for WooCommerce, NO ambos)
GA4 (comportamiento) ──Data API (solo lectura)──► F360: ga4_purchase_reconciliation
Woo pedido pagado ──► Commerce Facts (verdad) ──────────────────────────────┘
                     └─ cobertura, faltantes, sobrantes, duplicados y discrepancia por transaction_id = woo_order_id
```

**Principios V1.1:**
1. **GTM4WP** emite los eventos GA4 estándar de ecommerce. **CRO** emite solo `f360_*`.
2. **GTM** reenvía con una lista exacta y anclada (corrige H-1).
3. **Un solo `purchase` de navegador por pedido** (GTM4WP). **F360 no envía un segundo `purchase` a GA4** (§3).
4. **La reconciliación es offline**, de GA4 contra Commerce Facts. Nunca se corrige GA4 "rellenando" compras.

---

## 2. Matriz GTM4WP (código 2.0.5 + ajustes de producción)

GTM4WP tiene **un solo interruptor de ecommerce, activado**: empuja **todos** sus eventos al `dataLayer`. GTM decide qué reenvía.

| Evento | DISPONIBLE (lo empuja GTM4WP) | REENVIADO HOY a GA4 (T2) | TRIGGER real (código) | CONFIABILIDAD | ACCIÓN |
|---|---|---|---|---|---|
| `view_item_list` | Sí | **Sí, por accidente (H-1):** la regex de T2 no está anclada y `view_item_list` contiene `view_item` | Al pintar listados; **en lotes de 10** (`gtm4wp_product_per_impression = 10`). Versión blocks y clásica | Media: los lotes inflan el conteo (197k en R1) | Mantener **explícito** en la lista anclada. Documentar que N eventos ≠ N listados |
| `select_item` | Sí | **No** | Clic en un link de producto de una lista; **retrasa la navegación hasta 2,000 ms** (callback) | Media. Riesgo de lentitud en el navegador de Instagram | Habilitar solo tras medir el efecto del callback. **Opción:** bajar el timeout a 0 (el evento se envía igual, no bloquea) |
| `view_item` | Sí | Sí | **(a)** al cargar la ficha, con `item_id` = ID de **producto**; **(b) otra vez en cada `found_variation`** (elegir color o talla), con **`item_id` = ID de variación**, `item_group_id` = producto e `item_variant` = atributos en texto | **Inconsistente:** 2+ eventos por ficha y `item_id` cambia de nivel | **Contrato V1.1:** `view_item` cuenta solo la carga (a). La selección de variación es `f360_select_size` (CRO). Decidir si se desactiva (b) (requiere ajuste o filtro en GTM: `item_id` == `item_group_id`) |
| `add_to_cart` | Sí | Sí | Ajax add-to-cart de Woo (`added_to_cart`) y bloques | Buena | Mantener. Verificar que el sticky (CRO-4) genere **uno** |
| `remove_from_cart` | Sí | No | Quitar del carrito | Buena | Opcional (no está en V1) |
| `view_cart` | Sí (servidor, en la página de carrito) | **No** | Página de carrito | Buena | Agregar a la lista |
| `begin_checkout` | Sí (servidor, en el checkout) | Sí | Página de checkout | Buena | Mantener |
| `add_shipping_info` | Sí | **No** | Elegir o confirmar envío en el checkout (clásico y bloques) | Media: depende del DOM del checkout | Agregar a la lista |
| `add_payment_info` | Sí | **No** | Elegir pasarela | Media | Agregar a la lista |
| `purchase` | Sí (servidor, en "pedido recibido") | Sí | Primera vez que el pedido está en **Procesando / Completado / En espera**, **menos de 30 min**, "seguimiento fiable" **apagado** | **Baja:** ≤ 54% de cobertura (R1), 1 en R2 | §3 |

**PII:**
- "Datos del cliente" y "Datos del pedido" están **apagados**: GTM4WP no expone a la clienta.
- `cartContent` (sin PII) está activado.
- El único dato personal es `pagePostAuthor` (§7).

---

## 3. Diseño de `purchase` confiable

**Objetivo:** distinguir la **compra observada por el navegador** del **pedido realmente pagado**, sin dos `purchase` por pedido y sin inventar deduplicación.

**Identificador común:** `transaction_id` (GA4) = `woo_order_id` (Woo) = `commerce_orders.woo_order_id` / `external_ref = <target>:<id>` (F360). GTM4WP no usa prefijo, así que la igualdad es directa. **No se crea otro ID.**

| Opción | Qué es | A favor | En contra | Veredicto |
|---|---|---|---|---|
| **R1 (recomendada ya): reconciliación offline** | GA4 se queda con el `purchase` de navegador **como señal**. F360 cruza por `transaction_id` contra Commerce Facts y reporta cobertura y huecos | Cero riesgo de duplicar. Commerce Facts sigue siendo la verdad. No toca la privacidad. Encaja con la regla 0 | GA4 sigue subcontando dentro de GA4 | **Sí** |
| R2: "Seguimiento fiable de compras" de GTM4WP | Emite `purchase` en la siguiente página de la misma sesión si la clienta no vio "pedido recibido" | Mejora la cobertura del navegador sin código | Sigue dependiendo del navegador y la sesión (frágil en el IAB de Instagram). Es experimental | Probar **después** de R1, midiendo con R1 |
| R3: `purchase` server-side por **GA4 Measurement Protocol** desde F360 al quedar el pedido pagado | Fuente real del pago | Envía el pago real | Google: el MP es para **"augment, not replace"** la colección del cliente, y su reporte es parcial. La **deduplicación por `transaction_id` es por usuario** (doc. oficial): sin el **mismo `client_id`** del navegador, MP + navegador = **dos compras**. Requiere capturar `_ga` / `client_id` en el pedido (dato seudónimo → **LEGAL_REVIEW**) | **No ahora.** Solo si legal aprueba y siempre con el mismo `client_id` + `transaction_id` |

**Regla:** mientras no exista R3 con `client_id`, **F360 nunca envía `purchase` a GA4**. Un pedido = como mucho un `purchase` de navegador (GTM4WP) + su Commerce Fact.

---

## 4. Reconciliación GA4 ↔ Commerce Facts (diseño, solo lectura)

**Datos de GA4** (Data API `runReport`, propiedad 519011849):
- **Dimensiones:** `transactionId`, `date`, `deviceCategory`, `browser`, `country`.
- **Métricas:** `ecommercePurchases`, `purchaseRevenue`.
- **Sin PII:** ninguna de esas dimensiones identifica a la persona.
- El revenue de GA4 viene en la moneda de la propiedad (MXN, convertido por GA4). Si la Data API expone la moneda original por evento está **UNVERIFIED**.

**Tabla F360 (propuesta, staging primero):** `f360.ga4_purchase_snapshots(target, transaction_id, ga4_date, purchases, revenue_property_ccy, device, browser, country, fetched_at, run_id)`. Se reemplaza por ventana y es idempotente.

**Vista `f360.ga4_purchase_reconciliation`** (FULL OUTER JOIN por `transaction_id` = `woo_order_id`):

| Salida | Definición |
|---|---|
| **Cobertura `purchase`** | Pedidos `countable` en Commerce Facts con ≥ 1 `purchase` en GA4 ÷ `countable` (por periodo, mercado y origen) |
| **Pagados ausentes en GA4** | `countable` sin `transaction_id` en GA4 |
| **GA4 sin hecho pagado** | `transaction_id` en GA4 cuyo hecho es `never_paid` / `cancelled` / `reversed`, o que no existe en F360 |
| **Duplicados** | `ecommercePurchases > 1` para un `transaction_id` (GA4 debería deduplicarlo por usuario; si aparece, hay dos usuarios o dos IDs) |
| **Discrepancia de revenue** | Solo pedidos **MXN**: \|`purchaseRevenue` − `order_total`\|. Otras monedas: solo conteo (sin FX, D-G1-03) |
| **Mercado** | Del hecho (`commerce_orders.market`) |
| **Contexto del navegador** | Del hecho (`browser_class` de la atribución Woo) y, en paralelo, el `browser` de GA4 (dimensiones separadas) |

**Frescura:** `measurement_source_health` muestra GA4 como VERIFIED / STALE según la última corrida exitosa (patrón G1).

**Implementación (G2-B técnico, staging):**
- migración + función de lectura en la Edge `f360-woo-sync` o un script programado;
- pruebas;
- **nunca** escribe en GA4.

---

## 5. Instrucciones para la Data API (antes de crear credenciales)

**Hecho importante:** tu usuario de Google **no es administrador** de la cuenta ni de la propiedad de GA4 (la UI redirige al abrir "Gestión de accesos"). **Para dar de alta la service account hace falta un Administrador** de la propiedad (doc. oficial: agregar o modificar usuarios requiere rol de Administrador).

| # | Dónde | Qué |
|---|---|---|
| 1 | Google Cloud Console | Proyecto (nuevo, p. ej. `fuxia360-analytics`, o uno existente de Fuxia) |
| 2 | APIs & Services → Library | Habilitar **Google Analytics Data API** |
| 3 | IAM & Admin → Service Accounts | Crear una service account (p. ej. `ga4-reader`). **Sin roles de GCP** |
| 4 | Service account → Keys | Crear una llave JSON. **Va solo a los secretos de Supabase de staging** (`GA4_SA_KEY_JSON`). **Nunca** al repo, al chat ni a un archivo compartido |
| 5 | GA4 → Admin → **Gestión de acceso de la propiedad** (lo hace un **Administrador**) | Agregar el correo de la service account con rol **Lector (Viewer)** en la propiedad **519011849**. Según Google, el lector "puede ver configuración y datos… vía la UI o las APIs" |
| 6 | Supabase (staging) | Secretos `GA4_PROPERTY_ID=519011849` y `GA4_SA_KEY_JSON` |
| 7 | F360 | Prueba: un `runReport` de 1 día con `transactionId` → conteo, sin persistir |

**Alternativa sin llave JSON:** OAuth de un usuario con acceso de lector (`gcloud auth application-default login` con el scope `analytics.readonly`). Sirve para pruebas manuales, no para una corrida programada.

---

## 6. Zona horaria de GA4: propuesta (NO aplicada)

| Punto | Detalle |
|---|---|
| Actual | (GMT−07:00) Tijuana: hora del Pacífico, **con horario de verano**. Hoy es UTC−7 y desde el 1 de noviembre será **UTC−8** |
| Propuesto | **(GMT−06:00) Ciudad de México** (sin horario de verano desde 2022), igual que Commerce Facts y `f360_list_sales` |
| Datos históricos | **No cambian.** Según la ayuda de Google, el cambio solo afecta datos **de ahí en adelante** |
| Día del cambio | Google advierte un **"flat spot" o "spike"** por el corrimiento. De Tijuana a CDMX el reloj avanza, así que se espera un día con **una hora menos** (hueco). Los reportes pueden mostrar la zona vieja un rato mientras se procesa. Cambiarla **como máximo una vez al día** |
| Comparación con Commerce Facts | **Antes del cambio:** los días de GA4 terminan 1 h (2 h desde noviembre) después que los de CDMX, así que hay desfase en los bordes del día. **Después:** alineados. La reconciliación de §4 es **por `transaction_id`**, así que no depende de la zona; la comparación **diaria** sí, y para fechas anteriores al cambio debe marcar "zona Tijuana" |
| Cambio exacto | GA4 → Admin → **Detalles de la propiedad** → *Zona horaria de informes*: **México** / **(GMT−06:00) Ciudad de México** → Guardar. Opcional: anotación "zona horaria a CDMX" ese día |
| Quién | Un usuario con permiso para editar la propiedad. El rol exacto (Editor o Administrador) está **UNVERIFIED**; tu usuario actual probablemente **no** puede |
| Riesgo / rollback | Riesgo bajo: hueco de 1 h el día del cambio. Rollback: volver a Tijuana (otro corrimiento) |

---

## 7. Corrección P0: correo expuesto en el `dataLayer`

| Punto | Hallazgo |
|---|---|
| Ajuste | GTM4WP → **Variables de página** → pestaña **Datos de la entrada** → **"Nombre del autor del post"** = **activado** |
| Campo que genera | `pagePostAuthor` (y `pagePostAuthors` si hay varios autores) = **nombre para mostrar** del autor de la página o entrada. En este sitio, ese nombre es el **correo de la cuenta de la agencia** |
| ¿Quién lo consume? | **Nadie.** GTM v8 no tiene variables de `dataLayer` (solo integradas: Event, URL, Host, Path, Referrer). T2 tiene *user properties* activadas, pero **ninguna definida**. Meta no lo usa |
| Cambio exacto recomendado | Desactivar **"Nombre del autor del post"** → Guardar cambios → **Purgar caché de SG** |
| Raíz (opcional) | En WordPress → Usuarios → la cuenta de la agencia: cambiar "Mostrar este nombre públicamente" a un nombre que no sea el correo (también se ve en otros lugares, como feeds o páginas de autor) |
| Verificación | `curl` de `/mx/` → `pagePostAuthor` ausente. GA4 sin cambios |
| Riesgo / rollback | Ninguno conocido (nadie lo consume). Rollback: volver a activarlo |

---

## 8. H-1: `view_item_list` (RESUELTO)

- **Emisor:** GTM4WP. Lo empuja al pintar listados, en lotes de 10.
- **Por qué llega a GA4 y a Meta:** la condición de T2 y T4 es la regex `view_item|add_to_cart|begin_checkout|purchase` **sin anclas**. GTM la evalúa como "contiene", así que `view_item_list` coincide con `view_item`.
  - **HECHO:** el predicado `_re` se vio en `gtm.js` v8.
  - No hay `gtag`, Google for WooCommerce ni otro emisor en el HTML de Home, Tienda ni ficha.
- **Consecuencia en Meta:** T4 también envía `view_item_list` al pixel. Cómo lo traduce la plantilla (¿ViewContent?) está **UNVERIFIED** → G2-META-0.
- **Corrección propuesta (GTM):** cambiar el trigger a una lista **explícita y anclada**. Por ejemplo, `^(view_item_list|select_item|view_item|add_to_cart|view_cart|begin_checkout|add_shipping_info|add_payment_info|purchase)$` para GA4. **Separar el trigger de Meta** (su lista la decide G2-META-0).

---

## 9. Plan G2-META-0 · Meta Measurement Audit (no ejecutado)

**Objetivo:** **Purchase = pago confirmado.** Decidir **qué integración sobrevive**. No se asume que GTM debe ser el emisor final.

| Paso | Cómo (solo lectura) | Necesita |
|---|---|---|
| 1 | Events Manager → pixel `951926154215387` → por evento (PageView, ViewContent, AddToCart, InitiateCheckout, Purchase): **método de conexión** (navegador / servidor), **integración** (Partner WooCommerce, GTM), **deduplicación** (% deduplicado, `event_id`) | Acceso de Mario a Business Manager |
| 2 | **Test Events** de Meta en **staging4**: necesita un pixel de prueba o el modo test. staging4 hoy tiene Meta desactivado; hay que decidir cómo | Decisión de Mario |
| 3 | Leer el código de **Meta for WooCommerce 3.7.6** (público): en qué hook envía Purchase por CAPI (hipótesis: creación del pedido en el checkout) y qué opciones lo controlan | Permiso para consultar código y docs de Meta |
| 4 | Mapear qué envía la plantilla de GTM T4 por cada evento GA4 (incluido `view_item_list`) | — |
| 5 | **Matriz:** evento × emisor (T3/T4, M4W navegador, M4W servidor) × `event_id` × deduplicación × momento (antes o después del pago) | — |
| 6 | **Decisión:** (a) M4W como único emisor (navegador + CAPI con `event_id` compartido) con Purchase en el pago; o (b) GTM navegador + CAPI con otra integración. Se quita el emisor que no sobrevive | Aprobación |
| 7 | Revisar la sincronización del **catálogo** (218 productos desde M4W) frente al catálogo de F360 (homologación) | — |

**No se desactiva nada hasta tener la matriz.**

---

## 10. Otros puntos registrados

- **Cart Abandonment Recovery (2.1.3), activo en producción:**
  - **corrige G0** (decía MISSING);
  - **LEGAL_REVIEW_REQUIRED** + **FUTURE LIFECYCLE AUDIT**;
  - **no se toca** y no se activa ninguna automatización nueva.
- **Medición mejorada: `form_start` / `form_submit`:**
  - **Volumen (R1):** `form_submit` 14,207 (5.4 por usuario) · `form_start` 12,754. **R2:** 1,938 / 1,540.
  - **Páginas donde ocurre:** **UNVERIFIED**. El informe requiere la dimensión `page_location` + `form_id`, que se obtendrá con la Data API (§4).
  - **Hipótesis:** el formulario de variaciones / add-to-cart de Woo, el buscador y los checkouts generan `form_submit` repetidos.
  - **Valor:** probablemente bajo (ya existen `add_to_cart` y `begin_checkout`). **Ruido:** alto.
  - **Decisión pendiente**, con datos de la Data API.
- **Acceso a GTM:**
  - **Cómo identificar al dueño:** quien tiene rol **Administrador de la cuenta de GTM** que contiene `GTM-W2PZG3L5`. No es visible sin acceso. **Inferencia (no un hecho):** el sitio lo administra la agencia que figura como autora de las páginas de WordPress (su dominio aparece en `pagePostAuthor`), así que lo más probable es que la agencia o Adrián administren GTM.
  - **Qué pedir** (doc. oficial de GTM): a nivel **cuenta**, rol **Usuario**; a nivel **contenedor**, **Leer** (*Read*): "puede ver tags, triggers y variables, sin hacer cambios", suficiente para auditar. Para aplicar §8 hace falta **Editar** (borradores) y quien tenga **Publicar** los publica. **Pedir Publicar solo si Mario va a publicar.**
  - **Alternativa:** que el administrador exporte el JSON de la versión publicada.
  - **No se intentó modificar ningún acceso.**

---

## 11. Lista exacta de cambios propuestos en producción (cada uno con aprobación individual)

| # | Cambio | Dónde | Quién | Riesgo | Rollback | Prioridad |
|---|---|---|---|---|---|---|
| P1 | Desactivar "Nombre del autor del post" + purgar caché | wp-admin → GTM4WP | Mario (admin WP) | Ninguno conocido | Reactivar | **P0** |
| P2 | Trigger GA4 (T2) con lista explícita y anclada (incluye `view_cart`, `add_shipping_info`, `add_payment_info`; `select_item` según §2) | GTM: workspace → versión → publicar | Quien tenga Publicar | Bajo: cambia los conteos de `view_item_list` y agrega eventos | Volver a la versión 8 (*Versions → Publish*) | P1 |
| P3 | Separar el trigger de Meta (T4) de GA4 | GTM | Ídem | Medio (Meta) | Versión 8 | Después de G2-META-0 |
| P4 | Zona horaria GA4 → CDMX | GA4 Admin | Editor / Admin de la propiedad | Bajo (hueco de 1 h el día del cambio) | Volver a Tijuana | P1 |
| P5 | Service account lectora en GA4 (Data API) | GCP + GA4 (Admin de la propiedad) | Admin GA4 | Bajo (solo lectura) | Quitar el usuario y borrar la llave | P1 |
| P6 | "Seguimiento fiable de compras" (GTM4WP) | wp-admin | Mario | Medio (experimental; posible compra duplicada en la siguiente página) | Desactivar | P2, **después de** R1 (§3) para medir |
| P7 | `view_item` solo en la carga (no en `found_variation`) | GTM (filtro `item_id == item_group_id`) o ajuste de GTM4WP | Quien tenga Publicar | Bajo | Versión anterior | P2 |
| P8 | Meta: emisor único + Purchase en el pago | Meta for WooCommerce / GTM | Tras G2-META-0 | **Alto** (afecta campañas activas) | Según la matriz | Bloqueado |
| — | **No tocar:** Cart Abandonment, Clarity, consentimiento (LEGAL_REVIEW) | — | — | — | — | — |

---

## 12. Fuentes oficiales consultadas

- Google Analytics Help, *Minimize duplicate key events with transaction IDs*: https://support.google.com/analytics/answer/12313109 (deduplicación por usuario, solo web, no `transaction_id` vacío).
- Google Analytics, *Measurement Protocol (GA4)*: https://developers.google.com/analytics/devguides/collection/protocol/ga4 ("augment… not to replace", reporte parcial).
- Google Analytics Data API, *Quickstart*: https://developers.google.com/analytics/devguides/reporting/data/v1/quickstart-client-libraries
- Google Analytics Help, *Access and data-restriction management* / *Add users*: https://support.google.com/analytics/answer/9305587, https://support.google.com/analytics/answer/9305788 (agregar usuarios requiere Administrador; el lector ve datos vía la UI o las APIs).
- Google Tag Manager Help, *User permissions*: https://support.google.com/tagmanager/answer/6107011
- Ayuda de Google Analytics sobre la zona horaria de la propiedad: solo afecta datos futuros, "flat spot o spike", máximo una vez al día. La página exacta no se pudo abrir (404 en la URL probada); el texto proviene del resultado de búsqueda de support.google.com. **Verificar** en Admin → Detalles de la propiedad (ayuda contextual) antes de aplicar P4.
