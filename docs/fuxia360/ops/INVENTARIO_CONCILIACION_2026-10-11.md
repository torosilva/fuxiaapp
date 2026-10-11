# Conciliación de inventario México — 2026-10-11 (solo lectura)

**Nada se ajustó.** Este documento sale únicamente de consultas `SELECT` contra producción (`scripts/f360/prod_read.sh`, transacción `READ ONLY`). No se escribió en ninguna base de datos, no se movió stock y no se tocó WooCommerce.

Detalle completo por ubicación / modelo / color / talla: [`inventario_conciliacion_2026-10-11.csv`](inventario_conciliacion_2026-10-11.csv) (786 filas: 633 de F360 + 153 de la app legacy con existencias).

---

## 1. Resumen

- **Hecho — F360 (producción) tiene 645 pares** en `f360.inventory_balances`: Tienda Polanco 213, Bodega CDMX 174, San Jerónimo 99, Amsterdam 92, La Noria 65, En camino 2, Torreón 0. **No hay saldos negativos.** El ledger (`f360.inventory_movements`) cuadra 1 a 1 con los saldos en las 633 combinaciones variante/ubicación. Sin "En camino" (2 pares de la transferencia T-000005 Bodega → Polanco, abierta) quedan **643 pares físicos en México**.
- **Hecho — Carolina capturó 751 pares brutos** (RECEIPT + ADJUSTMENT de entrada, 3–8 oct). De ahí salieron: **72 por correcciones de captura** ("error", "error de color"), **19 por otras salidas por ajuste** ("salida", "salieron/movieron a bodega", "dañado", "se vendió", "salida a vale" y 6 marcadas "entrada" pero en sentido de salida) y **15 vendidos** en Tienda Polanco con venta F360 (8–10 oct). 751 − 72 − 19 − 15 = 645. **Si el ">700" es lo que se recuerda haber cargado, es el bruto (751) antes de corregir errores**; la carga neta de errores fue 679.
- **Hecho — la app legacy (`public.channel_inventory`) tiene 179 pares disponibles (stock − vendidos) en canales que NO existen en F360**: Contreras 153 (última actualización 30-sep), Monterrey 19, Guadalajara 5, y 2 en el canal legacy "Tienda Polanco". Nunca se migraron: `f360.location_cutovers`, `f360.legacy_inventory_map` y `f360.cutover_counts` están **vacías** en producción.
- **Hipótesis principal (no verificada): el ">700" incluye Contreras.** 645 + 153 = 798. Pero si los pares de Contreras se repartieron físicamente a Amsterdam / San Jerónimo / La Noria / Bodega (que se cargaron después en F360), sumarlos contaría doble. Solo Mario puede decir si Contreras sigue teniendo pares físicos.
- **Hecho — no existe conteo físico completo en el sistema.** La única sesión de conteo (`f360.opening_counts`, Bodega CDMX, modo doble, estado `preliminar`) tiene 9 pares contados de 672 líneas. Las cargas de tiendas se hicieron con "Recibir mercancía" / "Ajustar", no con el flujo de conteo. Ninguna ubicación tiene un conteo aprobado contra el cual comparar.
- **Hecho — las ventas en línea no explican la diferencia:** desde el 3-oct no hay pedidos Woo "countable" en `f360.commerce_orders` (1 cancelado y 1 reembolsado). Torreón (bazar) está en 0: si hay pares físicos en Torreón, nunca se capturaron.

## 2. Por ubicación

"Carga declarada" = entradas capturadas − correcciones por error (lo que Carolina dejó como inventario de arranque). "Diferencia" = F360 hoy − carga declarada (explicada por salidas, ventas y transferencias).

