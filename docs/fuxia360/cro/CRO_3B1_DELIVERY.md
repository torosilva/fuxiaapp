# CRO-3B1 · Modelo de ajuste + vínculo y verificación de reseñas — Entrega (STAGING, 2026-10-05)

**Estado:** aplicado en staging (`faltx…` + Edge Function `f360-storefront` + corrida en staging4).

| Verificación | Resultado |
|---|---|
| Pruebas 3B1 | **48/48** |
| Suite completa | **999/999** |
| Pruebas de la Edge Function | **12/12** |
| Rollback | Ensayado (deja 0 objetos de 3B1) |

**Producción:** no se tocó. **Pantallas:** ninguna en esta unidad (3B2 = PDP y cola de Carolina).

**Arquitectura aprobada (Mario):**
- CusRev sigue siendo el motor: texto, estrellas, fotos, moderación, recordatorios y Q&A.
- F360 agrega solo inteligencia:
  - ajuste, comodidad, recomendación;
  - verificación;
  - reseña → compra → variante canónica → modelo.
- Sin texto ni PII en F360. Sin otra identidad de producto.

## 1. Archivos

| Archivo | Qué |
|---|---|
| `supabase/migrations/20261011000100_f360_cro3b1_review_facts.sql` | Tablas, verificación, ajuste, métricas, regla de presentación, cola de Carolina |
| `supabase/rollbacks/20261011000100_f360_cro3b1_review_facts.down.sql` | Rollback |
| `supabase/staging/f360_cro3b1_tests.sql` (registrado en `scripts/f360/db_tests.mjs`) | 48 pruebas |
| `fuxia-native/supabase/functions/f360-storefront/handler.ts` (+ `test/handler.test.ts`) | Acción `review_sync` (solo llave de servidor) |
| `scripts/f360/review_backfill.php` | Herramienta WP-CLI: manda las reseñas existentes a F360 e imprime la clasificación |

## 2. Base de datos y API

**Tablas** (esquema `f360`, RLS sin políticas, sin acceso para app ni anon):

| Tabla | Qué guarda |
|---|---|
| `review_facts` | Una fila por reseña de CusRev: modelo, estrellas (número), moderación, nº de fotos/video, verificación, compra ligada (pedido Woo o venta de tienda), variante y talla compradas, y el ajuste (talla habitual, ajuste, comodidad, recomendaría). **Sin texto, autora, correo, teléfono ni hash** (hay una prueba de esto) |
| `review_purchase_candidates` | Compras en tienda cuya **compradora ya está probada** pero cuya pieza no tiene variante canónica (ventas del app viejo). Solo guarda nombre, talla y color de la pieza |
| `review_facts_log` | Bitácora append-only de cada cambio de verificación o de ajuste |

**Funciones:**

| Función | Quién | Qué hace |
|---|---|---|
| `f360_review_sync(target, review)` | service_role (Edge Function `review_sync`, llave de servidor) | Alta o actualización de la reseña, resuelve el modelo y verifica |
| `f360_review_set_fit(target, review, fit)` | service_role | Ajuste en talla MX o Fuxia (se guarda canónica); una sola vez por reseña. Lo usarán los formularios de 3B3 |
| `f360_review_confirm_candidate` / `_reject_candidate` | Dueña (Carolina) | Identifica o descarta la **pieza** de una compra con compradora probada |
| `f360_review_revoke_verification` | Dueña, con motivo | Quita una verificación (auditado) |
| `f360_review_work_queue()` | operator+ | La cola de Carolina (§6) |
| `f360_review_summary(product)` | viewer+ | La regla de presentación (§5) |

**Vistas y auxiliares:**
- vista `f360.review_model_metrics` (métricas por modelo, §7);
- `f360.size_mx` / `f360.size_from_mx`: la única conversión de talla en la base (MX = Fuxia − 13, la misma regla que la PDP y el KB de Hilo);
- `f360.wilson_lower`;
- `f360.review_params()`: umbrales en un solo lugar.

**Edge Function:** `review_sync` solo con `x-f360-key`. Un navegador recibe 403 (verificado en vivo). Solo se reenvía la forma permitida: si llegan `content`, `author` o `email`, se descartan (hay prueba).

## 3. Cómo se verifica (F360 decide con sus propios datos)

