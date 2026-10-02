# Track D · D2 Mapping: reporte para aprobación

**Fecha:** 2026-10-02. **Alcance:** solo staging.
**Guardrails cumplidos:**
- Sin producción.
- Sin cutover.
- Sin escritura de stock.
- Sin cambiar SKUs legacy.
- Sin tocar los 129 productos Woo.
- Sin push.

**Decisiones aplicadas (Mario, 2026-10-02):** P1–P5 (ver `../../ops/TRACK_D_LEGACY_TAKEOVER.md`).

## 1 · Delta producción vs staging4 (P1)

- **Método:** Store API pública de los dos sitios. Solo `GET`, sin credenciales, sin cookies y sin admin. Script `scripts/f360/d2_prod_delta.mjs`; resultado en `d2_prod_vs_staging4.json`. Lectura del 2026-10-02 19:49 UTC.

| | Productos | Variaciones |
|---|---|---|
| Producción (`fuxiaballerinas.com`) | 129 | 792 |
| staging4 | 130 | 810 |

- Solo en producción: **0**.
- Con cambios: **0**. Se compararon nombre, slug, SKU, tipo, precio, oferta, categorías, atributos, stock y los IDs y atributos de cada variación.
- Solo en staging4: **1**, Macarena (`3621`, `F360-MACARENA`), el producto de prueba de P2.3B.
- **Conclusión:** el catálogo legacy de producción es idéntico al de staging4. Los `variation_id` de staging4 son los de producción.
- **Hallazgo menor:** Macarena aparece en la Store API **pública** de staging4 (status `publish`), aunque en documentos anteriores figura como "privada". Es solo staging. Se reporta para corregir el documento o el estado.

## 2 · Números

| Medida | Valor |
|---|---|
| Productos Woo involucrados | **129** |
| Variaciones totales | **792** |
| **Modelos F360 propuestos** | **76**: 16 agrupan 2 o más productos Woo (69 productos) y 60 tienen un solo producto Woo |
| Mappings propuestos (estado *Propuesto*) | **414**: 318 con confianza alta y 96 con confianza media |
| Mappings confirmados | **0**. Le corresponden a Carolina; ninguna decisión se escribió en su nombre |
| Ambiguos (*Requiere revisión*) | **378**, ver §3 |
| Conflictos | **0** |
| Sin correspondencia | **0**: todas las variaciones tienen talla y una propuesta |
| **Cobertura** (confirmadas / total) | **0 %**. La cobertura de *propuesta* es 100 % (792 de 792), con 52.3 % listas para confirmar directamente |

**Por qué hay 378 en "Requiere revisión"** (ninguna se decidió de forma automática):

| Causa | Variaciones | Productos Woo |
|---|---|---|
| No se detectó color en el nombre (por ejemplo "Croc", "Tacon PR", "Plataforma Marcela") | 216 | 36 |
| Ya existe en staging un modelo F360 "Paula" creado aparte, con 3 pares de **prueba**: Carolina decide si es el mismo | 90 | 15 |
| El color aparece a mitad del nombre (por ejemplo "Botas Negras cortas", "Ballerinas puntudo vino taches") | 54 | 9 |
| Woo vende la talla como "cualquier color" (las 18 problemáticas, §3) | 18 | 3 |

- Los 76 modelos son una **propuesta**. La agrupación la confirma Carolina; el sistema nunca la aplica.
- Grupos propuestos con más productos Woo: Paula (15), Suecos cucarrones (9), Cucarron (8), Mafalda laser (5), Mafalda taches (5) y Cucarron láser (4).
- Ningún modelo propuesto mezcla precios ni categorías distintos en Woo.
- Detalle por producto y razón de cada propuesta: `d2_proposal.json`.

## 3 · Las 18 variaciones problemáticas

Las 18 están en **Requiere revisión**, con confianza baja, **bloqueadas para cutover** hasta que Carolina determine el color con certeza (P2). Ninguna tiene ventas registradas en la analítica de staging4.

| Producto Woo | variation_id | Talla | Por qué |
|---|---|---|---|
| `129` Mafalda laser caramelo | 428, 429, 430, 431, 432, 433 | 35–40 | Atributo local "Colores" BEIGE/TALCO (y "caramelo" en el nombre). Las variaciones son solo talla |
| `131` Mules Colectiva | 398, 399, 400, 401, 402, 403 | 35–40 | Además de 18 variaciones color × talla (Taupe, Verde, Vino) que **sí** se pueden mapear, tiene 6 "cualquier color" |
| `135` ByL puntudo | 374, 375, 376, 377, 378, 379 | 35–40 | `pa_color` Café/Dorado/Negro/Verde/Vino. Las variaciones son solo talla |

**Qué puede hacer Carolina:**
- Si sabe con certeza qué color físico sale, puede asignar el color en la pantalla.
- Si no, puede dejarlas en "Requiere revisión" con un motivo. Ese motivo queda registrado y bloquea la variación.
- **Protección en ingesta** (ya probada): una venta de una variación no adoptada de un producto Woo que sí se adoptó abre un aviso `unknown_sku` y no descuenta nada en silencio.

## 4 · Qué se construyó

