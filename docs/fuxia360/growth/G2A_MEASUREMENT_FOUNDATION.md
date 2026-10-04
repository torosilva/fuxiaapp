# G2-A · Measurement Foundation (sin acceso a GTM)

**Fecha:** 2026-10-04. **Rama:** `fuxia-360`.

**Alcance autorizado (Mario):**
- A. Measurement Contract V1;
- B. Clasificación fuente / canal V1;
- C. Gobierno de UTMs;
- D. Salud de las fuentes de medición.

**Sin:** código de producción, deploy, GTM, GA4, Meta / CAPI, Clarity, Campaign 360 ni `dataLayer` en staging4. G1 (Commerce Facts) queda congelado (commit `e025ccf`).

**Documentos:**

| Documento | Rol |
|---|---|
| `growth/G2_MEASUREMENT_CONTRACT.md` | **A.** Contrato V1: fuente única de verdad de los eventos. CRO lo implementa; Growth lo consume |
| Este documento | **B, C, D** + accesos + consentimiento + qué queda listo para G2-B |
| `cro/08_ANALYTICS.md` | Conserva el bloqueo de GTM y apunta al contrato (su tabla anterior queda reemplazada) |

---

## 1. Clasificación fuente / canal V1 (`channel_rules_v1`)

### 1.1 Principios

- **Entradas, que no se modifican:** los valores originales de `f360.commerce_woo_attribution`:
  - `source_type`, `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term`, `utm_id`, `referrer_host`.
- **Salidas, siempre derivadas** (una vista, nunca columnas en los hechos):
  - `channel_group`, `platform`, `channel_detail`;
  - `channel_rule_id` (qué regla aplicó) y `channel_rules_version`.
- **Separación:** SOURCE, MEDIUM y CAMPAIGN se conservan tal cual. `channel_group` es una interpretación que se puede recalcular.
- **Se puede recalcular:** cambiar las reglas implica una nueva versión (`channel_rules_v2`). Los hechos no se tocan; la vista vieja puede convivir para comparar.
- **No solo Meta:** la plataforma es una dimensión aparte: `instagram`, `facebook`, `tiktok`, `google`, `pinterest`, `whatsapp`, `email`…
- **Alias históricos** sin reescribir datos: `ig` → instagram, `fb` → facebook, `l.instagram.com` → instagram.

### 1.2 Reglas (en orden; gana la primera que coincide)

**Normalización previa:**
- todo a minúsculas y sin espacios;
- `social_hosts` = `instagram.com`, `l.instagram.com`, `facebook.com`, `m.facebook.com`, `l.facebook.com`, `lm.facebook.com`, `tiktok.com`, `pinterest.com`, `t.co`, `x.com`;
- `search_hosts` = `google.*`, `bing.*`, `yahoo.*`, `duckduckgo.*`, `ecosia.*`;
- `mail_hosts` = `com.google.android.gm`, `mail.google.com`, `outlook.live.com`;
- `paid_media` = `paid`, `cpc`, `ppc`, `paid_social`, `paidsocial`, `cpm`, `display`;
- `social_sources` = `ig`, `instagram`, `fb`, `facebook`, `meta`, `tiktok`, `pinterest`.

| # | `channel_rule_id` | Condición | `channel_group` |
|---|---|---|---|
| R0 | `no_attribution` | Sin atribución, o `source_type` vacío / `admin` / `unknown` | **UNKNOWN** |
| R1 | `email` | `utm_medium` ∈ (`email`, `newsletter`) o `referrer_host` ∈ `mail_hosts` | **EMAIL** |
| R2 | `whatsapp` | `utm_medium` o `utm_source` ∈ (`whatsapp`, `wa`) o `referrer_host` ∈ (`wa.me`, `api.whatsapp.com`, `web.whatsapp.com`) | **WHATSAPP** |
| R3 | `paid_social` | `utm_medium` ∈ `paid_media` **y** `utm_source` ∈ `social_sources` | **PAID_SOCIAL** |
| R4 | `other_paid` | `utm_medium` ∈ `paid_media` (otra fuente) | **OTHER_PAID** |
| R5 | `organic_social` | `utm_medium` ∈ (`social`, `organic_social`) o `utm_source` ∈ `social_sources` o `referrer_host` ∈ `social_hosts` | **ORGANIC_SOCIAL** |
| R6 | `organic_search` | `source_type = organic` o `utm_medium = organic` o `referrer_host` ∈ `search_hosts` | **ORGANIC_SEARCH** |
| R7 | `direct` | `source_type = typein` o `utm_source = (direct)` o `referrer_host` del propio sitio (`*.fuxiaballerinas.com`) | **DIRECT** |
| R8 | `referral` | `source_type = referral` (cualquier otro host) | **REFERRAL** |
| R9 | `unmapped_utm` | UTM con una combinación no reconocida | **UNKNOWN** (bandera `utm_noncompliant`) |

