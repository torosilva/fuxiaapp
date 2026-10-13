# D12 · Fase A: lecturas con sesión restringidas (STAGING) — 2026-10-11

> **Autorización de Mario (2026-10-11):** preparar, implementar y probar la fase A **solo en staging**.
> **Producción no se ha tocado.** Aplicarla allí requiere una autorización posterior.
> **Hallazgo de origen:** `docs/fuxia360/SECURITY_FINDING_2026-10-11_LEGACY_RLS.md`.

| Pieza | Archivo |
|---|---|
| Migración | `supabase/migrations/20261027000100_d12_legacy_rls_phase_a.sql` |
| Reversión | `supabase/rollbacks/20261027000100_d12_legacy_rls_phase_a.down.sql` |
| Prueba | `supabase/staging/test_d12_phase_a.sql` (BEGIN…ROLLBACK; se corre completa) |

## 1. Políticas: antes y después (diff exacto)
Huella de las políticas de `staff`, `offline_sales` y `support_tickets`:
- **Antes:** `2ec9510e087e128f34d390291306d617` (15 políticas). Es **idéntica en producción y en staging**.
- **Después:** `af59dcb17262410f50c250b4be082926` (12 políticas y 2 funciones `d12_*`).

```diff
 -- public.staff
-auth read staff            SELECT  {public}         auth.role() = 'authenticated'                       ← cualquier sesión veía el NIP
-staff_read_own             SELECT  {authenticated}  active = true                                       ← ídem (personal activo)
-admins_all_staff           ALL     {authenticated}  customers.phone = jwt.user_metadata.phone AND role='admin'   ← ver §3
+d12 staff read store roles SELECT  {authenticated}  d12_staff_reader()      -- admin/staff de la app, o owner/operator de F360
 anon_read_active_staff     SELECT  {anon}           active = true           -- SIN CAMBIO (fase B)
 staff admin write          ALL     {public}         my_role() = 'admin'     -- sin cambio (la admin lee y edita NIP)

 -- public.offline_sales
-auth read offline_sales            SELECT {public}        auth.role() = 'authenticated'                 ← cualquier sesión veía todas las ventas
-customers_read_own_sales           SELECT {authenticated} customer_phone = jwt.user_metadata.phone      ← ver §3
-admins_staff_all_sales             ALL    {authenticated} customers.phone = jwt.user_metadata.phone AND role IN (admin,staff)
+d12 offline_sales read store roles SELECT {authenticated} d12_store_reader()   -- admin/staff, o owner/operator/seller de F360
 offline_sales own by phone         SELECT {public}  customer_id = my_customer_id() OR customer_phone = my_phone()   -- sin cambio
 offline_sales staff insert/update         {public}  my_role() IN (admin,staff)                                     -- sin cambio
 anon_insert_offline_sales / anon_read_offline_sales / anon_read_own_sales                                       -- SIN CAMBIO (fase B)

 -- public.support_tickets
-auth read support_tickets       SELECT {public}        auth.role() = 'authenticated'            ← cualquier sesión veía todos los tickets
+d12 support_tickets read staff  SELECT {authenticated} my_role() IN ('admin','staff')
+d12 support_tickets read own    SELECT {authenticated} customer_id = my_customer_id()
```

`d12_store_reader()` y `d12_staff_reader()`:
- Son `SECURITY DEFINER` porque una sesión normal no puede leer `f360.user_roles`.
- Solo las puede ejecutar `authenticated`; a `anon` y `PUBLIC` se les revocó el permiso.
- No reciben argumentos y solo devuelven verdadero o falso.

La identidad sale siempre de `public.customers.auth_user_id` (`my_role`, `my_phone` y `my_customer_id`) o de `f360.user_roles`. **Nunca de datos que el usuario pueda editar.**

