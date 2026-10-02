# Track D · D3 Conteo físico de apertura: reporte

**Fecha:** 2026-10-02. **Alcance:** staging.

**Qué no se hizo:**
- No se cargó ningún opening balance.
- No se escribió inventario.
- No se tocó producción.

**Decisiones aplicadas (Mario, 2026-10-02):**
- La homologación hecha en staging se reutiliza en producción, previo un delta fresco y la validación de `woo_variation_id`. Cualquier diferencia queda bloqueada para revisión humana.
- El opening balance sale solo del conteo físico.
- Hay doble control y una ventana corta de congelamiento.
- Se permite un conteo preliminar.
- Antes de aprobar se reconcilian los movimientos posteriores y se recuentan las variantes afectadas.
- Ningún conteo modifica inventario.
- El opening balance requiere la aprobación explícita de Mario.

## 1 · Diseño

Migración `20261007000700_f360_d3_opening_count.sql`, aplicada en staging. Rollback: `supabase/rollbacks/…000700….down.sql`.

| Pieza | Qué es |
|---|---|
| `opening_counts` | Una sesión por ubicación y canal. Estados: `preliminar` → `congelado` → `aprobado`, o `cancelado`. Solo puede haber una abierta por ubicación. |
| `opening_count_lines` | Una línea por variante (modelo → color → talla). Guarda el conteo 1, el conteo 2 y el reconteo, cada uno con persona y hora; la cantidad final y su hora; el estado; lo que pasó después de contarla (`affected`); y la referencia de Woo. |
| `opening_count_unlisted` | Pares "sin ficha": encontrados físicamente pero sin variante homologada. |
| `opening_count_changes` | Historial de cada paso. Solo agrega; no se puede editar ni borrar. |

**Alcance de la hoja:** son las variantes **confirmadas** en Homologación del canal.
- "Actualizar lista" agrega lo que se confirme después.
- Si una homologación se reabre, esa variante queda "fuera de alcance". Su historial se conserva.

**Congelamiento:** reutiliza `f360.location_in_cutover`, el mismo bloqueo del corte C3. Mientras el conteo está `congelado` o `aprobado`, Bodega CDMX rechaza recibir, transferir y ajustar.

## 2 · UX: Admin → **Conteo de apertura** (dueñas y operación)

- **Arriba:**
  - El estado.
  - Una barra de avance con las tallas que tienen conteo final y su total de pares.
  - Contadores: sin contar, falta 2º conteo, diferencias, recontar y sin ficha.
- **Controles:**
  - Actualizar lista.
  - Congelar bodega (dueña).
  - Reconciliar.
  - Aprobar (dueña). El botón queda deshabilitado y lista **en palabras** lo que falta.
  - Cancelar.
- **Vistas:**
  - **1 · Conteo:** por modelo → color, una casilla grande por talla, y se guarda por color.
  - **2 · Segundo conteo (a ciegas):** la otra persona ve "Conteo 1 hecho", pero no el número.
  - **Reconteo:** solo las tallas que lo necesitan, con el motivo: "C1 3 · C2 2" o "vendió 1 en línea después de contarse".
  - **Pares sin ficha:** se anotan con descripción, talla y pares, y los resuelve una dueña.
  - **Reporte:** `Modelo · color · talla | Woo actual | Conteo 1 | Conteo 2 | Reconteo | Conteo físico (final) | Diferencia | Opening balance | Estado`, con descarga a CSV.
  - **Imprimir hoja de conteo** (`/conteo/hoja`): modelo → color, con una caja por talla para contar en papel.

## 3 · Controles de doble conteo

| Regla | Dónde se garantiza |
|---|---|
| El conteo 2 lo hace **otra persona** | En la base de datos: un CHECK `count2_by <> count1_by`, más una validación en la RPC |
| El conteo 2 es **a ciegas** | La hoja `conteo2` no devuelve los valores del conteo 1 |
| Nadie corrige el conteo 1 de otra persona | La RPC solo deja corregir el conteo 1 a quien lo hizo, y solo antes del conteo 2 |
| Si 1 = 2, ese es el final; si no, la talla pasa a **diferencia** y requiere reconteo | La RPC, con el estado por línea |
| El reconteo solo aplica donde hace falta (diferencia o recontar) | La RPC |
| La aprobación solo es de una dueña y lleva nota | La RPC, más el historial |

## 4 · Ventas entre el conteo y el cutover

- **El riesgo:** hasta el cutover, la tienda sigue vendiendo productos legacy y esos pares salen físicamente de Bodega CDMX. Fuxia 360 todavía no los descuenta.
- **Cómo se maneja:**
  1. **Conteo preliminar** con anticipación. Después, una **ventana corta de congelamiento**, que bloquea los movimientos de Fuxia 360 en la bodega.
  2. **Reconciliar** revisa, por cada talla con conteo final, dos fuentes:
     - las **líneas de pedido Woo** que el webhook registró después de la hora de su conteo (pedidos pagados, cruzando la variante o su `woo_variation_id`; solo cantidades, sin datos de clientes);
     - los **movimientos de Fuxia 360** en esa ubicación posteriores al conteo.
  3. Toda talla afectada pasa a **"Recontar"**. Si se recuenta después de reconciliar, el sistema exige **reconciliar de nuevo** antes de aprobar.
  4. Entre la aprobación y la carga del opening balance, la bodega **sigue congelada**. La carga (D4/cutover) debe hacerse inmediatamente después, y antes de cargar se reconcilia una vez más.
