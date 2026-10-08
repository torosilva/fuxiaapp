# 15 · Implementation Plan — Strategy & Board

> Plan. **Nada se implementa hasta que Mario apruebe esta especificación y las decisiones de §2.**
> Regla de entrega: **NO GREEN TESTS → NO DEPLOY.** Cada sprint: staging primero, dry-run de `db push`, migraciones con rollback en `supabase/rollbacks/`, pruebas SQL en `supabase/staging/f360_board_<sprint>_tests.sql` (patrón `BEGIN … ROLLBACK` con `pg_temp.as(uid, sql)`, ver `supabase/staging/f360_exec_dashboard_tests.sql:1-20`), e2e Playwright en `admin-web/e2e/`, unit tests en `admin-web/test/`. Producción solo con aprobación explícita y siguiendo `docs/fuxia360/ops/PASE_CHECKLIST.md`.

## 1. Infraestructura de pruebas existente (inventario, no ejecutado)

| Suite | Ubicación | Naturaleza |
|---|---|---|
| SQL de staging (≈40 archivos) | `supabase/staging/f360_*_tests.sql` | transacción con ROLLBACK; fixtures por `display_name` (Carolina, Adrián) y usuarios sintéticos `1555…@fuxia.app` |
| Runner | `scripts/f360/db_tests.mjs` | ejecuta las anteriores contra staging |
| ⚠ No ejecutar sin aprobación | `supabase/staging/f360_demo_reset.sql`, `f360_demo_seed.sql` | **destructivos** |
| e2e Playwright | `admin-web/e2e/*.spec.ts` (14), incl. `smoke-readonly.spec.ts`, `remote-smoke.spec.ts` | algunas escriben en staging |
| Unit | `admin-web/test/env-guard.test.ts`, `growth-model.test.ts` | puros |
| Rehearsals | `docs/fuxia360/audit/S0_0A_*`, `supabase/staging/f360_s03_before_after_probe.sql` | lab de seguridad |

Fixtures nuevos necesarios: miembro A (Carolina sintética), miembro B (Mario sintético), owner-no-miembro (rol de "Adrián"), operator, seller con sesión, viewer, authenticated sin rol, anon; clientas sintéticas con PII falsa para pruebas de fuga.

## 2. Decisiones que Mario debe tomar antes de SB0

| # | Decisión | Opciones / recomendación |
|---|---|---|
| D1 | Allowlist = Carolina + Mario por `auth_user_id`, independiente de owner (y además exige owner) | Recomendado sí |
| D2 | MFA (`aal2`) obligatorio para Strategy; re-auth para cap table/sala | Recomendado sí (hoy no hay MFA) |
| D3 | Dónde vive el costo unitario (`f360_board.product_cost_versions` vs `f360` core) y quién lo captura | Recomendado `f360_board` (costo no visible a operator); o COGS mensual manual al inicio |
| D4 | Definición de Net Revenue (precio cobrado vs ÷1.16 IVA); hoy IVA no está separado en ninguna fuente | Decidir antes de SB1 |
| D5 | Aprobaciones: ¿una o ambas firmas? Regla de conflicto (inversión de Mario la aprueba Carolina) | Recomendado: doble para cierre, budget, plan, gates con override, capital, cap table |
| D6 | Año fiscal = calendario; zona `America/Mexico_City` | Confirmar |
| D7 | Entidades legales (MX/CO) y si Cali se modela como ubicación F360 | Necesario para dimensión company/country |
| D8 | Relación `growth_plans`/`growth_scenarios` (B4) ↔ Plan 5 años / Scenario Lab | Recomendado: Plan aprobado es fuente; `growth_plans` del año en curso se deriva (o se lee) — una sola editable |
| D9 | Bucket privado y firma de URLs: política Storage con función definer (A) vs Route Handler con service role (B) | Recomendado A |
| D10 | Ventas legacy (`offline_sales` no-RPC, canales legacy) → ¿se cargan como `historical_sales` por Carolina? | Recomendado sí, por el flujo existente "Ventas pasadas" |
| D11 | AI Analyst: proveedor, retención, residencia | Fuera de SB0–SB7 |
| D12 | Corregir en G1 (no en Strategy) `commerce_source_health` para incluir producción y activar `woo_production` | Requisito para cerrar meses con ACTUAL en línea "VERIFIED" |

## 3. Sprints

