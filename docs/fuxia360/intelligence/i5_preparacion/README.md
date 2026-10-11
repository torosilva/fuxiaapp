# I5 · Estado de preparación (entregables previos a la autorización final)

> 2026-10-11 · Todo se hizo en **staging** o con **lecturas** de producción.
> - **Producción:** sin migraciones, sin pantallas ni funciones publicadas, sin secretos, sin cambios de roles ni permisos de usuarios reales.
> - **Base del plan:** `../I5_PLAN_PRODUCCION.md`.
> - **Cada cambio productivo** necesita una aprobación explícita (§9).

## 1. Pruebas de la contadora (D2, migración 0700) — staging
**Diseño aplicado:**
- La contadora **no tiene fila en `f360.user_roles`**. Su única identidad es `f360_board.finance_preparers`, y el panel la reconoce con `f360_finance_access_state()`.
- **Candados:**
  - no se puede registrar a una contadora que tenga un rol de Fuxia 360;
  - si después le dieran un rol por error, pierde la captura de inmediato (`conflicto: true`).
- **Segundo factor** obligatorio, igual que el consejo.

| Prueba | Resultado |
|---|---|
| Ensayo con ROLLBACK de 0700 | 0 filas · 0 permisos/RLS · 0 contratos cambiados. Solo cambia `require_finance_capture`; nuevas: `finance_preparers_guard`, `f360_finance_access_state`. Reversión exacta |
| **Recorrido de las 249 funciones** que puede invocar `authenticated`, **llamadas directas** como contadora, persona sin rol y viewer (sesión simulada, argumentos nulos, cada llamada revertida) | La contadora no pasa **ninguna** función más que una persona sin rol, salvo sus 6: `f360_finance_access_state`, `f360_close_prep_context`, `_entry_add`, `_entry_void`, `f360_finance_commitment_add`, `_event`. El viewer pasa 67; ella no hereda ninguna |
| **Recorrido de las 26 tablas** legibles por `authenticated` | La contadora ve exactamente lo mismo que una persona sin rol (ver hallazgo de seguridad: tablas de la app anterior) |
| Por nombre | Estrategia, cockpit, analista, presupuesto, aprobar cierre, `f360_me` y Conciliación (datos de clientas): **denegados** |
| **Llamadas directas a Edge Functions** con su sesión real | `f360-analyst`, `f360-fx-rates`, `f360-woo-sync`, `f360-email`, `f360-push`, `f360-hilo-intake` → 401 · `f360-woo-publish` (3 acciones bien formadas) → 403 "sin acceso" · `f360-woo-orders` → 401 (firma) · `f360-store-reserve`/`storefront` → 403 (origen) · `admin-points`, `inventory-approve` → 403 "requiere admin" · `my-orders` → 404 (sin perfil) · `hilo-chat` → 200 (el chat público de clientas, igual que para cualquiera) |
| Funciones de la app de clientas que actúan sobre la propia cuenta (`delete-account`, `link-orders`, `claim-sale`, `whatsapp-otp`) y `admin-broadcast-push` | No se llamaron, para no borrar la cuenta ni enviar mensajes. Revisión de código: validan el JWT y actúan solo sobre la cuenta propia; `admin-broadcast-push` exige `role === 'admin'` |
| E2E en el panel de staging (3/3) | La contadora sin rol entra, ve solo Cierre contable, captura y anula, registra y cancela un compromiso, y es redirigida desde 7 rutas. Mario y Carolina, sin cambios |

**Hallazgo colateral (fuera de I5):** `../../SECURITY_FINDING_2026-10-11_LEGACY_RLS.md`. En producción, tablas de la app anterior con RLS abierta:
- NIP del personal legible sin sesión;
- escritura anónima en ventas e inventario de la app anterior;
- todos los tickets de soporte legibles por cualquier clienta.

No se tocó. Requiere una decisión aparte (D12).