- **Requisito para producción:** el webhook de pedidos de Woo producción → Fuxia 360 tiene que estar activo **antes** del conteo, para que la reconciliación vea esas ventas. Hoy solo está en staging4.
- Si Mario prefiere, la ventana final también puede incluir poner la tienda en mantenimiento unos minutos. Es decisión de negocio y no está automatizada.

## 5 · Pruebas

- **Base de datos** (`supabase/staging/f360_d3_tests.sql`): **30 de 30 PASS**. Corren en una transacción que se revierte, con su propio canal y bodega.
  - **Permisos:** quién puede iniciar, congelar, aprobar y resolver.
  - **Una sola sesión abierta** por ubicación.
  - **Alcance:** lo que se agrega o se reabre en Homologación.
  - **Doble control:**
    - el conteo 2 no puede ser de la misma persona;
    - nadie sobrescribe el conteo 1 de otro;
    - el conteo 2 es a ciegas;
    - si coincide queda como final y si no, queda en diferencia → reconteo.
  - **Pares sin ficha.**
  - **Congelamiento:** con la bodega congelada, recibir se rechaza.
  - **Reconciliación:**
    - una venta Woo posterior → recontar;
    - un reconteo posterior a reconciliar → reconciliar de nuevo.
  - **Referencia Woo:** la diferencia solo se calcula si Woo controla stock.
  - **Aprobación:**
    - pide nota y lista sus bloqueos;
    - al aprobar, **0 eventos y 0 saldos de inventario**;
    - el conteo aprobado queda sellado y la bodega sigue congelada.
  - **Historial inmutable.**
  - **Cancelar** libera el congelamiento.
- **Suite completa:** **535 de 535 PASS** (14 archivos).
- **E2E** (`admin-web/e2e/d3-conteo.spec.ts`, contra Vercel staging): **1 de 1 PASS**. Participan dos personas reales de staging, Carolina (conteo 1) y Mario (conteo 2 a ciegas), sobre las 348 tallas que Carolina ya confirmó.
  - La sesión de prueba se canceló y después se borró con `scripts/f360/d3_test_session_cleanup.mjs`. Ese script solo borra conteos cancelados cuya nota empieza con "Prueba de pantalla".
  - Hoy staging tiene **0 conteos**.

## 6 · Screenshots (`d3_screens/`)

| Archivo | Muestra |
|---|---|
| `01-inicio.png` | Conteo iniciado (preliminar), avance y controles |
| `02-conteo-1.png` | Carolina cuenta Paula: Azul marino y Bambi |
| `03-conteo-2-a-ciegas.png` | Mario cuenta sin ver el conteo 1 ("Conteo 1 hecho") |
| `04-reconteo.png` | Talla 38: "C1 3 · C2 2", para recontar |
| `05-sin-ficha.png` | "Mule beige sin etiqueta · talla 37 · 1 par", por resolver |
| `06-congelado-bloqueos.png` | Bodega congelada, la aprobación deshabilitada y la lista de lo que falta |
| `07-reporte.png` | Reporte: Woo actual (sin control · en stock) / conteos / final / diferencia / opening balance |
| `08-hoja-imprimible.png` | Hoja para contar en papel |

## 7 · Rollback y readiness

- **Rollback:** `supabase/rollbacks/20261007000700_f360_d3_opening_count.down.sql`. Se niega a correr si hay un conteo congelado o aprobado; primero hay que cancelarlo. Restaura el bloqueo de C3 tal como estaba.
- **Readiness para un conteo real** (falta):
  1. Que Carolina termine la Homologación: hoy hay 348 tallas confirmadas.
  2. Fecha y personas para el conteo 1 y el conteo 2. Deben ser dos personas distintas con cuenta de operación o de dueña.
  3. Que, para producción, el webhook de pedidos Woo → Fuxia 360 esté activo antes del conteo (§4).
  4. D4: construir y probar en staging la **carga** del opening balance desde un conteo aprobado (§8). **No está construida.**

## 8 · D4 (preparación, nada construido todavía)

| Paso | Qué hace | Cómo se probará |
|---|---|---|
| Carga del opening balance | RPC de dueña, solo desde un conteo `aprobado`: un evento `OPENING_PHYSICAL_COUNT` hacia Bodega CDMX por las cantidades finales, idempotente. Reconcilia antes y libera el congelamiento al terminar. | Staging: aprobar un conteo de prueba, cargar, verificar que saldos = movimientos, y que un reintento no duplica |
| Vínculos legacy | Crear `woo_variant_links` `legacy_adopted` **solo** desde homologaciones confirmadas (el guard de D2 ya lo exige) | Staging4: sus variation IDs son los de producción |
| Envío de stock | El envío automático escribe `manage_stock`, la cantidad y `backorders: no`; con 0 se muestra agotado (P3) | Staging4: tallas en 0 se ven agotadas, y la reconciliación da 0 diferencias |
| Pedidos legacy | La ingesta por `variation_id` (D2) descuenta la variante en Bodega | Pedido de prueba en staging4: se descuenta una vez y la entrega repetida queda como duplicada |
| Rollback de D4 | Quitar los vínculos legacy, con la carga revertida de forma auditada | Ensayo completo en staging |

## 9 · Git

- **Commit D3:** `26c54cb` (migración, pruebas, pantalla). Este reporte y el e2e van en el commit siguiente.
- **Rama `fuxia-360`:** se hizo push hasta `29c79bd` después de revisar secretos. **No hay merge a main.**
- **Sin commit en la copia local:** los cambios de marca "by HiloLabs.ai" (`layout.tsx`, `login/page.tsx`, `Shell.tsx`) no son de este trabajo.
