# D12 · Interruptor por tienda: preparación del despliegue controlado — 2026-10-13

> **Autorización de Mario (2026-10-13):** preparar el despliegue controlado. **No** se ejecuta la migración, **no** se publica la OTA, **no** se apaga ninguna tienda y **no** se cierran las políticas anónimas.
> Todo lo que se hizo en producción fueron lecturas y ensayos `--dry-run`, que terminan en `ROLLBACK`. Después de los ensayos, producción quedó exactamente igual: sin columna, sin funciones, sin tabla, sin fila de migración y con las mismas huellas.

## 1. SQL exacto, dependencias y permisos efectivos
| Archivo | Qué es |
|---|---|
| `supabase/migrations/20261029000100_d12_legacy_pin_switch.sql` | migración probada en staging |
| `supabase/rollbacks/20261029000100_d12_legacy_pin_switch.down.sql` | su reversión |
| `supabase/pase/20261013_d12_interruptor.sql` | **pase de producción**: guardas previas, cuerpo idéntico a la migración (verificado con `diff`), fila en `schema_migrations` y guardas posteriores |
| `supabase/pase/20261013_d12_interruptor_reversion.sql` | **reversión de producción**: cuerpo idéntico al `.down.sql`. **Se niega** si hay tiendas apagadas o si el registro tiene cambios, para no perder la auditoría |
| `supabase/pase/20261013_d12_interruptor_prueba.sql` | prueba T1–T5 en producción, solo `--dry-run` |
| `supabase/pase/20261013_d12_interruptor_ensayo.sql` | aplicar → prueba → reversión en una transacción (solo `--dry-run`) |

**Qué crea:**
- `public.channels.legacy_pin_enabled boolean NOT NULL DEFAULT true`;
- `f360.legacy_pin_switch_log` (solo inserción);
- los disparadores `legacy_pin_log_immutable` y `channels_legacy_pin_guard`;
- `public.f360_legacy_pin_set(uuid, boolean, text)` y `public.f360_legacy_pin_status()`.

**No cambia** ninguna política, permiso existente ni dato.

**Dependencias** (todas existen en producción y se comprobaron):
- `public.channels`;
- `public.offline_sales` (`created_by_rpc`, `channel_id`, `created_at`);
- `f360.user_roles`, `f360.require_role` y `f360.role_rank` (owner 3 > operator 2 > seller 1);
- en producción no hay disparadores previos en `channels`.

**Permisos efectivos** (los comprueba la guarda posterior del pase; si no se cumplen, aborta todo):
| Objeto | anon | authenticated | Notas |
|---|---|---|---|
| `f360_legacy_pin_set` | **no** | sí, pero adentro exige `require_role('owner')` | `SECURITY DEFINER`, `search_path = pg_catalog, pg_temp` |
| `f360_legacy_pin_status` | **no** | sí, pero adentro exige `require_role('operator')` (operadora o dueña) | solo conteos y estado; no lee `public.staff` |
| `f360.legacy_pin_switch_log` | **no** | **no** (ni lectura ni escritura) | RLS sin políticas; disparador contra UPDATE/DELETE/TRUNCATE |
| disparadores `f360.*` | no | no | — |
| `channels.legacy_pin_enabled` | lectura (con la política actual de `channels`) | igual que hoy | solo cambia por la RPC; el disparador rechaza cualquier otro UPDATE, incluso de `postgres` |

## 2. Aislamiento: no arrastra cambios de otras sesiones
- **Migraciones en producción:** las últimas son `20261023000100/0200`, `20261025000100` y `20261027000100` (D12 fase A).
  - **No** hay ninguna `20261024*` (Centro de Inteligencia, I5 sin autorizar) ni `20261030*` (Academy; solo vive en la rama `academy/a1`, sin aplicar en ningún ambiente).
- **El pase contiene solo el cuerpo de `20261029000100`.** No es un `db push` de la rama, así que no puede llevarse otras migraciones.
- **El cuerpo no referencia** `approval_*`, `can_approve`, `f360_academy`, `f360_board*` ni `fx_*`.
- **Guardas previas** del pase; si algo no coincide, se detiene:
  - tiendas `4f613a63…`;
  - políticas anon `a8609ffb…` (7);
  - políticas de `channels` `383f6af1…` (5);
  - permisos de `channels` `6efe9c24…`;
  - y que no exista ningún objeto del interruptor.

## 3. Todas las tiendas quedan encendidas y ninguna desaparece
- **Guarda posterior del pase:**
  - las 5 tiendas tienen `legacy_pin_enabled = true`;
  - siguen siendo 5, y 5 activas y visibles;
  - la huella de las tiendas no cambia;
  - el registro está vacío.
