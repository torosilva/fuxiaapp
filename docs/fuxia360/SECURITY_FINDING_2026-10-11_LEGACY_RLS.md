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
