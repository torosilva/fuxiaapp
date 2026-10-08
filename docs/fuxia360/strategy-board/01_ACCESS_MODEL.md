# 01 · Access Model — Strategy & Board

> Spec. Nada implementado. Citas de la auditoría del 2026-10-08.

## 1. Quién entra

**Solo dos personas: Carolina y Mario.** Nadie más, en ningún rol:

| Persona / rol | Acceso a Strategy & Board |
|---|---|
| Carolina (owner) | Sí — todas las áreas |
| Mario (owner) | Sí — todas las áreas |
| Otro `owner` técnico (p. ej. "Adrián" en staging) | **No** |
| `operator` | **No** |
| `seller` / vendedoras / tiendas | **No** |
| `viewer` | **No** |
| Agencias, staff, contadores, inversionistas, clientas | **No** (sin cuentas externas en esta fase) |
| `service_role` / Edge Functions | **No** como canal de lectura de usuario. Solo migraciones. |

## 2. Por qué NO basta `require_role('owner')`

Hallazgos (detalle en `14_SECURITY_MODEL.md`):

1. `owner` es un rol operativo, no una identidad. La migración de PII ya tuvo que separar "owner" de "persona autorizada": *"Carolina and Mario. Adrián (owner, technical) is NOT a viewer"* — `supabase/migrations/20261010000100_f360_crm_c1_customer_profile.sql:90`.
2. Hoy en prod `user_roles` tiene 2 owners (Carolina, "Mario Silva"), pero cualquier migración o service role futuro puede agregar otro owner (p. ej. soporte técnico) y heredaría el módulo completo.
3. `role_rank` iguala seller y viewer (`20260930000100_f360_c1_locations_roles.sql:18-19`), y hay un trigger que **otorga automáticamente** el rol `seller` cuando una clienta con teléfono registrado como vendedora vincula su cuenta (`20261013000100_f360_sellers_admin.sql:67-79`, `f360.activate_seller` `:40-52`). "Tener rol F360" es una señal débil.

**Decisión de diseño:** allowlist explícita por `auth_user_id`, **independiente** de `user_roles` pero que además exige `role = 'owner'` (doble condición). Patrón ya probado: `f360.customer_pii_viewers` + `f360.require_pii_viewer()` (`20261010000100…:83-101`).

## 3. Mecanismo propuesto

```
f360_board.board_members (auth_user_id PK → auth.users, display_name, scopes text[], active, granted_at, granted_by_name, note)
f360_board.board_member_changes (append-only, reject_audit_change)
f360_board.require_board_member(p_scope text) RETURNS uuid  -- SECURITY DEFINER, search_path = pg_catalog, pg_temp
```

`require_board_member(scope)`:

1. `auth.uid()` no nulo (identidad SOLO del JWT verificado; nunca `user_metadata`, `app_metadata`, `customers.role`, teléfono, ni un parámetro del cliente).
2. Existe fila activa en `board_members` **y** el scope pedido está en `scopes`.
3. Existe `f360.user_roles` con `role = 'owner'` para ese uid (defensa en profundidad: si le quitan owner, pierde Strategy).
4. (Recomendado, decisión D2) `auth.jwt()->>'aal' = 'aal2'` — MFA obligatorio para el módulo. Hoy no hay uso de MFA en el repo (grep `aal|mfa` sin resultados en `admin-web/src` y migraciones).
5. Inserta una fila en `f360_board.access_log` (ver §6) — también cuando **falla** (vía bloque separado que registra el intento denegado sin PII; patrón de `20261001000200_f360_s02_persist_denials.sql`).
6. Si falla: `RAISE … USING ERRCODE = 'insufficient_privilege'` con mensaje genérico ("No disponible.") que no revela que el módulo existe.

**Alta/baja de miembros:** solo por migración revisada (como `customer_pii_viewers`), insertando por `auth_user_id` verificado — **nunca por `display_name`**. Hallazgo: la semilla de PII usa `WHERE display_name IN ('Carolina','Mario')` (`20261010000100…:92-93`) y en prod el nombre es "Mario Silva"; funcionó por otra vía, pero el patrón por nombre es frágil y no debe repetirse. Cada alta/baja escribe `board_member_changes`.

No habrá RPC para que un miembro agregue a otro. Agregar una tercera persona exige migración + aprobación escrita de ambos dueños en el Decision Log (`08_BOARD_GOVERNANCE.md`).

## 4. Separación de dominios de datos (scopes)

