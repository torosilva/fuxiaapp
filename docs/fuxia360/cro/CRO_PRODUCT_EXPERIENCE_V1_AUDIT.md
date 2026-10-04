# CRO / Product Experience V1 — CRO-0 audit

**Fecha:** 2026-10-04. **Alcance:** solo STAGING. Es una auditoría: no se escribió código ni migraciones, ni se desplegó nada.

**Fuentes revisadas:**
- Documentación: `docs/fuxia360/` (00–10, INVENTORY_MODEL, growth/CUSTOMER_360_MODEL, omnichannel/APARTADO_GOLD, ops/BITACORA_2026-10-02_04).
- Migraciones `20260925…`–`20261007002300`.
- admin-web y fragmentos `tools/storefront/*`.
- Funciones `f360-*`.
- HTML real de staging4 (PDP Botas Largas, Tienda, home) y home pública de producción (solo lectura).
- Base de staging (solo lectura).

## A. Hechos clave encontrados

1. **No hay inventario certificado en ninguna ubicación.**
   - Ninguna tiene evento `OPENING_PHYSICAL_COUNT` ni cutover `completed`.
   - Bodega CDMX tiene un conteo de apertura **preliminar** abierto.
   - Polanco (7 pares) y San Jerónimo (13) recibieron mercancía por `RECEIPT`, sin conteo.
   - La señal de confiabilidad **ya existe implícitamente** (evento de apertura por ubicación o cutover `completed`, con su índice único), pero no está expuesta como "inventario certificado".
2. **Conflicto creado hoy por mí:** el fragmento de producto convierte "1 disponibles" en **"¡Último par!"** (`tools/storefront/f360-entrega-inmediata.html`, función `limpiarStock`, commit `Último par`). Viola el guardrail §14 del prompt.
3. **Tracking:**
   - Producción `/mx/` carga **GTM-W2PZG3L5**, **Meta Pixel** (`connect.facebook.net`) y **Microsoft Clarity**.
   - **staging4 no carga ninguno.**
   - El repo no tiene eventos de analítica (ni `dataLayer` ni `gtag`).
4. **Reseñas:** ya está instalado **Customer Reviews for WooCommerce** (`ivole`, v5.122):
   - Shortcode `cr-all-reviews-shortcode` con `custom_ratings: true`, `add_review`, compra verificada propia.
   - WP avisa que los **recordatorios por correo están desactivados en staging**.
   - Hoy hay 0 reseñas y el bloque se oculta en 0 (fragmento de producto).
5. **Datos de clienta:** `public.customers` ya tiene **`shoe_size`**. No existe ningún campo de **consentimiento** de marketing. Hay `push_tokens` (1) y `wishlists` (0).
6. **SiteGround Optimizer** activo en staging4: `defer` en unos 30 scripts y caché dinámica. Es el primer sospechoso para el navegador dentro de Instagram (IAB) y para scripts dependientes de jQuery.
7. **Página de producto:** no hay **sticky ATC** (solo la barra superior es sticky). La guía de tallas es una **imagen** (`Guia-de-tallas-01-1.jpg`).
8. **La operación no está probada de punta a punta:**
   - `online_store_shipments` y el push a la tienda existen y tienen pruebas de base de datos.
   - La **app de vendedoras no está conectada** (pantallas escritas, sin build de prueba; Android sin Firebase).
   - La promesa "Entrega inmediata en Zona Metropolitana" ya está publicada en staging4.

## B. Matriz

Estados: EXISTS, PARTIAL, MISSING, CONFLICT, BLOCKED. Dueño: F360, Woo, Bricks, C360, Growth.