### SB0 — Access + Data Foundation
- **Objetivo:** el módulo existe, es invisible e inaccesible para todos salvo Carolina y Mario, y tiene dónde registrar el cierre mensual.
- **Alcance:** esquema `f360_board`; `board_members` (+changes), `require_board_member`, `access_log`, `f360_board_me`, `f360_board_access_log`; `fiscal_periods`, `close_accounts`, `monthly_close_entries` (+log), `close_actual_snapshots`, `fx_rates`, `metric_catalog`; ruta `/estrategia` con layout guard y pantalla "Cierre de mes".
- **Dependencias:** D1, D2, D5, D6, D7(parcial). G1 desplegado (sí, en prod).
- **Schema:** nuevo esquema; 0 cambios a `f360`/`public` (salvo funciones `public.f360_board_*`).
- **Frontend:** `admin-web/src/app/(app)/estrategia/layout.tsx`, `page.tsx`, `cierre/`; nav condicional en `Shell.tsx`; tipos en `lib/f360.ts` (o `lib/board.ts`).
- **Backend:** RPCs definer; sin Edge Functions.
- **Seguridad:** matriz de permisos completa; MFA si D2.
- **Tests:** permisos (8 identidades × cada RPC); `has_schema_privilege` false; access log en allowed/denied; void+nuevo en cierre; append-only (UPDATE/DELETE rechazados); idempotencia; montos en moneda válida; PII: ninguna RPC devuelve campos PII; e2e: no-miembro recibe 404 en `/estrategia` y no ve el ítem.
- **Aceptación:** Carolina captura OPEX/COGS/caja de un mes en < 5 min; Mario lo aprueba (si D5); operator/seller/owner-no-miembro no pueden ni leer ni saber que existe.
- **Rollback:** `DROP SCHEMA f360_board CASCADE` + `DROP FUNCTION public.f360_board_*` (script en `supabase/rollbacks/`); quitar rutas.
- **Complejidad:** M.

### SB1 — CEO Cockpit
- **Objetivo:** ACTUAL vs BUDGET vs FORECAST vs VARIANCE, MTD/QTD/YTD/FY, con calidad y fuentes.
- **Alcance:** vistas `v_sales_actual_monthly`, `v_inventory_position`, `v_customer_aggregates`; `budget_versions/lines` (captura simple mensual); `f360_board_cockpit`; UI cockpit + "¿de dónde sale?".
- **Dependencias:** SB0; D4; D10 (para histórico); D12 recomendado.
- **Schema:** tablas budget; vistas en `f360_board`.
- **Frontend:** `estrategia/cockpit`, `estrategia/presupuesto`.
- **Backend:** RPC agregada; posible extracción de `f360.commerce_period_totals` compartida con `f360_exec_dashboard` (sin cambiar su resultado).
- **Seguridad:** FINANCIAL; sin PII; test-orders excluidos igual que el panel.
- **Tests — financial truth:** con fixtures, revenue del cockpit = Σ `net_product` countable MXN + históricos = valor de `f360_exec_dashboard` para el mismo periodo (igualdad exacta); COP/USD nunca sumados a MXN; consolidado solo con `fx_rates`; KPI sin fuente → `MISSING` (nunca 0); EBITDA null si falta OPEX o COGS; varianza calculada en servidor; pedidos `never_paid`/`cancelled` no cuentan; reembolso tardío no altera el cierre congelado.
- **Aceptación:** cada KPI muestra estado real (tabla de `02` §2); Mario valida 3 cifras contra Woo/Carolina.
- **Rollback:** drop de vistas/tablas/RPCs de SB1.
- **Complejidad:** L.

### SB2 — Forecast 18M
- **Objetivo:** forecast rolling versionado, driver-based, sin doble conteo.
- **Alcance:** `forecast_versions/lines/drivers`, `forecast_snapshots(+lines)`, publish, cron mensual de snapshot, UI de edición por drivers.
- **Dependencias:** SB1.
- **Tests — forecast calculations:** fórmulas por método (fixtures de oro) iguales en TS y SQL; `decomposition` no suma al total; CUSTOMER_BASE no se suma; mes cerrado muestra ACTUAL; ventana se desplaza al cerrar; publish inmutable; snapshot append-only; cliente no puede enviar totales.
- **Aceptación:** Mario publica v1 con 18 meses y ve su comparación con budget.
- **Rollback:** drop tablas SB2; desactivar cron.
- **Complejidad:** L.

### SB3 — Scenario Lab + Five-Year Plan
- **Objetivo:** simular sin tocar budget/forecast; registrar el plan 2027–2031 como TARGETS DRAFT.
- **Alcance:** `scenarios(+revisions)`, import desde `growth_scenarios`; `plan_versions/years/initiatives/revisions`; carga de las metas DRAFT (15M/25M/40M/60M/85M MXN) **por Mario/Carolina en la UI**, no por migración.
- **Dependencias:** SB2; D8.
- **Tests — scenario isolation:** SAVE/DUPLICATE/ARCHIVE no cambian hashes de budget/forecast; PROMOTE solo crea decisión PROPOSED; inputs faltantes → outputs null; rótulo TARGET presente; 2027 alerta si difiere de `growth_plans`.
- **Aceptación:** comparar 3 escenarios; plan v1 aprobado vía decisión.
- **Rollback:** drop tablas SB3 (los `growth_*` no se tocan).
- **Complejidad:** M.

