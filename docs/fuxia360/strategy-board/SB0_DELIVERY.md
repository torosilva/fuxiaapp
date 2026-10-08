# SB0 · Strategy & Board — Access + Data Foundation · DELIVERY (STAGING ONLY)

> 2026-10-08 · rama `fuxia-360` · staging `faltxpkaicwpnlqaxrdu` · autorización de Mario 2026-10-08 (D9–D15).
> **Producción: sin cambios** (solo lecturas `scripts/f360/prod_read.sh`, sin PII: versiones de migración, ids de dueños, Plan 2027).
> Specs implementados: `00`, `01`, `13` §0–3/§11, `14` §3, `15` SB0; más D10B, D11, D12, D13 de la autorización.

## 1. Resumen

El módulo **Strategy & Board 🔒** existe en staging, es **invisible e inaccesible** para todos salvo Carolina y Mario (allowlist por
`auth.users.id` + rol `owner`), registra cada acceso permitido, negado y cada escritura sensible, y tiene la base de datos de
dirección: calendario fiscal (enero–diciembre), cierre de mes con versiones, catálogo de métricas, base de budget/forecast
inmutable, decision log con **conflicto de interés** y el **Plan 2027** de Growth B4 ligado (una sola fuente). Además se cerró el
hallazgo F1/D13: las vendedoras ya no pueden leer los reportes agregados de demanda/intención por PostgREST.
**No** se construyó el CEO Cockpit (SB1); la UI es la mínima para validar permisos y operar el cierre de mes.

## 2. Qué se implementó

| Migración (staging, aplicada) | Contenido |
|---|---|
| `20261015000100_f360_board_sb0_access.sql` | esquema `f360_board` (sin USAGE para anon/authenticated/service_role); `board_members` (+`person_key`, `evidence`), `board_member_changes`, `settings` (+`settings_changes`), `access_log` (append-only); `member_denial`, `require_board_member`, `log_write`, `denied`; RPCs `f360_board_me`, `f360_board_nav_visible`, `f360_board_access_log` |
| `20261015000200_f360_board_sb0_finance_foundation.sql` | `reporting_entities` (solo `fuxia` = alcance de gestión, no entidad legal), `fiscal_periods` (+events), `close_accounts`, `monthly_close_entries` (+log), `close_actual_snapshots`, `metric_catalog` (22 métricas con disponibilidad real), `budget_versions/lines`, `forecast_versions/lines/snapshots`, `close_readiness`; RPCs de periodos y cierre |
| `20261015000300_f360_board_sb0_governance_plan.sql` | `decisions` (+revisions, events, recusals) con D10B; `plan_versions/years/revisions`; importación del Plan 2027 de B4 como fila **ligada**; RPCs de decisiones y planes |
| `20261015000400_f360_d13_intent_reports_operator.sql` | D13: `f360_stock_demand`, `f360_favorites_report`, `f360_review_summary`, `f360_store_order` pasan de `viewer` a `operator` (solo el literal del gate, tomado de la definición viva) |

Membresía de staging (no es migración): `supabase/staging/sb0_board_members_staging.sql`.

### 2.1 Funciones / RPCs (todas `SECURITY DEFINER`, `search_path = pg_catalog, pg_temp`, nombres calificados, `REVOKE … anon`, `GRANT … authenticated`, gate en la primera instrucción)

| RPC | Scope | Escribe |
|---|---|---|
| `f360_board_me()` | cualquier miembro | — |
| `f360_board_nav_visible()` | — (boolean sobre el propio llamante; **no** se registra; solo pista de menú) | — |
| `f360_board_access_log(days)` | BOARD | — |
| `f360_board_periods(year)` · `f360_board_close_get(period)` · `f360_board_metric_catalog()` · `f360_board_plans()` | FINANCIAL | — |
| `f360_board_close_entry_add(key, period, account, amount, currency, source, evidence, note, dimension)` | FINANCIAL | captura (idempotente) |
| `f360_board_close_entry_void(entry, reason)` | FINANCIAL | anulación |
| `f360_board_close_entries_approve(period)` | FINANCIAL | aprueba capturas **de la otra persona** |
| `f360_board_period_transition(period, to, reason, exception)` | FINANCIAL | OPEN → UNDER_REVIEW → CLOSED → REOPENED → … |
| `f360_board_decisions(limit)` | BOARD | — |
| `f360_board_decision_propose(…)` · `_revise(…)` · `_act(id, APPROVE/REJECT/DEFER/WITHDRAW)` | BOARD | decisiones |