## 2. D0 — ocultar las pantallas incompletas en producción (preparado, NO publicado)
- **Mecanismo:** `admin-web/src/lib/feature.ts` → `intelEnabled()` es verdadero solo si `NEXT_PUBLIC_F360_ENV = staging` o `NEXT_PUBLIC_F360_INTEL = on`. En producción no hay que configurar nada para que queden ocultas.
- **Qué hace al estar apagado:**
  - el menú no muestra Dirección, Inteligencia ni Cierre contable;
  - esas rutas responden 404;
  - el panel no consulta el acceso de la contadora;
  - el login no admite a una contadora (no existe en producción).
- **Commit fijo:** `c901e60`. Diff exacto contra lo publicado hoy en producción (`5668b89`): `D0_diff_admin_5668b89_c901e60.diff`. Son 12 archivos de `admin-web`, +67/−30.
- **Commits incluidos (todos de esta sesión, ninguno de otra):** `d0ca96a` (correcciones del analista F1–F3; pantalla oculta), `61e9b48` (D0 + contadora) y `c901e60` (login de la contadora).
- **Componentes:** solo el panel (Vercel `fuxia360`). Sin base de datos ni funciones. No requiere ninguna migración: la RPC de la contadora no se llama con el interruptor apagado.
- **Pruebas:**
  - `tsc` y `lint` limpios;
  - `next build` correcto;
  - en staging (interruptor encendido) E2E 3/3;
  - con el interruptor apagado se verifica después del despliegue: `/direccion`, `/inteligencia` y `/cierre-contable` → 404 y menú sin esas entradas (prueba de humo §6).
- **Rollback:** Vercel → fuxia360 → Deployments → `fuxia360-dlavhb5zj` (el actual) → Promote.
- **Publicación desde commit fijo (D8):** `deploy_prod_admin_sha.diff`, propuesta para que el script publique **solo** `F360_DEPLOY_SHA`, muestre los archivos y commits incluidos y pida confirmación. Hoy el script publica la punta de la rama; así llegaron estas pantallas a producción.

## 3. Matriz de aprobadores (D3) — producción actual y propuesta
**Personas en producción:**
- Mario Silva (`d11a8d33…`): dueño, consejo y datos de clientas.
- Carolina (`31da6b13…`): dueña, consejo y datos de clientas.
- 3 vendedoras.
- No hay contadora: la tabla `finance_preparers` todavía no existe en producción.

| Operación | Regla que la controla | Hoy en producción | Con I5 (propuesta) |
|---|---|---|---|
| Aprobar descuento de tienda | alcance `store_discount` | **Carolina** | Sin cambio (no se toca) |
| Aprobar tasa mensual de cambio | dueña + alcance `fx_rate` (0100) | Cualquier dueña (versión anterior de `f360_fx_rate_approve`) | **Mario** (fila `fx_rate`) |
| Proponer tasa mensual | sistema (lectura diaria) o dueña/operador | — | Sistema; nadie la aprueba por defecto |
| Crear o editar borrador de presupuesto | consejo FINANCIAL o contadora con `can_budget` | — | Mario, Carolina (contadora: no, `can_budget = false`) |
| Validación comercial del presupuesto | consejo FINANCIAL | — | Carolina (o Mario) |
| Aprobar presupuesto | consejo + alcance `budget` | — | **Mario** (fila `budget`) |
| Definir metas | consejo + alcance `budget` | — | **Mario** |
| Capturar cierre y compromisos | consejo FINANCIAL o contadora con `can_close` | — | Contadora (D5) y consejo |
| Aprobar capturas del cierre | consejo FINANCIAL, nunca quien capturó (existente) | Mario o Carolina | Sin cambio |
| Aprobar compromisos financieros | consejo FINANCIAL, nunca quien capturó | — | Mario o Carolina |
| Aprobar costo por modelo | rol owner (existente) | Mario o Carolina | Sin cambio |
| Cambiar límites o apagar el analista | consejo + alcance `budget` + motivo | — | **Mario** |