## 2. Quién ve qué (después)
| Identidad | `staff` (con NIP) | `offline_sales` | `support_tickets` |
|---|---|---|---|
| Anónimo (pantalla de NIP de la app anterior) | personal activo, **sin cambio** (fase B) | **sin cambio** (fase B) | nada |
| Clienta con sesión | **nada** | solo las suyas (`customer_id` o su teléfono registrado) | solo los suyos |
| Clienta que falsifica `user_metadata.phone` | nada | solo las suyas | solo los suyos |
| Personal de la app anterior (`customers.role = staff`) | todo, incluido el NIP (lo necesita la pantalla de NIP con sesión) | todo | todo |
| Admin (`customers.role = admin`) | todo; además da de alta, edita y borra | todo | todo |
| Vendedora de F360 (`seller`, rol `customer` en la app) | nada | todo (inicio y ventas del día en ubicaciones de la app anterior) | nada |
| Operadora o dueña de F360 | todo (el "modo anterior" busca por NIP) | todo | solo si además es admin/staff |

**Cuentas reales en producción (conteo):**
- 2 admin (dueñas F360);
- 3 staff (2 de ellas vendedoras F360);
- 1 vendedora F360 con rol `customer`.

Todas quedan cubiertas por las nuevas políticas.

## 3. Hallazgo adicional que la fase A cierra: identidad falsificable
Tres políticas confiaban en `auth.jwt() -> 'user_metadata' ->> 'phone'`: `admins_all_staff`, `admins_staff_all_sales` y `customers_read_own_sales`.

Cualquier usuario puede cambiar su propio `user_metadata` con `supabase.auth.updateUser({ data: { phone } })`. Por eso:
- una clienta que pusiera ahí el teléfono de una admin obtenía **ALL** (leer, editar y borrar) sobre el personal, NIP incluidos, y sobre las ventas;
- poniendo el teléfono de otra clienta, leía sus compras.

La prueba P2 lo cubre: con el teléfono de la admin falsificado no ve ni modifica nada, y con el de otra clienta solo ve sus propias ventas.

**Fuera del alcance autorizado, en el mismo patrón:** `channels.admins_all_channels` y `channel_inventory.admins_all_inventory` tienen el mismo problema. Se cierran en la fase B, junto con `anon_update_inventory_sold`.

## 4. Pruebas (staging, 2026-10-11, después de la copia nocturna de las 13:14)
`test_d12_phase_a.sql` crea dentro de la transacción las identidades, una tienda, una vendedora con NIP, 3 ventas y 2 tickets. Todo se deshace al final; se verificó que quedan 0 usuarios `zz-d12-*`.

| Bloque | Qué comprueba | Resultado |
|---|---|---|
| P1 | La clienta no ve el personal ni encuentra un NIP; ve solo su venta y su ticket. Su venta no reclamada aparece por teléfono (`tracking/index.tsx`). Una segunda clienta ve solo la suya. | OK |
| P2 | Con `user_metadata.phone` falsificado (de la admin o de otra clienta) no gana acceso ni puede editar `staff`. | OK |
| P3 | El personal de la app anterior ve todo el personal, encuentra a la vendedora por NIP, ve ventas y tickets y **registra una venta**. | OK |
| P4 | La admin lee todo y **edita el NIP** (pantallas `admin/staff`). | OK |
| P5 | La vendedora de F360 ve las ventas de la tienda, pero no el personal ni los tickets. | OK |
| P6 | La operadora de F360 en "modo anterior" encuentra a la vendedora por NIP y no ve tickets. | OK |
| P7 | Para el usuario anónimo **nada cambia**: la pantalla de NIP lista al personal activo, se puede registrar la venta anterior y no ve tickets. | OK |
| P8 | Ninguna función `SECURITY DEFINER` ejecutable por clientes lee `staff` o `support_tickets`. Las 6 que leen ventas con rol (`f360_get_sale`, `favorites_report`, `review_work_queue`, `legacy_store_sales_import`, `review_confirm_candidate`, `hist_sales_save`) rechazan a la clienta. | OK |

**Control negativo:** sin la migración, la misma prueba falla en P1 ("customer reads staff").