| # | Capability | Estado | Fuente de verdad hoy | Qué existe | Qué falta de verdad | Dueño propuesto | Prio | Esfuerzo | Dependencias | Riesgo de regresión |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Fit / talla (calce por modelo) | MISSING | — | Tallas MX (−13) en PDP y Tienda; `customers.shoe_size` | Campos estructurados por modelo (calce, ancho, recomendación entre tallas, notas). Pantalla "Ajuste y talla" para Carolina. Presentación en PDP solo si hay datos | F360 (dato) + Bricks (presentar) | P1 | M | Que Carolina capture los datos por modelo | Bajo (aditivo) |
| 2 | Guía de tallas | PARTIAL | Imagen en Woo/Bricks | Link "Guía de tallas" (JPG). Hilo responde tallas (MX = −13, **solo staging**) | Guía en texto/tabla con la regla −13 y medida en cm por talla. Coherencia con Hilo en producción | F360 (tabla) + Bricks | P1 | S | Confirmar cm por talla (hoy la tienda usa 23/24/25/25.5/26/27) | Bajo |
| 3 | Reseñas | PARTIAL | Plugin **ivole** (Woo comments) | Plugin, formulario, compra verificada, fotos. Bloque oculto en 0 | Recordatorios desactivados en staging. Sin ligar reseña ↔ modelo F360 (reseña por producto Woo; legacy vs unido). Sin migrar reseñas de productos legacy al producto unido | Woo/ivole (captura) + F360 (vínculo modelo) | P1 | M | Decidir plugin vs nativo (pregunta 2). Unión de modelos | Medio (productos legacy ocultos tienen reseñas) |
| 4 | Fit feedback | MISSING | — | ivole tiene `custom_ratings` (posible pregunta "¿Cómo te quedó?") | Campo SMALL/TRUE/LARGE (+ ancho) por reseña, ligado a modelo/variante. Umbral mínimo para mostrar % | F360 (agregado) + ivole (captura) | P2 | M | #3. Umbral (ej. ≥ 20 respuestas) | Bajo |
| 5 | Persuasión en PDP | PARTIAL | F360 `description`, `short_description` | Descripción (justificada), entrega, cambios, Gold, Hilo | Bloques "Por qué te va a encantar", "Comodidad", "Materiales y detalles" como datos estructurados | F360 + Bricks | P2 | M | #1, #6, #7 | Bajo |
| 6 | Materiales | MISSING | Texto libre en descripción | — | Campos `materials` / `details` por modelo (y quizá por color) | F360 | P2 | S | Carolina captura | Bajo |
| 7 | Comodidad | MISSING | — | — | `comfort_notes` (plantilla, tacón, flexibilidad) | F360 | P2 | S | #1 | Bajo |
| 8 | Sticky ATC (móvil) | MISSING | — | Barra superior sticky (Bricks) | Barra fija al pasar el CTA: modelo, color, precio, talla, Agregar. Respeta estados inmediata / 5–7 / agotado | Bricks (fragmento) | P1 | S | Ninguna | Medio (convive con "Descarga la app", botón Hilo y burbuja de chat) |
| 9 | Confianza cerca del CTA | PARTIAL | Bricks (bloque de pagos) + fragmento | Pagos, envío gratis, "cámbialas", Gold | Consolidar en una línea compacta junto al CTA. Hoy está repartido | Bricks | P2 | S | — | Bajo |
| 10 | Disponibilidad | EXISTS | F360 `online_ats` (Bodega + tiendas − Gold) → Woo | Estados en PDP y filtros | Mostrarla **con guard de confiabilidad** (ver #11) | F360 | — | — | — | — |
| 11 | "Último par" / "Quedan X" | **CONFLICT** | Woo stock = `online_ats` (no certificado) | **Yo lo agregué hoy** ("¡Último par!") | Guard explícito `inventory_verified` por ubicación (apertura / cutover). Mostrar escasez solo si **todas** las ubicaciones que suman ATS están certificadas | F360 (guard) + Bricks | **P0** | S | Decisión 1 | Bajo (quitarlo) |
| 12 | 5–7 días (MTO) | EXISTS | `products.make_to_order` → Woo `backorders` | Copy aprobado, interruptor por modelo, `made_to_order` | — | — | — | — | — | — |
| 13 | Agotado | EXISTS (sin probar en vivo) | ATS = 0 y MTO off → backorders no | Lógica en sync y PDP | E2E en PDP con un modelo MTO off (hoy todos están en on) | F360 | P2 | S | — | Bajo |
| 14 | Gold (probártelas) | EXISTS | `f360.reservations` | Web (teléfonos de prueba) y BD | Envío real de códigos (WhatsApp). App de vendedoras sin conectar | F360 | — | — | Track app | — |
| 15 | Hilo | PARTIAL | `hilo-chat` (KB por palabras, app) + chat guiado web | Chat "a la medida" en PDP | Hilo web no responde preguntas libres (solo flujo guiado). KB de tallas corregida solo en staging | F360/Hilo | P2 | M | — | Bajo |
| 16 | A la medida | EXISTS | `f360.custom_requests` | Chat + admin + WhatsApp | — | — | — | — | — | — |
| 17 | Búsqueda | EXISTS | `f360_storefront_catalog` + `storefront_searches` | Sugerencias, categorías, populares y más buscados | Búsqueda **sin resultado** no se marca como señal de demanda (ver #26) | F360 / Growth | P2 | S | — | Bajo |
| 18 | Filtros | EXISTS | F360 catálogo | Categoría, color, talla MX, inmediata | Nombres de color duplicados (Negra/Negro, Cafe/Café): datos, no código | F360 (datos) | P2 | S | Carolina | — |
| 19 | Más vendidas | PARTIAL / CONFLICT leve | F360 ventas 60 días **+ histórico Woo 90 días** (`legacy_woo_map.sold_90d`) | Carrusel | Mientras F360 tenga poca historia se suma el histórico Woo (decisión interina documentada en la migración `002200`). El prompt dice "todos los canales / 60 días" | F360 | P2 | S | Decisión 3 | Bajo |
| 20 | Nuevas | EXISTS | 45 días o `new_override` | Carrusel e interruptor en admin | Hoy 0 nuevas: todo viene del catálogo legacy | — | — | — | — | — |
| 21 | Relacionados | PARTIAL | Woo (Bricks "Productos relacionados") | Responsivo (fix de hoy) | No usa F360 (mismo color/talla disponible, complementos) | Woo → F360 | P2 | M | — | Bajo |
| 22 | Avísame cuando llegue | MISSING | — | `wishlists` (app, 0 filas) | Intención (contacto, modelo, color, talla, mercado, UTM) **solo cuando ATS = 0 y MTO off**. Match al recibir inventario. Sin envío hasta resolver consentimiento | F360 + C360 | P1 | M | Consentimiento (falta campo) | Bajo |
| 23 | Carrito abandonado | MISSING | — | Woo sessions. Sin plugin | Diseño de captura + consentimiento | Woo → C360 / Growth | P2 | M | Consentimiento, identidad | Medio (privacidad) |
| 24 | UGC | MISSING | — | Fotos en reseñas ivole | Modelo + flujo de aprobación (solo diseño) | F360 / C360 | P2 | S (diseño) | Permisos | — |
| 25 | Navegador de Instagram / Facebook (IAB) | **BLOCKED** (sin diagnóstico) | — | Nada probado | Matriz iOS/Android × IAB/navegador y telemetría técnica. Sospechosos: SG Optimizer (defer/combine), cookies de sesión Woo en IAB, redirecciones de Mercado Pago/ePayco/3DS | Woo / Bricks / F360 (telemetría) | **P0** | M | Teléfonos reales (iPhone y Android con Instagram). Checkout de staging con pasarela en modo prueba | Alto si se tocan caché o checkout |
| 26 | Analítica / eventos | PARTIAL / BLOCKED | GTM-W2PZG3L5 (**solo producción**), Pixel, Clarity | Producción ya mide (contenedor no auditado) | Auditar el contenedor GTM (qué eventos GA4 existen). Contenedor o entorno de staging. `dataLayer` desde los fragmentos con nombres GA4 estándar | Growth (GTM) + Bricks (dataLayer) + C360 | P1 | M | **Acceso al contenedor GTM** | Medio |

## C. Contradicciones prompt ↔ realidad (NO resueltas)

1. **"Último par" ya está publicado en el fragmento de producto** (lo agregué hoy). Choca con §10 y §14, porque ninguna ubicación está certificada.
2. **"Entrega inmediata en Zona Metropolitana" ya es promesa pública en staging4**, pero §15 pide demostrar antes el flujo de punta a punta. La app de vendedoras no está conectada y no hay acuse "envíalo hoy" probado. La promesa también se basa en inventario no certificado.
3. **Más vendidas** suma el histórico Woo de 90 días como respaldo, y el prompt dice "todos los canales / 60 días".
4. **Reseñas:** el prompt dice "no instalar plugin", pero ya hay uno instalado (ivole). La decisión es si se **usa** como base.
5. **Analítica:** el prompt pide no duplicar eventos GA4, pero no puedo ver qué eventos dispara GTM-W2PZG3L5 sin acceso a GTM. Staging no tiene GTM, así que no se puede probar en staging tal como está.
6. **Hilo:** la respuesta de tallas (MX = −13) está corregida **solo en staging**. La app de producción sigue diciendo "cm = talla mexicana".
7. **Unión de modelos y reseñas/SEO:** los productos por color quedaron privados. Sus reseñas (si las hay en producción) y URLs no se migraron al producto unido, porque faltan las redirecciones (CSV listo, no importado).

## D. Preguntas de negocio necesarias

1. **"Último par":** ¿lo quito ya del fragmento de staging hasta que exista el guard de inventario certificado? (Recomiendo sí.) ¿Y "Entrega inmediata" se mantiene en staging mientras se demuestra el flujo de punta a punta, o se suaviza?
2. **Reseñas:** ¿usamos el plugin existente (ivole) para capturar y mostrar, y F360 solo guarda el vínculo modelo/variante y el *fit feedback*? ¿O reseñas nativas en F360?
3. **Más vendidas:** ¿se mantiene el respaldo del histórico Woo 90 días mientras F360 junta 60 días de ventas reales?
4. **Analítica:** ¿quién tiene acceso a **GTM-W2PZG3L5**? ¿Creamos un entorno de staging en ese contenedor?
5. **Ajuste y talla:** ¿Carolina usa el concepto de **horma**? ¿Qué categorías de calce maneja hoy (talla exacta / chico / grande)?

## E. Orden propuesto (unidades pequeñas)

| Orden | Unidad | Por qué |
|---|---|---|
| 1 | **CRO-5a · Guard de inventario certificado** (+ quitar "Último par") | P0. Hoy hay copy que viola el guardrail |
| 2 | **CRO-IAB-0 · Diagnóstico Instagram/Facebook** (paralelo, sin cambios) | P0. Matriz en teléfonos reales + telemetría técnica mínima |
| 3 | **CRO-OPS · E2E de entrega inmediata** (pedido → tienda → push → "envíalo hoy" → acuse) | Respalda la promesa ya publicada; depende de la app de vendedoras |
| 4 | **CRO-1A · Fit Intelligence** (BD + admin "Ajuste y talla") | P1 |
| 5 | **CRO-1B · Presentación de fit + guía de tallas en texto** | P1, solo si hay datos |
| 6 | **CRO-4 · Sticky ATC móvil** | P1, bajo esfuerzo |
| 7 | **CRO-8 · Analítica** (auditar GTM → dataLayer) | P1, requiere acceso |
| 8 | **CRO-2A/B · Reseñas sobre ivole + fit feedback con umbral** | P1/P2 |
| 9 | **CRO-6A · Avísame cuando llegue** (+ campo de consentimiento) | P1 |
| 10 | **CRO-3 · Campos de persuasión** (materiales, comodidad) | P2 |
| 11 | **CRO-6B · Carrito abandonado (diseño)** · **UGC (diseño)** · relacionados F360 | P2 |

**Pruebas por unidad:** permisos de BD, idempotencia, MX/CO, stock > 0 / 0 + MTO / 0 sin MTO, producto legacy vs unido, caché, sincronización Woo, móvil y escritorio. En IAB solo se declara PASS con prueba real en dispositivo.
