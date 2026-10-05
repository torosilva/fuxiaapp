# CRO-3B (reseñas + ajuste) y CRO-3C (preguntas) · Auditoría y diseño (2026-10-05)

**Estado:** solo auditoría y diseño. **No hay nada implementado.** Se espera la aprobación de Mario.

**Regla:** no se construye un segundo motor de reseñas. Se extiende **CusRev** (Customer Reviews for WooCommerce, `ivole`), que ya está instalado.

**Fuentes auditadas (solo lectura):**
- staging4 con WP-CLI: opciones `ivole_*`, `wp_comments` / `wp_commentmeta` y el código del plugin 5.122.0;
- producción solo por la Store API pública (`/wp-json/wc/store/v1/products/reviews`);
- F360 staging con conteos en transacción READ ONLY.

---

## 1. Qué puede hacer CusRev hoy (5.122.0, plan Free)

| Función | Estado en staging4 | Evidencia |
|---|---|---|
| Reseñas sobre los comentarios de Woo (estrellas, resumen con barras, orden, votos útil / no útil, respuesta de la tienda) | **Activo** | `comment_type = review`, meta `rating`, `ivole_review_votes`, `ivole_reply` |
| Fotos y video en el formulario de la PDP | **Activo**: hasta 5 archivos de 25 MB | `ivole_attach_image = yes`, `_quantity = 5`, `_size = 25` |
| Moderación previa | **Activa** | `ivole_enable_moderation = yes` |
| Quién puede reseñar en la PDP | Cualquiera | `ivole_review_forms[0].rev_perm = anybody` |
| Criterios de calificación extra (1–5 estrellas, p. ej. "Comodidad") | Disponibles, **ninguno configurado**. Máximo 3 (filtro `cr_onsite_ratings`) | `rtn_crta = []`; `class-cr-settings-forms-rating.php:222` |
| Preguntas extra en el formulario de la PDP | Disponibles, **ninguna**. Máximo 2 (filtro `cr_onsite_questions`). **Solo texto o número** (no hay opción múltiple) | `cus_atts = []`; `class-cr-reviews.php:42` `onsite_q_types = text, number` |
| Recordatorio de reseña por correo | **Apagado**. Si se enciende: pedido `completed` + 5 días, correo con el mailer de WordPress, formulario local | `ivole_enable = no`, `ivole_delay = 5 / email`, `ivole_mailer_review_reminder = wp`, `ivole_order_status = wc-completed` |
| Casilla de consentimiento en el checkout | **Activa**. Su texto dice "un mensaje de **CusRev** (un servicio de reseñas independiente)" | `ivole_customer_consent = yes`. En producción, 60 pedidos con `_ivole_cr_consent`: 9 sí, 51 no (`growth/G1_COMMERCE_FACTS_DESIGN.md:149`) |
| Fotos en el formulario del recordatorio | Apagado | `ivole_form_attach_media = no` |
| Insignia de compra verificada en la nube de CusRev | Apagada | `ivole_verified_reviews = no` |
| Preguntas y respuestas (Q&A) por producto | **Existe, apagado** | `includes/qna/*`; la opción `ivole_questions_answers` no existe (= `no`) |
| Recordatorio por WhatsApp | Existe la clase, pero pasa por la nube de CusRev | `includes/emails/class-cr-wtsap.php` |
| Marcado para Google (rich snippets) | Activo (el de Woo + extras) | readme |

## 2. Qué reseñas reales tenemos

| | Producción (Store API pública) | staging4 (copia) |
|---|---|---|
| Total aprobadas | **26** | 14 (10 públicas + 4 en productos privados) |
| Calificación | 26 de 5★ | 14 de 5★ |
| Compra verificada | **1** | 1 (Suecos cucarrones dorado) |
| Fechas | 07-31 (13, en lote), 08-01, 09-27 (2), **10-01 (10, en lote)** | 07-31, 08-01 |
| Máximo por modelo | **4** (Mafalda láser taupe); casi todos tienen 1–2 | 4 (Mafalda) |
| Con foto o video | — (la API pública no lo expone) | 2 (1 foto, 1 video) |
| Con talla o ajuste | **0** | 0 |

**Hallazgos:**
1. **Ningún modelo tiene volumen.** "4.9 · 14 opiniones" no es real por modelo hoy; el máximo es 4.
2. **Las reseñas llegan en lotes** (13 el 07-31, 10 el 10-01) y casi ninguna está verificada. Una dice "Los compré en Polanco": son **compras en tienda**. Woo nunca puede verificarlas, porque no hay pedido en línea.
   - **Pendiente con Carolina:** de dónde salió cada lote (¿ella las capturó de clientas reales?).
   - No se etiquetan como verificadas **sin evidencia**.