**Dimensiones adicionales:**
- `platform`: instagram / facebook / tiktok / google / … según la fuente o el host.
- `channel_detail`: por ejemplo, `instagram_bio` cuando `utm_content = link_in_bio`, `gmail_app`, `organic_google`.

**Casos a confirmar (no se adivinan):**
- `app.atomchat.io` (1 pedido) queda en **REFERRAL**. Si Fuxia lo usa como plataforma de WhatsApp, pasa a WHATSAPP en `v2`. **Pregunta para Mario.**
- `com.google.android.gm` (app de Gmail) va a EMAIL por R1, con `channel_detail = gmail_app`.

### 1.3 Validación de solo lectura sobre los 82 pedidos de staging4 (consulta `READ ONLY`, sin escribir)

| channel_group | platform | Pedidos |
|---|---|---|
| PAID_SOCIAL | instagram | 20 |
| PAID_SOCIAL | facebook | 3 |
| ORGANIC_SOCIAL | instagram | 21 (incluye `link_in_bio` y referrals de `l.instagram.com`) |
| ORGANIC_SOCIAL | facebook | 1 |
| DIRECT | — | 20 |
| ORGANIC_SEARCH | — (google) | 14 |
| EMAIL | — (gmail_app) | 1 |
| REFERRAL | — | 1 (`app.atomchat.io`) |
| UNKNOWN | — | 1 (pedido de prueba por API, sin atribución) |

**Implementación (G2-B):**
- Vista `f360.commerce_channel_v1` sobre `commerce_woo_attribution`, más una función `f360.classify_channel_v1(...)` inmutable.
- Pruebas por regla, incluidos los alias históricos.
- Solo lectura vía las RPCs de owner / operator. **No se creó en G2-A.**

---

## 2. Gobierno de UTMs (convención oficial Fuxia, campañas futuras)

**Reglas generales:**
- Minúsculas, sin acentos ni espacios (guion medio), solo `[a-z0-9-_]`.
- **Nunca PII.** Nada de teléfonos, correos ni nombres de clientas: los links personalizados de WhatsApp o Hilo usan IDs de campaña, no datos de la persona.
- **Los valores históricos no se reescriben** (`ig`, `fb`, numéricos). El clasificador los traduce con alias.

| Parámetro | Regla | Valores permitidos / formato | Ejemplo |
|---|---|---|---|
| `utm_source` | **Quién envía el tráfico** (plataforma o remitente) | `instagram`, `facebook`, `tiktok`, `google`, `pinterest`, `whatsapp`, `email` (o el nombre del proveedor: `resend`, …), `hilo`, `influencer-<handle>`, `qr-<lugar>` | `instagram` |
| `utm_medium` | **Tipo de canal** (vocabulario cerrado) | `paid_social`, `social` (orgánico), `cpc`, `display`, `email`, `whatsapp`, `referral`, `influencer`, `qr`, `sms`, `app` | `paid_social` |
| `utm_campaign` | **Nombre legible y estable** de la campaña | `{aaaamm}-{mercado}-{objetivo}-{tema}`. Objetivo ∈ `conv`, `traf`, `alc`, `ret` | `202611-mx-conv-buen-fin` |
| `utm_id` | **ID externo de la campaña** en la plataforma (opaco) | Valor dinámico de la plataforma, si lo soporta | `120251089837130626` |
| `utm_content` | **Creativo o anuncio** | `{formato}-{creativo}` o el ID dinámico del anuncio. `link_in_bio` reservado para la bio de Instagram | `reel-macarena-nude` |
| `utm_term` | **Conjunto de anuncios / audiencia** (o keyword en búsqueda) | Slug o ID dinámico | `lookalike-compradoras` |