| Ubicación F360 | Tipo | Capturado bruto | Correcciones por error | Carga declarada | Otras salidas por ajuste | Vendido F360 | Transferencias neto | **F360 hoy** | Legacy (stock − vendido) | Último conteo físico |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Tienda Polanco | tienda | 249 | 26 | 223 | 18 | 15 | +23 | **213** | 2 (canal legacy "Tienda Polanco", tallas MX) | ninguno |
| Bodega CDMX | bodega | 203 | 5 | 198 | 1 (dañado) | 0 | −23 | **174** | — (sin canal legacy) | sesión preliminar: 9 pares de 672 líneas |
| San Jerónimo Lídice | tienda | 122 | 22 | 100 | 0 | 0 | −1 | **99** | — | ninguno |
| Amsterdam 264 | tienda | 111 | 17 | 94 | 0 | 0 | −2 | **92** | — | ninguno |
| La Noria | tienda | 66 | 2 | 64 | 0 | 0 | +1 | **65** | — | ninguno |
| En camino | tránsito | 0 | 0 | 0 | 0 | 0 | +2 | **2** | — | n/a |
| Torreón | bazar | 0 | 0 | 0 | 0 | 0 | 0 | **0** | — | ninguno |
| **Total F360** | | **751** | **72** | **679** | **19** | **15** | **0** | **645** | | |
| Contreras (sin ubicación F360) | tienda legacy | — | — | — | — | — | — | 0 | **153** | ninguno |
| Monterrey (sin ubicación F360) | bazar legacy | — | — | — | — | — | — | 0 | **19** | ninguno |
| Guadalajara (sin ubicación F360) | bazar legacy | — | — | — | — | — | — | 0 | **5** | ninguno |
| **F360 + legacy no migrado** | | | | | | | | | **645 + 179 = 824** | |

Notas:
- Bodega −23 y Polanco +23: 17 envíos Bodega → En camino → Polanco (recibidos) más T-000005 (2 pares en camino). Amsterdam envió 11 a En camino y le regresaron 9 (RETURN).
- Polanco "otras salidas" (18): "salida" 7, "entrada" capturada como salida 6, "salieron/movieron a bodega" 3, "se vendió" 1, "salida a vale" 1. **Los 3 pares "a bodega" salieron de Polanco por ajuste, no por transferencia**: no hay evidencia en el ledger de que hayan entrado a Bodega como tal (Bodega se cargó con "entrada" genérica).
- Hay 42 combinaciones variante/ubicación con movimientos que netean 0 y sin fila en `inventory_balances` (51 pares capturados y corregidos). No afectan el total.

## 3. Por modelo y talla

### 3a. F360: carga declarada vs hoy (77 combinaciones con diferencia, neto −34)

Todas las diferencias dentro de F360 están explicadas por movimientos registrados; no hay faltantes "sin explicación" en el ledger. Las principales:

