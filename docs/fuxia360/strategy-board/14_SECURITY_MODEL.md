# 14 · Security Model — Strategy & Board

> Spec + hallazgos de auditoría (2026-10-08). **Los hallazgos se documentan, no se corrigen aquí.**

## 1. Cómo funciona hoy la autorización en Fuxia 360 (auditado)

| Capa | Mecanismo | Evidencia |
|---|---|---|
| Esquema `f360` | No expuesto: `REVOKE ALL ON SCHEMA f360 FROM PUBLIC, anon, authenticated`; tablas sin grants | `supabase/migrations/20260925010000_f360_admin_v1_inventory_core.sql:14-16,144-145` |
| Roles | `f360.user_roles(auth_user_id, role ∈ owner/operator/seller/viewer)`, escrito solo por migraciones/service role/RPCs owner | `:19-25`; `20260930000100_f360_c1_locations_roles.sql:15-16` |
| Chequeo | `f360.require_role(p_min)` SECURITY DEFINER, identidad solo de `auth.uid()` | `20260925010000…:152-166` |
| Rango | `role_rank`: owner 3, operator 2, **seller 1, viewer 1** | `20260930000100…:18-19` |
| Ubicación | `f360.require_location(p_location)`: owner/operator cualquiera; seller solo asignada | `20260930000100…:57-67`; redefinida en `20261003000100_f360_transfers.sql:44` |
| PII | `f360.customer_pii_viewers` + `f360.require_pii_viewer()` | `20261010000100_f360_crm_c1_customer_profile.sql:83-101` |
| Sesión vendedora | `f360.require_seller_session(token, location)` | `20261001000100_f360_s02_seller_sessions.sql:88`; revocación al cambiar rol `:239` |
| Auditoría | `f360.reject_audit_change()` append-only; `f360.access_changes` | `20260927010000_f360_p22_woo_publishing.sql:108-113`; `20260929000200_f360_audit_message.sql`; `20260930000100…:43-53` |
| Admin web | `proxy.ts` solo exige sesión ("Authorization itself is enforced by the f360 RPCs"); cliente servidor con anon key + cookie, **sin service role** | `admin-web/src/proxy.ts:6-7`; `admin-web/src/lib/supabase/server.ts:4-5` |
| Guardas de página | `canWrite(role)` = owner/operator → `redirect('/')`; algunas `me.role !== 'owner'` | `admin-web/src/lib/f360.ts:169`; `tablero/page.tsx`, `growth/page.tsx:14`, `vendedoras/page.tsx:10` |
| Errores de acceso | `rpc()` redirige a `/salir` en `42501` | `admin-web/src/lib/f360.ts:91-102` |
| Edge Functions | 22 de 28 directorios de funciones usan `SUPABASE_SERVICE_ROLE_KEY`; despliegue prod de funciones de tienda con `--no-verify-jwt` + secreto propio, por lista blanca | `fuxia-native/supabase/functions/*/index.ts`; `scripts/f360/deploy_prod_function.sh:16-18,36` |

Estado de prod (prod_read 2026-10-08): `f360.user_roles` = 2 filas, ambas `owner` ("Carolina", "Mario Silva"); `customer_pii_viewers` = esas 2; `location_assignments` = 1; `access_changes` = 2.

## 2. Hallazgos

Severidad respecto a **Strategy** (qué pasaría si Strategy copiara el patrón) y respecto al sistema actual.

