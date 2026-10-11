# Hallazgo de seguridad · Políticas RLS abiertas en tablas de la app anterior (PRODUCCIÓN) — 2026-10-11

> Se encontró durante la prueba de aislamiento de la contadora (0700). Primero en staging, que es una copia de producción, y luego se
> confirmó en producción **solo con lecturas** de `pg_policies`, conteos y nombres de columnas.
> **No se imprimió ningún dato personal y no se cambió nada.** Está fuera del alcance de I5 y su corrección requiere la autorización de Mario.

## Qué está abierto (esquema `public`, app anterior)
| Tabla | Filas | Política | Quién | Efecto |
|---|---|---|---|---|
| `staff` | 10 | `anon_read_active_staff` (SELECT, `active = true`) | **anon** (sin sesión, con la llave pública de la app/web) | Lee el personal activo **incluida la columna `pin`** |
| `staff` | | `auth read staff` (SELECT, `auth.role() = 'authenticated'`) | cualquier sesión (clientas de la app) | Igual |
| `offline_sales` | 43 | `anon_read_offline_sales` / `anon_read_own_sales` (SELECT `true`) | **anon** | Lee todas las ventas de tienda anteriores (`customer_phone`, total, artículos…) |
| `offline_sales` | | `anon_insert_offline_sales` (INSERT) | **anon** | Puede **registrar ventas** |
| `offline_sales` | | `auth read offline_sales` | cualquier sesión | Lee todas |
| `channel_inventory` | 165 | `anon_update_inventory_sold` (UPDATE `true`) | **anon** | Puede **modificar el inventario de la app anterior** |
| `channel_inventory` | | `anon_read_inventory` / `read_inventory` | anon / sesión | Lee |
| `support_tickets` | 9 | `auth read support_tickets` | cualquier sesión | Lee **todos** los tickets (`customer_name`, `customer_phone`, `last_messages`, `notes`) |
| `inventory_change_requests` | 103 | `icr read open` (SELECT `true`, rol public) | anon y sesión | Lee las solicitudes |
| `channels` | 5 | lectura | anon / sesión | Bajo riesgo |

## Riesgo
- **Alto:**
  - **NIP del personal** expuesto a cualquiera con la llave pública.
  - **Escritura anónima** en ventas e inventario de la app anterior.
  - **Datos personales de clientas** en tickets y ventas, legibles por cualquier usuaria de la app.
- **Fuxia 360** (esquemas `f360` y `f360_board`) **no** está afectado: el recorrido de 249 funciones y 26 tablas no encontró accesos indebidos fuera de estas tablas `public`.

## Propuesta (NO aplicada; requiere autorización y coordinación con la app)
1. Revisar qué pantallas de la app móvil y del admin anterior todavía usan esas políticas. Algunas (`anon_*`) pueden ser restos del sistema anterior a Fuxia 360.
2. Por pase, con ensayo y reversión:
   - quitar `anon_update_inventory_sold`, `anon_insert_offline_sales`, `anon_read_offline_sales`, `anon_read_own_sales` y `anon_read_active_staff`;
   - restringir `auth read staff/offline_sales/support_tickets` a staff/admin (`my_role()`) o a la propia clienta (`my_customer_id()`).
3. **Rotar los NIP** del personal si la app anterior todavía los usa para algo.
4. Probar la app móvil (compras, puntos, tickets) y la tienda antes y después.

## Investigación de uso (2026-10-11, solo lecturas de código y producción)
**Conclusión: el modo anterior de la app (NIP sin sesión) sigue vivo en producción.** Cerrar hoy las políticas `anon_*` dejaría sin vender a las tiendas que todavía lo usan.

**Ventas de los últimos 30 días en `public.offline_sales`** (consulta en producción)

| Canal | Vía | Ventas | Última |
|---|---|---|---|
| Guadalajara | app anterior (insert directo) | 27 | 2026-09-30 |
| Tienda Polanco | app anterior | 5 | 2026-10-05 |
| Contreras | app anterior | 1 | 2026-09-17 |
| (sin canal) | Fuxia 360 (RPC, `created_by_rpc`) | 7 | 2026-10-10 |

**Código que depende de cada política**

| Política | Quién la usa |
|---|---|
| `anon_read_active_staff` (incluye `pin`) | `fuxia-native/app/vendedora/index.tsx:132`. La pantalla de NIP filtra `staff` por `pin` sin sesión. Se muestra a quien no tiene cuenta (`index.tsx:48`) y a dueñas y operadoras en "modo anterior". |
| `anon_insert_offline_sales` | `fuxia-native/app/vendedora/sale.tsx:190` (venta del modo anterior) |
| `anon_update_inventory_sold` | `vendedora/sale.tsx:162` (`sold + qty` desde el cliente) y `vendedora/inventory.tsx:92` (`stock`) |
| `icr read open` | `vendedora/inventory.tsx:60` y `admin/inventory-approvals.tsx` |
| `auth read support_tickets` | Solo pantallas de admin: `admin/index.tsx`, `admin/customer/[id].tsx`, `admin/dashboard-today.tsx`. La Edge Function `escalate-to-staff` usa la llave de servicio. |
| `auth read offline_sales` | Admin (`admin/*`), `vendedora/home.tsx` y `sales-today.tsx`, y `tracking/index.tsx:123` (la clienta busca ventas no reclamadas por su teléfono). |

## Pase propuesto, en dos fases (NO aplicado)
**Fase A: no rompe nada; se puede aplicar ya con su "sí".**
- `support_tickets`: lectura solo para `my_role() in ('admin','staff')`.
- `offline_sales` (sesión): admin/staff, o la clienta dueña (`customer_id = my_customer_id()` o su teléfono).
- `staff` (sesión): admin/staff. Quitar `pin` del SELECT para `authenticated` con privilegios por columna.
- Ensayo en staging, prueba de la app (admin, vendedora F360, tracking) y `.down.sql`.

**Fase B: requiere decidir el retiro del modo anterior.**
- Mover Guadalajara y Contreras (y Polanco, si todavía alterna) al turno de Fuxia 360, o reemplazar el NIP por un RPC `SECURITY DEFINER` que valide en el servidor sin devolver `pin`.
- Después, quitar `anon_read_active_staff`, `anon_insert_offline_sales`, `anon_update_inventory_sold` y `anon_read_*`.
- Rotar los NIP. Hoy los puede leer cualquiera que tenga la llave pública.

## Estado (2026-10-11, tarde)
- **Fase A:** implementada y probada **solo en staging** (autorizado por Mario). Detalle, diff, pruebas y reversión en `docs/fuxia360/security/D12_FASE_A.md`. Producción sin cambios; requiere autorización posterior.
  - Además se encontraron y cerraron en staging tres políticas que confiaban en `user_metadata.phone`, que el propio usuario puede editar.
- **Fase B:** solo plan, en `docs/fuxia360/security/D12_FASE_B_PLAN.md`. No ejecutada.
  - Nuevo punto de alta prioridad: la Edge Function `claim-sale` acredita puntos con el total que manda el cliente, sin identificar a quien llama.