- **Prueba T1** (ensayo en producción): como `anon`, que es como entra la pantalla de NIP, se ven las 5 tiendas activas, igual que antes.
- **Ensayo completo en producción** (aplicar, prueba T1–T5, revertir): **OK**. Ensayo del pase de aplicación solo: **OK**.

## 4. Compatibilidad de la app con la base de producción
| App | Base sin interruptor (hoy) | Base con interruptor |
|---|---|---|
| **Actual publicada** (OTA del 11-oct: `fdfdfc9c` runtime 1.0.2 y `5e315529` runtime 1.0.1 iOS) | igual que hoy | la columna nueva no se pide (`select('id, name, type, location')`), así que **igual que hoy** |
| **Nueva** (`vendedora/index.tsx`, commit b78aa6e) | `select('*')` funciona; la columna no viene, `undefined !== false`, y se ven **todas** | se ven las encendidas, que son **todas** mientras nadie apague una |

`channels` solo tiene columnas que `anon` ya puede leer (`id, name, type, location, event_date, active, created_at` y la nueva). `select('*')` no expone nada adicional.

**Orden:** A y B son independientes; cualquier orden es seguro. Se recomienda **A primero**.

## 5. Plan de publicación OTA (solicitud B)
- **Qué se publica:** desde la última OTA (commit `4a73122`, 11-oct) **solo cambió** `fuxia-native/app/vendedora/index.tsx` (b78aa6e). **Sin cambios nativos:** `app.json`, `package.json`, `ios/`, `android/` y `eas.json` están intactos, así que es apto para OTA.
- **Desde un commit fijo**, en un *worktree* limpio en `b78aa6e` (o el SHA que se apruebe), igual que la regla D8 del admin. Así no se publica nada sin revisar ni archivos sin seguimiento.
- **Canal y runtimes:**
  1. `eas update --branch production --message "D12: tiendas migradas no aparecen en la pantalla de NIP anterior (sin efecto mientras todas estén encendidas)"` → runtime **1.0.2** (Android Play e iPhone 1.0.2).
  2. En el mismo worktree, `version` 1.0.1 de forma temporal → `eas update --branch production --platform ios` → runtime **1.0.1** (iPhone de la App Store; Carolina). Luego se descarta el cambio de `app.json`.
- **Dispositivos que la reciben:** todos los que tienen la app.
  - Hay 40 personas con notificaciones registradas: 36 clientas, 2 de personal y 1 admin.
  - Además, los teléfonos de tienda que entran a la pantalla de NIP sin sesión. Esos no se pueden contar: la app anterior no registra el dispositivo.
  - **Mientras todas las tiendas estén encendidas, el comportamiento visible es idéntico.**
- **Validación posterior:**
  - (a) `eas update:list` muestra los dos grupos nuevos;
  - (b) en un iPhone (1.0.1) y en un Android (1.0.2): cerrar y reabrir la app dos veces y abrir Vendedora sin sesión; deben verse las 5 tiendas, sin el aviso "¿No ves tu tienda?";
  - (c) vendedora F360 de Polanco: abre turno y ve su tienda;
  - (d) ventas del día normales (§9).
- **Reversión:** `eas update:republish --group fdfdfc9c-131d-47fa-9e77-e9a2223962a8` (1.0.2) y `--group 5e315529-1837-417e-9c86-9ac90c48c990` (1.0.1 iOS). Los teléfonos vuelven a la versión anterior en su siguiente arranque.

## 6. La función exige a la dueña y no confía en datos editables
- `f360_legacy_pin_set` llama a `f360.require_role('owner')`, que busca `f360.user_roles` por `auth.uid()`. Ese valor es el `sub` del JWT, **firmado por Supabase**; la usuaria no lo puede cambiar.
- **No lee `user_metadata`,** ni `customers.phone`, ni `my_role()`.
- **Pide motivo** (mínimo 3 caracteres). El actor y su nombre los toma el servidor, no el cliente.
- **El disparador `channels_legacy_pin_guard`** rechaza cualquier cambio de la columna que no venga de la RPC (bandera local de la transacción). Esto incluye la política heredada `channels.admins_all_channels`, que sí confía en `user_metadata.phone` (hallazgo D12, sigue abierta).

## 7. Ocultar una tienda NO revoca permisos (declaración explícita)
**Apagar el interruptor de una tienda solo la quita de la lista de la pantalla de NIP en la app nueva. No cambia nada en la base de datos:**
- **siguen vigentes** `anon_read_active_staff` (lectura del personal **con NIP**), `anon_insert_offline_sales` (registrar ventas), `anon_read_offline_sales` / `anon_read_own_sales` (leer ventas) y `anon_update_inventory_sold` (modificar el inventario de la app anterior), **para todas las tiendas**, apagadas o no;
- una versión vieja de la app, o cualquiera con la llave pública, puede seguir usando esa tienda por la vía anónima;
- **el interruptor es una guía operativa de la migración, no un control de seguridad.** El cierre real es el §5 de `D12_FASE_B_PLAN.md`, no autorizado.

