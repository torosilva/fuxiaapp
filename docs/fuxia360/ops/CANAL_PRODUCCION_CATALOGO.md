# fuxiaballerinas.com como segundo canal de Fuxia 360 (solo catálogo)

**Estado:** PLAN (2026-10-05). Nada construido ni conectado.
**Objetivo (dueño):** Fuxia 360 es donde se trabaja el catálogo; cada tienda es un canal. Se publica todo en staging4, se sigue trabajando en
F360 y después se actualiza fuxiaballerinas.com desde F360. Inventario y pedidos de producción siguen apagados hasta el pase de inventario
(`PRODUCTION_INVENTORY_CUTOVER.md`). Manifiesto de lo que pasa: `STAGING4_TO_PRODUCTION_MANIFEST.md`.

## Decisiones tomadas (regla del dueño: lo trabajado pasa tal cual)
- Se consolidan en producción **todos** los modelos (un producto por modelo), igual que staging4.
- Mientras Woo producción controle su stock (`stock_policy='woo_owned'`), las variaciones nuevas **heredan el estado de stock** de la variación vieja; modelos nuevos sin historia: `instock` (se venden sobre pedido, 10 días hábiles).
- F360 puede crear términos `pa_color`/`pa_medida` en producción.
- Reseñas (y preguntas de CusRev) de los productos viejos **se mueven** al producto unido.
- Redirecciones 301 con el plugin Redirection, **verificadas antes de ocultar** los productos viejos.
- Lo que requiere a Mario: crear la llave de WooCommerce de producción (usuario dedicado con rol solo-catálogo, sin pedidos ni clientas) y encender el canal.

## Problemas del código que el plan corrige
1. Activar un segundo target rompe funciones que asumen uno solo (`resolve_target`, `20260927010000:136-148` → "Hay más de una tienda"), mueve `online_location()` (`20261004000100:176-179`) y expone el catálogo a anon (`20261010000700:110-117`, `20261007002200:28-30`). → `woo_production` queda **`active=false`** toda la fase de catálogo; el catálogo usa su propia bandera.
2. Solo insertar una fila de producción cambia tableros de staging (`20261010000300:22`, `20261010000700:198`). → condición `is_production AND active AND stock_sync_mode<>'off'`.
3. `f360_store_availability` y `f360_scarcity_state` buscan `woo_variation_id` en todos los targets (`20261007001100:79-83`, `20261007002400:47-50`). → acotar por target.
4. Republicar un producto ya público termina `partial` siempre (`mapping.ts:96`) → bloquea la propagación (pasa hoy en staging4).
5. El publicador crea variaciones con `manage_stock:true, stock 0` y empuja stock (`mapping.ts:65-70`, `publisher.ts:154-178`); en producción (sin control de stock) saldría "agotado". → política de stock por canal.
6. La visibilidad (ocultar/mostrar) es catálogo, no stock: no debe apagarse con el kill switch de stock.
7. Guardas de legacy revisan el mapa de todos los targets (`20261007001900:132-157`). → acotar por target.
8. `f360_review_sync` falla si una reseña cambia de producto (`20261011000100:259`). → ruta de "mover" auditada.
9. `consolidate_finish` oculta los productos viejos de inmediato (`20261007001900:96-110`) → 404 sin redirecciones. → ocultar solo con redirecciones verificadas.
10. `expire_stale_jobs` no recibe target (`20260927010000:151-157`).
11. Repo ligado a producción (X3): toda migración con `--db-url` de faltx y `--dry-run`.

## Unidades
| U | Qué | Archivos principales |
|---|---|---|
| U1 | Capacidades por canal en `sales_targets`: `catalog_mode`, `stock_sync_mode`, `storefront_enabled`, `auto_propagate`, `stock_policy`, `allow_term_create`; auditoría append-only de cambios; RPC solo dueña con confirmación tecleando el dominio para encender en producción; reemplazo de los rechazos `is_production` por chequeos de capacidad (catálogo sí, stock/pedidos/conteo no). Staging4 queda idéntico. | `supabase/migrations/20261012000100_f360_channel_capabilities.sql` (+ rollback) |
| U2 | Funciones Edge multi-canal: secretos por target (`WOO_<KEY>_BASE_URL/USER/SECRET/WRITES`), verificación de identidad de la tienda antes de escribir, adaptador con guarda que bloquea cualquier escritura de stock si el canal no lo permite, publicador sin `allowProduction` fijo. | `_shared/f360-woo/{targets,guard,publisher,mapping,types,sync,content}.ts`, handlers `f360-woo-publish`, `f360-woo-sync`, `f360-store-reserve:61,109`, `deploy_woo_functions.sh` |
| U3 | Propagación: cada edición en F360 (precio, foto, texto, color) genera un trabajo por canal con catálogo encendido y `auto_propagate` (espera 3 min mientras Carolina edita; cron cada 5 min). | `20261012000200_f360_catalog_propagation.sql` |
| U4 | Admin: estado por canal en cada modelo, botón "Publicar en fuxiaballerinas.com", publicación en lote, tarjeta de canales con "Detener ya"; quitar `woo_staging4` fijo (`actions.ts:89`, `f360.ts:179,211`, `ConteoClient.tsx:28,55`). | `admin-web/src/app/(app)/…` |
| U5 | Terminar unión por canal: mostrar nuevo → redirecciones (CSV + verificación 301) → ocultar viejos → mover reseñas (registro `review_moves`, conteos verificados) → stock solo si el canal lo permite. Cada paso reversible. | `20261012000300_f360_consolidation_finish_v2.sql`, adaptador `listReviews/moveReview` |
| U6 | Identidad de producción: `woo_production` creado inactivo, categorías por slug, delta D1–D16 por lectura pública, re-anclaje auditado de la homologación (solo filas exactas). | `scripts/f360/woo_production_target.mjs`, `f360_legacy_reanchor` |

Cada unidad lleva pruebas (BD con rollback; Node con tienda simulada sin red; prueba de que ninguna escritura de stock llega a producción) y criterio de aceptación; detalle en el informe de diseño del 2026-10-05.

## Ensayo seguro
**No** se apunta un `woo_production` falso a staging4 (comparten ids y SKUs; el publicador adoptaría productos de staging4). En su lugar:
1. Tienda simulada cargada con el catálogo real de producción (lectura pública) para correr todo el flujo en pruebas.
2. Un clon nuevo de producción en SiteGround (p. ej. `staging5`) como `woo_prod_rehearsal` con las mismas reglas de producción; un modelo nuevo y una unión completa con redirecciones y reseñas; simulacro de apagado.

## Orden
1. U1 en faltx (sin cambio de comportamiento) → 2. U2 → 3. U3/U4/U5 en staging4 y **publicar los 58 modelos en staging4** → 4. ensayo →
5. U6 (lectura) → 6. llave de escritura de producción + encender catálogo (Mario) → 7. piloto: un modelo nuevo y una unión →
8. el resto por lotes → `auto_propagate` en producción. Stock, pedidos y tienda siguen apagados hasta el pase de inventario.
