# Centro de control (panel ejecutivo) — STAGING, 2026-10-05

**Decisión (Mario, 2026-10-05):** un tablero "joya de la corona", con vista interna y vista de presentación (para inversionistas o banco). **Siempre con datos reales, nunca inventados.** El diseño de referencia (DEMO, con datos de ejemplo) es el artifact "Fuxia 360 · Dashboard ejecutivo".

**Dónde:** admin → Ventas → **Centro de control** (`/tablero`). Pueden verlo dueñas y operadoras.

**Archivos:**
- Migración `supabase/migrations/20261010000300_f360_exec_dashboard.sql` (una sola RPC de lectura: `f360_exec_dashboard(periodo, presentación)`).
- Rollback `supabase/rollbacks/20261010000300_f360_exec_dashboard.down.sql`.
- Pruebas `supabase/staging/f360_exec_dashboard_tests.sql` (17/17; suite 894/894).
- Pantalla: `admin-web/src/app/(app)/tablero/{page.tsx,ControlCenter.tsx,control.css}` y `lib/f360.ts` (`getExecDashboard`).

## Reglas de los números

| Tema | Regla |
|---|---|
| Ventas | Venta neta de producto (`commerce_orders.net_product`, solo `countable`, por fecha de pago, hora de CDMX) |
| Monedas | El titular es **MXN**. COP y USD se muestran aparte y **nunca se suman** |
| Ventas pasadas | `historical_sales_active` cuenta solo en los periodos que cubre completos (por ejemplo, en "Este año"), con una marca visible |
| Pedidos de prueba | Se excluyen `sales_targets.is_test`. **Excepción:** en una base sin tienda de producción (staging) se incluyen y la pantalla muestra la franja "STAGING · INCLUYE PEDIDOS DE PRUEBA". Lo decide el servidor; la pantalla no puede pedirlo |
| Comparación | Hoy contra el mismo día de la semana pasada; 7 días contra los 7 anteriores; mes y año contra el mismo avance del periodo anterior |
| Privacidad | Sin datos personales. Los nombres de cumpleaños (primer nombre + inicial) solo los recibe un `customer_pii_viewer`, y nunca en la vista de presentación |
| Animación | Solo revela el número real (conteo, trazo); el feed muestra las últimas ventas reales. Respeta "reducir movimiento" |

## Pendientes y límites conocidos
- **No hay meta mensual** en el sistema, por eso no hay anillo de meta. Se puede agregar cuando exista la meta (plan de Growth).
- El inventario se valúa a **precio de venta**: no existe el costo.
- "Pedidos por enviar" cubre los envíos desde tienda (`online_store_shipments`); los que salen de Bodega no están en esa tabla.
- Las ligas de pago se cuentan por caso abierto. Saber si se pagaron requiere ligar el número de pedido (cambio de esquema futuro, en `pay_links`, que es de la sesión 67).
- Falta la revisión visual con sesión de dueña (ver reporte).
