# Manifiesto de cambios · staging4.fuxiaballerinas.com → fuxiaballerinas.com

**Fecha:** 2026-10-05 · **Estado:** inventario de solo lectura (base F360 `faltx…` en solo lectura, Store API pública de ambos sitios, repo). Nada promovido.
**Instrucción del dueño:** todo lo que se cambió en staging4 pasa a producción. **Método:** se **repite** cada cambio en producción (con F360 o a mano según la capa); **nunca** se copia staging4 encima, porque producción cambió después de la copia (ver §0).
Complementa `PRODUCTION_INVENTORY_CUTOVER.md` (inventario).

## 0. Lo que tiene producción y staging4 no (se conserva)
- 12 reseñas nuevas (09-27 y 10-01): producción 26, staging4 10. Varias en productos que staging4 ocultó (1065, 3228, 3379, 782, 838).
- Etiqueta "Favoritos Fuxia Mailing" (id 42) en 3440, 873, 687.
- Página de inicio (16) editada en producción el 2026-10-05 16:47.
- GTM4WP "author name" apagado en producción.
- Pedidos, clientas y existencias reales desde ~09-24.
- No hay productos nuevos visibles en producción después de la copia (id máximo 3597); borradores/privados no son visibles públicamente.

## 1. Catálogo (hecho con Fuxia 360 contra staging4)

**Corrección 2026-10-05 (verificado en la base F360, solo lectura).** Lo que pasa a producción es **el catálogo de Carolina en Fuxia 360**,
no "9 uniones": **58 modelos activos** (4 archivados), cada uno con sus colores, tallas, fotos y precios, que en la tienda deben quedar
**un producto por modelo**. Estado de esos 58 frente a Woo (staging4):

| Grupo | Modelos | Situación |
|---|---|---|
| Ya publicados como un producto por modelo | 9: Ballerinas resorte taches, Botas cortas, Botas Largas, Cucarron, Cucarron single, Mafalda taches gamuza, Paula gamuza, Sandalia flor, Sandalias tiras amarrar | Unidos en staging4 |
| A medias | 3: Ballerinas BYL puntudo, Cucarron láser, Sueco cucarrón | Unión "publicando" sin terminar |
| Siguen como los productos viejos de Woo | 41, entre ellos **Paula (15 colores = 15 productos Woo)**, Mafalda Láser (5), Mafalda Taches (5), Flats picudos con taches (2), Loafer suede, Mules Colectiva, y los de un solo color (sandalias, plataformas, tacones) | Homologados, sin publicar desde F360 |
| **No existen en Woo** | 5: Braid, Canutillos, Ibiza, Leather Loafers, Nina Classic Strap | Modelos nuevos de Carolina: se crean |

Datos que faltan en F360 antes de publicar: **sin precio** Canutillos, Leather Loafers, Nina Classic Strap; **sin categoría** Flats picudos con taches,
Mafalda Láser, Mafalda Taches, Nina Classic Strap.
Por lo tanto, el trabajo de catálogo en producción es publicar los 58 modelos desde F360 (49 de ellos por primera vez, contando los 3 atorados),
ocultar los productos viejos por color de cada uno, mover sus reseñas y poner redirecciones. La tabla de abajo es el detalle de lo que ya se hizo en staging4.

Hoy **todo** camino de escritura de catálogo rechaza un canal de producción (`20260928000100:171`, `20261007001400:30`, `20261007001900:46`, `20261007002000:9`, `20261007000900:170`, `publisher.ts:38` + `allowProduction:false` en `f360-woo-publish/handler.ts:76`). Repetirlo exige una migración aprobada que abra producción.