**Para que Campaign 360 pueda relacionar UTM → ID externo → campaña → gasto → Commerce Facts:**
1. `utm_id` = ID externo, que es la llave técnica de la campaña.
2. `utm_campaign` = slug, la llave humana. Campaign 360 guardará los dos.
3. Hoy el **histórico** trae en `utm_campaign` un número igual a `utm_id`. Queda como **valor externo opaco**. **No se asume** que es un ID de Meta hasta que Campaign 360 lo confirme con la plataforma.
4. Un UTM fuera de la convención no se corrige: se marca `utm_noncompliant` (R9) y se reporta.
5. **Plantillas por plataforma** (las configura quien administre cada cuenta; no se aplica nada desde Fuxia 360): se documentan en G3. **No se tocan Meta ni Google** en G2.

---

## 3. Salud de las fuentes de medición

Mismo patrón que G1 (`f360.commerce_source_health`), extendido a un **registro de fuentes**:

| Fuente | Estado hoy | Por qué | Cómo se medirá (G2-B y siguientes) |
|---|---|---|---|
| **Woo Commerce Facts** | **VERIFIED** (staging) | Poll cada 15 min con éxito (G1) | Ya implementado: STALE después de 60 min sin un poll exitoso |
| **Woo Order Attribution** | **VERIFIED** (staging) | 81 de 81 pedidos del checkout | Cobertura % por periodo: menos de 95% de los pedidos del checkout → PARTIAL |
| **GTM** | **UNVERIFIED** | Contenedor sin auditar (sin acceso) | Auditoría + versión publicada conocida |
| **GA4** | **UNVERIFIED** | No conectado; sin acceso | Data API: última consulta exitosa → VERIFIED; vieja → STALE; `purchase` contra `countable` fuera de tolerancia → CONFLICTED |
| **Meta** | **CONFLICTED** | DQ-01: marca Purchase en 23 pedidos no pagados | Fuera de alcance. Se queda CONFLICTED hasta la auditoría de Meta / CAPI |
| **Clarity** | **UNVERIFIED** | No conectado; sin investigar | Fuera de alcance |

**Definiciones (iguales para todas las fuentes):**

| Estado | Significado |
|---|---|
| **VERIFIED** | Conectada, sincronizada en su ventana y reconciliada con Commerce Facts dentro de la tolerancia |
| **PARTIAL** | Conectada, pero con cobertura incompleta (consentimiento, bloqueadores, campos faltantes) |
| **UNVERIFIED** | No conectada o nunca validada. **No se muestran cifras como confiables** |
| **STALE** | Conectada, pero sin sincronización exitosa en su ventana |
| **CONFLICTED** | Contradice a Commerce Facts más allá de la tolerancia (p. ej., compras de pedidos no pagados) |

**Implementación (G2-B):**
- Vista `f360.measurement_source_health`: Woo con su salud real; GA4, GTM, Meta y Clarity como filas declarativas con su estado y motivo, hasta que exista conexión.
- **Nunca** se marca como conectada una fuente que no lo está.

---

## 4. Checklist exacta de accesos

### 4.1 GTM (contenedor `GTM-W2PZG3L5`)

| # | Qué conseguir | Detalle |
|---|---|---|
| 1 | **Quién administra** la cuenta de GTM dueña de `GTM-W2PZG3L5` | Adrián, la agencia o Carolina. Nombre y contacto |
| 2 | **Acceso al contenedor** para el correo de Google de Mario | A nivel **contenedor**: permiso **Leer** (*Read*), suficiente para auditar tags, triggers, variables, versiones y la configuración de consentimiento. **No** pedir *Publicar* para la auditoría |
| 3 | **Permiso adicional solo si se crea un entorno de staging** | Crear Environments o un contenedor aparte requiere más permisos (**por verificar** el nivel exacto en la ayuda oficial de GTM antes de pedirlo; ver §4.3) |
| 4 | **Alternativa sin acceso** | El administrador exporta el contenedor (Admin → *Export container*, JSON de la versión **publicada**) y lo comparte. La auditoría se puede hacer sobre ese archivo |
| 5 | **Sitios que cargan el contenedor** | Qué dominios y rutas (`/mx/`, `/co/`, raíz) y si hay otros contenedores o plugins (*Google for WooCommerce*, *Facebook for WooCommerce*, PixelYourSite…) que también envían eventos |
| 6 | **Versión publicada** y fecha | Para fijar la línea base de la auditoría |
| 7 | **Decisión sobre staging** | ¿Entorno de GTM para staging4 o contenedor aparte? (Hoy staging4 no carga GTM.) |

### 4.2 GA4 (es otro producto: **tener GTM no da acceso a GA4**)