3. **Todo es 5★.** No es un problema técnico, pero un promedio de 5.0 con n pequeña convence menos que 4.8 con n grande.

## 3. Qué datos guarda CusRev

| Dónde | Campo | Nota |
|---|---|---|
| `wp_comments` | autora (nombre como lo escribe), **correo**, texto, fecha, `comment_approved`, `comment_post_ID` (**producto padre**, no variación) | El correo es dato personal: no sale de WP |
| `wp_commentmeta` | `rating` (1–5), `verified` (0/1) | Lo pone **WooCommerce** al enviar, no CusRev |
| | `ivole_media_count`, `ivole_review_image*`, `ivole_review_video*` | Adjuntos de WP |
| | `ivole_c_questions` | Respuestas a criterios y preguntas extra |
| | `ivole_order` | **Solo** en reseñas que llegan por el formulario del recordatorio (liga la reseña al pedido) |
| | `ivole_country`, votos, `ivole_reply`, `cr_coupon_code` | — |
| **No guarda** | variación, talla, ajuste, pedido (en reseñas de la PDP), teléfono, compra en tienda | Esto es lo que falta |

## 4. Compra verificada

- **Cómo funciona hoy:**
  - WooCommerce pone `verified = 1` al enviar la reseña si `wc_customer_bought_product(correo, usuario, producto)`. Busca pedidos **en línea** pagados con ese correo o usuario.
  - CusRev solo lee esa marca (`class-cr-reviews.php:1785-1827`).
- **Lo que no puede:**
  - verificar **compras en tienda** (offline);
  - verificar **qué talla** compró;
  - verificar a una clienta que reseña con otro correo.
- **F360 sí puede.** Conoce las ventas en línea (`commerce_order_lines`, con variante canónica) y las de tienda (`offline_sales`, con clienta). La verificación correcta es de F360, y Woo solo recibe la marca para mostrar la insignia (ver §8).

## 5. Fotos

- Ya funcionan en la PDP (5 archivos, 25 MB, moderadas). Viven como adjuntos de WP. **No se construye otra subida de fotos.**
- **Pendientes:**
  - activar fotos también en el formulario del recordatorio (`ivole_form_attach_media`, es un ajuste);
  - permiso explícito para **reusar** una foto fuera de la reseña (CRO-3D "Así las usan").

## 6. Recordatorios

- **Están apagados.** El mecanismo existe: correo con el mailer de WP, formulario local que liga la reseña al pedido (`ivole_order`) y límite de recordatorios.
- **Riesgos antes de encenderlos:**
  1. **Texto legal:** la casilla dice que el mensaje lo manda "CusRev, un servicio independiente". Con el mailer `wp` y los formularios locales lo manda Fuxia, así que el texto no es exacto → **LEGAL_REVIEW_REQUIRED**.
  2. Solo se manda a quien marcó la casilla (9 de 60).
  3. Las compras en tienda nunca reciben recordatorio.
  4. Marketing y notificaciones masivas siguen congelados. Encenderlo es una decisión de Mario.
- **WhatsApp de CusRev:** no, porque pasa por su nube. Si se quiere WhatsApp, lo manda F360 con el consentimiento de reseñas (fase posterior).

## 7. Q&A

- **CusRev ya lo trae:**
  - pestaña "Preguntas" en la PDP, shortcode y moderación;
  - correo a quien preguntó cuando se responde;
  - votos y captcha;
  - permisos: cualquiera / registradas / compradoras verificadas;
  - etiqueta "compradora verificada" en las respuestas.
- Se guarda como `wp_comments` con `comment_type = cr_qna`; la respuesta es un comentario hijo.
- **Encenderlo es un ajuste, no código.**
- **Para Hilo:** CusRev no expone el Q&A por REST de forma limpia (el endpoint de Woo es solo para reseñas). Se necesita un endpoint mínimo de solo lectura (§9).

## 8. APIs y hooks disponibles