| Cambio en staging4 | Detalle | Cómo se repite en producción | Decisión |
|---|---|---|---|
| Modelos unidos (un producto por modelo) | 9 publicados: Ballerinas resorte taches 3719, Botas cortas 3720, Botas Largas 3721, Mafalda taches gamuza 3819, Cucarron single 3821, Paula gamuza 3861, Cucarron 3883, Sandalia flor 3892, Sandalias tiras amarrar 3915. **3 atorados**: Cucarron láser (borrador 3793), Sueco cucarrón (en cola), Ballerinas BYL puntudo (falló 504) | Publicador F360 contra `woo_production` (borrador → revisión → visible) | Sí: estructura, URLs/SEO, reseñas, ids GA4 |
| Productos ocultados | 43 → privado: 26 por unión (144, 147, 145, 146, 2808, 2809, 845, 2776, 701, 873, 586, 593, 600, 579, 3239, 1065, 1079, 1086, 747, 782, 789, 796, 803, 824, 831, 838) y 17 "no existe" (3228, 139, 1072, 3379, 141, 133, 142, 138, 2841, 134, 130, 136, 152, 634, 153, 2910, 542) | Solicitudes de visibilidad contra producción; **redirecciones antes** | Sí (reseñas de producción quedan ocultas) |
| Vínculos retirados | 264 variaciones de 44 productos viejos | Llegan con la unión | — |
| Content push | 145 → "Botas Largas Café", 146 → "Botas Largas Negro" (nombre, descripción, fotos, precio 4200 + COP/USD) | Innecesario si se une (ambos quedan privados) | — |
| Paula adoptadas | 90 variaciones de 15 productos Paula por color | Vínculo al canal de producción después del conteo aprobado | — |
| Homologación | 792 variaciones: 666 confirmadas, 114 "no existe", 12 por revisar | Reutilizable si los ids coinciden (`d2_prod_delta.mjs`, lectura pública) | — |
| Categorías | ballerinas 18, botas 19, sandalia-alta 20, sandalia-plana 21 — **mismos ids en producción** | Mismas filas para el canal de producción | No |
| Fotos | 143 subidas a la biblioteca de staging4 | Se suben de nuevo al publicar | — |
| Precios COP/USD | 27 precios (8 COP, 19 USD), 28 cambios de Carolina (10-02 a 10-05); p. ej. Botas Largas COP 650000 / USD 300; Paula COP 400000 / USD 180 | Viajan con publicar/content push | **Sí (regla 13: precios vivos)** |
| Precios MXN | Sin diferencias en los 86 productos compartidos | — | — |
| Términos de color | Nude (42), Rojo (43) | Se crean al publicar | — |
| Stock | 257 variaciones con control de stock y backorders en tallas en 0 | **No se copia**: inventario por su propio plan | Ver inventario |
| **Macarena 3621** | Producto de prueba, **público** en staging4, huérfano en F360 | **No se promueve**; ocultarlo en staging4 | — |

## 2. WordPress / tema / plugins