**Regresión (con la fase A aplicada):**
- **OK:** `test_store_sale_customer` (venta de tienda F360 con clienta), `test_favorites` y `test_finance_access` (recorrido completo de funciones y tablas de la contadora).
- **Fallan igual sin la fase A** (se comprobó revirtiéndola dentro de una transacción). No las causa este cambio:
  - `test_sales_reconciliation` ("Solo las personas autorizadas…");
  - `test_link_my_account` (la función ya existe);
  - `test_sellers_admin` ("Carolina Munoz ya es vendedora": choca con datos reales de la copia);
  - `test_sb0_access` ("T0 16 table privileges": son los permisos de producción que trajo la copia).
- **No se corrieron:** `test_admin_customer_add` y `test_thanks_member` terminan en `COMMIT` y dejarían datos.

## 5. Funciones RPC y Edge Functions (condición 5)
- **RPC:** ninguna función ejecutable por clientes lee `staff` (ni el NIP) ni `support_tickets` saltándose RLS (P8). Las que leen `offline_sales`:
  - con `require_role` operator/owner: `get_sale`, `favorites_report`, `hist_sales_save`, `review_*` y `legacy_store_sales_import`;
  - `f360_claim_store_sale`: exige sesión y un código, y actualiza solo la venta reclamada;
  - `f360_storefront_catalog`: solo usa cantidades agregadas por variante;
  - `f360_record_store_sale*`: requieren turno de vendedora.
- **Edge Functions en producción:**
  - `escalate-to-staff`: solo inserta el ticket y devuelve su id; no lee.
  - `inventory-approve`: valida `getUser` y `customers.role = 'admin'`.
  - `notify-approval-pending`: solo envía avisos a admins.
  - `loyalty-credit`: exige un secreto en el encabezado.
- ⚠️ **`claim-sale` (prioridad alta, va a la fase B):**
  - No identifica a quien llama; basta la llave pública, porque `verify_jwt` acepta el JWT anónimo.
  - Con `action = scan_qr` crea una venta ya reclamada y **acredita puntos con el `total` y los `items` que manda el cliente** para cualquier `qr_code`.
  - Con el reclamo por código, acredita a cualquier teléfono.
  - No evade la fase A (usa la llave de servicio para escribir y no devuelve listas), pero contradice la regla 6 de CLAUDE.md: no confiar en precios, totales ni puntos que manda el cliente.
  - Lo usan `vendedora/sale.tsx` (venta anterior) y `claim.tsx`.

## 6. Reversión (ensayada)
| Paso | Huella |
|---|---|
| Aplicada | `af59dcb1…` (12) |
| `.down.sql` | `2ec9510e…` (15, igual a producción), 0 funciones `d12_*` |
| Prueba sin fase A | falla en P1, como se espera |
| Reaplicada | `af59dcb1…` |
| Prueba | OK |

La reversión se ensayó dos veces: con la primera versión de la migración y con la definitiva.

La fila `20261027000100` de `supabase_migrations.schema_migrations` está en staging. Como la migración está en `origin/fuxia-360`, la copia nocturna la vuelve a aplicar.

## 7. Producción (NO ejecutado; requiere autorización posterior)
1. Verificar la huella previa con `prod_read.sh`. Debe ser `2ec9510e…` con 15 políticas; si difiere, abortar.
2. Aplicar con `scripts/f360/prod_sql.sh`, primero en ensayo y luego en aplicación, en una sola transacción, con su fila en `schema_migrations`.
3. Verificar la huella posterior (`af59dcb1…`, 12 políticas).
4. Prueba en la app real:
   - la admin abre Personal, Reportes y Tickets;
   - una vendedora de Polanco abre su turno y hace una venta;
   - una clienta abre "Mis compras" y Tracking.
5. **Reversión:** `.down.sql` con `prod_sql.sh` y borrar la fila de `schema_migrations`. La huella debe volver a `2ec9510e…`.