| Ubicación | Modelo | Color | Talla | F360 hoy | Carga declarada | Diferencia | Tipo | Causa en ledger |
|---|---|---|---|---:|---:|---:|---|---|
| Bodega CDMX | Sueco cucarrón | Taupe | 39 | 1 | 3 | −2 | faltante | transferido a Polanco |
| Tienda Polanco | Ballerinas BYL puntudo | Gris | 37 | 0 | 2 | −2 | faltante | "salida" por ajuste |
| Tienda Polanco | Botas Largas | Negro | 39 | 0 | 2 | −2 | faltante | "salida" por ajuste |
| Tienda Polanco | Mafalda taches gamuza | Café | 37 | 0 | 2 | −2 | faltante | "salida" por ajuste |
| Tienda Polanco | Botas Largas | Negro | 35 / 40 | 0 | 1 c/u | −1 c/u | faltante | "salida" por ajuste |
| Tienda Polanco | Mafalda taches gamuza | Café | 38 / 39 / 40 | 0 | 1 c/u | −1 c/u | faltante | "salida" por ajuste |
| Tienda Polanco | Cucarron | Café 37, Verde 36 | — | 1 | 2 | −1 c/u | faltante | "salida" por ajuste |
| Tienda Polanco | Cucarron single | Chocolate | 38 | 0 | 1 | −1 | faltante | "salida" por ajuste |
| Tienda Polanco | Mafalda chocolate pepas grandes | chocolate | 37 | 0 | 1 | −1 | faltante | "salida" por ajuste |
| Tienda Polanco | Paula | Azul marino 36, Café 38 | — | 1 | 2 | −1 c/u | faltante | "salida" por ajuste |
| Tienda Polanco | Pointed Aladdin | Dorado | 37 / 38 | 1 / 0 | 2 / 1 | −1 c/u | faltante | venta F360 |
| Tienda Polanco | Ballerinas BYL puntudo | Dorado 39, Vino 39 | 39 | 1 / 0 | 2 / 1 | −1 c/u | faltante | venta F360 |
| Tienda Polanco | Cucarron | Dorado 40, Negro 40 | 40 | 1 / 0 | 2 / 1 | −1 c/u | faltante | venta F360 |
| Tienda Polanco | Canutillos · Leo Aladin · Mafalda Taches · Paula · Sandalia doble tira · Tacón grueso estoperoles · Cucarron láser | varios | varias | — | — | −1 c/u | faltante | venta F360 (ver CSV) |
| Bodega CDMX | Paula | Café / Negro / Talco | 39 y 40 | — | — | −1 c/u | faltante | transferido a Polanco |
| Bodega CDMX | Flats picudos con taches | Vino | 38 | 0 | 1 | −1 | faltante | "dañado" |
| Bodega CDMX | Leather Loafers | Beige | 37 / 38 | 0 | 1 c/u | −1 c/u | faltante | en camino (T-000005) |
| Tienda Polanco | Sueco cucarrón | Taupe | 39 | 2 | 0 | +2 | excedente | recibido de Bodega |
| Tienda Polanco | Paula | Café / Negro / Talco | 39 y 40 | 1 | 0 | +1 c/u | excedente | recibido de Bodega |
| Tienda Polanco | Mules Colectiva | Verde | 38 / 40 | 1 | 0 | +1 c/u | excedente | recibido de Bodega |
| La Noria | Cucarron | Negro | 36 | 2 | 1 | +1 | excedente | recibido (transferencia) |

Lista completa (77 filas F360 con diferencia + 633 en total): CSV, columna `fuente_comparacion = "F360 carga declarada…"`.

### 3b. Legacy no migrado (faltante en F360: 179 pares)

Tallas en numeración **MX** (22–27) en la app legacy; F360 usa **EU** (35–40). **No se convirtieron tallas** (no hay tabla de equivalencias aprobada), así que no se puede afirmar a qué variante F360 corresponde cada par.

| Canal legacy | Modelo (texto legacy) | Color | Talla | Legacy disp. | F360 | Diferencia |
|---|---|---|---|---:|---:|---:|
| Monterrey | Paula | Negro | 24 | 19 | 0 | −19 |
| Guadalajara | Botas | Negro | 25 | 3 | 0 | −3 |
| Contreras | Ballerinas Byl puntudo beige | Beige | 24 | 2 | 0 | −2 |
| Contreras | Cucarrón café | Café | 23 | 2 (+1 en otra fila) | 0 | −3 |
| Contreras | Cucarrón negro | Negro | 23 | 2 | 0 | −2 |
| Contreras | Mafalda dorados | Dorado | 24 | 2 | 0 | −2 |
| Contreras | Paula animal print | — | 23 | 2 | 0 | −2 |
| Contreras | Botas Cafés Largas | Cafe | 37 | 1 (2 − 1 vendido) | 0 | −1 |
| Guadalajara | Botas largas | Negro | 23 | 1 | 0 | −1 |
| Guadalajara | Paula | Negro | 28 | 1 | 0 | −1 |
| Tienda Polanco (legacy) | Ballerina | Negro | 25 | 2 | 0 | −2 |
| Contreras | resto de filas (Paula, Cucarrón, Mafalda, Sueco, Flats picudos, Mules colectiva, Ballerina puntudo/resorte, Byll puntudo, Botas, Croc, Slingback, Aladino, Mocasín) | varios | 22–27 | 1 c/u | 0 | −1 c/u |

