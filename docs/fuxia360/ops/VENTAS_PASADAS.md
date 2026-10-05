# Ventas pasadas (resumen histórico) — STAGING, 2026-10-05

**Decisión (Mario, 2026-10-05):** Carolina carga las ventas generales de este año hechas **antes** de Fuxia 360. No hay datos de clientas.
- Un bazar se carga con nombre, fechas, monto y pares.
- Una tienda se carga con mes, monto y pares (aproximados).

Lo de la tienda en línea **no** se carga: viene de WooCommerce y Commerce Facts.

**Pantalla:** admin → Ventas → **Cargar ventas pasadas** (`/ventas/pasadas`). Pueden usarla dueñas y operadoras.

**Archivos:**
- Migración `supabase/migrations/20261010000200_f360_historical_sales.sql`.
- Rollback `supabase/rollbacks/20261010000200_f360_historical_sales.down.sql`.
- Pruebas `supabase/staging/f360_historical_sales_tests.sql` (26/26; suite 877/877).
- `admin-web/src/app/(app)/ventas/pasadas/*`, `lib/f360.ts` (`listHistSales`) y `actions.ts` (`saveHistSaleAction` / `voidHistSaleAction`).

## Reglas

| Regla | Por qué |
|---|---|
| Es un **resumen**, no una venta: no tiene modelo, talla, clienta, puntos ni movimiento de inventario | Los pares ya salieron; sin detalle no puede alimentar "top modelos" ni el CRM |
| Tienda: cualquier día → el mes completo; **uno activo por tienda y mes** | No duplicar |
| Bazar: por nombre (sin crear una ubicación) o un bazar existente; máximo 31 días; uno activo por bazar y fecha de inicio | Los bazares viejos no ensucian la lista de ubicaciones |
| No se acepta el mes en curso, fechas futuras, fechas antes de 2025 ni antes de la apertura (`locations.starts_on`, si existe) | Solo periodos terminados |
| **No se cuenta doble:** se rechaza el periodo si esa tienda ya tiene ventas registradas por la app de Fuxia 360 (`offline_sales.created_by_rpc`) | El periodo ya está contado pieza por pieza |
| Solo MXN | Nunca mezclar monedas |
| Corregir = anular con motivo y volver a cargar; bitácora append-only `f360.historical_sales_log` con snapshot | Trazabilidad |

## Pendiente
- El dashboard usará `f360.historical_sales_active`: aparece en totales por mes y ubicación, marcado como "resumen histórico".
- Ninguna tienda tiene fecha de apertura en staging. Si Carolina la pone (por ejemplo, Polanco en septiembre), el sistema evita cargas anteriores a esa fecha.
