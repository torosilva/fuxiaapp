# Fuxia Storefront V1 · Closeout audit

**Fecha:** 2026-10-05.

**Tipo: solo lectura.** No se cambió código, staging4, WordPress, plugins, Supabase, GTM, Meta ni producción.

**Evidencia usada:**
- documentos y código del repo (`tools/storefront/*`, `docs/fuxia360/cro/*`, `growth/*`, `ops/*`, funciones Edge);
- consultas SELECT de solo lectura a staging Supabase;
- GET anónimos a staging4 y a producción (HTML y Store API pública).

**Incorporada (§M):** la respuesta de la sesión `fuxiaapp-67`, dueña de los snippets de checkout, ligas de pago y video, sobre qué está *instalado realmente* en staging4.

> **Regla de lectura.**
> - "DONE" = construido y con evidencia en staging4.
> - **Nada de lo F360 del storefront está en producción.** Producción no tiene Hilo, sticky ATC ni panel post-ATC; tiene Joinchat y el top bar.
> - "PASS en teléfono real" solo existe para Instagram Android (#4111, #4114).

## 0. Decisiones de Mario (2026-10-05) — cierran los CONFLICT de promesa, cambios y piloto

1. **Promesa de entrega** (una sola, en todos lados: PDP, checkout, gracias, Hilo, admin, top bar, docs):
   - **Talla y color en existencia** → **"Entrega Inmediata en Zona Metropolitana"**.
   - **Sin existencia** de la talla o el color → **se hace a la medida** de lo que la clienta requiera y **se entrega en 10 días hábiles**.
   - "5 a 7", "3 a 5" y "1 a 3" quedan eliminados.
   - Abierto: el tiempo para envíos *con existencia fuera de la Zona Metropolitana* y para CO. Mientras tanto: "te confirmamos el tiempo al hacer tu pedido".
2. **Política de cambios:**
   - **30 días;**
   - **no hay reembolsos ni devoluciones;**
   - **descuento directo en el zapato → sin cambio;**
   - **descuento por cupón → sí tiene cambio.**
   - Lo que dice Hilo hoy está mal y se quita.
3. **Macarena** fue un producto de pruebas, no es de Fuxia. **Los pilotos salen solo de productos que ya están en Fuxia 360.** Ese catálogo es el que Carolina está actualizando para producción.

### 0.1 Hilo (HiloLabs, repo `~/Documents/GitHub/fuxia-chatbot`, tabla `kb_articles`) — respuestas a corregir

**Estado:**
- El parche (a) del 2026-10-04 ya corrigió tallas, "apretadas", defectuoso, "¿puedo devolver?" y a la medida.
- **Siguen mal en vivo:** las respuestas de abajo. Además el parche (a) dejó "los pares con descuento no tienen cambio" sin el matiz del cupón.

**Bloqueo:** el permiso para escribir en ese repo fue denegado en esta sesión. Mario decide si lo autoriza, o si lo aplica él con el mismo patrón de `scripts/kb_patch_2026_10.py`: `--dry-run`, luego `--apply --backup`.

| Pregunta en el KB | Respuesta nueva |
|---|---|
| ¿Qué pasa si pido una talla y no me quedó? | Tienes 30 días desde que recibes tu pedido para cambiarlas por otra talla, color o modelo disponible, sin uso y con su caja. No hacemos devoluciones ni reembolsos de dinero. Tú nos llevas o envías el par a tu tienda Fuxia más cercana y nosotros te enviamos el nuevo sin costo. Los pares con descuento directo en el precio no tienen cambio; si usaste un cupón (por ejemplo BIENVENIDA10), tu par sí tiene cambio dentro de los 30 días. |
| ¿Puedo devolver si no me quedan? | No hacemos devoluciones de dinero, pero sí cambios: tienes 30 días… (igual que arriba, con el matiz de descuento y cupón). |
| ¿Cuánto tiempo tengo para devolver? | No hacemos devoluciones ni reembolsos. Para cambios tienes 30 días desde que recibes tu pedido, sin uso y con su caja. (Matiz de descuento y cupón.) |
| ¿Quién paga el envío de la devolución? | No hacemos devoluciones, solo cambios. El envío del cambio es mitad y mitad: tú nos llevas o envías el par a tu tienda Fuxia más cercana y nosotros te enviamos el nuevo sin costo. |
| ¿Cómo recibo el reembolso? | No hacemos reembolsos ni devoluciones de dinero. Lo que sí hacemos son cambios por otra talla, color o modelo disponible dentro de los 30 días, sin uso y con su caja. Si recibiste un par con defecto, lo resolvemos con un cambio sin costo. |
| ¿Puedo cambiar por otro modelo? | Sí, dentro de los 30 días, sin uso y con su caja, por otro modelo disponible; si tiene otro precio, ajustamos la diferencia. (Matiz de descuento y cupón.) |
| ¿Puedo cambiar un par que compré con descuento? | Los pares con descuento directo en el precio no tienen cambio. Si usaste un cupón (por ejemplo BIENVENIDA10), tu par sí tiene cambio dentro de los 30 días. |
| ¿Cuánto tarda el envío en México? | Si tu talla y color están en existencia: Entrega Inmediata en Zona Metropolitana. Si no están en existencia, te los hacemos a la medida y se entregan en 10 días hábiles. Para envíos fuera de la Zona Metropolitana te confirmamos el tiempo al hacer tu pedido. |

**Pendientes de validar** (no se tocan sin Carolina o Mario):
- "memory foam", "cómodas 8–10 horas" y "piel de subproducto / en proceso de certificación";
- lealtad: "1 punto por peso, 100 pts = 10 MXN", que no coincide con la regla F360 de 100 pts por par;
- "¿Puedo cancelar mi pedido?": dice "reembolso completo", que choca con "no hay reembolsos".

**Además:** `kb/seed.json` todavía trae los textos viejos. Si alguien re-ingesta el KB, se reintroducen. Hay que actualizarlo junto con el parche.

### 0.2 Storefront (snippets de la sesión 67) — textos a alinear
- `pagina-cambios.html:58`: "Pares con descuento no tienen cambio" → descuento directo sin cambio; cupón sí.
- La barra de confianza `f360-compra.html:361` ("cámbialas") queda bien para cupón; revisar que no lo prometa en descuento directo.
- **Re-pegar** `f360-entrega-inmediata.html` en staging4: la versión instalada todavía dice "5 a 7".
- **Top bar** (Adrián, también en producción): "ENTREGA INMEDIATA EN LA MAYORÍA DE NUESTROS MODELOS" → "Entrega Inmediata en Zona Metropolitana".
- Línea de 10 días en `/co/`: pendiente la regla de CO.

---

## 1. Matriz única

Leyenda de estado: DONE · PARTIAL · MISSING · CONFLICT · BLOCKED · N/A.
Dueños: Car = Carolina · Adr = Adrián · 67 = sesión fuxiaapp-67 · c4 = esta sesión.

| Unidad | Capacidad | Estado | Fuente de verdad | Implementación existente | Gap | Dependencia | Negocio | Tec | Riesgo | Esfuerzo | Acción propuesta | Prod |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DISC | Home | MISSING | — | Solo el teaser de Hilo (`f360-hilo-global.html:309`) y el top bar de Adrián | No hay home F360; el top bar promete "ENTREGA INMEDIATA" (ver CRO-6) | CRO-6 | Mario | Adr | M | M | Fuera del closeout técnico: solo alinear el copy del top bar con la matriz de promesa | Sí (copy del top bar) |
| DISC | Shop / Tienda + búsqueda + filtros | DONE | `f360_storefront_catalog` | `tools/storefront/f360-tienda.html`; `f360-store-reserve` `catalog` | `woo_staging4` hardcoded (`handler.ts:58-66`); las búsquedas sin resultado no se guardan como demanda | — | Car | 67 | M (hardcode al pasar a prod) | S | Parametrizar el canal antes de producción; guardar las búsquedas con 0 resultados | No |
| DISC | Nuevas | DONE (vacío) | regla 45 d / `new_override` | catálogo | 0 productos nuevos (todo es legacy) | catálogo | Car | — | B | — | Ninguna; se llena con productos F360 | No |
| DISC | Más vendidas | PARTIAL / CONFLICT | `legacy_woo_map.sold_90d` + F360 60 d | `06_INVENTORY_CONVERSION.md:103-111` | El retiro automático del histórico (`bestseller_history_ready`) no está construido; ventanas 60/90 d mezcladas | Commerce Facts prod | Mario | c4 | M | S | Una sola regla documentada (Bitácora dec. 9) | No |
| DISC | Cambios | DONE / CONFLICT | `pagina-cambios.html` (pág. 4080) | staging4 | El footer dice "Cambios y devoluciones" (Adr); el WhatsApp es solo el de MX, también en /co/; **Hilo (hilo-chat) dice 15 días con reembolso y la página dice 30 días, solo cambio** | Adr | Car | Adr/67 | **A** (promesa legal contradictoria) | S | Una sola política; quitar los textos viejos de Hilo | Sí (footer) |
| PDP | Modelo unificado color × talla | PARTIAL | `f360.products` + `mapping.ts` | 7 modelos unidos | 4 reintentos; 5 bloqueados por Carolina; **sin redirecciones = 404 en las ligas viejas** | Car, Adr | Car | c4/67 | A (SEO / 404) | S | Reintentar; importar las redirecciones | Sí al publicar |
| PDP | Fotos por color, stock por variante, selector | DONE | Woo variations (publicadas por F360) | `f360-selector-color.html` | La guía de tallas es un JPG fijo; un twin file conserva el toggle "Colombia/CM" | CRO-3A | Car | 67 | B | S | Reemplazar la guía por el bloque Fit (CRO-3A) | No |
| PDP | MX / CO | DONE (emulado) | talla MX = talla − 13 | `05_MOBILE_IAB_RESULTS.md` | Falta en teléfono real CO | CRO-7 | — | 67 | M | S | Incluirlo en la matriz CRO-7 | No |
| PDP | Macarena (producto de aceptación) | **CONFLICT** | — | Woo 3621 en staging4 | **No existe en `f360.products`**; su línea de venta `F360-MACARENA-NUDE-37` no se resuelve; no existe en producción | decisión | Mario | c4 | A (el piloto no es F360) | S | Decidir: crear Macarena en F360 (publicarla de verdad) o elegir otro piloto F360 (ver §F) | No |
| CRO-3A | Fit / talla / horma / ancho | MISSING | — (texto libre) | `02_FIT_SIZE.md` (propuesta; 6 preguntas a Carolina sin respuesta) | No hay campos; `short_description` vacío en 62/62 | Car | Car | c4 | M | M | Tabla `product_knowledge` por MODELO en F360 + bloque PDP | No |
| CRO-3A | Materiales, comodidad, tacón, punta, cuidados | MISSING / CONFLICT | `description` libre (33/62 mencionan material) | — | Errores de copiar y pegar (Marcela "estas botas"); Hilo afirma "memory foam", "8-10 horas", "piel de subproducto" **sin validar** | Car | Car | c4 | **A** (afirmaciones sin validar) | M | Campos estructurados validados por Carolina; quitar afirmaciones no validadas | No |
| CRO-3B | Reviews (CusRev / ivole 5.122) | PARTIAL | CusRev (WP) | Plugin activo en staging y en prod; bloque oculto si hay 0 reseñas (`f360-entrega-inmediata.html:263-270`); fotos y video habilitados | Reseñas: 10 en staging, 26 en prod (18 productos, todas 5.0); reminders apagados en staging; el texto de consentimiento CusRev está oculto en la página de gracias; `03_REVIEWS.md` no existe; reviews "No autorizadas" (`00_CRO:9`) | Car (selección); consentimiento | Car | c4 | M | M | Extender CusRev (meta propia + agregados en F360) | Sí (después) |
| CRO-3B | Fit feedback por reseña + agregados | MISSING | — | D-CRO-03 = ivole + fit feedback F360 | Sin modelo ni umbral | 3B | Car | c4 | M | M | `review_fit_feedback` en F360 ligado a la reseña CusRev y al pedido; mostrar el % solo con n ≥ umbral | No |
| CRO-3C | Q&A | MISSING | — | "Preguntas frecuentes" solo en el footer; CusRev Q&A **no activo** (sin `cr-qna`) | — | Car (preguntas reales) | Car | c4 | B | M | Evaluar el Q&A nativo de CusRev antes de construir; FAQ estructurado por modelo en F360 que también consuma Hilo | No |
| CRO-3D | UGC | MISSING | — | Diseño solamente | Sin fotos de clientas | 3B | Car | c4 | B | S | Fotos de reseñas CusRev verificadas → "Así las usan"; estado vacío explícito | No |
| CRO-4 | Sticky ATC móvil | DONE (emulado) | Woo variation form | `stickyCompra()` `f360-entrega-inmediata.html:275-327` | Sin prueba en teléfono real; `04_STICKY_ATC.md` dice "5–7 días" (viejo) | CRO-7 | — | 67 | M | S | Certificar en CRO-7 y corregir el doc | No |
| CRO-4 | Panel post-ATC "✓ Agregado / Pagar ahora / Seguir" | DONE en código / estado instalado **sin confirmar** | WPCode footer | `f360-compra.html:15-19,192-224` | `09_CHECKOUT.md:64` dice "Instalar… pendiente"; el video demo lo inyecta | 67 | — | 67 | M | S | Registro de snippets instalados (§L) | No |
| CRO-5 | Back-in-stock "Avísame" | MISSING | — | Solo el evento reservado `f360_back_in_stock_intent` (`G2_MEASUREMENT_CONTRACT.md:114`) | Sin tabla, UI ni consentimiento operativo; `07_INTENT_CRM.md` no existe | CRM C1 (consent architecture) | Mario | c4 | M | M | `stock_intents` en F360 + propósito de consentimiento `operational_notification` (C1 ya separa privacidad/marketing) | No |
| CRO-6 | Promesa de entrega | **CONFLICT** | — (repartida) | PDP "Entrega inmediata ZM 8–19 h" (`:377-382`); 10 días hábiles sin stock (`:1,331`, checkout, admin, migración `20261009000100`); top bar prod "ENTREGA INMEDIATA" | "5 a 7" sigue en `04_STICKY_ATC`, `admin-web/src/lib/f360.ts:221`, migraciones 001500/002200/test_targets, Bitácora; la línea de 10 días se muestra en /co/ aunque el doc dice "nunca en /co/"; Hilo dice "3 a 5 días; CDMX 1 a 3" y "$150 envío"; `CRO_OPS_E2E` dice que la entrega inmediata **no está lista** (sin pantalla de vendedora ni acuse) | Mario (regla); C2 (vendedora) | Mario | c4 | **A** (promesa incumplible) | M | Matriz de promesa (§1.1) + copy conservador hasta que la vendedora pueda acusar | Sí (top bar) |
| CRO-6 | "Último par" / escasez | DONE (guardado) | `scarcity` (migración 002400) | Oculto salvo inventario certificado | Ninguna ubicación certificada → nunca se muestra (correcto) | conteo | Car | c4 | B | — | Nada; se activa con el conteo | No |
| CRO-6 | MSI, envío gratis, pago seguro, cambios | PARTIAL / CONFLICT | copy | "Envío GRATIS y 6 MSI tiempo limitado" | La barra de confianza promete "cámbialas" en pedidos con cupón, pero la regla dice "pares con descuento no tienen cambio" (`pagina-cambios.html:58` vs `f360-compra.html:361`) | Car | Car | 67 | **A** | S | Alinear con la política de cambios | No |
| CHK | Checkout visual Fuxia + barra móvil | DONE en código | WPCode | `f360-compra.html` | Instalación sin confirmar | 67 | — | 67 | M | S | §L | No |
| CHK | Cupón 10% BIENVENIDA10 | PARTIAL | Cupón Woo (admin) | Auto-aplicado `f360-compra.html:245-276`; popup `fuxia_lead` (**PHP fuera del repo**) | El popup no está versionado | Adr/67 | Mario | 67 | M | S | Versionar el snippet `fuxia_lead` | Sí (ya existe en prod) |
| CHK | Métodos de pago (3 de Mercado Pago) | CONFLICT | Plugin MP 8.9.4 | Demo con 3 métodos; pedidos reales IG-Android | `09_CHECKOUT:16` dice "No hay métodos de pago disponibles"; **la regla del theme en prod que deja solo tarjeta no está documentada**; MP de staging4 ahora ligado a un TESTUSER (revisar antes de cada prueba) | Adr | Mario | 67/Adr | M | S | Documentar la regla de prod (sin cambiarla) | **No cambiar** |
| CHK | Pedido recibido | DONE / PARTIAL | `f360-compra.html:278-327` | — | Siempre dice "✓ Recibimos tu pago" sin leer el estado (pendiente, fallido) | — | — | 67 | M | S | Mensaje según el estado del pedido | No |
| CHK | Payment-link fallback | PARTIAL / CONFLICT | `f360-store-reserve` `pay_link` + migración 20261009000200 | Servidor y límites listos; "not deployed" en el commit `d2f7db1` | Solo MX en el servidor, pero `vigilarErrores()` abre el panel en /co/ y la petición falla | 67 | Mario | 67 | M | S | Ocultar en CO o soportar CO; prueba e2e | No |
| CHK | WhatsApp / crear cuenta / campos | PARTIAL | Woo checkout | Correo y WhatsApp prellenados desde el popup | Sin auditar en teléfono real | CRO-7 | Mario | 67 | B | S | Revisar en CRO-7 | No |
| POST | Pedido → F360 | DONE | Commerce Facts | `f360-woo-orders` + G1 | Pedidos de prueba marcados `is_test` | — | — | 67/c4 | B | — | — | No |
| POST | Hilo | DONE (staging) / CONFLICT | HiloLabs (railway) | `f360-hilo-global.html`; escalación → Bandeja | **La KB de HiloLabs no está en el repo**; `hilo-chat` interno (sin uso) con afirmaciones y política viejas | HiloLabs | Mario | HiloLabs | **A** | M | Hilo debe consumir el conocimiento F360 (CRO-3A/3C) y retirar el KB viejo | No |
| POST | Review flow (reminder) | MISSING | CusRev | Reminders apagados en staging | — | consentimiento | Car | c4 | M | S | Diseñar con el consentimiento de reseñas separado | No |
| POST | Loyalty | PARTIAL | `loyalty_cards` / `loyalty_apply` | Popup +50 pts; la página de gracias sugiere la app | Nombres "puntos Hilo" vs "Club Fuxia"; sin puntos en la PDP | CRM C1 | Mario | c4 | B | S | Unificar el nombre | No |
| CRO-7 | Certificación móvil (4 navegadores) | PARTIAL | `05_MOBILE_IAB*.md` | 10 perfiles emulados PASS; IG Android real (#4111, #4114) **sin registrar** en los docs | iPhone IG / Safari reales: NOT TESTED; Chrome Android real: NOT TESTED | teléfonos | Mario/Car | c4 | A (49% de pedidos pagados en prod vienen por IAB, `G1:191`) | M | Matriz formal (§1.2) | No |
| CRO-8 | Medición | PARTIAL / FROZEN | `G2_MEASUREMENT_CONTRACT.md`, V1.1 | Snippet V1.1 en staging4 (mu-plugin); B2.2 parcial | `tools/measurement/…php:3` dice "Not installed" (stale; está instalado); eventos fit/reviews/Q&A/UGC no definidos; GTM sin cambios | Mario reabre Growth | Mario | c4 | M | M | Extender el contrato con f360_* de decisión; certificar sin publicar tags | **No** sin aprobación |

### 1.1 Matriz de promesa de entrega (propuesta para CRO-6; copy conservador hasta validarla)

| Estado de inventario | Ubicación | Mercado | Promesa propuesta | Hoy dice |
|---|---|---|---|---|
| En existencia en Bodega CDMX | Bodega | MX | "Sale en 1–2 días hábiles" (pendiente de la regla de paquetería) | "Entrega inmediata" (top bar) |
| En existencia en tienda + ZM + 8–19 h | Tienda | MX | "Puede llegar hoy en ZM" **solo** cuando la vendedora tenga acuse (C2) | "Entrega inmediata ZM" (sin acuse operativo) |
| Sin existencia (sobre pedido) | Taller | MX / CO | "10 días hábiles" | 10 días ✓ / "5 a 7" en docs, admin y Hilo ✗ |
| Cualquiera | Bodega CDMX → CO | CO | regla CO por definir (aduana / paquetería) | se muestra la línea MX de 10 días |

### 1.2 Matriz CRO-7 (estado hoy)

| Paso | IG Android | Chrome Android | IG iPhone | Safari iPhone |
|---|---|---|---|---|
| Home → Shop → PDP → color → talla → ATC → checkout → MP → pagado → F360 | **PASS real** (#4111 / #4114, antes de los cambios nuevos) | NOT TESTED (emulado PASS) | NOT TESTED | NOT TESTED |
| Fit, reviews, Q&A, sticky ATC, post-ATC, pedido recibido, Hilo | NOT TESTED (real) | NOT TESTED | NOT TESTED | NOT TESTED |

---

## A. Ya construido (no reconstruir)
- Tienda con búsqueda y filtros.
- Selector color → talla con foto por color.
- Stock por variante y guard de escasez.
- MX / CO.
- Publicación F360 → Woo.
- Pedido Woo → F360 con idempotencia y reconciliación.
- Sticky ATC.
- Panel post-ATC, checkout Fuxia y barra móvil (en código).
- Auto-cupón.
- Pedido recibido.
- Servidor de ligas de pago.
- Hilo en el storefront con escalación a Bandeja.
- Página de Cambios.
- CusRev instalado, con fotos y video.
- Commerce Facts e identidad canónica.
- CRM C1: consentimiento separado por propósito.

## B. Parcial
- Unión de modelos (4 reintentos, 5 bloqueados).
- Más vendidas.
- Reseñas (pocas y sin reminders).
- Ligas de pago (CO, sin desplegar).
- Pedido recibido (sin estado).
- Cupón (popup fuera del repo).
- Loyalty en el storefront.
- Certificación móvil (solo IG Android real).
- Medición V1.1 (B2.2 parcial).

## C. Falta de verdad
- Conocimiento de producto estructurado (CRO-3A).
- Fit feedback y agregados de reseñas.
- Q&A.
- UGC.
- Back-in-stock y su consentimiento operativo.
- Matriz de promesa.
- Certificación en iPhone y Chrome Android reales.
- Eventos de decisión (fit, reviews, Q&A, UGC).
- Home.
- Registro de snippets instalados.

## D. Contradice decisiones anteriores
1. **Promesa de entrega:** "inmediata" / 5–7 / 10 días hábiles / "3–5 días" de Hilo.
2. **Política de cambios:** Hilo dice 15 días con reembolso; la página dice 30 días sin reembolso; la barra promete cambio en pares con descuento.
3. **Entrega inmediata pública vs `08_OMNICHANNEL.md:14`** ("no publicar disponibilidad por ubicación hasta que el inventario sea confiable") vs `CRO_OPS_E2E` ("no listo").
4. **Afirmaciones de material y comodidad de Hilo** sin validar por Carolina.
5. **Macarena** como piloto sin ser producto F360.
6. **Docs viejos:** `WOO_PUBLISHING_V1_PLAN.md:95,102`; `INVENTORY_MODEL.md:69,124`; `09_CHECKOUT.md:16` (métodos de pago); `05_MOBILE_IAB.md` (teléfono real pendiente); `tools/measurement` ("Not installed").

## E. NO construir (ya existe)
- **Otro motor de reseñas:** se extiende CusRev.
- **Otro asistente:** es Hilo/HiloLabs.
- **Otro carrito:** el sticky ATC usa el formulario de variaciones de Woo.
- **Otro descuento:** BIENVENIDA10.
- **Otra tabla de clientas o de consentimiento:** CRM C1.
- **Otra identidad de producto:** canonical F360.
- **Otro catálogo de búsqueda:** `f360_storefront_catalog`.
- **Otra capa de medición:** G2 / V1.1.

## F. PDP piloto recomendadas (8)

**Aviso sobre la evidencia:**
- Las ventas son de **staging**: 56 pedidos y 78 pares, de jun a oct 2026, Woo, MXN+COP mezclado. No es la venta real de producción.
- Las búsquedas (14 filas) no sirven como señal.
- Las reseñas de producción son 26.
- **No hay ranking confiable;** se eligió por cobertura de categoría y fit más la evidencia disponible.

| # | PDP | Por qué | Evidencia | Falta |
|---|---|---|---|---|
| — | ~~Macarena~~ | **Descartada (Mario 2026-10-05: producto de pruebas)** | — | — |
| 2 | Paula | Ballerina clásica; #1 en ventas | 19 pares; descripción rica (piel, suela acolchada) | 0 reseñas |
| 3 | Cucarron (incl. láser) | Volumen y reseñas | 18 + 12 pares; reseñas en prod (verde 3, láser caramelo 2) | Descripción de plantilla genérica |
| 4 | Sueco cucarrón | Zueco: horma distinta | 11 pares; 1 reseña en staging y 1 en prod | — |
| 5 | Ballerinas BYL puntudo | Punta afilada: fit distinto | 6 pares; 2 reseñas en prod | Fotos de colores (Carolina) |
| 6 | Mafalda láser | Flat más reseñado | 4 reseñas (staging y prod) | `category_key` nulo |
| 7 | Botas largas | Botas: altura y caña | 4 pares; ya unido en F360; inventario cargado en 3 ubicaciones | 0 reseñas |
| 8 | Sandalia (Sandalia flor o Sandalia 8) | Sandalia: ajuste por tiras | Sandalia flor unida en F360; Sandalia 8 con 6 pares | 0 reseñas |

Opcional: Tacón RMX hebilla, por variedad de tacón (2 reseñas, 0 ventas).

## G. Roadmap por unidades (cada una: auditar → construir en staging → test → reporte → aprobación)

| # | Unidad | Contenido | Bloquea |
|---|---|---|---|
| 0 | **Decisiones** | Política de cambios única, matriz de promesa, Macarena en F360 sí/no, piloto final, umbral de % de fit | Todo CRO-3 / 6 |
| 1 | CRO-3A | `product_knowledge` por modelo en F360 (fit, recomendación, horma, ancho, materiales ×3, tacón, punta, comodidad, cuidados, `validated_by`); editor en admin para Carolina; bloque "Ajuste y talla" en la PDP; mismo dato expuesto para Hilo, app y admin | 3B, 3C, Hilo |
| 2 | CRO-3B | Extender CusRev (meta/hook) + `review_fit_feedback` en F360 ligado a pedido, variante y reseña; agregados con umbral; reminder con consentimiento de reseñas | 3D |
| 3 | CRO-3C | Probar el Q&A nativo de CusRev; FAQ estructurado por modelo en F360, consumible por Hilo | — |
| 4 | CRO-3D | "Así las usan" desde fotos de reseñas verificadas, con estado vacío | — |
| 5 | CRO-4 | Certificar sticky ATC + panel existente y conectar el estado de variación | — |
| 6 | CRO-5 | `stock_intents` + consentimiento `operational_notification` + vista "N clientas esperan X" en el admin | — |
| 7 | CRO-6 | Fuente única de promesa, copy conservador, "último par" solo certificado, alinear la barra de confianza | Decisiones |
| 8 | CHECKOUT | Registro de snippets; pedido recibido por estado; ligas de pago CO; versionar `fuxia_lead`; documentar la regla de pago de prod | 67 |
| 9 | CRO-7 | Matriz con teléfonos reales | Teléfonos (Mario/Carolina) |
| 10 | CRO-8 | Contrato + eventos f360_* de decisión + certificación en staging4 (sin tags en prod) | Mario reabre medición |

## H. Carolina en paralelo (sin esperar código)
1. Elegir y confirmar los 5–10 pilotos.
2. Por piloto:
   - fit (exacta / chica / grande);
   - recomendación ("entre dos tallas, elige…");
   - horma;
   - ancho;
   - materiales (exterior / forro / suela);
   - tacón o plataforma en cm;
   - punta;
   - comodidad;
   - cuidados.
3. Responder las 6 preguntas de `02_FIT_SIZE.md`.
4. Lista de preguntas reales de clientas (WhatsApp / Hilo) por modelo.
5. **Validar o corregir** las afirmaciones que hoy hace Hilo: memory foam, 8–10 h, piel de subproducto.
6. Política de cambios final (días, descuento, reembolso).
7. Fotos y categorías pendientes de la unión de modelos.

## I. Bloqueos externos
- **HiloLabs:** su base de conocimiento no está en el repo; tiene que leer F360.
- **Adrián:** footer "Cambios", redirecciones, top bar, regla de tema de pago en producción y popup `fuxia_lead`.
- **Teléfonos reales:** iPhone (IG y Safari) y Chrome Android.
- **Mercado Pago:** la cuenta de staging4 se puede religar; revisar antes de cada prueba.
- **Paquetería:** la regla de días por zona y para CO.
- **Legal:** textos de consentimiento (C3).
- **Conteo:** sin inventario certificado no hay "último par" ni entrega inmediata confiable.

## J. Definition of Done (actualizado)

Se mantiene la lista del prompt, con estos cambios:
- **Fit:** solo para pilotos validados por Carolina, con `validated_by`.
- **Reseñas:** % de fit visible solo con n ≥ umbral (propuesta: 5 respuestas de fit; abajo de eso, "Aún no hay suficientes opiniones de ajuste").
- **UGC:** "estado vacío explícito" cuenta como hecho.
- **Promesa:** una sola fuente y ningún texto contradictorio en PDP, checkout, gracias, Hilo, admin ni docs.
- **Cambios:** una sola política en página, Hilo, barra de confianza y footer.
- **Móvil:** PASS solo en teléfono real, con fecha, dispositivo y número de pedido.
- **Medición:** eventos definidos y probados en staging4. No publicar en GTM de prod sin aprobación.
- **Registro de snippets instalados:** staging4 vs prod, actualizado.

## K. Fuentes de verdad

**Decisiones:**
- `ops/BITACORA_2026-10-02_04.md` (con la enmienda de 10 días pendiente);
- `cro/00_CRO_PRODUCT_EXPERIENCE_V1.md`;
- `cro/CRO_PRODUCT_EXPERIENCE_V1_AUDIT.md`.

**Por unidad:**
- `cro/02_FIT_SIZE.md`;
- `cro/04_STICKY_ATC.md`;
- `cro/05_MOBILE_IAB*.md`;
- `cro/06_INVENTORY_CONVERSION.md`;
- `cro/09_CHECKOUT.md`;
- `cro/CRO_OPS_E2E.md`.

**Datos y medición:**
- `growth/G2_MEASUREMENT_CONTRACT.md`;
- `growth/G2B2_CANONICAL_IDENTITY.md`;
- `growth/G1_*`;
- `INVENTORY_MODEL.md` (corregir las líneas 69 y 124).

**Código:** `tools/storefront/*.html` y `fuxia-native/supabase/functions/{f360-store-reserve,f360-hilo-intake,_shared/f360-woo}`.

**Documentos que faltan crear:**
- `cro/03_REVIEWS.md`;
- `cro/07_INTENT_CRM.md`;
- `cro/SNIPPETS_INSTALLED.md`;
- la regla de pago de producción.

## L. Git status clasificado (2026-10-05 ~10:30)

**Rama:** `fuxia-360`, igual a `origin` (0 adelante; el último commit es de la sesión 67).

| Archivo | Sesión / unidad | Acción |
|---|---|---|
| `admin-web/src/app/layout.tsx`, `login/page.tsx`, `components/Shell.tsx` (líneas "by HiloLabs.ai") | Marca HiloLabs (otra petición de Mario) | Decisión de Mario: publicar o descartar |
| `docs/fuxia360/INVENTORY_MODEL.md` (regla 9) | G2-B2.1 (c4), fuera del commit por decisión | Pendiente de Mario |
| `fuxia-native/lib/notifications.ts`, `package.json`, `package-lock.json` | Otra sesión (app nativa / Expo) | No tocar |
| `fuxia-native/app/vendedora/{apartados,tienda,venta}.tsx`, `lib/f360Store.ts` | 67 → cedidos a c4 para C2 (borrador) | C2 |
| `fuxia-native/supabase/supabase/` | Desconocido (probablemente CLI temp) | Revisar con Mario |
| `docs/fuxia360/growth/G2B1_SAFE_CORRECTIONS.md`, `G2B_MEASUREMENT_CORRECTION_PLAN.md` | G2 (c4), medición congelada | Commit cuando se reabra G2 |
| `tools/measurement/` | G2-B2.2 (c4), snippet staging4 | Igual |
| `AndroidApp/`, `fuxia360-audit.zip`, `supabase/.temp/` | Otros / temporales | Nunca comitear |

**Respuesta de la sesión 67:** ver §M. No tiene nada en curso ni sin comitear; las líneas de `db_tests.mjs` ya entraron en el commit `f6e8fcb`.

## M. Instalado realmente (respuesta de la sesión 67, 2026-10-05)

| Dónde (staging4) | Snippet | Versión instalada vs repo |
|---|---|---|
| Bricks Code · plantilla de producto | `f360-entrega-inmediata.html` | **Instalada la versión vieja con "5 a 7"** y sticky ATC; el repo ya dice "10 días hábiles" (falta re-pegar) → **CONFLICT en vivo** |
| Bricks Code · página Tienda y plantilla Categoría | `f360-tienda.html` | Instalada (incluye la hoja de filtros móvil) |
| WPCode 4099 "Hilo – chat global" | `f360-hilo-global.html` | Instalada (con recomendaciones de catálogo) |
| WPCode 4105 "Fuxia 360 · Compra" | `f360-compra.html` | Instalados: panel Agregado, estilo, barra de resumen, barra de confianza, cupón y popup WA. **Sin confirmar si se pegaron:** página de gracias, "sin método preseleccionado", rescate con liga de pago y prellenado |
| Theme `bricks-child/functions.php` (~l. 840, caso MX) | regla de métodos de pago | Mario la cambió en staging4 para permitir `woo-mercado-pago-custom` + `basic` + `credits` |
| Página 4080 + link en el footer | Cambios | Instalada |
| Mercado Pago | — | Ligado a un vendedor de PRUEBA |

**Producción:**
- No tiene ninguno de estos snippets.
- `functions.php` de producción deja **solo tarjeta en MX y solo ePayco en CO** (verificado en Store API, `cart.payment_methods`). Ya queda documentada la regla; **no se cambia** sin autorización.

**Correcciones a la matriz con esta información:**
- **CHK · Métodos de pago:** el CONFLICT queda explicado. Staging4 tiene 3 métodos de Mercado Pago porque se editó `functions.php`; producción tiene solo tarjeta en MX y ePayco en CO. Llevarlo a producción es parte del "grupo A" que plantea la sesión 67.
- **CHK · Liga de pago:** **desplegada y probada de punta a punta** (#4115 / #4116), solo MX. Riesgos nuevos:
  - el pedido se crea con `free_shipping` fijo (solo válido mientras el envío en MX sea gratis);
  - **no vacía el carrito** después de crear la liga (riesgo de compra doble);
  - los correos quedan en cola (sin Resend).
- **CHK · Resumen del pedido:** muestra "Medida: 36" (talla de tienda) en vez de la talla MX; se arregla con PHP o renombrando el atributo.
- **CRO-6 · Promesa:** en vivo staging4 todavía dice "5 a 7" en la PDP. Hilo (KB de HiloLabs) dice "10 días hábiles" para **todos** los envíos. La matriz G (asesora) sigue sin cerrar formalmente. El texto de Woo producción "Disponible para reserva" es otra variante más.
- **Siguiente de la sesión 67 (pendiente de Mario):** snippets que distingan staging4 de producción y un plan de pase a producción del grupo A (regla de métodos de pago, banner, checkout y gracias sin liga de pago, sticky ATC, Cambios).
- **Primer paso concreto de CHECKOUT:** crear `cro/SNIPPETS_INSTALLED.md` con esta tabla y verificar en staging4 cada versión pegada contra el repo.

## N. CRO-5 + CRO-6 — construido en STAGING (2026-10-05, autorizado por Mario)

**Fuentes de verdad, reutilizadas:**
- identidad: `f360.channel_variant_identity`;
- existencia en línea: `f360.online_ats` (Bodega + tiendas − Gold; los bazares no cuentan);
- sobre pedido: `products.make_to_order`, hoy en los 62 modelos;
- escasez certificada: `f360.online_scarcity_reliable`;
- clientas y consentimiento: CRM C1.

**Nuevo:**
- **`f360.delivery_promise_rules`**: la promesa es un **dato**, una fila por mercado × caso, con estado `known` o `blocked` (= BLOCKED_BY_BUSINESS_RULE).
- **`f360.delivery_promise()`**: la **única regla** (variante → existencia → sobre pedido → mercado → promesa). La consumen la PDP (vía `f360_storefront_promise`), el checkout, Hilo y Pedido recibido. Ver "Pendiente" para su integración.
- **`f360.trust_claims()`**: solo claims comprobables: cambios en 30 días (o "Precio con descuento: sin cambio" si el modelo tiene `sale_price`) y pago seguro. MSI y envío gratis **no** se emiten, porque no hay fuente en F360.
- **"Último par"** solo con inventario certificado; hoy nunca se muestra.
- **`f360.stock_intents`** ("Avísame cuando llegue"):
  - guarda modelo y SKU canónicos, color, talla, mercado, canal, fecha y origen;
  - `customer_id` si la clienta ya existe (no se duplica Customer 360); si no, solo el teléfono normalizado;
  - consentimiento **operacional** (`stock_notification`, nuevo tipo `operational`, versión `2026-10-05-v1`), separado de marketing;
  - un aviso activo por persona y talla;
  - límites: 10 por teléfono al día y 30 por IP por hora (la IP se guarda como hash);
  - se rechaza si la talla sí se puede pedir.
- **`f360_stock_demand()`** y la pantalla **/demanda**, "Demanda sin inventario": por modelo, color y talla, *esperando* (avisos) + *vendidos sobre pedido*. Sin datos personales. Está en el menú y en el Centro de control.
- **Edge Function `f360-storefront`** (pública, staging): acciones `promise` y `notify_me`. El canal sale de la configuración (`F360_STOREFRONT_TARGET`), nunca del navegador. Si falla, devuelve vacío y la página conserva su propio estado.
- **Snippet `tools/storefront/f360-promesa-avisame.html`**: la caja de promesa con confianza junto a "Añadir al carrito" y el formulario "Avísame". **No está instalado** en staging4; se probó inyectado en el navegador.

**Reglas cargadas:**

| Mercado | Con existencia | Sin existencia + sobre pedido | Agotada (sin sobre pedido) |
|---|---|---|---|
| MX | ✅ "Entrega Inmediata en Zona Metropolitana" (+ fuera de ZM: "te confirmamos el tiempo") | ✅ "Producción: 10 días hábiles" | ✅ "Agotada" + Avísame |
| CO | ⛔ BLOCKED: "Te confirmamos el tiempo de entrega al hacer tu pedido" | ⛔ BLOCKED: "Lo hacemos a la medida para ti" (sin tiempo) | ✅ "Agotada" + Avísame |
| Otros | ⛔ BLOCKED | ⛔ BLOCKED | ✅ |

**Pruebas:**
- SQL `f360_cro5_cro6_tests.sql`: 25/25. Suite: 948/948.
- Edge Function: 7/7 (node --test).
- E2E contra staging real:
  - Botas Largas MX: 8 con existencia / 4 sobre pedido;
  - CO: blocked;
  - Paula (legacy homologado): OK;
  - origen ajeno: 403.

**Evidencia:** `docs/fuxia360/cro/screens/cro5-cro6/`. La captura `03` es una **simulación** en el navegador, porque hoy ningún modelo está "agotado".

**Pendiente / BLOCKED:**
- Instalar el snippet en staging4 y **quitar las líneas de promesa** del snippet de la PDP de la sesión 67 ("Entrega inmediata…", "10 días hábiles…"). También retirar la caja del tema "Envío GRATIS y 6 MSI · Entrega INMEDIATA en la mayoría de nuestros modelos" y la barra superior (Adrián).
- Checkout, Pedido recibido y Hilo deben leer `promise` en vez de su texto propio (sesión 67 / HiloLabs).
- Regla de Colombia y de envíos con existencia fuera de la ZM: decisión de Mario.
- "Avísame" en tallas sobre pedido (¿también ofrecerlo?): decisión de Mario.
- Texto legal del consentimiento operacional: revisión legal (C3).
- Envío de avisos cuando llegue la talla: **no construido**, sin campañas por decisión.
- Certificación en teléfono real (IG/Chrome Android, IG/Safari iPhone): NOT TESTED, porque el snippet no está instalado.

## O. CRO-5/6 · Integration closeout en staging4 (2026-10-05)

**Decisiones de Mario (2026-10-05):**
1. "Avísame" **solo** en variantes realmente no comprables, **nunca** en tallas sobre pedido. Ya era así: `can_notify` solo aplica a `unavailable`, y la intención se rechaza con `available`.
2. Colombia: copy conservador, sin días.
3. Fuera de la Zona Metropolitana: copy conservador, sin días.
4. El consentimiento de stock es operacional y está marcado como **LEGAL_REVIEW_REQUIRED** (no bloquea staging).
5. F360 es la única fuente de la promesa dinámica. Lo estático no compite.

**Regla de horario incorporada** (no se cambió a escondidas): el snippet de la PDP ya tenía 8–19 h CDMX → "Entrega Inmediata en Zona Metropolitana", y fuera de horario → "Entrega mañana a partir de las 8 a. m. en Zona Metropolitana". Ahora es dato de `delivery_promise_rules` (migración `20261010000800`, pruebas 27/27, suite 950/950).

### Arquitectura (fuente única)

```
PRODUCT / VARIANT (f360.channel_variant_identity)
        ↓
INVENTORY (f360.online_ats) + MARKET + FULFILLMENT (sales_targets.fulfillment_location_id) + MTO (products.make_to_order)
        ↓
DELIVERY PROMISE RULE  (f360.delivery_promise_rules + f360.delivery_promise)  ← único lugar donde vive el texto
        ↓  Edge Function f360-storefront · action 'promise'
 ┌──────┼──────────┬────────────┐
PDP ✅   CHECKOUT ◐  HILO ◐      PEDIDO RECIBIDO ◐
```
✅ = lee la regla · ◐ = todavía tiene su propio texto (ver pendientes).

### Promesas duplicadas encontradas en staging4

| Texto | Fuente | Ubicación | Condición | Tipo | Dueño | Acción tomada |
|---|---|---|---|---|---|---|
| "Esta talla y color se entrega en **5 a 7** días hábiles" | Bricks · plantilla "Producto Fuxia" (1955) · elemento Code `oyoypn` (versión instalada vieja de `f360-entrega-inmediata.html`) | PDP, bajo el selector | Talla sin existencia | Estática | F360 (sesión 67) | **REPLACE**: versión del repo sin líneas de promesa, firmada por **msilva (Mario)**, firma de Bricks válida. Respaldo `~/f360-backups/bricks_1955_page_content_2_20261005-213202.json` |
| "🛵 Entrega Inmediata en Zona Metropolitana" / "Entrega mañana a partir de las 8 a. m." | El mismo elemento `oyoypn` | PDP | En existencia, MX | Semidinámica (horario en JS) | F360 (67) | **REPLACE** por la regla F360 (el horario ahora es dato) |
| "Envío GRATIS y 6 MSI tiempo limitado **· Entrega INMEDIATA en la mayoría de nuestros modelos**" (y variantes CO/US/promo) | WPCode **#2551 "Fuxia envio pagos promo"** v22 (`fuxia_texto_envio()`) | Barra superior `#fx-topbar` y caja `.fx-trust` bajo el botón | Siempre | Estática | Sitio (Adrián/Mario), **también en producción** | **REMOVE** solo la frase de entrega en staging4 (4 reemplazos). Envío gratis, MSI y logos se quedan. Respaldo `~/f360-backups/wpcode_2551_20261005-212944.txt`. **Producción sin tocar** |
| "6 MSI tiempo limitado" | WPCode #2551, rama "normal" (la promo terminó el 31-jul) | Barra y caja bajo el botón | MX | Estática | Sitio | **KEEP**, pero CONFLICT reportado: la promo venció y el texto dice "tiempo limitado". Decisión comercial de Mario |
| "Disponible para reserva" | WooCommerce (backorder) | Checkout, línea del par sobre pedido | Talla sin existencia | Woo por defecto | Woo | **PARTIAL**: el snippet que lo reemplaza (`f360-compra.html`, WPCode 4105) no tiene instalada esa versión. Debe leer `promise` |
| "A la medida · se entrega en 10 días hábiles" | `f360-compra.html` (repo) | Checkout y Pedido recibido | Sobre pedido | Estática | F360 (67) | **PARTIAL**: coincide con la regla, pero es texto propio |
| "Cambios fáciles · Hasta 30 días" / "Envío a todo el mundo…" | Footer del tema | Pie de página | Siempre | Estática | Sitio | **KEEP**: consistente (cambios 30 días; costo de envío, no tiempo) |
| Respuestas de Hilo sobre entrega | KB de HiloLabs (parche c) | Chat | — | Estática (mismo texto que la regla) | HiloLabs | **PARTIAL**: no lee la regla. Integración mínima propuesta abajo |

### Pruebas reales en staging4 (navegador, sin inyectar)

| Caso | Resultado | Evidencia |
|---|---|---|
| A · F360 con existencia, MX (Botas Largas Café 36) | ✅ Una caja: "Entrega Inmediata en Zona Metropolitana" + fuera de ZM + "Cambios en 30 días". ATC → "✓ Agregado a tu carrito" → Pagar ahora → checkout sin texto contradictorio | `10_`, `11_`, `12_` |
| B · F360 sobre pedido, MX (Café 35) | ✅ PDP "Producción: 10 días hábiles · Lo hacemos a la medida". Checkout: "Disponible para reserva" (Woo) → ◐ | `13_` |
| C · F360 agotado / no comprable | **PENDIENTE**: no existe hoy (los 62 modelos permiten sobre pedido). Requiere el OK de Mario para apagar temporalmente el sobre pedido de un modelo. La deduplicación del aviso está probada en base de datos (25/25 → 27/27), no en vivo | `03_…SIMULADO` (simulación) |
| D · legacy homologado (Paula azul marino) | ✅ "Entrega Inmediata en Zona Metropolitana"; apartado Gold en tienda sigue funcionando | `14_` |
| E · México | ✅ (A, B, D) | — |
| F · Colombia (Botas Largas /co/) | ✅ "Te confirmamos el tiempo de entrega al hacer tu pedido", sin días; tallas 35–40; ePayco | `15_` |

### Regresión

| Qué | Resultado |
|---|---|
| Producto F360 | ✅ |
| Legacy | ✅ |
| MX | ✅ |
| CO | ✅ |
| Selector color / talla | ✅ |
| Fotos | ✅ |
| Sticky ATC (presente y actualizado con la talla) | ✅ |
| Añadir al carrito | ✅ |
| ✓ Agregado | ✅ |
| Carrito / checkout | ✅ (con el ◐ anterior) |
| Cupón ("Añadir cupones" visible) | ✅ |
| Hilo (widget presente) | ✅ |
| Una sola caja de promesa en todas las PDP probadas | ✅ |
| Instagram Android real | **Pendiente de Mario** |
| iPhone / Chrome Android | CRO-7 |

### Demanda (Growth)

`VARIANT → UNAVAILABLE → STOCK INTENT → DEMAND COUNT` queda listo.
- **Cada intención guarda:** `variant_id`, `canonical_sku`, `product_key`, `market` y fecha.
- **Se cruza por SKU canónico con:**
  - inventario: `online_ats`;
  - ventas: `commerce_order_lines.canonical_sku`;
  - sobre pedido: `made_to_order`.
- **Campañas:** por `source` / `page_url` y, a futuro, `utm` sin PII.
- No se implementó Campaign 360.

### Pendientes

1. **Caso C en vivo:** OK de Mario para apagar el sobre pedido de un modelo durante la prueba.
2. **Checkout y Pedido recibido** deben leer `promise`: instalar la versión de `f360-compra.html` que reemplaza "Disponible para reserva" y cambiar su texto por la regla.
3. **Hilo, integración mínima:** una herramienta en HiloLabs (`app/core/tools.py`, `get_delivery_promise(woo_product_id, market)`) que llame a `f360-storefront` `promise`. Sin tabla ni regla nueva.
4. **Instagram Android real.**
5. **"6 MSI tiempo limitado"** con la promo vencida: decisión comercial.
6. **Producción:** nada de esto está ahí. El snippet #2551 de producción sigue diciendo "Entrega INMEDIATA en la mayoría de nuestros modelos".

**Estado: CRO-5 = PARTIAL** (falta el caso C en vivo). **CRO-6 = PARTIAL** (PDP ✅; checkout, Pedido recibido y Hilo todavía con texto propio; IG Android real pendiente).

## P. CRO-5/6 · Cierre en staging (2026-10-05, autorizado por Mario) — reemplaza el estado de §O

**Fuente única.** Las 4 superficies leen `f360.delivery_promise` (regla en `f360.delivery_promise_rules`) a través de la Edge Function `f360-storefront`. Ninguna guarda el texto de la regla. Cambiar una fila de `delivery_promise_rules` cambia PDP, checkout, Pedido recibido y Hilo sin tocar código.

```
f360.delivery_promise_rules ─→ f360.delivery_promise(variant, fulfillment, market, now)
   ├─ action 'promise'        (por producto) ─→ PDP (f360-promesa-avisame.html)   · Hilo (tool get_delivery_promise, llave servidor)
   └─ action 'promise_lines'  (por variación, migración 20261010001000) ─→ Checkout · Pedido recibido (f360-promesa-checkout.html; mu-plugin imprime solo ids de variación)
```

### P.1 Matriz por superficie (staging4)

| SUPERFICIE | EXISTENCIA (MX) | SOBRE PEDIDO (MX) | AGOTADO | COLOMBIA | SOURCE |
|---|---|---|---|---|---|
| **PDP** | "Entrega Inmediata en Zona Metropolitana" (8–19 h CDMX; fuera de horario "Entrega mañana a partir de las 8 a. m. en Zona Metropolitana") | "Producción: 10 días hábiles" | "Agotada" + Avísame (consentimiento operacional) | "Te confirmamos el tiempo de entrega al hacer tu pedido" | `promise` → `f360.delivery_promise` |
| **CHECKOUT** | Por línea: "Talla MX 23 · Entrega Inmediata en Zona Metropolitana" | Por línea: "Talla MX 22 · Producción: 10 días hábiles". Sin "Disponible para reserva" | No llega (no se puede comprar) | Mismo texto conservador por línea | `promise_lines` → `f360.delivery_promise` |
| **PEDIDO RECIBIDO** | Por línea, mismo texto | Por línea, mismo texto. Sin "Reservado" | No aplica | Mismo texto conservador | `promise_lines` (ítems del pedido, `order_key` verificado con `hash_equals`) |
| **HILO** | Consulta la tool → "Entrega Inmediata en Zona Metropolitana" | Consulta la tool → "Producción: 10 días hábiles" | Consulta la tool (caso `unavailable`) | Consulta la tool → "se confirma al hacer el pedido" | tool `get_delivery_promise` → `promise` (rama local `f360-delivery-promise`, **sin deploy**) |

- **Talla en checkout y Pedido recibido:** solo presentación. "Medida: 36" se muestra como "Talla MX: 23" (talla Fuxia − 13, igual que la PDP). El valor de la variación en Woo no cambia.
- **Pedido con promesas mixtas** (una línea en existencia y otra sobre pedido): cada línea muestra su propia promesa, sin un mensaje combinado. **BUSINESS_RULE_PENDING (Mario):** ¿se envía todo junto (fecha = la más tardía) o en dos envíos? No se simplificó.

### P.2 CRO-5 · Caso C en vivo (agotado)

- **Piloto:** Botas cortas (F360 `fb29e937-…`, Woo 3720), staging F360 `faltx…` + staging4.
- **Estado original:** `make_to_order = true`, Woo `backorders = notify`.
- **Durante la prueba:**
  - 21:39 UTC: `make_to_order = false` (como Carolina, `catalog_changes` 169). Woo pasó a `backorders = no`.
  - PDP Café talla Fuxia 35 (variación 3734) → "Agotada" + "Avísame cuando llegue" (`20_`, `21_`).
  - Se mandó el teléfono de prueba 55 0000 0001, nombre "Prueba CRO5", con consentimiento → intención `F360-BOTAS-CORTAS-CAFE-35`, MX, `pdp`, `waiting`, consentimiento `stock_notification` v`2026-10-05-v1`. **No se creó una clienta** (`22_`).
  - Demanda (`/demanda`, `f360_stock_demand()`): Botas cortas Café 35 = **1** en espera.
- **Dedupe:** la misma persona escrita "+52 1 55 0000 0001", misma variante → `already: true`, sin intención nueva; la demanda siguió en 1 (`23_`).
- **Restauración:** 21:48 UTC `make_to_order = true` (`catalog_changes` 170), Woo `backorders = notify`, intención de prueba → `cancelled`. Verificado después: `promise` 3720 MX = 8 sobre pedido / 4 en existencia, 0 agotadas.
- **Nota:** las capturas 20–23 son anteriores al retiro de "6 MSI tiempo limitado" (por eso aún se ve en la caja).

### P.3 Pruebas Hilo (local, rama `f360-delivery-promise`)

- **Montaje:** Claude real y regla F360 real (staging). Solo la búsqueda de catálogo de WooCommerce se sustituyó por los datos públicos de staging4, porque el `.env` local no tiene llaves de Woo y no se usaron las de producción.

| Pregunta | Tools llamadas | Respuesta |
|---|---|---|
| Paula azul marino talla 24 MX, CDMX | search → check_inventory → **get_delivery_promise(655, MX)** | "Entrega Inmediata en Zona Metropolitana" ✅ |
| Botas Largas café talla 35, CDMX (sobre pedido) | … → **get_delivery_promise(3721, MX)** | "Producción: 10 días hábiles — las hacemos a la medida" ✅ |
| Botas Largas café talla 36, CDMX | … → **get_delivery_promise(3721, MX)** | "Entrega Inmediata en Zona Metropolitana" ✅ |
| Paula azul marino talla 37, Bogotá | … → **get_delivery_promise(655, CO)** | "Para Colombia el tiempo de entrega se confirma al hacer el pedido" ✅ |
| "¿Cuánto tarda el envío en general?" | ninguna (pregunta sin modelo) | Responde con el **KB** (texto copiado de la regla + EE. UU./Canadá DHL 10–12 días) ◐ |

**Hallazgos (Hilo, no se corrigieron aquí):**
- **Tallas:** convirtió 24 MX → 36 y 26 MX → 38 (correcto: 37 y 39). La tabla correcta (MX = Fuxia − 13) ya está en el KB, pero no se recupera en preguntas de entrega. Es un problema de recuperación en Hilo, separado de la regla de promesa; queda como unidad aparte.
- **Liga de compra:** inventó la liga `…/?variation_id=657` cuando `check_inventory` no trajo `buy_url` (en la prueba porque estaba sustituido). Hay que revisarlo en el deploy.

**Parche de KB (d)** (`fuxia-chatbot/scripts/kb_patch_2026_10d.py`, **dry-run, NO aplicado**):
- quita el texto copiado de la regla en "¿Cuánto tarda el envío?" y en "¿Qué métodos de pago aceptan?";
- con eso la pregunta general pide modelo, talla y lugar, y Hilo consulta la tool.

Es un cambio de producción (KB en vivo), así que se aplica junto con el deploy de Hilo y con autorización de Mario.

### P.4 "6 MSI tiempo limitado" y otra copia comercial

- **staging4:**
  - WPCode #2551 ahora dice "Envío GRATIS" (respaldo `~/f360-backups/wpcode_2551_20261005-215116.txt`); `fuxia_promo_vigente()` = false.
  - Verificado por HTML (Botas Largas, Paula MX, Paula /co/): 0 "MSI", 0 "tiempo limitado", 0 "Entrega INMEDIATA".
  - "Disponible para reserva" solo vive en el JSON de variaciones de Woo y está oculto con CSS (`.available-on-backorder{display:none}`).
- **Afirmaciones que quedan (verificables):**
  - "Envío GRATIS" (configuración de envío actual);
  - "Cambios en 30 días" (política de Mario);
  - "Pago 100% seguro" + logos (pasarelas configuradas).
- **El KB de Hilo** dice "Por el momento no manejamos meses sin intereses", y el **sitio de producción** sigue anunciando 6 MSI. Es una contradicción comercial para Mario.
- **Producción (sin tocar). Para el pase**, WPCode #2551 "Fuxia envio pagos promo" (`fuxia_texto_envio()`):
  - línea 46, texto normal: "Envío GRATIS y 6 MSI tiempo limitado · Entrega INMEDIATA en la mayoría de nuestros modelos";
  - líneas 41, 44 y 45: variantes CO / US / promo con "Entrega INMEDIATA en la mayoría de nuestros modelos";
  - `FUXIA_PROMO_MSJ_MX` y el bloque `fx-trust-msi`: condicionados a la promo; revisar al pase.
  - Se ve en la barra `#fx-topbar` y en la caja `.fx-trust` bajo "Añadir al carrito".

### P.5 Reglas de negocio pendientes

| Regla | Estado |
|---|---|
| Colombia: tiempo de entrega | **BUSINESS_RULE_PENDING**: copy "Te confirmamos el tiempo de entrega al hacer tu pedido" (`status = blocked`) |
| México fuera de la Zona Metropolitana | **BUSINESS_RULE_PENDING**: mismo copy conservador. Hoy la regla no distingue CP. La promesa MX en existencia dice "en Zona Metropolitana" |
| EE. UU. / Canadá (DHL 10–12 días hábiles) | **BUSINESS_RULE_PENDING**: solo existe en el KB de Hilo, no en la regla F360. Es una segunda fuente que hay que decidir: llevarla a la regla o quitarla |
| Pedido con promesas mixtas | **BUSINESS_RULE_PENDING**: se muestra por línea |
| Consentimiento `stock_notification` v1 | **LEGAL_REVIEW_REQUIRED** (no bloquea) |
| 6 MSI | Decisión comercial (§P.4) |

### P.6 Definition of Done

**CRO-5:**

| Criterio | Estado |
|---|---|
| Agotado probado en vivo | ✅ |
| Intención registrada | ✅ |
| Dedupe probado | ✅ |
| Demanda actualizada | ✅ |
| Piloto restaurado | ✅ |
| Sin regresión | ✅ (suite DB 951/951; PDP A/B/D/F) |

**→ CRO-5 = DONE (técnico, staging).**

**CRO-6:**

| Criterio | Estado |
|---|---|
| PDP usa la regla F360 | ✅ |
| Checkout usa la regla F360 | ✅ |
| Pedido recibido usa la regla F360 | ✅ |
| Sin "Disponible para reserva" | ✅ |
| Talla MX correcta (solo presentación) | ✅ |
| Fallback CO | ✅ |
| Legacy | ✅ |
| Hilo consulta la regla | ◐ Implementado y probado en local; falta deploy (= producción de Hilo) y parche KB (d) |

**→ CRO-6 = PARTIAL** hasta que Hilo con la tool esté desplegado y el KB ya no tenga el texto copiado.

**REAL_DEVICE_ACCEPTANCE_PENDING_MARIO:** Instagram Android real. Es aparte del DONE técnico.

### P.7 Cambios exactos en staging

| Dónde | Cambio | Rollback |
|---|---|---|
| Supabase staging `faltx…` | Migración `20261010000800` (horario en la regla) | `supabase/rollbacks/20261010000800_*.down.sql` |
| Supabase staging `faltx…` | Migración `20261010001000` (`f360_storefront_promise_lines`) | `supabase/rollbacks/20261010001000_*.down.sql` |
| Edge Function `f360-storefront` | `promise_lines` + llave servidor-a-servidor; `notify_me` cerrado a llamadas de servidor | Redeploy de la versión anterior |
| Secret `F360_STOREFRONT_SERVER_KEY` | Nuevo (no está en el repo) | Borrar el secret |
| staging4 · mu-plugin `f360-promesa-avisame-staging4.php` | PDP + checkout + Pedido recibido; host guard `staging4.` | Borrar el archivo |
| staging4 · Bricks 1955 `oyoypn` | `f360-entrega-inmediata.html` sin líneas de promesa, firmado msilva | `~/f360-backups/bricks_1955_page_content_2_20261005-213202.json` |
| staging4 · WPCode #4105 | `f360-compra.html` sin "A la medida · 10 días" | `~/f360-backups/wpcode_4105_20261005-215524.txt` |
| staging4 · WPCode #2551 | Sin "Entrega INMEDIATA…", sin "6 MSI tiempo limitado" | `~/f360-backups/wpcode_2551_20261005-212944.txt`, `…-215116.txt` |
| Datos de prueba | Botas cortas MTO apagado y restaurado (`catalog_changes` 169/170); intención de prueba `cancelled`; pedido Woo #4264 `cancelled` | — |

**Hilo:**
- rama local `f360-delivery-promise`, commit `0bf4779`, **sin push** (push a `main` = producción);
- variables nuevas para Railway: `F360_STOREFRONT_URL` y `F360_STOREFRONT_SERVER_KEY`. Hoy apuntan a staging F360; en producción deben apuntar a la F360 de producción.

### P.8 Diferencias conocidas contra producción

1. Producción no tiene esquema F360, regla, Edge Function, mu-plugin ni snippets F360 (opción B pendiente).
2. #2551 de producción sigue con "6 MSI tiempo limitado" y "Entrega INMEDIATA en la mayoría de nuestros modelos" (§P.4).
3. **Hilo de producción:**
   - el KB sigue con el texto de la regla (parche c);
   - no tiene la tool;
   - si se despliega antes de la F360 de producción, consultaría staging. Hay que desplegarlo junto con el pase, o mapear los ids de Woo de producción.
4. Los ids de Woo de staging4 (3720/3721) son de staging. El mapeo `channel_variant_identity` de producción se arma en el pase.
5. **Encabezado del thank-you** ("✓ Recibimos tu pago / confirmado") aparece también en pedidos pendientes. Es de `f360-compra.html` (sesión 67), no se tocó y se reporta.

### P.9 Decisión de Mario (2026-10-05, posterior a §P.1–P.8)

**Resolución:** CRO-5 = DONE en staging (aprobado). **CRO-6 = PARTIAL**, a propósito.

- **No se despliega Hilo ni se aplica el parche KB (d) todavía.** Hilo de producción no debe depender de F360 staging.
- Los dos pasos forman parte del pase de F360 a producción: `docs/fuxia360/ops/PASE_A_PRODUCCION_OPCION_B.md` §F5 "Storefront / promesa de entrega".

**Corrección de tallas en Hilo** (rama `f360-delivery-promise`, commit `eaf12eb`, sin push):
- **Problema:** la tabla correcta (MX = Fuxia − 13) ya estaba en el KB, en el artículo "¿Cuál es la equivalencia entre talla mexicana y americana?", pero la búsqueda no lo traía en preguntas de entrega o stock.
- **Ahora** (`app/core/rag.py` `with_size_table`), cuando la clienta menciona una talla:
  - ese mismo artículo se agrega al contexto, leído de `kb_articles`;
  - no hay tabla nueva ni números en el código o el prompt;
  - el prompt dice que "Medida" es talla Fuxia y que se convierte solo con ese artículo.
- **La tool** pide repetir `headline`/`detail` tal cual, sin agregar "después de producción…" ni rutas o razones.
- **Prueba local:** Claude real + regla F360 staging; solo el catálogo de Woo sustituido.

| Pregunta | Talla | Promesa |
|---|---|---|
| Paula 24 MX, CDMX | 37 ✅ (antes 36) | Entrega Inmediata en Zona Metropolitana ✅ |
| Paula 26 MX, CDMX | 39 ✅ (antes 38) | Producción: 10 días hábiles, sin agregados ✅ |
| Botas Largas 23 MX | 36 ✅ | (el stub de catálogo no encontró el modelo; es de la prueba, no de Hilo) |
| Paula 37, Bogotá | 37 | "Te confirmamos el tiempo de entrega al hacer tu pedido" ✅ |

**Parche KB (d):** preparado (`scripts/kb_patch_2026_10d.py`, dry-run verificado) y **no aplicado**.

**Pendientes de negocio** (sin respuesta inventada; Hilo y la tienda usan el copy conservador o no dicen nada):
1. **Colombia:** tiempo de entrega.
2. **México fuera de la Zona Metropolitana:** tiempo de entrega.
3. **EE. UU. / Canadá:** hoy solo existe "DHL 10–12 días hábiles" en el KB de Hilo, fuera de la regla F360. Hay que decidir si se lleva a la regla o se quita.
4. **Pedido mixto:** ¿se envía junto (fecha de la línea más tardía) o separado? Hoy cada línea muestra su promesa.
5. **Avísame:** revisión legal del consentimiento `stock_notification` v1 (LEGAL_REVIEW_REQUIRED).
6. **6 MSI:** el sitio de producción lo anuncia, el KB de Hilo dice "no manejamos meses sin intereses" y en staging4 se quitó.

**Bug P0 separado (antes del pase a producción):**
- Pedido recibido muestra "✓ Recibimos tu pago" y "está confirmado" aunque el pedido esté **pendiente de pago** (visto en el pedido de prueba #4264, `24_`/`25_`).
- Está en `tools/storefront/f360-compra.html` (WPCode #4105), unidad de la sesión 67. No se corrigió dentro de CRO-6.

**Estado final: CRO-5 = DONE (staging). CRO-6 = PARTIAL**: PDP, checkout y Pedido recibido ✅; Hilo listo en rama y se despliega en el pase.