| # | Cambio | Cómo se hizo | En repo | Cómo se pasa | Decisión |
|---|---|---|---|---|---|
| 1 | mu-plugin promesa de entrega + "Avísame" + líneas de checkout/gracias | SSH a `wp-content/mu-plugins` (`build_storefront_muplugin.py`) | Sí | Variante de producción: quitar guarda de host (`:16`), endpoints de producción; después de funciones Edge de producción | Sí |
| 2 | mu-plugin de medición (ids canónicos) | SSH | **No (sin commit)** | Commit; cambio de GTM; Growth congelado | Sí |
| 3 | Bricks plantilla 1955 `cshkxp` (tallas y color) | Bricks a mano | Sí | Pegar, firmar, purgar caché; cambiar la imagen de guía de tallas de staging4 (`f360-tallas-y-color-completo.html:19`) | Sí |
| 4 | Bricks 1955 `oyoypn` (entrega inmediata, apartado Gold 2 h, Hilo, botón fijo, tallas MX) | Bricks a mano | Sí | Pegar con endpoint de producción (`f360-entrega-inmediata.html:107`) | Sí |
| 5 | Bricks Tienda y plantilla de categoría (buscador, filtros, carruseles; 60 por página) | Bricks + ajuste de consulta | Parcial | Pegar código + ajuste a mano | Sí |
| 6 | WPCode #4099 Hilo chat global (reemplaza Joinchat) | WPCode | Sí | Nuevo snippet; **apagar Joinchat** en producción | Sí |
| 7 | WPCode #4105 "Fuxia 360 · Compra" (panel tras agregar, CSS checkout, franja de confianza, cupón BIENVENIDA10, sin método preseleccionado, gracias, rescate con link de pago) | WPCode | Sí, **sin confirmar qué versión está pegada** | Nuevo snippet **después de corregir el P0**: "Recibimos tu pago" aparece en pedidos pendientes (`STOREFRONT_V1_CLOSEOUT.md:659-661`) | Sí |
| 8 | WPCode #2551 `fuxia_texto_envio` (sin "Entrega INMEDIATA en la mayoría…" ni "6 MSI") | A mano | **No** | Mismas ediciones en producción | **Sí (MSI)** |
| 9 | Textos de d1ba621 (a la medida · 10 días hábiles; Entrega Inmediata ZM + fuera de ZM; cambios con cupón) | Vía 1, 4, 7, 10 | Sí | Con esos puntos | Sí (Colombia / fuera de ZM) |
| 10 | Página `/cambios/` (4080) + liga en footer | A mano | Parcial; liga del footer en duda | Crear página y footer | **Sí (texto legal)** |
| 11 | `bricks-child/functions.php` ~l.840: MX permite Mercado Pago custom/basic/créditos | A mano (Mario) | **No** | A mano en producción | **Sí (pagos)** |
| 12 | Mercado Pago en modo prueba | WP admin | — | **No se promueve** | — |
| 13 | Usuario REST `fuxia360-staging` + llave | WP admin | — | Llave **nueva** en producción | Sí |
| 14 | Ajustes de stock de Woo (manejo sí, ocultar agotados no, umbral 0) | heredado | — | Verificar en producción | Sí |
| 15 | Aislamiento del clon (Joinchat/Meta/GTM/Clarity apagados, correos bloqueados, no indexar) | WP admin | — | **No se promueve** | — |
| 16 | Firmas Bricks, regla `.htaccess` Authorization, cron real de SiteGround | A mano | — | Verificar en producción | — |
| 17 | Redirecciones de URLs viejas | **No instaladas** (404 en staging4) | CSV desde admin | Importar antes de ocultar/unir | **Sí (SEO)** |
| 18 | CSS que oculta "Disponible para reserva" | probablemente #1 | Parcial | Con #1 | — |
| 19 | Popup `fuxia_lead`, CusRev | sin cambios | — | — | — |
| ? | Páginas contacto (21) y nosotros (19) editadas en staging4 el 10-04 | **sin rastro** | No | Inspeccionar en WP admin | — |

## 3. Inventario
Ver `PRODUCTION_INVENTORY_CUTOVER.md`. Las cantidades de staging4 **no** se copian; el inicial son las cargas aprobadas de Carolina (decisión del dueño 2026-10-05: "son lo real") más los movimientos posteriores. Pedidos de staging4 son pruebas: nunca se promueven.

## 4. Integraciones
| Pieza | Staging hoy | Producción necesita |
|---|---|---|
| Webhooks Woo | 2 de F360 → `f360-woo-orders` de staging; los heredados "Fuxia App" y "Loyalty Sync" apagados | Webhook firmado nuevo al final; conservar los de producción; **rotar el secreto expuesto de Loyalty** |
| Funciones Edge | `f360-woo-*`, `f360-store-reserve`, `f360-storefront`, `f360-hilo-intake`, `f360-email` con secretos de staging | Desplegar en producción con sus secretos; quitar `woo_staging4` fijo (`f360-store-reserve/handler.ts:61,109`, `actions.ts:89`, `f360.ts:179,211`, `ConteoClient.tsx:28,55`, `deploy_woo_functions.sh:8`) |
| Snippets | 7 endpoints fijos a `faltx…` | Variantes de producción |
| Hilo | Widget llama al agente HiloLabs de producción; rama `f360-delivery-promise` sin push; parche de base de conocimiento sin aplicar | Apuntar a F360 de producción |
| Links de pago | crean pedido pendiente en staging4 | Secretos de producción; envío gratis fijo, carrito no se vacía, solo MX |
| Correos | prefijo `[STAGING] ` | Prefijo vacío; `RESEND`/`EMAIL_FROM` de producción |