| # | Qué conseguir | Detalle |
|---|---|---|
| 1 | **Quién administra** la propiedad GA4 | Puede ser otra persona que la de GTM |
| 2 | **Acceso a la propiedad** para el correo de Mario | Rol **Viewer** (lector) a nivel **propiedad**: suficiente para leer reportes y la configuración |
| 3 | **Property ID** (numérico) | Admin → *Property details*. Lo requiere la Data API |
| 4 | **Measurement ID** (`G-XXXXXXX`) | Admin → *Data streams* → stream web. Para comprobar qué ID usa la etiqueta de GTM |
| 5 | **Data streams** | Cuántos y para qué dominios / rutas |
| 6 | **Acceso por API (Data API)** | Un proyecto de Google Cloud con **Google Analytics Data API** habilitada, una **service account** y su correo agregado a la propiedad GA4 con rol **Viewer**. Alternativa: OAuth del usuario. La llave de la service account **nunca** va al repo |
| 7 | **Configuración relevante** | Moneda y zona horaria de reporte, retención de datos, eventos de ecommerce recibidos (¿`purchase`?), *enhanced measurement*, Google Signals, conversiones marcadas |
| 8 | **Opcional, futuro** | Si existe la vinculación con BigQuery (export) |

### 4.3 Verificación pendiente

- **GTM:** el nivel de permiso exacto para crear Environments no lo verifiqué en la documentación oficial de Google. Se revisa en G2-B antes de pedirlo, si Mario autoriza consultar la ayuda de Google.
- **GA4:** que el rol Viewer basta para la Data API también se confirma en G2-B con la documentación oficial.
- No se asumió acceso a ninguna API.

---

## 5. Dependencias de consentimiento (LEGAL_REVIEW_REQUIRED sigue abierto)

**Nada se activa hasta que legal resuelva el alcance:** tags nuevos, Meta, Clarity, tracking de marketing ni Consent Mode.

| Depende del consentimiento | Elemento |
|---|---|
| Sí | Enviar eventos a GA4, Meta Pixel / CAPI, Clarity, cualquier tag nuevo de marketing, avísame / carrito abandonado / lifecycle |
| A definir por legal | Telemetría técnica propia (CRO-IAB). **Cookies `sbjs_*` de Woo Order Attribution, ya activas en producción** (pregunta nueva de G2-A). El uso analítico de Commerce Facts |
| No (operación) | Registrar el pedido y su dinero sin PII. El `push` local al `dataLayer`, mientras no tenga destino |

Detalle por evento en el contrato §8.

---

## 6. Vínculo con Commerce Facts

| Del contrato | A Commerce Facts | Uso |
|---|---|---|
| `purchase.transaction_id` | `commerce_orders.woo_order_id` | **Solo reconciliación:** cobertura de la medición (% de pedidos `countable` con `purchase` observado). Nunca revenue |
| `items[].item_variant` | `commerce_order_lines.woo_variation_id` → `variant_id` | Funnel por variante: selección de talla → carrito → venta real, **en agregado** |
| `items[].item_id` | `woo_product_id` | Demanda por modelo |
| `items[].item_category` | `category_key` | Taxonomía común (calzado y accesorios) |
| `market`, `currency` | Mismas reglas que `commerce_orders.market` / `currency_original` | Cortes comparables. Nunca se mezclan monedas |
| `browser_context` | `commerce_woo_attribution.browser_class` | Misma clasificación |
| Canal (sesión de GA4, futuro) | `channel_group` V1 (Woo first-party) | Columnas **separadas** con su `provenance`. Nunca se suman ni se reemplazan |

---

## 7. Qué queda listo para G2-B

| Listo (diseñado y validado) | G2-B (con autorización; no necesita GTM) | Bloqueado |
|---|---|---|
| Contrato V1 (eventos, parámetros, dedup, PII, versionado) | Vista `f360.commerce_channel_v1` + pruebas por regla (staging) | Auditoría de GTM (acceso §4.1) |
| Reglas de canal V1 validadas en solo lectura (82 pedidos) | Vista `f360.measurement_source_health` (filas declarativas + Woo real) | GA4 Data API (acceso §4.2) |
| Convención de UTMs | Validador de UTMs (`utm_noncompliant`) en SQL | Cualquier destino de eventos (legal) |
| Checklist de accesos | Implementar el `dataLayer` en los fragmentos **detrás de una bandera apagada**, con pruebas locales, **sin desplegar** a staging4 (requiere la autorización de cambios al storefront y coordinar con CRO) | Meta / CAPI / Clarity (fuera de alcance) |
| Separación fuente / navegador | — | Decisión `app.atomchat.io` (Mario) |