| Fuente | Prueba de identidad | Prueba de compra | Resultado |
|---|---|---|---|
| **Pedido Woo pagado** | La cuenta Woo de la reseña = `woo_customer_id` del pedido, **o** WordPress encontró el pedido por el correo de la autora (el correo nunca sale de WP) | Commerce Facts: `ever_paid`, pagado **antes** de la reseña, con una línea del **mismo modelo** | `VERIFIED_ONLINE` |
| **Venta en tienda F360** | SHA-256 del correo = correo de la clienta F360 (se compara al vuelo, no se guarda), o cuenta Woo = `customers.wc_customer_id` | `offline_sales` antes de la reseña, pieza con variante canónica del mismo modelo, **no** autoventa de vendedora | `VERIFIED_STORE` |
| **Venta vieja del app (histórico)** | Igual que la anterior (probada por el sistema) | Pieza sin variante canónica (solo texto) | `NEEDS_REVIEW`: Carolina identifica **la pieza** (como en la homologación). No puede elegir otro modelo |
| Sin evidencia | — | — | `UNVERIFIED` |

- **No existe ninguna función para marcar una reseña como verificada a mano.** Hay una prueba que lo comprueba. Carolina solo puede actuar sobre candidatas cuya compradora ya probó el sistema.
- La verificación es **pegajosa**: re-sincronizar no la quita. Solo una dueña puede revocarla, con motivo.
- **Ventas históricas agregadas** (bazar: fecha, monto, pares) no verifican nada, porque no tienen clienta.
- **Por modelo:** todos los colores comparten horma. `evidence.match` dice si compró **el mismo producto** (`same_product`) o **el mismo modelo en otro color** (`same_model`), para que la PDP nunca dé a entender un color que no compró.
- **Etiquetas para la UI** (3B2): "Compra verificada · Online" (`VERIFIED_ONLINE`) y "Compra verificada · Tienda Fuxia" (`VERIFIED_STORE`).

## 4. Ajuste estructurado

- **Campos:** talla habitual, talla comprada, ajuste (`small` / `true` / `large`), comodidad 1–5, recomendaría sí/no.
- **Tallas:** se guardan en la escala canónica (Fuxia 35–40) y se capturan en MX o Fuxia (23 MX → 36).
- **Talla comprada:** sale de la compra verificada. Si compró varias tallas del modelo, solo puede elegir una de esas. Una talla distinta se rechaza.
- Una reseña **no verificada** puede guardar su ajuste, pero **no cuenta** en ningún agregado.

## 5. Regla de presentación (aprobada) — `f360.review_summary`, la misma para PDP, Hilo y admin

| Compras verificadas con ajuste | Se muestra |
|---|---|
| n < 5 | Solo el ajuste **validado** por Carolina: "Horma: talla exacta · Según Fuxia". Si no está validado, **nada** |
| 5–9 | Conteo: "4 de 5 compradoras verificadas dicen que viene a talla exacta · Basado en 5 compras verificadas" |
| ≥ 10 | "92% dice que viene a talla exacta · Basado en 25 compras verificadas" |

- **Afirmación fuerte** (`claim`, para el ✓ y para Hilo): solo si n ≥ 10 **y** el límite inferior de Wilson ≥ 0.70.
  - 9/10 → muestra el 90%, sin afirmación fuerte;
  - 23/25 → la permite.
- Comodidad y "% la recomendaría" usan los mismos umbrales con su propia n.
- Siempre se devuelve la n.
- Spam y papelera salen de los agregados (probado).
- **Sin placeholders:** con los datos reales de hoy, ningún modelo tiene línea de ajuste. Solo aparece "4 opiniones · 5.0" donde las hay.

## 6. Cola de Carolina — `f360_review_work_queue()` (la pantalla llega en 3B2)

Un solo lugar, sin texto de reseñas ni PII; liga al admin de CusRev para leer la reseña.

| Sección | Hoy en staging |
|---|---|
| Modelos prioritarios (unidades de 90 días, en línea + tienda) | 10 (Cucarrón, Paula, Cucarrón láser…) |
| Modelos sin ajuste validado | 58 de 58 |
| Modelos con pocas reseñas verificadas (< 5) | 58 |
| Reseñas pendientes de moderación | 0 |
| Reseñas con compra posible (`NEEDS_REVIEW`, con sus candidatas) | 0 |
| Reseñas de productos Woo sin modelo F360 | 0 |

**Preguntas pendientes:** se agregan en 3C1.

## 7. Métricas por modelo para Growth (vista `f360.review_model_metrics`, ventana de 24 meses)