| # | Hallazgo | Evidencia | Severidad | Implicación para Strategy |
|---|---|---|---|---|
| F1 | `seller` = `viewer` en `role_rank` → todo RPC con `require_role('viewer')` es alcanzable por vendedoras vía PostgREST aunque la UI lo oculte. Ejemplos con datos comerciales: `f360_favorites_report` (incluye `sold`), `f360_stock_demand`, `f360_review_summary` | `20260930000100…:18-19`; `20261012000800_f360_favorites_intent.sql` (comentario "viewer+"); `20261010000700…`; `20261011000100…` | Media (sistema actual) | Strategy no usa `require_role` en absoluto; usa allowlist |
| F2 | "owner" ≠ Carolina+Mario. Existe precedente de owner técnico ("Adrián", staging) excluido de PII | `20261010000100…:90`; `supabase/staging/f360_exec_dashboard_tests.sql` (fixture `adrian`) | Alta si se usara `require_role('owner')` | Allowlist `board_members` + exigir owner |
| F3 | Semilla de `customer_pii_viewers` por `display_name IN ('Carolina','Mario')`; en prod el nombre es "Mario Silva" | `20261010000100…:92-93`; prod_read | Baja/Media (fragilidad) | Altas por `auth_user_id` verificado, nunca por nombre |
| F4 | Altas/bajas en `customer_pii_viewers` sin tabla de historia ni trigger (no se encontró trigger en migraciones) | grep `TRIGGER.*customer_pii_viewers` sin resultados | Baja | `board_member_changes` obligatorio |
| F5 | Auto-concesión de rol: trigger `customers_activate_seller` otorga `seller` (y asignación) cuando una cuenta se vincula a un teléfono registrado como vendedora | `20261013000100_f360_sellers_admin.sql:40-52,67-79` | Baja (diseño aprobado) | "Tener rol F360" no implica confianza; la allowlist lo neutraliza |
| F6 | **P0-10 conocido**: confianza en `user_metadata.phone` (editable por la usuaria). Políticas RLS vigentes en prod: `admins_all_channels`, `admins_all_inventory`, `admins_all_staff`, `admins_staff_all_sales`, `customers_read_own_sales`, `Users manage their own push tokens` (pg_policies 2026-10-08). La parte RLS está neutralizada por la RLS de `customers` según `S0_0A_TEST_REPORT.md:72`; la parte Edge Function sigue en el repo: `delete-account/index.ts:38` resuelve la clienta solo por `user_metadata.phone` | `docs/fuxia360/audit/LIVE_RECONCILIATION.md:74`; `fuxia-native/supabase/functions/delete-account/index.ts:38-49`; `my-orders/index.ts:57`; `link-orders/index.ts:54` | **Alta** (sistema actual; ya registrado como P0-10/A7) | Strategy jamás lee `user_metadata`, `app_metadata`, `customers.role`, `public.my_role()` (`baseline…:293-298`) |
| F7 | Panel ejecutivo es operator+ y expone ventas totales de la empresa a operators | `20261010000300_f360_exec_dashboard.sql:13,19` | Info (decisión de Mario 2026-10-05) | Strategy FINANCIAL es más estricto; no reutilizar ese RPC como fuente para owners sin pasar por `require_board_member` |
| F8 | "valor" de inventario del panel = precio de venta × pares | `20261010000300…:137-138` | Media (riesgo de interpretación) | Rotular "a precio de venta"; costo solo con D3 |
| F9 | `commerce_source_health` excluye targets de producción (`WHERE t.active AND NOT t.is_production`); en prod `woo_production.active=false`, `commerce_sync_state` vacío | `20261008000100_f360_g1_commerce_facts.sql:455`; `pg_get_viewdef` en prod | **Alta para verdad financiera** | El cockpit no puede afirmar completitud del ACTUAL en línea de prod; cierre mensual exige excepción explícita hasta corregirse (en G1, no en Strategy) |
| F10 | Ventas legacy (36/37 filas de `public.offline_sales`, `created_by_rpc=false`) fuera de Commerce Facts; canales legacy (Guadalajara, Monterrey, Contreras, Cali) no existen como `f360.locations` | `20261008000100…:418`; prod_read | Media (completitud) | Revenue histórico PARTIAL; no inventar ubicaciones |
| F11 | Todos los buckets de Storage son públicos (`avatars`, `tryon-temp`, `product-images`) | prod_read `storage.buckets` | Info | Investor Room necesita bucket privado nuevo (D9) |
| F12 | Sin MFA en el admin (grep `aal|mfa` sin resultados) | `admin-web/src`, migraciones | Media para datos de dirección | Recomendado `aal2` para `require_board_member` (D2) |
| F13 | Funciones en prod desplegadas con `--no-verify-jwt` dependen de su propio chequeo (secreto/origen) | `scripts/f360/deploy_prod_function.sh:36` | Info (controlado por lista blanca) | Strategy no agrega Edge Functions |