**Base de datos.** Dos migraciones aplicadas en staging con `supabase db push --db-url` (antes se hizo `--dry-run`, que mostró exactamente esas dos). Cada una tiene su rollback.

1. `20261007000100_f360_d2_legacy_homologation.sql`
   - `f360.legacy_woo_map`: una fila por variación Woo con la foto de Woo (solo referencia), la propuesta y la decisión.
   - `f360.legacy_woo_map_log`: historial de solo agregar.
   - RPCs:
     - `f360_legacy_load_snapshot` y `f360_legacy_propose`: solo `service_role`.
     - `f360_legacy_homologation`, `f360_legacy_confirm`, `f360_legacy_mark` y `f360_legacy_reopen`: operator o owner.
   - **Una confirmación humana jamás se sobrescribe.** Se garantiza con `human_locked` y con un trigger que rechaza cualquier cambio automático. El candado no se puede quitar y las filas no se borran.
   - **Un mismo modelo F360 recibe varios productos Woo.** Un producto Woo es un color (o, en los multicolor, un color de la variación). Una variante F360 corresponde como máximo a una variación Woo por canal (índice único).
   - Confirmar crea **solo catálogo** (modelo, color, variante y SKU `F360-…`). No crea inventario, ni vínculo con Woo, ni envío de stock, ni precio.
   - No se puede mezclar un producto Woo legacy con un modelo publicado desde F360 (Macarena).
2. `20261007000200_f360_d2_legacy_channel_links.sql`, diseño para D4. **No crea ningún vínculo.**
   - `woo_variant_links.origin` (`f360_published` | `legacy_adopted`) más `woo_product_id`.
   - **Ingesta legacy por `variation_id → variant_id`, sin exigir que el SKU Woo sea igual al SKU F360.** Los productos publicados por F360 conservan la validación de SKU.
   - El envío de stock y la reconciliación toman el padre Woo del vínculo de variante.
   - Candados:
     - Un vínculo legacy solo existe si hay una confirmación humana que coincide.
     - El publicador F360 rechaza modelos legacy, para no duplicar productos Woo.
     - Una variante adoptada no puede tener un vínculo `f360_published`.

**Script de propuesta:** `scripts/f360/d2_homologation_propose.mjs`
- Agrupa por modelo usando el nombre normalizado.
- Toma el color del final del nombre, con un vocabulario basado en `pa_color` y en los nombres legacy.
- Nunca usa el SKU legacy como identidad.
- Aborta si el delta con producción no es cero.

**Pantalla para Carolina:** `admin-web` → **Homologación** (operator o owner).
- Columnas: Woo producto | color detectado | tallas y `variation_id` | producto F360 | color F360 | talla F360 | confianza y estado.
- Filtros por los 5 estados y búsqueda por modelo, producto Woo, SKU o `variation_id`.
- Flujo **"Revisar y confirmar"**:
  - Se elige un modelo nuevo o uno existente (así se agrupan varios productos Woo por color bajo un modelo).
  - Se pone un color F360 por producto Woo.
  - Las variaciones "cualquier color" nunca vienen preseleccionadas.
- Acciones adicionales: "Marcar…" (Requiere revisión o Sin correspondencia, con motivo) y "Reabrir" (con motivo).
- Canal de práctica `?canal=demo_d2`: una copia de 6 productos Woo para practicar sin escribir decisiones en la homologación real.

## 5 · Pruebas

- **Base de datos** (`supabase/staging/f360_d2_tests.sql`): **50 de 50 PASS**, en una transacción que se revierte y sobre un canal desechable.
  - Antes de aplicar se corrieron las migraciones con las pruebas dentro de una transacción revertida: 50 de 50.
  - **Suite completa después de aplicar:** 13 archivos, **475 de 475 PASS** (425 anteriores más 50 nuevas).
  - **Cubre:**
    - Snapshot y cambios de talla rechazados.
    - Permisos: la vendedora, anon y authenticated no pueden escribir propuestas ni leer la tabla.
    - Conflicto entre propuestas y su corrección.
    - Que el sistema nunca propone "confirmado".
    - Varios productos Woo bajo un solo modelo.
    - SKU F360 nuevo con el SKU legacy intacto.
    - Que no se crea inventario, vínculo ni envío de stock.
    - El candado humano: no lo sobrescribe la propuesta, no lo sobrescribe un UPDATE directo, no se desmarca y la fila no se borra.
    - Que el historial es inmutable.
    - Conflicto al confirmar.
    - Que no se mezcla con un modelo publicado por F360.
    - "Cualquier color" con la misma talla.
    - Marcar y reabrir con motivo.
    - Vínculos legacy válidos e inválidos.
    - El candado del publicador.
    - **Ingesta legacy:** con un SKU distinto, **sin SKU**, entrega repetida, conteo 0 que da `oversold` (nunca negativo), variación no adoptada que da aviso, producto nunca adoptado que da `legacy`, y Macarena con SKU incorrecto que sigue dando `sku_mismatch`.
    - El envío de stock y la reconciliación con el padre legacy (ATS 0, que Woo mostraría como agotado, P3).