## 5. Orden propuesto
0. Congelar y registrar: commit de lo no versionado; registro de lo pegado en WPCode/Bricks/functions.php (`cro/SNIPPETS_INSTALLED.md`); respaldo de producción; foto de lo nuevo en producción (§0). Terminar o abandonar las 3 uniones atoradas; ocultar Macarena en staging4.
1. Decisiones del dueño (§6).
2. Infraestructura F360 en producción (migraciones, `woo_production` **inactivo**, funciones Edge, llave nueva, quitar constantes de staging4).
3. Presentación sin promesa de stock: página Cambios + footer, #2551, tallas y color, Tienda.
4. Checkout #4105 (con el P0 corregido); `functions.php` y Mercado Pago a mano con autorización.
5. Hilo + Joinchat apagado.
6. Catálogo con F360: categorías → publicar unidos como borrador → revisar → redirecciones → mostrar/ocultar → precios.
7. Webhook de producción → modo sombra → stock (inventario), junto con la promesa de entrega y "entrega inmediata" en el producto.
8. Medición: cuando Growth se descongele.

## 6. Decisiones del dueño (resueltas 2026-10-05)
**Regla general: todo lo trabajado en staging4 pasa a producción tal cual.**
1. Se unen los 12 modelos (9 publicados + 3 atorados, que se terminan primero en staging4). Las **reseñas** de los productos viejos se **mueven al producto unido**.
2. Se ocultan los 43 productos.
3. Precios COP/USD: como están en los productos de F360.
4. **"6 MSI" se queda** (está en producción): la edición de #2551 en staging4 que lo quitó **no** se promueve en esa parte.
5. Política de cambios: la página `/cambios/` tal cual.
6. Código PHP en `bricks-child/functions.php` que agrega **Mercado Pago Checkout Pro**: pasa a producción (primero exportarlo y versionarlo).
7. Hilo reemplaza a Joinchat.
8. Redirecciones de URLs viejas: sí, antes de ocultar/unir.
9. Promesa Colombia / fuera de ZM: sigue abierta (no se inventa texto).
10. **Macarena no existe**: se quita de staging4 y nunca se promueve.
11. Página contacto: en producción dice "Newton 199, Polanco, Local 301" y el inicio de producción ya dice "Campos Elíseos 158"; staging4 lo corrigió a Campos Elíseos 158 → **se promueve**. Página nosotros: sin cambio de contenido (la fecha es por la regeneración de firmas de Bricks; el carrusel solo refleja el catálogo) → nada que promover.
12. P0 del checkout corregido en el repo (`tools/storefront/f360-compra.html` + `scripts/f360/build_storefront_muplugin.py`): "Recibimos tu pago" solo cuando el servidor confirma `is_paid()`; si no, "Registramos tu pedido… en cuanto se confirme tu pago te avisamos". Falta reinstalar en staging4 (#4105 y mu-plugin) y probar con un pedido pendiente.

## 7. Sin rastro (inspeccionar en WP admin antes de pasar)
Contenido exacto pegado en #4105, #4099, #2551 y Bricks `oyoypn`/`cshkxp`/Tienda (respaldos en `~/f360-backups`, fuera del repo); ediciones de contacto y nosotros; liga del footer; dónde vive el CSS de backorder; código de `fuxia_lead`, redirección `/co/` y `fuxia_set_country`; paginación de Tienda; identidad de Jetpack en staging4; entorno de HiloLabs; borradores/ajustes/webhooks de producción.