**Por qué el gate devuelve `{ok:false,"No disponible."}` en vez de `RAISE`:** un `RAISE` revierte su propia fila de log
(lección de `20261001000200_f360_s02_persist_denials.sql`). El spec `01 §3` pedía las dos cosas (registrar la negación **y** `RAISE`);
se eligió que la negación **quede registrada**; la respuesta no contiene datos ni confirma que el módulo existe. `anon` sigue
recibiendo 401/42501 (sin `EXECUTE`).

### 2.2 Reglas de negocio implementadas (y de dónde vienen)

- **D10 acceso:** `member_denial` = sesión JWT ∧ fila activa en `board_members` ∧ scope ∧ `user_roles.role='owner'` ∧ (si `settings.require_aal2`) `aal2`. Nunca `display_name`, `user_metadata`, `app_metadata`, `customers.role`, teléfono ni parámetros. Altas/bajas solo por script revisado, por id; cada cambio queda en `board_member_changes`.
- **D10B conflicto de interés:** tipos `MARIO_INVESTMENT / MARIO_OWNERSHIP / MARIO_TECH_CONTRIBUTION / MARIO_COMPENSATION` (y `OTHER_RELATED_PARTY` con miembros nombrados) marcan RELATED PARTY + CONFLICT OF INTEREST; el miembro con `person_key='MARIO'` se agrega solo como parte interesada (aunque la propuesta nombre a otra persona); queda **RECUSED** (`decision_recusals`); sus intentos de aprobar/rechazar se rechazan **y se registran** (`APPROVAL_REFUSED_RECUSED` + `access_log`); la aprobación válida queda como `APPROVED_BY_OTHER_MEMBER_RELATED_PARTY`. La tabla misma rechaza un aprobador interesado (`CHECK NOT (approved_by && interested_members)`). Sin reglas legales finales.
- **D5 (pendiente, valores por defecto en `settings`, cambiables solo por migración auditada):** el cierre lo aprueba la persona que **no** lo mandó a revisión; las capturas las aprueba alguien distinto a quien capturó (también `CHECK` en tabla); una decisión ordinaria la aprueba alguien distinto a quien la propone.
- **D11:** año fiscal calendario; 12 meses + 4 trimestres + 1 año por año (2026 y 2027 sembrados; `f360_board.ensure_fiscal_year` para más); `CHECK` impide periodos no calendario. Trimestre/año = roll-up de meses.
- **Cierre de mes:** `OPEN / UNDER_REVIEW / CLOSED / REOPENED`; capturar/anular solo en OPEN/REOPENED; cerrar exige capturas aprobadas y, si algún componente está `DATA_INCOMPLETE`, una **excepción escrita**; cada cierre crea `close_version` + foto inmutable (`close_actual_snapshots`, hash); reabrir exige motivo; corrección = anular + capturar (nunca editar monto). Componentes: ventas (G1, SB1), COGS, utilidad bruta, OPEX, gasto de marketing (**S-G0**), caja, inventario, impuestos. **Ventas no se teclean** en el cierre.
- **D12 Plan 2027:** `plan_years(2027)` está **ligado** a `f360.growth_plans` (`linked_source`, sin monto propio — `CHECK`); `f360_board_plans` lee el North Star en vivo + historia de `growth_plan_changes`; la importación (valor + escenarios + historia) queda como revisión 1 inmutable. Etiqueta **DRAFT MANAGEMENT TARGET**. Growth sigue siendo el único lugar editable (D8). Metas 2028–2031 **no** se cargaron (spec: SB3, por los dueños en la UI).
- **Budget/forecast (base):** versión aprobada/publicada congelada por trigger (líneas, nombre, estado); publicar forecast escribe `forecast_snapshots` (append-only, hash); solo borradores se borran. Sin RPCs de escritura (SB1/SB2).
- **D9:** `reporting_entities` soporta `LEGAL_ENTITY` (MX/CO) pero **no se pobló**. Cali: casa matriz, PENDING BUSINESS CONFIRMATION, **no registrada**.
- **Coordinación S-G0:** no se creó `fx_rates`, `product_cost_versions` ni gasto de marketing; se citan en `metric_catalog.depends_on` y en `close_readiness`.

