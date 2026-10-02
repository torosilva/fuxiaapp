# Track D · Legacy Inventory Takeover

**Arrancado:** 2026-10-02, por decisión de Mario.
**Objetivo:** adoptar en Fuxia 360 el inventario del catálogo Woo legacy (129 productos), sin cambiar SKUs ni productos Woo. "Liberar" significa homologación **terminada, probada y lista para cutover**. El track **se detiene antes del cutover** con un reporte completo para aprobación.

## 1 · Decisiones de Mario (2026-10-02)

| # | Decisión |
|---|---|
| D-1 | **Liberar ≠ conectar producción.** Woo producción no se conecta al envío automático de stock hasta la aprobación explícita de Mario, después de revisar el conteo real. |
| D-2 | **Se conservan los SKUs legacy de Woo.** La variante F360 tiene su SKU canónico `F360-MODELO-COLOR-TALLA`, y el mapping la liga al SKU / variation ID legacy existente. Los productos **nuevos** creados desde F360 usan `F360-{PRODUCT}-{COLOR}-{SIZE}`. |
| D-3 | **El opening balance de Bodega CDMX es el conteo físico aprobado.** Woo es solo referencia: `Woo actual \| Conteo físico \| Diferencia \| Opening balance F360`. Antes del cutover no se escribe ninguna diferencia en Woo producción. |
| D-4 | **Woo México se alimenta solo de Bodega CDMX** (`INVENTORY_MODEL.md`). Colombia también, por ahora (N1, decisión vigente). `09_MIGRATION_PLAN.md` Phase 5 quedó marcada como *superseded*, con traza. |

**Guardrails:**
- Sin producción.
- Sin envío automático de stock a Woo producción.
- Sin modificar SKUs legacy.
- Sin consolidar los 129.
- Sin usar Woo como opening balance.
- Sin push a git sin autorización aparte.

## 2 · Fases

| Fase | Entregable | Estado |
|---|---|---|
| **D1 Discovery** | `audit/trackd/D1_DISCOVERY.md`, catálogo y CSV por variación | ✅ Sobre staging4. Pendientes P1–P4 |
| **D2 Mapping** | Tabla `woo_variation_id ↔ variante F360` aprobada por Carolina, más el cambio de esquema/código para vínculos legacy | ✅ Construido en staging (2026-10-02): migraciones, propuesta, pantalla y pruebas. **Reporte: `audit/trackd/D2_REPORT.md`.** Las confirmaciones son de Carolina (hoy 0) |
| **D3 Conteo físico** | Hoja de conteo de Bodega CDMX generada del mapping; captura y aprobación del conteo | Diseño en §4 |
| **D4 Dry run** | Carga completa en **staging**: opening balance y vínculos legacy contra staging4; pruebas de pedido y de envío | Diseño en §5 |
| D5 Reporte | Diferencias, excepciones y procedimiento de cutover para aprobación | Al terminar D4 |
| Cutover | — | **Fuera de Track D hasta aprobación** |

## 3 · D2 Mapping

> **Decisiones de Mario (2026-10-02), P1–P5:**
> - **P1:** lectura pública de producción, solo para el delta.
> - **P2:** las 18 "cualquier color" van a "Requiere revisión" (Carolina las resuelve; si no hay certeza, quedan bloqueadas para cutover).
> - **P3:** conteo 0 = agotado. Sobre pedido solo como MAKE_TO_ORDER explícito.
> - **P4:** ventas agregadas solo como contexto.
> - **P5: opción B.** En F360 la estructura es modelo → color → talla; varios productos Woo se mapean al mismo modelo. La opción A (espejo) queda **rechazada**.
>
> Lo implementado está en `audit/trackd/D2_REPORT.md`. La tabla de abajo es el análisis original y se conserva como historia.

**Ancla:**
- `woo_variation_id` por canal (D1 H1).
- El SKU legacy del padre se guarda como referencia inmutable: el valor que Woo reportaba al ligar, aunque sea una "copia" (H2).