**Columnas:**
- `reviews`, `rating_avg`;
- `verified_reviews` (online / tienda), `verified_rate`;
- `fit_n` y `fit_small` / `fit_true` / `fit_large`;
- `comfort_avg`, `recommend_yes / recommend_n`;
- `photo_reviews`, `photo_rate`, `last_review_at`.

**Pendiente:** preguntas frecuentes y sin responder (llegan en 3C1). No hay atribución de conversión.

**Eventos:** los del Measurement Contract (`f360_review_view`, `f360_review_submit`, `f360_review_photo_view`) se emiten en 3B2/3B3. Para ser compatibles llevan `product_key` y, en el submit, `rating`; sin PII.

## 8. Las reseñas existentes — clasificación (punto 7)

**staging4 (copia de producción, 14 reseñas)**, con `review_backfill.php` contra F360 staging:

| Clasificación | n | Reseñas |
|---|---|---|
| **VERIFIED_ONLINE** | 2 | **171** (Suecos cucarrones dorado; Woo también la marca verificada); **170** (Cucarrón verde: compró Cucarrón **nude** 38 antes de la reseña → mismo modelo, otro color, `same_model`; **Woo no la verificaba**) |
| VERIFIED_STORE | 0 | En staging no hay ventas de tienda de estas clientas |
| NEEDS_REVIEW | 0 | — |
| **UNVERIFIED** | 12 | Sin cuenta ni pedido pagado del modelo. **Quedan publicadas, sin etiqueta** |

- **Nada se borró ni se marcó a mano.** La herramienta **no escribe en WordPress**: solo manda datos a F360 y lee.
- **Producción (26 reseñas):** no se corrió (sin autorización). Se corre en el pase, cuando exista F360 de producción con las ventas reales de tienda (`offline_sales` de producción) y la captura de pedidos. Se espera:
  - que las 10 del 10-01 ("Los compré en Polanco") puedan quedar `VERIFIED_STORE` o `NEEDS_REVIEW` **solo** si su correo coincide con una clienta con venta registrada;
  - si no, `UNVERIFIED`.
- **Límite de Commerce Facts:** solo tiene pedidos desde que se captura. Un pedido viejo fuera de esa ventana no verifica. En producción, primero se hace el backfill de pedidos.

## 9. Seguridad

- La Edge Function exige llave de servidor para `review_sync`. Las RPC de escritura son solo `service_role`; las de Carolina exigen rol (dueña para verificar o revocar).
- El correo nunca llega a F360: solo su SHA-256, comparado al vuelo y nunca guardado. Hay pruebas sobre la evidencia, la bitácora y los nombres de columnas.
- La herramienta de backfill se niega a correr fuera de staging4 sin `F360_ALLOW_HOST` explícito. La llave entra por stdin, nunca en el repo ni en la línea de comandos.

## 10. Migración y rollback

- **Aplicación:** con psql directo + registro en `schema_migrations`, porque `db push` también intentaría aplicar `20261010000900` (de la sesión fuxiaapp-3e, todavía sin aplicar).
- **Cambio posterior:** después se reemplazaron 2 funciones con `CREATE OR REPLACE`, para agregar `evidence.match`. El archivo de la migración ya tiene la versión final.
- **Rollback** (`.down.sql`): ensayado dentro de una transacción con ROLLBACK; quita las tablas y funciones de 3B1 y su fila en `schema_migrations`. CusRev y Woo no se tocan.

## 11. Criterios de aceptación

| Criterio | Estado |
|---|---|
| Verificación de compra online, tienda e histórico con evidencia | ✅ |
| Nunca verificada "porque Carolina dice" | ✅ (probado) |
| Online vs Tienda distinguibles | ✅ |
| Mismo modelo / mismo producto | ✅ |
| Ajuste estructurado con identidad canónica | ✅ |
| Regla progresiva + Wilson + n siempre | ✅ |
| Sin placeholders | ✅ |
| Sin texto ni PII en F360 | ✅ |
| Cola de Carolina (datos) | ✅ (pantalla en 3B2) |
| Métricas Growth por modelo | ✅ (preguntas en 3C1) |
| Clasificación de las reseñas existentes | ✅ staging4; producción en el pase |
| Regresión: promesa MX / CO / líneas / legacy, PDP 200 | ✅ |

## 12. Pendiente para 3B2 (no iniciado)

- Acción pública `review_summary` en `f360-storefront`.
- Componente de PDP: estrellas · opiniones · preguntas, línea de ajuste junto a la talla, comodidad, recomendación, etiquetas de verificación, filtros.
- Pantalla "Reseñas" en el admin con la cola de Carolina.
- Eventos del Measurement Contract.