| Tipo | Nombre | Uso previsto |
|---|---|---|
| Filtro | `cr_review_form_before_comment` | Agregar al formulario de la PDP los campos de ajuste (talla habitual, talla comprada, cómo le quedó, comodidad, recomendaría) |
| Filtro | `cr_onsite_ratings`, `cr_onsite_questions` | Límites de criterios y preguntas. No se necesitan si los campos de ajuste van por el hook anterior |
| Acción | `comment_post` (WP / CusRev `action_after_review_added`) | Al guardar una reseña: mandar a F360 el id de la reseña + los campos de ajuste |
| Acción | `transition_comment_status` (WP) | Aprobar, rechazar o marcar spam → F360 cuenta solo las aprobadas |
| Acción | `cr_reviews_summary`, `cr_reviews_count_row`, `woocommerce_review_before_comment_text` | Pintar el resumen de ajuste y la línea "Talla 24 · le quedó exacto" en cada reseña |
| Acción | `cr_submit_onsite_question` | Nueva pregunta Q&A → aviso a Carolina |
| REST | `ivole/v1/review`, `ivole/v1/review-reply` | Son de la nube de CusRev (licencia). **No se usan** |
| REST | Woo `wc/v3/products/reviews` (con llaves), Store API `wc/store/v1/products/reviews` (pública, lectura) | Lectura de reseñas |
| Plantilla | `tema/customer-reviews-woocommerce/cr-single-product-reviews.php` | Se evita: una copia de la plantilla se queda vieja con cada actualización |

## 9. Qué se puede extender sin romper actualizaciones

- **Solo un mu-plugin** (patrón del de staging4: guard de host y generado desde el repo). **Nunca** se editan archivos del plugin ni se copia su plantilla.
- **El mu-plugin:**
  1. agrega los campos de ajuste al formulario de la PDP por `cr_review_form_before_comment`;
  2. en `comment_post` manda a F360 (Edge Function, llave de servidor) `{woo_review_id, woo_product_id, campos}`;
  3. en `transition_comment_status` manda el nuevo estado;
  4. expone **un** endpoint de solo lectura con llave de servidor para el Q&A aprobado (para que F360 lo proyecte a Hilo);
  5. pinta el resumen y las líneas de ajuste leyendo F360 (igual que la promesa de entrega).
- **Ajustes de CusRev sin código** (con OK de Mario, en staging): encender Q&A, fotos en el formulario del recordatorio y recordatorios (este último bloqueado por la revisión legal).
- **Si CusRev cambia un hook en una actualización,** la reseña se sigue guardando y solo deja de capturarse el ajuste. Se detecta con una prueba de humo después de cada actualización.

## 10. Qué vive en F360 (y qué no)

| Dato | Dueño | Por qué |
|---|---|---|
| Texto, estrellas, fotos, moderación, respuesta de la tienda, preguntas y respuestas | **CusRev / WP** | Ya funciona; F360 no copia el texto |
| Ajuste estructurado por reseña: talla habitual, talla comprada, cómo le quedó, comodidad, recomendaría | **F360** (`f360.review_fit`) | Es inteligencia de clienta y de producto: se cruza con la variante canónica, la talla MX y la ficha de producto, y lo consume Hilo |
| Verificación (en línea / tienda) y liga a pedido y variante | **F360** | Solo F360 ve las ventas en línea y en tienda con la variante canónica |
| Marca `verified` en Woo | Proyección desde F360 | Para que CusRev muestre su insignia |
| Agregados (% talla exacta, comodidad, % recomienda, conteos) | **F360**, calculados | Una sola fórmula para PDP, admin y Hilo |
| Ajuste declarado por Fuxia (`product_knowledge.fit_category`, horma, ancho) | **F360** (CRO-3A, ya existe) | Respaldo cuando no hay muestra suficiente |
| Q&A para Hilo | CusRev es dueño; F360 guarda una proyección de solo lectura de las **aprobadas**, ligadas al `product_key` | Hilo consulta un solo endpoint F360 (conocimiento validado + Q&A aprobado + resumen de ajuste) |

**`f360.review_fit` (propuesta):**

| Campo | Descripción |
|---|---|
| `woo_review_id` | Único |
| `product_id` | F360 |
| `canonical_variant_id` | Nulo si no se puede ligar |
| Liga a la compra | `commerce_order_line_id` **o** `offline_sale_item_id` (nulos si no hay compra) |
| `verified_source` | `online_order` / `store_sale` / `none` |
| `usual_size_mx` | Talla habitual |
| `purchased_size_mx` | Talla comprada (de la variante cuando está verificada) |
| `fit` | `small` / `true` / `large` |
| `comfort` | 1–5 |
| `would_recommend` | Sí / no |
| `review_status` | Espejo de la moderación de WP |
| `created_at` | — |

- Se escribe solo por la Edge Function (servicio) y es auditable.
- **No** guarda texto, nombre, correo ni teléfono.