- **Alcance `close`:** ninguna función lo usa. Las aprobaciones de cierre se basan en el consejo y en "quien captura ≠ quien aprueba". **Recomendación:** no cargar filas `close` en producción, para no dejar configuración sin efecto (D3b).
- **Carga de filas (cuando se apruebe):** `INSERT … ON CONFLICT DO NOTHING` de `fx_rate` y `budget` para Mario. Nunca se borra ni se toca `store_discount`.

## 4. Inventario de migraciones, dependencias y compatibilidad con producción
**Orden:** 0100 → 0200 → 0300 → 0400 → 0500 → 0600 → 0700 (detalle de cada una en el plan §1).

| Comprobación (solo lectura) | Resultado |
|---|---|
| Dependencias en producción | Todas presentes: fx_rates, board finance, Conciliación, Meta, `approval_scopes` (23000200) y descuentos (25000100) |
| `f360.can_approve` | Idéntica en repo, staging y producción (huella `565a9163…`) |
| Regla de alcances de producción | `fx_rate, budget, close, store_discount`. Mis migraciones **no la redefinen** |
| **Definiciones**: 697 objetos de producción contra staging (copia de producción + 0100–0700) | Solo difieren las **2 funciones que se reemplazan a propósito**: `f360_fx_rate_approve` y `f360_measurement_run_failed` |
| **Permisos, RLS y políticas** de los 697 objetos compartidos | Ninguna diferencia viene de 0100–0700. Las diferencias que hay vienen del proceso de copia de staging: 60 tablas con el permiso del dueño escrito distinto, 8 funciones con el orden de PUBLIC distinto y 2 tablas de la app anterior con permisos de más **en staging**. Ya avisé a la sesión responsable |
| Migración pendiente ajena | 20261017000100 (earn-in) y Academy 20261026* (solo propuestas). Academy amplía la regla de alcances conservando los míos (confirmado con esa sesión) |

## 5. Commit exacto para producción
| Componente | Commit | Contenido |
|---|---|---|
| D0 (panel, ocultar) | **`c901e60`** | §2 |
| I5 · base de datos | `e0f1902` o posterior (migraciones 0100–0700 sin cambios desde entonces) | Se fija al pedir la ejecución, con la huella de cada archivo |
| I5 · funciones | `3a40c95` (`f360-analyst` con requisito 8) y `c445968` (`f360-fx-rates`) | Se publican con un comando explícito por función |
| I5 · panel | `c901e60` + `NEXT_PUBLIC_F360_INTEL=on` en Vercel producción, o un commit posterior revisado | Se enciende solo después de E1–E3 |

Antes de ejecutar se revisa de nuevo `git log` del panel desde lo publicado. Hoy no hay commits de otras sesiones en `admin-web` desde `5668b89`.

## 6. Checklist GO / NO-GO
- [ ] D0–D12 decididas (§9).
- [ ] Foto de negocio E0 en producción tomada (pedidos, hash Woo, eventos y saldo de inventario, costos, cierres, presupuestos, tasas, alcances) y repetida después de cada etapa, sin diferencias atribuibles a I5.
- [ ] Ensayo en staging recién copiado de producción con 0100–0700 en orden: 0 filas, 0 permisos, 0 contratos ajenos cambiados (hecho hoy).
- [x] Reversión completa ensayada (§7).
- [x] Contadora aislada (§1).
- [x] Analista: 23/23 + requisito 8 (24/24 pruebas de la función).
- [ ] `F360_PUBLISHER_URL` presente en Vercel producción (verificar solo el nombre).
- [ ] Ninguna otra sesión migrando producción en la ventana (Academy, descuentos).
- [ ] Llave de Anthropic de producción **no** creada hasta E6 (§8).
- **NO-GO si:**
  - cambia cualquier dato de negocio;
  - un ensayo falla;
  - cambia la regla o las filas de `approval_scopes` de descuentos;
  - la llave pasa por un canal que no sea el panel de Supabase;
  - aparece una cifra no verificada en la validación.

