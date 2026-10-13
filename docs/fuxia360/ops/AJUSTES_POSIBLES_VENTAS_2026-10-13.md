# Ajustes de inventario que podrían ser ventas — REPORTE (solo lectura) — 2026-10-13

> **Autorización de Mario (2026-10-13):** identificarlos **sin convertirlos automáticamente ni modificar puntos**.
> Nada se cambió: el inventario, las ventas y los puntos siguen igual.
> **Fuente:** producción, `f360.inventory_events` de tipo `ADJUSTMENT` con salida (`from_location_id` sin `to_location_id`), con el texto de la nota tal como lo capturó la persona. Las horas están en hora de Ciudad de México.

## Resumen (56 eventos de salida por ajuste, 101 pares)
| Clase | Eventos | Pares | Ubicaciones | Lectura |
|---|---|---|---|---|
| **A · venta explícita** ("vend…") | 4 | 5 | Amsterdam 264, Polanco | **casi seguro son ventas**: no generaron venta ni puntos ni clienta |
| **B · salida sin motivo o a una persona** ("salida", "salida a vale", "salida valeria garcia") | 6 | 13 | Polanco, Amsterdam 264 | **podrían ser** ventas, préstamos, consignación o entregas a personal: **hay que preguntar** |
| C · corrección de error ("error", "error de color", "eroor") | 40 | 73 | todas las tiendas y Bodega | correcciones de captura del 5 al 12 de octubre (sobre todo Paula, Sueco cucarrón, Byl y Loafer). **No** parecen ventas |
| C · traslado registrado como ajuste ("Salieron/Movieron a bodega") | 3 | 3 | Polanco | debió ser **transferencia** a Bodega CDMX. Bodega no recibió esos pares por ledger |
| C · dañado | 1 | 1 | Bodega CDMX | merma (debió ser `WRITE_OFF`) |
| C · **la nota dice "entrada" pero el movimiento es salida** | 2 | 6 | Polanco | **inconsistencia de captura**: `d282c8b0` (Byl 37, 2 pares, 5-oct 20:46) y `a238ec00` (Dallas 35/39/40, 4 pares, 7-oct 21:20) |

## A · Ventas explícitas (4 eventos, 5 pares)
| Cuándo | Ubicación | Nota | Artículos | Evento |
|---|---|---|---|---|
| 2026-10-07 12:12 | Tienda Polanco | "se vendio" | Cucarron single 38 | `bbb1d508` |
| 2026-10-12 09:48 | Amsterdam 264 | "vendido semana 5-10 oct" | Cucarron 38 | `312b6118` |
| 2026-10-12 09:49 | Amsterdam 264 | "vendidos semana del 5 al 10 oct" | Cucarron 38, Cucarron 39 | `42c58850` |
| 2026-10-12 09:50 | Amsterdam 264 | "vendido la semana del 5-10 oct" | Cucarron 40 | `5b0ca624` |

## B · Salidas que podrían ser ventas (6 eventos, 13 pares)
| Cuándo | Ubicación | Nota | Artículos | Pares | Evento |
|---|---|---|---|---|---|
| 2026-10-05 18:14 | Tienda Polanco | "salida" | Cucarron 37 | 1 | `3174e7d5` |
| 2026-10-05 18:33 | Tienda Polanco | "salida" | Cucarron 36 | 1 | `2646983a` |
| 2026-10-05 18:58 | Tienda Polanco | "salida" | Mafalda taches gamuza 37/38/39/40 | 5 | `bffbc47a` |
| 2026-10-09 13:12 | Tienda Polanco | "salida a vale" | Mafalda chocolate pepas grandes 37 | 1 | `8fe5313c` |
| 2026-10-11 11:37 | Tienda Polanco | "salida valeria garcia" | Croc 38 | 1 | `d24e29c2` |
| 2026-10-11 22:53 | Amsterdam 264 | "salida" | Paula 36/38/39/40 | 4 | `983d05b3` |

"vale" puede ser un vale o una persona: **no se interpreta**.

## Cruce con ventas registradas (para no contar doble)
- **Ventas de tienda desde el 1-oct:** 1 de la app anterior en Polanco (5-oct 12:34, "Ballerina 25") y 9 por turno F360 (8 al 12-oct). Ninguna coincide en fecha, ubicación y artículo con las clases A o B.
- **Amsterdam 264, San Jerónimo y La Noria no tienen ninguna venta por turno F360.** Sus vendedoras no tienen cuenta (ver `D12_FASE_B_PLAN.md`, oleada 2). Por eso, en esas tiendas las ventas solo pueden aparecer como ajuste o no aparecer.

## Qué implica (sin cambiar nada)
- **Ventas e ingresos:** las clases A (y B, si se confirman) no están en `offline_sales`. El reporte de ventas, la conciliación y el Centro de Inteligencia **subestiman** esas ventas. Tampoco hay precio cobrado ni forma de pago registrados.
- **Puntos:** si la compradora era clienta del club, **no recibió puntos**. No se acreditan retroactivamente sin decisión, porque no se sabe quién compró.
- **Inventario:** el saldo físico sí refleja la salida. No hay nada que corregir en el inventario por esto.

## Opciones para cuando Carolina responda (ninguna se ejecuta sin autorización)
1. **Solo etiquetar**, sin tocar inventario ni ventas: guardar en una tabla de revisión que el evento X "fue venta", "préstamo" o "corrección". Así los reportes pueden mostrar "ventas registradas como ajuste: N pares" por separado.
2. **Registrar la venta histórica** con el registro de ventas históricas por periodo (`f360_hist_sales_save`: totales por ubicación y fechas, auditado, por operadora), **sin** volver a mover el inventario, que ya salió. Requiere el precio cobrado y, si aplica, la clienta.
3. **Hacia adelante:** que Amsterdam, San Jerónimo y La Noria vendan por turno F360 (oleada 2) y que el ajuste no admita "vendido" como motivo (cambio de pantalla, con su propia autorización).