**Efecto esperado en producción:** las pantallas de admin y de vendedoras siguen igual. Una clienta deja de poder leer el personal (con NIP), las ventas ajenas y los tickets ajenos.

## 8. PRODUCCIÓN — aplicada el 2026-10-13 (autorización de Mario; la ejecutó él con `prod_sql.sh`)
**Pase:** `supabase/pase/20261013_d12_fase_a.sql@9429fe1`. Su cuerpo es idéntico, verificado con `diff`, a la migración probada en staging. Primero corrió el ensayo y luego la aplicación, que dio `APLICADO`.

### Diagnóstico previo y ensayos (todos en producción, sin cambios)
| Paso | Resultado |
|---|---|
| Huella de `staff` / `offline_sales` / `support_tickets` | `2ec9510e…` (15), igual a lo revisado |
| Políticas `anon` | `a8609ffb…` (7) |
| Políticas de `channel_inventory` / `channels` / `inventory_change_requests` | `daeca86a…` (13) |
| Permisos de tabla (7 tablas) | `27b518b7…` |
| `my_role` / `my_phone` / `my_customer_id` | `684e0a8a…`, idénticas a staging |
| Prueba por perfil antes de aplicar | falla como se espera: "clienta lee staff (10 filas)" |
| Ensayo aplicar + revertir | OK |
| Ensayo aplicar + prueba por perfil | OK |

### Después
| Comprobación | Antes | Después |
|---|---|---|
| Políticas de las 3 tablas | `2ec9510e…` (15) | **`af59dcb1…` (12)** = staging |
| Políticas `anon` (app anterior) | `a8609ffb…` (7) | `a8609ffb…` (7) **sin cambio** |
| Otras tablas de la app anterior | `daeca86a…` (13) | sin cambio |
| Permisos de tabla | `27b518b7…` | sin cambio |
| `d12_store_reader` / `d12_staff_reader` | — | `SECURITY DEFINER`; anon **no** ejecuta, authenticated sí |
| Fila de la migración en `schema_migrations` | 0 | 1 |
| Ventas `offline_sales` (n / total / última) | 45 / $205,900 / 2026-10-12 20:52 | **igual** |
| Inventario anterior `channel_inventory` (filas / stock / vendidos) | 165 / 231 / 52 | **igual** |
| Ledger F360 (eventos / último) | 498 / 2026-10-13 03:22 | **igual** |
| Personal (filas / activos / huella de NIP y estado) | 10 / 8 / `daf02872…` | **igual** |
| Tickets | 9 | 9 |

**Políticas instaladas:**
- `staff`: `d12 staff read store roles`, `staff admin write` y `anon_read_active_staff`.
- `offline_sales`: `d12 offline_sales read store roles`, `offline_sales own by phone`, `offline_sales staff insert/update` y `anon_insert_offline_sales` / `anon_read_offline_sales` / `anon_read_own_sales`.
- `support_tickets`: `d12 support_tickets read staff` y `d12 support_tickets read own`.

**Prueba por perfil con cuentas reales** (`20261013_d12_fase_a_prueba.sql`, en modo ensayo; solo lee y se deshace): **OK**.
- **Clienta real:** 0 filas del personal; solo sus ventas y sus tickets.
- **Clienta con el teléfono de la admin en `user_metadata`:** nada adicional.
- **Personal y admin:** las 10 personas del personal, las 45 ventas y los 9 tickets.
- **Vendedora F360 (rol `customer`):** todas las ventas; 0 del personal; solo sus tickets.
- **Anónimo:** 8 personas activas, 45 ventas y 165 filas de inventario, como antes; 0 tickets.

**Reversión:** `supabase/pase/20261013_d12_fase_a_reversion.sql`. Su ensayo en producción después de aplicar dio OK. Se ejecuta con `scripts/f360/prod_sql.sh supabase/pase/20261013_d12_fase_a_reversion.sql` y vuelve a `2ec9510e…` (15).