## 3. Identidad de Carolina y Mario (evidencia)

**Staging** (verificado 2026-10-08 antes de escribir):

| auth id | `user_roles` | `customer_pii_viewers` | `auth.users` | Board |
|---|---|---|---|---|
| `aa375921-4cef-4004-9127-b8e80bd0a933` | owner "Carolina" | sí (migración 20261010000100) | car***@staging.invalid (login demo) | **CAROLINA** |
| `c50849b9-6dbe-4822-a75c-fd48066612c3` | owner "Mario" | sí (misma) | mar***@staging.invalid (login demo) | **MARIO** |
| `bc6bc0e2-d733-4e6d-a85a-6b1a18eaafdf` | owner "Adrián" (técnico) | no | adr***@… | **no** (prueba T3) |

**Producción** (prod_read, solo ids/roles): Carolina `31da6b13-70eb-4d89-8019-6f04c3207300` (owner, PII viewer "pase G8 (decisión Mario 2026-10-05)"); Mario `d11a8d33-cae6-46a5-9d0f-bd2516e8712b` (owner "Mario Silva", PII viewer "pase G8 (Mario 2026-10-06)"). Son los únicos 2 owners de prod. El nombre "Mario Silva" ≠ "Mario" confirma que el nombre no sirve como identificador.

## 4. UI (admin-web)

- `src/lib/board.ts` (cliente propio; una negación nunca redirige a `/salir`).
- `src/app/(app)/estrategia/layout.tsx`: `force-dynamic`; `f360_board_me` → si no, `notFound()`.
- `estrategia/page.tsx`: consejo y reglas, Plan 2027 (DRAFT), periodos 2026/2027 con roll-up, catálogo de métricas con disponibilidad, registro de accesos con alerta de intentos de no miembros.
- `estrategia/cierre/[id]/page.tsx` + `estrategia/actions.ts`: cierre de un mes (componentes y DATA INCOMPLETE, capturas con quién capturó/aprobó, anular, aprobar las de la otra persona, mandar a revisión / regresar / cerrar con excepción / reabrir, historia y fotos).
- Menú: grupo "Dirección → Strategy & Board 🔒" (`Shell.tsx`) y tarjeta en `/mas`, solo si `f360_board_nav_visible()`; la seguridad la hacen las RPCs.
- D13: `/favoritos` y `/productos/orden` redirigen a quien no es owner/operator (antes una vendedora llegaba y la RPC la habría mandado a `/salir`); el enlace "Orden en la tienda" se oculta. `/demanda` ya estaba protegido.

## 5. Pruebas (todas en transacciones revertidas; nada se escribe)

Runner: `scripts/f360/sb0_staging_tests.sh rehearse|applied` (rechaza cualquier URL que no sea staging).