| Scope | Contenido | Carolina | Mario | Notas |
|---|---|---|---|---|
| `OPERATIONAL` | Agregados operativos (pares, tiendas, pedidos) — ya visibles a owner/operator en F360 | ✔ | ✔ | Strategy no amplía nada que no sea ya owner/operator |
| `CUSTOMER_PII` | Datos personales de clientas | — | — | **Strategy nunca lo usa.** Solo agregados (conteos, tasas). Sigue gobernado por `customer_pii_viewers` en CRM |
| `FINANCIAL` | ACTUAL/BUDGET/FORECAST, cierre mensual (COGS, OPEX, caja, gasto), escenarios | ✔ | ✔ | |
| `BOARD` | Reuniones, actas, decisiones, action items, gates | ✔ | ✔ | |
| `CAP_TABLE` | Partes, instrumentos, aportaciones, préstamos, ownership formal | ✔ | ✔ | Escritura con **doble aprobación** (D5) |
| `VALUATION` | Escenarios indicativos | ✔ | ✔ | Sin cálculo por socio hasta ownership formal aprobado |
| `INVESTOR_ROOM` | Documentos curados | ✔ | ✔ | Sin enlaces públicos |

Los scopes existen aunque hoy ambas personas tengan todos: permiten, en el futuro, dar a un tercero (p. ej. un consejero) un subconjunto sin rediseñar — siempre con migración + decisión.

## 5. Dónde se aplica (capas)

| Capa | Control | Es seguridad real |
|---|---|---|
| Postgres | Esquema `f360_board` sin `USAGE` a `anon/authenticated`; tablas sin grants; RLS habilitado sin políticas (deny-all) como segunda barrera | **Sí** |
| RPC | Cada `public.f360_board_*` llama `require_board_member(scope)` en su primera línea; `REVOKE ALL FROM PUBLIC, anon`; `GRANT EXECUTE TO authenticated` | **Sí** |
| Next.js server | Layout de `(app)/estrategia` llama `f360_board_me()`; si falla → `notFound()` (no `redirect`, para no confirmar existencia). `export const dynamic = 'force-dynamic'`, `fetchCache = 'force-no-store'` | Complementaria |
| Navegación | Ítem "Estrategia" solo si `f360_board_me` responde | Cosmética |

Hallazgo que se debe evitar repetir: en el admin actual varias páginas se protegen con `canWrite()` → `redirect('/')` (`admin-web/src/lib/f360.ts:169`; p. ej. `tablero/page.tsx`, `growth/page.tsx:14`) y el menú filtra `admin: true` (`admin-web/src/components/Shell.tsx`, `mas/page.tsx:31`), pero algunas RPCs con datos comerciales están en `require_role('viewer')` y por tanto alcanzables por vendedoras directamente vía PostgREST: `f360_favorites_report` (incluye `sold`, `20261012000800_f360_favorites_intent.sql`), `f360_stock_demand` (`20261010000700…`), `f360_review_summary` (`20261011000100…`). Strategy no debe tener **ninguna** RPC por debajo de `require_board_member`.

## 6. Registro de accesos (sensitive-access logging)

`f360_board.access_log` (append-only, `reject_audit_change`):

| Columna | Contenido |
|---|---|
| id | bigint identity |
| at | `clock_timestamp()` |
| auth_user_id | `auth.uid()` (puede ser no-miembro en intentos denegados) |
| rpc | nombre de la función |
| scope | scope pedido |
| outcome | `allowed` / `denied` |
| object_ref | id del objeto leído/escrito (meeting, decision, version), nunca contenido |
| params_hash | hash de parámetros (no los valores) |
| request_id | de `request.headers` si existe |

Lectura: `public.f360_board_access_log(p_days)` — solo miembros. Retención: indefinida (volumen bajo: 2 usuarios). Alertas: un `denied` desde un uid no miembro aparece como aviso en la portada del módulo de ambos dueños.

Para escrituras de negocio (decisiones, cierres, cap table) el log de acceso **no sustituye** a las tablas de historia propias de cada entidad (ver `13_DATA_MODEL.md`).

## 7. Sesión

- Misma sesión Supabase del admin (`admin-web/src/proxy.ts` refresca cookie y manda a /login a quien no tenga sesión; la autorización la hacen las RPCs — comentario en `proxy.ts`).
- Recomendado: re-autenticación (o MFA step-up) al entrar a `CAP_TABLE` y `INVESTOR_ROOM`; timeout de inactividad corto en rutas `/estrategia/*` (cliente) — decisión D2.
- **Modo presentación** (como `p_presentation` del panel ejecutivo, `20261010000300…:16`): oculta cap table, valuación y notas privadas cuando se proyecta en pantalla.

## 8. Pruebas obligatorias de acceso (resumen; detalle en `15_IMPLEMENTATION_PLAN.md`)

Para **cada** RPC `f360_board_*`: anon → error; authenticated sin rol → error; viewer → error; seller (con sesión de tienda) → error; operator → error; owner no miembro (fixture "Adrián" en staging) → error; miembro sin scope → error; miembro con scope → OK; cada intento queda en `access_log`; `SELECT` directo sobre `f360_board.*` como `authenticated` → `permission denied for schema`.