## 11. Cómo se liga reseña → pedido → variante canónica → ajuste

| Origen de la reseña | Cómo se liga | `verified_source` |
|---|---|---|
| Formulario del recordatorio (en línea) | `ivole_order` → pedido Woo → línea del producto → `variation_id` → `f360.channel_variant_identity` → variante canónica | `online_order` |
| PDP, clienta que compró en línea (mismo correo o usuario) | F360 busca en `commerce_order_lines` por el correo (hash) y el producto. Si compró **una** talla, queda ligada; si compró varias, "talla comprada" se elige **entre las que compró** | `online_order` |
| Compra en tienda (fase 2) | Liga de reseña por línea de venta (token opaco y revocable, como el QR). La manda la vendedora o Carolina por WhatsApp, con consentimiento de reseñas. El producto y la talla ya vienen puestos | `store_sale` |
| PDP sin compra encontrada | Se publica (como hoy) y el ajuste se guarda como **declarado** | `none` → **no cuenta** para el % de talla |

## 12. Propuesta visual en la PDP

```
Botas Largas                                         $4,200
★★★★★ 4.9 · 14 opiniones · 6 preguntas        ← liga a cada sección; se oculta con 0
───────────────────────────────────────────────
COLOR  ● café  ○ negro
TALLA (MÉXICO)  22 23 [24] 25 26 27      Guía de tallas
  ✓ 92% dice que viene a talla exacta · 25 compras verificadas
     (con muestra baja: "Horma: talla exacta · según Fuxia", del ajuste validado de CRO-3A)
[ Añadir al carrito ]
  Entrega Inmediata en Zona Metropolitana        ← CRO-6 (ya existe)
───────────────────────────────────────────────
OPINIONES  ★ 4.9 (14)
  Cómo queda    chico ▏▏ 4%   exacto ████████████ 92%   grande ▏ 4%
  Comodidad     4.8 / 5          Recomiendan  96%
  [Con foto]  [Talla 24]  [Más recientes]
  ┌──────────────────────────────────────────────┐
  │ ★★★★★  Ana G. · ✓ Compra verificada · ago 2026 │
  │ Talla habitual 24 · Compró 24 · Le quedó exacto │
  │ Comodidad ●●●●● · Sí la recomienda              │
  │ "Las uso todo el día…"   [foto]                  │
  └──────────────────────────────────────────────┘
PREGUNTAS (6)   [Haz una pregunta]
  ¿La horma es angosta? — Fuxia: Es normal; si tienes pie ancho…  ✓ 3 útiles
```

- Las estrellas, la lista, las fotos y el Q&A son los de CusRev, con estilo de la marca por CSS.
- Lo nuevo (línea de ajuste junto a la talla, barra "Cómo queda", comodidad, % recomienda, línea por reseña) lo pinta el snippet F360 con datos de F360.
- **Nunca** se muestra un promedio de la marca dentro de la ficha de un modelo.

## 13. % talla exacta y muestra mínima

**Cálculo** (por **modelo** F360, todas las tallas y colores juntos, porque comparten horma):
- `n` = reseñas **aprobadas**, **verificadas** (`online_order` o `store_sale`) y con `fit` contestado, de los últimos 24 meses;
- `% exacta = fit = true / n`; también `% chica` y `% grande`.

**Muestra mínima y redacción:**

| n verificadas | Qué se muestra |
|---|---|
| 0–4 | Nada de % de clientas. Si CRO-3A está **validado**: "Horma: talla exacta · según Fuxia". Si no, nada |
| 5–9 | "4 de 5 compras verificadas dicen talla exacta" (conteo, sin %) |
| ≥ 10 | "92% dice que viene a talla exacta · 25 compras verificadas" |
| ≥ 10 y < 70% exacta | En vez del %, la dirección: "Viene chica: el 40% pidió media talla más" (si `chica` domina) |

- **Por qué 10:** con n = 10 y 90%, el intervalo de confianza del 95% (Wilson) va de ~60% a ~98%. Por debajo de 10 un % engaña más de lo que ayuda. Con n ≥ 25 el intervalo baja a ±~12 puntos.
- El **% con su n** se muestra siempre desde 10 (es un hecho).
- La **frase categórica** ("✓ Viene a talla exacta", y lo que Hilo afirma sin dar el %) exige además que el **límite inferior de Wilson** sea ≥ 70%. Ejemplos:
  - 9/10 (límite ~60%) muestra "90% · 10 compras verificadas", sin la frase;
  - 23/25 (límite ~75%) sí lleva la frase.