| # | Prueba | Archivo | Resultado |
|---|---|---|---|
| 0 | Sin grants de esquema/tablas; RLS sin políticas; 15 RPCs definer + search_path + gate primero; anon sin EXECUTE | `test_sb0_access.sql` | PASS |
| 1 | No autorizado: anon 42501; usuario sin rol → `ok:false` en 14 RPCs; SELECT directo → permission denied | `test_sb0_access.sql` | PASS |
| 2 | Vendedora (y operator, viewer) no accede | `test_sb0_access.sql` | PASS |
| 3 | Owner genérico fuera de la allowlist no accede | `test_sb0_access.sql` | PASS |
| 4 | Carolina autorizada (7 lecturas, nav, sin PII en respuestas) | `test_sb0_access.sql` | PASS |
| 5 | Mario autorizado | `test_sb0_access.sql` | PASS |
| 5b | Sin scope / inactivo / pierde owner / MFA `aal2` → negado; cambios auditados | `test_sb0_access.sql` | PASS |
| 6 | Negaciones registradas con motivo y conservadas; log append-only | `test_sb0_access.sql` | PASS |
| 7 | Escrituras sensibles registradas (`write` + id, parámetros solo hash) | `test_sb0_access.sql` | PASS |
| 8 | Historia no sobrescribible: cierre/fotos/eventos/log, forecast publicado + snapshot, budget aprobado, decisiones, plan | `test_sb0_history.sql` | PASS |
| 19 | Vendedora y viewer → 42501 en `f360_stock_demand`, `f360_favorites_report`, `f360_review_summary`, `f360_store_order`; operator/owner sí; control negativo: sin la migración 0400 la vendedora **sí** leía `f360_stock_demand` | `test_sb0_access.sql` | PASS |
| 20 | Flujo de venta de vendedora intacto: `f360_s02` (28), `f360_c3` (100), `f360_s05_s03` (37), `f360_reservations` (24), `f360_reservations_app` (22), `test_store_sale_customer` (turno, catálogo, alta/búsqueda de clienta, `record_store_sale_for`) | runner | PASS |
| D10B | Mario no es aprobador único de decisiones suyas; Carolina sí aprueba; intentos registrados | `test_sb0_history.sql` | PASS |
| D11/D12/cierre | calendario; cierre completo v1→reabrir→v2 con v1 intacta; Plan 2027 ligado en vivo | `test_sb0_history.sql` | PASS |
| Regresión | suite completa `scripts/f360/db_tests.mjs` (38 archivos, ~1,030 checks) con SB0 aplicado | — | ALL PASS |
| API real | JWT reales vía Auth + PostgREST: anon 401; Carolina/Mario `ok:true`; Adrián `ok:false` + `nav false` | — | PASS |
| admin-web | `tsc --noEmit`, `eslint .`, `next build`, unit tests `env-guard` + `growth-model` (11) | — | PASS |

Nota: en modo `rehearse` (DDL dentro de la misma transacción larga) `f360_c3` y `f360_s05_s03` chocaron por *deadlock* con los cron
de staging (el ensayo retiene locks de FK sobre `f360.locations`/`auth.users` durante minutos); la línea base sin SB0 pasa y, ya
aplicado (transacciones cortas), ambos pasan. No es un efecto de SB0 en operación.

## 6. Muestra del registro de accesos (staging, sin PII)

```
168 10-08 12:53:33 Carolina             f360_board_me      ANY       allowed
169 10-08 12:53:33 Carolina             f360_board_periods FINANCIAL allowed
171 10-08 12:53:35 Mario                f360_board_me      ANY       allowed
174 10-08 12:53:36 Adrián (no miembro)  f360_board_me      ANY       denied  not_member
175 10-08 12:53:37 Adrián (no miembro)  f360_board_periods FINANCIAL denied  not_member
```

## 7. Datos que faltan (se muestran como DATA INCOMPLETE / MISSING, nunca inventados)

Ventas en el cierre (G1 → SB1; definición de ingreso D4 / S-G0), COGS y costo unitario (S-G0 `product_cost_versions`), OPEX, caja e
impuestos (captura de cierre: 0 capturas), gasto de marketing / CAC / ROAS / MER (S-G0), foto de inventario a fin de mes (SB1),
tipos de cambio (S-G0 `fx_rates`), entidades legales (D9), metas 2028–2031 (SB3), año base verificado (`reported_figures` = 0).

## 8. Decisiones abiertas

D2 MFA (`settings.require_aal2`, hoy `false`) · D5 firmas (defaults descritos en §2.2) · D4 Net Revenue · D8 qué plan es fuente
después de aprobar un plan del consejo · D9 entidades legales / Cali · D3 costo (S-G0) · si `OPERATIONAL`/`VALUATION`/`INVESTOR_ROOM`
deben estar en la membresía inicial (hoy: todos los scopes para ambos).

## 9. Contradicciones y hallazgos (regla 14)