- **E2E** (`admin-web/e2e/d2-homologacion.spec.ts`, local contra staging): **2 de 2 PASS**.
  - **Real `woo_staging4`, solo lectura.** Resumen 792/129, detalle por `variation_id` y filtro "Requiere revisión".
  - **Práctica `demo_d2`:**
    - Confirmó 3 productos Woo (Cucarron negro, nude y vino) como **un** modelo "Demo · Cucarron" con 3 colores.
    - Marcó "cualquier color" como Requiere revisión.
    - Confirmó los 3 colores de Mules Colectiva.
    - El conflicto de Croc → Demo · Cucarron / Nude / 35 fue **rechazado**.
    - Reabrió Cucarron vino con motivo.
- **Estado real después de todo:** `woo_staging4` tiene 0 confirmadas, 0 filas con decisión humana y 0 vínculos `legacy_adopted`.

## 6 · Screenshots del flujo de Carolina (`d2_screens/`)

| Archivo | Qué muestra |
|---|---|
| `01-resumen-real.png` | Homologación real: 792 variaciones, 76 modelos, 0 confirmadas, filtros por estado |
| `02-modelo-propuesto-suecos.png` | Modelo propuesto "Suecos cucarrones": 9 productos Woo como 9 colores, con detalle por `variation_id` |
| `03-requiere-revision-cualquier-color.png` | Mules Colectiva: la unidad "cualquier color" en Requiere revisión |
| `04-practica-antes.png` | Canal de práctica antes de decidir |
| `05-confirmar-modelo-cucarron.png` | Panel "Revisar y confirmar": modelo nuevo y 3 productos Woo, cada uno con su color F360 |
| `06-confirmado-un-modelo-tres-colores.png` | Resultado: un modelo F360, 3 colores, 18 variantes confirmadas |
| `07-mules-colores-de-la-variacion.png` | Multicolor: color tomado de la variación; "cualquier color" no preseleccionado |
| `08-mules-confirmado-y-bloqueado.png` | Colores confirmados; "cualquier color" se queda bloqueado |
| `09-conflicto-rechazado.png` | Conflicto rechazado, con el mensaje que ve Carolina |
| `10-practica-despues.png` | Estado final de la práctica (54 variaciones, 30 confirmadas, 55.6 %) |

Nota: en las capturas de página completa, el aviso amarillo fijo de "ambiente de pruebas" aparece a la mitad. Es un efecto de la captura, no de la pantalla.

## 7 · Qué falta exactamente para iniciar D3 (conteo físico)

1. **Carolina termina la homologación** de las 792 variaciones en staging. **Criterio propuesto:** 0 en *Propuesto* y 0 en *Conflicto*. Cada variación queda *Confirmada* o, con motivo, en *Requiere revisión* (bloqueada para cutover) o en *Sin correspondencia*.
   - La hoja de conteo sale **solo** de variantes confirmadas.
   - Un par físico que no tenga ficha se anota como "par sin ficha".
2. **Decisión de Mario: la homologación se hace en staging y se traslada a producción en el cutover** por `variation_id` (son idénticos, delta = 0), con un nuevo delta justo antes del cutover. La alternativa es repetirla en producción.
3. **Decisión de Mario: los productos de prueba de staging** ("Paula", "Paula cafe gamuza", "Sueco cucarron azul", "Suede Loafers", con pares de demo) **chocan con nombres reales**.
   - Recomendación: renombrarlos "Demo · …" en staging, para que Carolina pueda crear el modelo real "Paula" sin mezclar inventario de prueba. Hoy las 90 variaciones de Paula esperan esa decisión.
4. **Construir D3**, que todavía **no existe** para Bodega CDMX:
   - Hoja de conteo generada del mapping, en el orden físico que indique Carolina.
   - Captura del conteo.
   - Reporte `Woo actual (sin control · en stock) | Conteo físico | Diferencia | Opening balance F360`, con las ventas agregadas como contexto.
   - Aprobación de Mario.
   - El flujo `OPENING_PHYSICAL_COUNT` de C3 existe para tiendas legacy y se reutilizará donde aplique. Esto requiere su propio plan, pruebas y aprobación.
5. **Logística del conteo:**
   - Fecha.
   - Quién cuenta.
   - Congelar movimientos de Bodega CDMX durante el conteo.
   - Regla para las ventas Woo que ocurran **entre el conteo y el cutover** (se registran y se descuentan al tomar autoridad, o se cuenta lo más cerca posible del cutover). Esto entra en el procedimiento de cutover (D5).
6. **Corrección menor:** confirmar si Macarena debe seguir pública en staging4 (§1).

**No se hizo y no se hará sin aprobación:**
- Nada en producción.
- Ningún vínculo `legacy_adopted`.
- Ningún opening balance.
- Ninguna escritura de stock en Woo.
- Ningún cambio a SKUs ni a productos Woo.

**Rollback** (si se rechaza D2):
1. `supabase/rollbacks/20261007000200_….down.sql`. Se niega a correr si existiera algún vínculo legacy.
2. Después, `…000100_….down.sql`.

Los modelos "Demo · …" del canal de práctica son filas de catálogo de staging y se pueden archivar.