## 3. Modelo para Strategy

### 3.1 Roles y identidad
- Identidad: solo `auth.uid()` del JWT verificado por PostgREST.
- Autorización: `f360_board.require_board_member(scope)` = allowlist activa ∧ scope ∧ `user_roles.role='owner'` ∧ (opcional D2) `aal2`.
- Nunca: `user_metadata`, `app_metadata`, `customers.role`, `my_role()`, teléfono, `display_name`, parámetros del cliente, cookies propias, headers.

### 3.2 RLS
- `f360_board.*`: sin `USAGE` para `anon/authenticated`; RLS habilitado sin políticas (deny-all). La seguridad real es "sin grants + definer"; RLS es segunda barrera ante un `GRANT` accidental.
- Prueba en CI de staging: `SELECT has_schema_privilege('authenticated','f360_board','USAGE')` = false; `has_table_privilege` false para todas.

### 3.3 Service role
- Ni `admin-web` ni Edge Functions usan service role para Strategy. Excepción posible solo para signed URLs del bucket privado (D9 opción B) — preferida la opción A (política de Storage con función definer).
- `cron` (snapshots mensuales de forecast) ejecuta funciones `f360_board.*` internas como owner de la base, sin RPC pública.

### 3.4 Edge Functions
- Ninguna nueva. Si el AI Analyst llega, corre en Route Handler de `admin-web` con la sesión de la usuaria (`12`).

### 3.5 RPCs
- Convención: `public.f360_board_<area>_<verb>`; `SECURITY DEFINER`; `SET search_path = pg_catalog, pg_temp`; nombres calificados; primera línea `require_board_member`; `REVOKE ALL FROM PUBLIC, anon`; `GRANT EXECUTE TO authenticated`.
- Escrituras: `idempotency_key uuid` obligatorio (patrón de `f360_receive_inventory`, `20260930000100…:72-77`); valores calculados (totales, outputs, varianzas, % ownership) **siempre en servidor**; el cliente nunca envía totales (CLAUDE.md regla 6).
- Mensajes de error genéricos; `ERRCODE insufficient_privilege` → el `rpc()` del admin ya redirige a `/salir` (`f360.ts:96-97`). Para Strategy conviene que la página haga `notFound()` antes, para no revelar la sección.

### 3.6 Vistas
- Solo en `f360_board` (no expuestas). Ninguna vista en `public` con datos de dirección. (Las vistas G1 viven en `f360`, tampoco expuestas.)

### 3.7 API / Frontend
- Rutas `/estrategia/*` en `admin-web/src/app/(app)/estrategia/` con layout servidor que llama `f360_board_me()`; `dynamic = 'force-dynamic'`, sin caché compartida; no se pasan datos a componentes cliente más allá de lo que se pinta.
- Nav: ítem visible solo si `f360_board_me()` OK (cosmético).
- Modo presentación: oculta CAP_TABLE, VALUATION, INVESTOR_ROOM y notas privadas.
- Exportaciones (CSV/print) registran evento en `access_log`.

### 3.8 Logging de accesos sensibles
`f360_board.access_log` (allowed + denied), `investor_room_events` (VIEW/DOWNLOAD), eventos de decisiones/capital. Panel "Accesos" para ambos dueños con alertas de `denied` de no miembros.

### 3.9 Moneda y PII
- Moneda original siempre; consolidación solo con `fx_rates` explícito.
- Sin PII: las vistas de clientas devuelven conteos; prueba automática que busca columnas `name|phone|email|address|birthday` en los JSON de respuesta de todas las RPCs `f360_board_*` (fixture con PII sintética en staging).