### SB4 — Capital + Ownership
- **Objetivo:** registrar compromisos/aportaciones/despliegues sin supuestos legales.
- **Alcance:** tablas de `07`; doble aprobación; documentos (si D9 resuelto, si no solo referencias).
- **Dependencias:** SB0; D5, D7, D9.
- **Tests — capital permissions:** solo CAP_TABLE; transición a COMMITTED/FUNDED requiere segunda persona; compromiso de Mario requiere aprobación de Carolina; totales derivados de movimientos; DEPLOYED ≤ FUNDED; montos no editables tras COMMITTED; ningún % calculado sin `ownership_snapshot`; el registro inicial de Mario queda `EVALUATING` y tecnología `PENDING_VALUATION` sin monto.
- **Aceptación:** pantalla muestra "Cap table formal no registrado" y el compromiso de Mario como EVALUATING.
- **Rollback:** drop tablas SB4.
- **Complejidad:** M.

### SB5 — Board + Decision Log
- **Objetivo:** reuniones, board pack congelado, minutas y decisiones inmutables.
- **Alcance:** tablas de `08`; vista imprimible (patrón `conteo/hoja`); integración con gates (`06`) — gates entran aquí.
- **Dependencias:** SB1–SB4 (contenido del pack).
- **Tests — decision immutability:** UPDATE de contenido tras APPROVED rechazado; DELETE rechazado; supersede crea nueva y marca anterior; revisiones append-only; pack ISSUED inmutable con hash; gate ELIGIBLE solo con ACTUAL; métrica MISSING → requisito UNKNOWN; override exige ambos.
- **Aceptación:** primer consejo trimestral con pack emitido y 3 decisiones registradas.
- **Rollback:** drop tablas SB5.
- **Complejidad:** L.

### SB6 — Investor Room
- **Objetivo:** sala privada de documentos curados.
- **Alcance:** bucket `board-private`, `investor_room_items/events`, subida/descarga firmada, índice.
- **Dependencias:** D9; SB3–SB5.
- **Tests — PII isolation:** ninguna RPC de sala lee `public.customers`; escaneo de secretos bloquea archivos de texto con patrones; bucket `public=false`; anon/authenticated no-miembro no pueden listar ni descargar (`storage.objects`); URL firmada expira; cada VIEW/DOWNLOAD registrado.
- **Aceptación:** Mario sube un deck y lo descarga; Carolina ve el evento.
- **Rollback:** vaciar y borrar bucket (solo objetos de Strategy), drop tablas.
- **Complejidad:** M.

### SB7 — Valuation + Forecast Accuracy
- **Objetivo:** escenarios indicativos con disclaimer y precisión del forecast.
- **Alcance:** `valuation_*`, `forecast_accuracy`.
- **Dependencias:** SB2 (snapshots), SB4 (ownership para la sección por socio — que seguirá oculta mientras no haya snapshot formal).
- **Tests — historical snapshots:** accuracy usa snapshot ≤ horizonte, nunca interpola; A = cierre congelado; bias con signo correcto; APE con A=0 → n/a; **cross-country currency:** errores por moneda, nunca mezclados; valuación: múltiplo sin source/date/reason rechazado; métrica MISSING → sin resultado; disclaimer presente en respuesta de cada RPC; % por socio nunca calculado sin ownership formal.
- **Aceptación:** primer reporte de accuracy (aunque diga "sin snapshot a 90d" hasta ene-2027).
- **Rollback:** drop tablas SB7.
- **Complejidad:** M.

## 4. Matriz de pruebas transversal (todas las fases)

| Categoría | Qué se prueba siempre |
|---|---|
| Permissions | 8 identidades × cada RPC; SELECT directo a `f360_board` falla; nav oculta + 404 |
| Financial truth | igualdad contra G1/panel; MISSING ≠ 0; servidor calcula |
| Forecast calculations | fixtures de oro TS=SQL; sin doble conteo |
| Scenario isolation | hashes de budget/forecast intactos |
| Historical snapshots | append-only; inmutables; usados por accuracy y cierre |
| Decision immutability | triggers |
| Capital permissions | doble firma; conflicto de interés |
| Cross-country currency | MXN/COP/USD nunca sumados sin `fx_rates`; rótulo de TC |
| PII isolation | ningún campo PII en respuestas; fixtures sintéticos |

## 5. Top riesgos

1. **Verdad financiera incompleta en prod** (F9/F10): salud del canal de producción invisible, `woo_production` inactivo, ventas legacy fuera de G1 → el cockpit podría parecer "bajo" sin serlo. Mitigación: calidad visible, D10, D12.
2. **Costo/OPEX/caja dependen de captura manual**: si no se hace el cierre, la mitad del cockpit queda MISSING. Mitigación: formulario de 5 minutos, recordatorio el día 5.
3. **Dos fuentes de plan** (B4 vs Plan 5 años) → D8.
4. **Escalamiento de privilegios por "owner"**: mitigado por allowlist (D1).
5. **Conflicto de interés en capital** (Mario parte y aprobador) → D5.
6. **Fuga por impresión/exportación**: lo impreso sale del control → advertencias y log.
7. **Sobre-confianza en forecast con poca historia** → etiquetas de método + accuracy.