- **Contradicción:** si con n ≥ 10 lo que dicen las clientas contradice el `fit_category` validado por Carolina, el admin le avisa. **No se cambia solo.**
- **Hilo** usa la misma función y los mismos umbrales.

## 14. Qué puede hacer Carolina esta semana (sin código)

1. **Llenar y validar "Ajuste y talla" (CRO-3A) de sus 10 modelos más vendidos.** Hoy hay **0 validados** de 58 productos F360. Es el respaldo de la PDP y de Hilo mientras no haya muestra.
2. **Contar de dónde salieron las reseñas en lote** (07-31 y 10-01): ¿son de clientas reales de tienda? Se quedan publicadas, pero sin la etiqueta de verificada.
3. **Anotar las 15–20 preguntas que más le hacen** por WhatsApp y en tienda, con su respuesta y por modelo. Son la semilla del Q&A y de Hilo.
4. **Elegir 10 clientas frecuentes de tienda** que aceptarían dejar reseña con foto (para la prueba de la fase 2, con su consentimiento).
5. **Confirmar la pregunta de "talla habitual":** ¿en talla mexicana (22–27)? Se recomienda que sí, igual que la PDP.

## 15. Qué NO debemos construir

- Otro motor de reseñas: tabla de textos, estrellas propias, moderación propia o subida de fotos propia.
- Copiar el texto de las reseñas o datos personales de las autoras a F360.
- Un sistema de recordatorios propio mientras el de CusRev sirva. Tampoco el WhatsApp de la nube de CusRev ni funciones Pro.
- Editar archivos del plugin, o la copia de la plantilla de reseñas en el tema.
- % de talla por variante o color (muy poca muestra), o un % con n < 10.
- Un promedio de la marca dentro de la ficha de un modelo.
- Reseñas escritas por el equipo, generadas con IA o marcadas como verificadas sin evidencia.
- Puntos o premios por reseña: cambia las reglas de lealtad y no se hace a escondidas. Si se quiere, es una decisión aparte de Mario.
- Q&A propio en F360: se usa el de CusRev y F360 solo lo proyecta para Hilo.
- Importar reseñas de Google o redes.

## 16. Unidades propuestas (después de la aprobación; todas en staging)

| Unidad | Qué | Depende de |
|---|---|---|
| **3B-1** | `f360.review_fit` + función de agregados con umbrales y pruebas + acción `reviews_summary` en `f360-storefront` | — |
| **3B-2** | mu-plugin: campos de ajuste en el formulario de la PDP, envío a F360, espejo de moderación; ligado a compra en línea | 3B-1 |
| **3B-3** | Snippet en la PDP: línea de ajuste junto a la talla, barra "Cómo queda", línea por reseña; estrellas · conteo · preguntas bajo el título | 3B-1 |
| **3B-4** | Recordatorio de CusRev encendido (correo, formulario local con fotos) | **Revisión legal del texto** + OK de Mario |
| **3B-5** | Reseña de compras en tienda (liga por línea de venta) | Consentimiento de reseñas + OK de Mario |
| **3C-1** | Encender el Q&A de CusRev en staging4 (ajuste) + estilo de la marca | OK de Mario |
| **3C-2** | Endpoint de solo lectura del Q&A aprobado + proyección en F360 + tool de Hilo `get_product_answers` (conocimiento validado + Q&A + resumen de ajuste) | 3C-1, 3B-1. **El deploy de Hilo va en el pase** |

## 17. Decisiones para Mario

| # | Decisión | Recomendación |
|---|---|---|
| D-3B-1 | ¿El % de talla cuenta solo compras **verificadas**? | Sí |
| D-3B-2 | Umbrales: 5 (conteo) / 10 (%) / Wilson ≥ 70% para decir "talla exacta" | Sí |
| D-3B-3 | ¿Talla habitual en talla MX? | Sí |
| D-3B-4 | ¿Encender el recordatorio de CusRev? | Después de la revisión legal del texto de la casilla |
| D-3B-5 | Reseñas de tienda por liga de WhatsApp | Fase 2, con consentimiento de reseñas separado |
| D-3C-1 | Q&A: ¿cualquiera puede preguntar (con moderación) o solo registradas? | Cualquiera + moderación + captcha |
| D-3C-2 | ¿Quién responde el Q&A? | Carolina, en WP → Reseñas → Q&A. Si le resulta pesado, una pantalla en el admin F360 que escriba en CusRev (sin otro motor) |