## 7. Reversión ensayada — staging, una transacción con ROLLBACK
Se aplicaron los 7 `.down.sql` en orden 0700 → 0100 y se comparó con las huellas leídas hoy de producción:

| Comprobación | Resultado |
|---|---|
| `f360_fx_rate_approve` y `f360_measurement_run_failed` iguales a producción | ✅ ✅ |
| `can_approve` intacta y regla de descuentos intacta | ✅ ✅ |
| Funciones, tablas y columnas propias restantes | 0 · 0 · 0 |
| Cron `f360-fx-rates` y filas en `schema_migrations` | 0 · 0 |
| Datos de negocio (pedidos, hash Woo, inventario, costos, cierres, tasas, alcance de descuentos) | **Idénticos** |

Otros componentes:
- **Panel:** Promote del despliegue anterior en Vercel.
- **Funciones:** `supabase functions delete <nombre>`.
- **Analista:** borrar el secreto o `enabled = false`.

## 8. Llave de Anthropic (D6), funciones (D7), apagado, monitoreo y etiquetas financieras
**D6 · Llave de producción.** Procedimiento (no ejecutado):
1. Workspace `fuxia360-produccion` con límite de USD 100.
2. Key creada por Mario.
3. Mario la pega directamente en Supabase de **producción**, Edge Functions → Secrets → `ANTHROPIC_API_KEY`, en mayúsculas.
4. Claude verifica solo el nombre con `supabase secrets list`.
5. Se pone **después** de que la función responda 503 "sin configurar".

**D7 · Funciones, independientes y en este orden:**
1. `f360-fx-rates`:
   - Publicar: `supabase functions deploy f360-fx-rates --no-verify-jwt --project-ref tgzgiwfzddsghnxgkcqd`.
   - Verificar: POST sin sesión → 401; con el secreto del cron → `daily` 200; `measurement_runs` `fx_rates` ok.
   - Revertir: `functions delete` + down de 0100 (cron).
2. `f360-analyst` (el mismo comando con su nombre):
   - Verificar: sin llave → 503 auditado; vendedora → 403; dueña sin consejo → 403 "denegado".
   - Revertir: borrar el secreto (inmediato) o `functions delete`.

**Apagado inmediato del analista, sin tocar otros módulos** (de menor a mayor alcance):
1. `/inteligencia` → Consumo → `enabled = false` (solo Mario, con motivo, auditado).
2. Borrar el secreto `ANTHROPIC_API_KEY` (503 al instante).
3. `functions delete f360-analyst`.

Ninguno afecta ventas, inventario, Growth ni otros módulos: el analista solo lee por `f360_intel_query`.

**Monitoreo diario** (lecturas, 7 días después de E6; consultas listas en el plan §7):
- **Errores:** `ai_queries.status in ('error','denegado')` por día, y `measurement_runs` `fx_rates` con `ok = false`.
- **Consumo:** `sum(cost_usd)` del mes contra USD 100, alerta al 80% (`f360_ai_quota.warning`), y preguntas por persona contra 40.
- **Accesos denegados:** `f360_board.access_log` con `outcome = 'denied'` por función y usuario, incluido `actor_kind = 'ai_analyst'`.
- **Respuestas sin datos:** `answer->'validacion'->>'estado' = 'incompleta'`, `jsonb_array_length(answer->'sin_fuente') > 0`, `unverified <> '[]'`, y preguntas cuyas herramientas devolvieron todas `FALTA`.

**Etiquetas de información financiera** (requisitos 7 y 8):
- Cada número del cockpit y del analista lleva `disponibilidad`:
  - **COMPLETA** = DISPONIBLE;
  - **INCOMPLETA** = PARCIAL o FALTA, con qué falta y quién lo da;
  - **ESTIMADA** = la nota "ESTIMADO: incluye costos estimados" (`cost_basis = 'estimated'`).