1. **Staging está atrás de producción:** faltan `20261012001100` y `20261013000100…0600` en staging (prod los tiene). `test_store_sale_customer` los antepone dentro de la transacción revertida. Recomendación: pase de esas 7 a staging aparte.
2. Spec `01 §3` "registrar negación + RAISE" es contradictorio (el RAISE borra el log) → se registra y se responde `ok:false` sin datos.
3. Spec `13 §2` ubica `fx_rates`/`product_cost_versions` en `f360_board`; la autorización los asigna a S-G0 en `f360` → no se crearon.
4. Spec `02 §3` pone gasto de marketing en el cierre; S-G0 es dueño → no hay cuenta de marketing en `close_accounts`.
5. Spec usa `IN_REVIEW`; Mario pidió `UNDER_REVIEW` + `REOPENED` → se usó lo de Mario.
6. `f360_growth_plan` ya era `operator` en la definición viva (no `viewer` como en la migración original) → no se tocó.
7. Siguen en `require_role('viewer')` otros RPCs con datos de negocio no agregados de intención (p. ej. `f360_product_knowledge_overview`, `f360_inbox_list`, `f360_custom_requests_list`, `f360_made_to_order_list`, `f360_online_store_shipments`): fuera de D13; revisar por separado.

## 10. Plan de paso a producción (requiere aprobación escrita de Mario; NO ejecutado)

1. Aprobar este documento. Verificar en prod (prod_read) que `20261015*` no existe y que S-G0 no ha redefinido las 4 funciones de D13 de forma incompatible (la migración 0400 aborta si no hay exactamente 1 gate `viewer`).
2. Commit de un archivo de pase `BEGIN; … COMMIT;` con, en orden: `20261015000100`, `0200`, `0300`, `0400` (contenido íntegro) + sus 4 filas en `supabase_migrations.schema_migrations`. `scripts/f360/prod_sql.sh` lo ensaya (ROLLBACK) y luego lo aplica.
3. Membresía de producción en un **segundo** archivo de pase (aprobado aparte, por id, nunca por nombre), con guarda:
   ```sql
   BEGIN;
   DO $$ DECLARE x uuid; BEGIN
     FOREACH x IN ARRAY ARRAY['31da6b13-70eb-4d89-8019-6f04c3207300','d11a8d33-cae6-46a5-9d0f-bd2516e8712b']::uuid[] LOOP
       IF NOT EXISTS (SELECT 1 FROM f360.user_roles r JOIN f360.customer_pii_viewers v USING (auth_user_id) WHERE r.auth_user_id = x AND r.role = 'owner')
       THEN RAISE EXCEPTION 'ABORT %', x; END IF; END LOOP;
     INSERT INTO f360_board.board_members (auth_user_id, person_key, display_name, scopes, granted_by_name, evidence, note) VALUES
       ('31da6b13-70eb-4d89-8019-6f04c3207300','CAROLINA','Carolina', f360_board.valid_scopes(),'Mario <fecha> (pase SB0)','prod auth id; user_roles owner; customer_pii_viewers pase G8','D10'),
       ('d11a8d33-cae6-46a5-9d0f-bd2516e8712b','MARIO','Mario', f360_board.valid_scopes(),'Mario <fecha> (pase SB0)','prod auth id; user_roles owner; customer_pii_viewers pase G8','D10');
   END $$;
   COMMIT;
   ```
   Aprueba: Mario (y confirmación de Carolina de su propio alta, recomendada).
4. Desplegar admin-web (`scripts/f360/deploy_prod_admin.sh`) solo después de 2–3.
5. Verificación en prod (lectura): `has_schema_privilege('authenticated','f360_board','USAGE') = false`; Carolina y Mario ven `/estrategia`; un owner no miembro no existe en prod (solo 2 owners) → probar con la RPC desde una sesión de vendedora: `f360_stock_demand` → 42501; venta de prueba de tienda según `PASE_CHECKLIST.md`.

## 11. Rollback

Orden inverso con los scripts `supabase/rollbacks/20261015000400…0100_*.down.sql`. `0400` restaura `viewer` (re-abre F1; solo con OK de Mario).
`0300`/`0200`/`0100` borran el módulo (`DROP SCHEMA f360_board CASCADE` al final); **exportar antes** `access_log`, decisiones y cierres si ya
tienen registros reales. `f360.growth_*` nunca se modifica, así que el Plan 2027 de Growth queda igual. admin-web: revertir el commit (las
páginas de `/estrategia` sin el esquema solo responden 404).