**Cambios necesarios.** Una migración aditiva, con rollback y pruebas staging. Se presenta antes de aplicar:
1. `woo_product_links` y `woo_variant_links` llevan `origin` (`f360_published` | `legacy_adopted`) y `woo_sku_at_link`.
2. **Publicador:** un producto `legacy_adopted` **nunca** se publica ni se edita desde F360 (contenido, SKU, atributos e imágenes quedan intactos).
3. **Ingesta de pedidos** (H5): un vínculo `legacy_adopted` valida el SKU de la línea contra `woo_sku_at_link`. Si alguien cambió el SKU en Woo, sigue abriendo `sku_mismatch`; no descuenta a ciegas.
4. **Identidad F360:** cada variante adoptada recibe su SKU `F360-…` (D-2), bloqueado igual que hoy.

**P5 · Agrupación en F360 (decisión necesaria).** Los 129 son "un producto Woo por color". En Woo no se consolidan (D-2). En F360 hay dos caminos:

| Opción | F360 | Pros | Contras |
|---|---|---|---|
| **A · Espejo (recomendada para Track D)** | 1 producto F360 por producto Woo (por ejemplo, "Paula plata con verde": 1 color, 6 tallas) | Mapping 1:1 sin interpretación. No depende de que Carolina agrupe 129 productos antes del conteo. El esquema de vínculos no cambia de forma. | El catálogo F360 queda "un producto por color" como Woo, contra la regla 2 de `INVENTORY_MODEL.md`, como excepción temporal y documentada |
| B · Por modelo | "Paula" con 15 colores; cada color liga a su producto Woo | Cumple el modelo desde el día 1 | Carolina debe aprobar la agrupación de 129 productos (los SKUs no sirven para deducirla, H2). `woo_product_links` necesita un vínculo por color, que es un cambio de esquema más grande |

- Con A, consolidar después (B) solo mueve colores entre productos F360.
- **Los `variant_id`, SKUs F360, balances y vínculos de variación no cambian** (regla 14 de `INVENTORY_MODEL.md`), así que el inventario contado en D3 sigue valiendo.

**Clases de D1 en el mapping:**
- 444 `limpio`, 108 `sku_de_copia` y 204 `sin_sku` → se mapean, revisadas por Carolina.
- 18 multicolor con color → se mapean.
- 18 "cualquier color" → excepción (P2).

## 4 · D3 Conteo físico (Bodega CDMX)

- **Hoja de conteo.** Se genera del mapping aprobado: una fila por variante, en el orden físico que Carolina indique.
- **Solo pares físicamente en Bodega CDMX.** No se cuentan tiendas, bazares ni "En camino". Las tiendas entran por su propio flujo C2/C3.
- **Captura.** Reutiliza el conteo de apertura ya probado en C3 (`OPENING_PHYSICAL_COUNT`, con reaperturas auditadas: `20261004000100…`, `20261004000200…`). Una variante física sin mapping se anota como "par sin ficha", no se descarta.
- **Reporte de diferencias.** Formato de D-3, con la columna "Woo actual" = "sin control · en stock" (H4) y, si se aprueba P4, las ventas recientes como señal.
- **Aprobación del conteo:** Mario. Ese conteo aprobado es el opening balance.

## 5 · D4 Dry run (solo staging)

1. Aplicar en staging la migración de D2 y cargar los vínculos `legacy_adopted` del mapping aprobado contra **staging4**. Staging4 es copia de producción: los variation IDs coinciden si P1 confirma que no hay deriva.
2. Cargar el conteo aprobado como opening balance de Bodega CDMX en staging.
3. Pruebas, todas en staging y staging4:
   - Un pedido legacy de prueba descuenta exactamente una vez.
   - El reenvío del webhook queda `duplicate`.
   - Un SKU cambiado en Woo abre `sku_mismatch`.
   - Una variación "cualquier color" queda `legacy` sin descuento.
   - El publicador rechaza un producto adoptado.
   - El envío de stock en staging4 refleja Bodega con la política aprobada en P3.
   - La reconciliación queda en 0 diferencias.
4. Ensayo de rollback: se deshacen los vínculos y la apertura, auditado.

**Entregable:** reporte D5 con el procedimiento de cutover para producción. **No se ejecuta.**

## 6 · Fuera de alcance

- Cutover en producción.
- Escrituras en Woo producción.
- Corregir productos Woo multicolor.
- Consolidar productos Woo.
- Migrar `channel_inventory` (Track C).
- Retirar `wc_product_id` y `wc_variation_id` (N3).