## 8. Un usuario no autorizado no puede cambiar el estado
| Intento | Resultado | Prueba |
|---|---|---|
| anon llama a la RPC | rechazado (sin permiso de ejecución) | staging S5; producción T2 |
| anon hace UPDATE directo | 0 filas (sin política) y el disparador como respaldo | producción T2 |
| vendedora, operadora, clienta o admin de la app sin rol F360 llaman a la RPC | `insufficient_privilege` | staging S3; producción T3 (vendedora y clienta reales) |
| clienta con el **teléfono de una admin en `user_metadata`** hace UPDATE directo (la política `admins_all_channels` lo permitiría) | **el disparador lo rechaza** | staging S2; producción T3 (`clienta_falsificada`) |
| `postgres` hace UPDATE directo | el disparador lo rechaza | staging S2; producción T4 |
| vendedora o clienta leen el estado | rechazado | staging S7; producción T3 |
| UPDATE o DELETE al registro | rechazado, incluso a `postgres` | staging S6 |

## 9. Monitoreo de ventas por tienda durante la transición
- **Diario (operadora o dueña):** `f360_legacy_pin_status()` da, por tienda, el interruptor, las ventas por la app anterior en 14 días, la última venta anterior y el último cambio.
- **Diario (yo, solo lectura):** consulta en producción por tienda y día:
  - ventas de la app anterior (`created_by_rpc = false`);
  - ventas por turno F360;
  - ajustes de salida con "vend" o "salida" (reporte `../ops/AJUSTES_POSIBLES_VENTAS_2026-10-13.md`).
- **Alertas para revisar el mismo día:**
  1. una venta de la app anterior en una tienda **apagada** (teléfono sin la OTA o vía anónima directa);
  2. una tienda que vendía y lleva 2 días hábiles sin ventas por ningún camino (¿se volvió a anotar como ajuste?);
  3. intentos de turno fallidos repetidos (`f360.seller_auth_events`);
  4. ajustes con "vend…" en tiendas con turno F360.

## 10. Criterios para apagar y reactivar Polanco
**Apagar** (todas las condiciones; lo ejecuta la dueña con `f360_legacy_pin_set(Polanco, false, motivo)`):
1. Carolina confirma por escrito que todas las vendedoras activas de Polanco (Reyna, Valeria García, Valeria Pérez y ella) venden **solo** con su turno F360, y que nadie usa el NIP anterior.
2. 14 días sin ventas de la app anterior en Polanco. La última fue el 2026-10-05, así que se cumple a partir del 2026-10-19 si no hay otra.
3. Las solicitudes A y B están aplicadas y la OTA validada en los teléfonos de Polanco (punto 5b).
4. El primer día con alguien disponible para resolver NIP y turnos (`f360_admin_seller_reset_pin`).

**Reactivar** (cualquiera basta; la dueña enciende con motivo y la app anterior vuelve el mismo día):
- una vendedora no puede vender con su turno y no se resuelve en 15 minutos;
- F360 o el inicio de sesión fallan en tienda;
- Carolina lo pide.

**Después de apagar** (opcional, con autorización aparte): desactivar en `public.staff` a Reyna y "Valeria" de Polanco (`active = false`, sin borrar).

---

## SOLICITUD A · Migración en producción
**Qué:** aplicar `supabase/pase/20261013_d12_interruptor.sql@10a30f8` con `scripts/f360/prod_sql.sh` (primero ensayo, luego aplicación). Te pido ejecutarlo tú, igual que la fase A.

**Efecto:** se agrega el interruptor con **todas las tiendas encendidas**. No cambia nada visible ni ningún permiso.

**Verificación posterior:**
- la prueba T1–T5 en `--dry-run`;
- las huellas (tiendas, políticas anon y de `channels`, permisos) iguales a las de antes;
- ventas e inventario sin cambios.

**Reversión:** `supabase/pase/20261013_d12_interruptor_reversion.sql`, ensayada dentro del ensayo combinado.

## SOLICITUD B · Publicación OTA
**Qué:** publicar `fuxia-native` desde el commit fijo `b78aa6e`, en los runtimes 1.0.2 y 1.0.1 iOS, según el §5.

**Efecto:** nada visible mientras todas las tiendas estén encendidas.

**Verificación:** §5 (a)–(d).

**Reversión:** `eas update:republish` de los grupos `fdfdfc9c…` y `5e315529…`.

**Independiente de A:** la app nueva funciona con y sin la migración.