Por familia de modelo en Contreras (153 pares, 148 filas; agrupado por texto del nombre legacy): Cucarrón 30, Ballerina/Byl puntudo/resorte 28, Paula 28, Mafalda 26, Sueco 16, Flats picudos 11, Botas 4, otros (Croc, Mules, Slingback, Mocasín, Aladino) 10. Detalle exacto en el CSV (`ubicacion = "Contreras (legacy, sin ubicacion F360)"`).

## 4. Explicaciones posibles del ">700" (de más a menos probable con la evidencia)

| # | Explicación | Cifra | Estado |
|---|---|---:|---|
| 1 | Se suma Contreras (legacy) a lo de F360 | 645 + 153 = 798 | Hipótesis: depende de si Contreras aún tiene pares o ya se repartieron |
| 2 | Es lo capturado en bruto por Carolina, antes de corregir errores | 751 | Hecho que el bruto fue 751; hipótesis que de ahí venga la cifra |
| 3 | Inventario al arrancar menos lo vendido después en Woo/tiendas legacy | 679 neto de errores | No llega a 700 por sí solo |
| 4 | Pares físicos no capturados (Torreón, bazares Monterrey/Guadalajara, Bodega incompleta) | 0 / 19 / 5 / ? | Bodega se cargó sin conteo formal; no hay forma de verificar sin conteo |
| 5 | Pares que salieron por "salida"/"a bodega" (19) siguen físicamente en algún lado | ≤ 19 | Hipótesis: 3 "a bodega" sin transferencia |

## 5. Qué falta para cerrar la conciliación

1. **Mario: ¿de dónde sale ">700"?** (hoja de conteo, app legacy, Woo, memoria de la carga de Carolina, factura de fábrica). Con el número exacto y su fecha se compara por ubicación.
2. **Mario: ¿Contreras 516 sigue teniendo pares?** Si sí → falta crear/cortar esa ubicación (C3) y migrar sus 153. Si no → ¿a qué tiendas se repartieron? (para no contar doble) y el legacy queda obsoleto.
3. **Bazares Monterrey (19) y Guadalajara (5):** ¿regresaron esos pares? ¿a dónde? ¿Torreón tiene pares físicos hoy?
4. **Conteo físico por ubicación** con el flujo de conteo (no "Recibir/Ajustar"), empezando por Bodega CDMX (la sesión actual está preliminar con 9 pares). Sin conteo no hay "faltantes/excedentes" contra realidad, solo contra lo capturado.
5. **Carolina: revisar las 19 "otras salidas"** (en especial 6 "entrada" registradas como salida y 3 "a bodega" sin transferencia) y confirmar si son reales.
6. **Tabla de equivalencia de tallas MX ↔ EU aprobada por Mario** si se quiere comparar legacy contra F360 talla por talla (no se inventa).

## 6. Fuentes consultadas (producción, solo lectura)

`f360.locations`, `f360.inventory_balances`, `f360.inventory_events`, `f360.inventory_movements`, `f360.transfers`, `f360.transfer_lines`, `f360.location_cutovers` (vacía), `f360.legacy_inventory_map` (vacía), `f360.cutover_counts` (vacía), `f360.opening_counts` / `opening_count_lines`, `f360.commerce_orders`, `f360.woo_variant_links`, `public.channels`, `public.channel_inventory`, `public.offline_sales`. Contexto: `docs/fuxia360/INVENTORY_MODEL.md` (§1 regla 7 y 9: "En camino" y bazares no suman a la existencia en línea), `docs/fuxia360/ops/PRODUCTION_INVENTORY_CUTOVER.md` (X1: Carolina cargó por "Recibir/Ajustar", no por conteo), `supabase/migrations/20260930000200_f360_c2_legacy_mapping.sql:17` (unidades legacy = `stock − sold`).

**Confirmación: no se ajustó ningún saldo, no se escribió en ninguna base de datos y no se tocó WooCommerce.**