- **Requisito 8 (nuevo, desplegado en staging):** un hecho del analista que mencione margen, EBITDA, utilidad, rentabilidad, ganancia o COGS con cifras:
  - solo se acepta si la herramienta `margen` respondió DISPONIBLE;
  - con PARCIAL, solo si el texto dice "estimado";
  - si no, pasa a "sin fuente · no verificado".
- Hoy los costos están en 0 (FALTA), así que el analista no puede presentar margen ni EBITDA como verificados. Probado (24/24).

## 9. Decisiones humanas pendientes (aprobación explícita por cambio productivo)
| # | Decisión | Qué autoriza exactamente |
|---|---|---|
| D0 | Publicar en producción el panel `c901e60` (ocultar pantallas) | 1 despliegue de Vercel `fuxia360`; sin base de datos |
| D8 | Aplicar `deploy_prod_admin_sha.diff` al script de despliegue | Cambio del script (publicar solo commits fijos) |
| D1 | Fecha y hora de I5 | Ventana sin otras sesiones migrando |
| D3 | Alcances `fx_rate` y `budget` = Mario | 2 filas en `approval_scopes`; no se toca `store_discount` |
| D3b | No cargar filas `close` (sin efecto) | — |
| D4 | Meta ecommerce MX: **México · tienda en línea · $300,000 MXN/mes · desde 2026-11 (o 2026-10) · responsable Mario** | La registra Mario en `/direccion/presupuesto` |
| D5 | Identidad de la contadora (nombre y correo) | Alta solo después; sin rol en Fuxia 360 |
| D6 | Crear la llave de Anthropic de producción | En la etapa E6, por Mario |
| D7 | Publicar `f360-fx-rates` y `f360-analyst` en producción | 2 comandos explícitos |
| D9 | Aprobar las tasas mensuales de mayo a septiembre | Mario en `/direccion/tipo-de-cambio` después de E2. Hasta entonces el consolidado MXN dice "sin tasa aprobada" |
| D10 | Ejecutar las 7 migraciones en producción (E1) | 7 pases con ensayo previo |
| D11 | Encender las pantallas en producción (`NEXT_PUBLIC_F360_INTEL=on`) | 1 variable de Vercel + redespliegue |
| D12 | Corregir el hallazgo de seguridad de las tablas de la app anterior | Fuera de I5; propuesta aparte |

## Corrección 2026-10-11 (tarde): permisos de `service_role` en `f360_board` (0200)
Tras la copia de staging con los permisos exactos de producción, `test_sb0_access` T0 detectó 16 permisos de tabla en `f360_board`. Venían de la migración **0200**, que daba `GRANT ALL … TO service_role` sobre `finance_preparers`, `goals`, `financial_commitments` y `financial_commitment_events` (y `SELECT` sobre `commitments_current`).
- **No es un hallazgo de producción:** allí la misma consulta da 0, porque la 0200 todavía no se ha aplicado.
- **Corrección:** la 0200 ahora revoca también a `service_role`, como exige la convención de SB0: `f360_board` es deny-all y solo se llega por RPC `SECURITY DEFINER`. Ninguna Edge Function ni script usa esas tablas con `service_role`; la evaluación usa psql como `postgres`. El `REVOKE` ya está aplicado en staging.
- **Pruebas actualizadas:**
  - `test_sb0_access` acepta `require_finance_capture` como primer control en las 3 RPC de captura de presupuesto, que es la puerta diseñada en la 0200/0700, y cuenta como miembros reales del Consejo solo los que tienen `person_key` (los seeds de staging agregan miembros "(demo)").
  - En `test_intel_inputs` y `test_intel_metrics` la contadora de prueba ya no tiene rol de F360, como exige la 0700.
- **Resultado:** `test_sb0_access` (T0–T19), `test_intel_inputs`, `test_intel_metrics`, `test_finance_access`, `test_ai_analyst` y `test_d12_phase_a` pasan en staging.
