# I5 · Plan de paso a producción del Centro de Inteligencia — SOLO PLAN (no ejecutado)

> 2026-10-11 · Mario autorizó **preparar** I5: planificación, auditoría y documentación. **No** autorizó ejecutarlo.
> Toda la información de producción de este documento se obtuvo con lecturas (`scripts/f360/prod_read.sh`, transacciones READ ONLY,
> `vercel ls`). No se ejecutaron migraciones, no se desplegaron funciones, no se cambiaron roles, permisos ni secretos, y no se activó Claude en producción.

## 0. Hallazgo previo: las pantallas ya están en el panel de producción
- **Qué pasó:** hoy, hace unas 3 horas, otra sesión (descuentos) desplegó el panel de producción con `deploy_prod_admin.sh`. Ese script publica **todo** lo que hay en `origin/fuxia-360`, y en ese momento la rama apuntaba a `5668b89`, que ya incluía las pantallas I2/I3.
- **Qué ven hoy Mario y Carolina** en el menú de producción: "Dirección 🔒", "Inteligencia 🔒" y "Cierre contable". Esas pantallas **no funcionan**: las funciones de base que llaman no existen en producción, así que muestran error o "no disponible".
- **Riesgo:**
  - **No hay riesgo de datos ni de costo.** La función `f360-analyst` no existe en producción, no hay llave de Claude y las pantallas no pueden escribir sin las migraciones.
  - **Sí hay confusión:** las pantallas son visibles antes de tiempo.
  - Las vendedoras **no** las ven (requieren consejo y segundo factor), y en producción no hay usuarias `viewer`.
- **Causa de fondo:** `deploy_prod_admin.sh` no permite elegir qué módulos se publican.
- **Decisión D0 (abajo):** dejarlo así hasta I5, u ocultarlo antes con un interruptor de entorno.

## 1. Migraciones: inventario, orden, dependencias y estado de producción

**Estado de producción hoy:**
- **Aplicadas:** 20261014000100…0600, 20261015000100…0400, 20261016000100…0500, 20261018000100, 20261019*, 20261020*, 20261021000100, 20261022000100…0500, 20261023000100 (Meta), **20261023000200 (approval_scopes, de descuentos)** y **20261025000100 (descuentos)**.
- **Pendientes de I5, en este orden:**

| # | Migración | Qué hace | Depende de (todas ya en prod) | Toca datos de negocio |
|---|---|---|---|---|
| 1 | 20261024000100_f360_fx_daily | `fx_observations`, `fx_daily`, propuesta mensual, regla de tasa en reportes, cron diario `f360-fx-rates`. Reemplaza `f360_fx_rate_approve`: ahora también exige alcance `fx_rate`. Reemplaza `f360_measurement_run_failed`: acepta `fx_rates` | fx_rates (14000300/16000300), measurement_runs, approval_scopes (23000200), Vault `f360_sync_url`/`f360_sync_secret` (existen) | No. fx_rates en prod tiene 0 filas |
| 2 | 20261024000200_f360_intel_inputs | RPCs de presupuesto versionado, `goals`, `cost_basis` (columna generada), contadora (`finance_preparers`) y compromisos | board finance (15000200/0300), product_cost_versions (14000400) | DDL en `budget_versions` (0 filas) y `product_cost_versions` (0 filas); vista `product_cost_effective` + 1 columna (sin dependientes en prod). Sin DML |
| 3 | 20261024000300_f360_intel_metrics | Capa de métricas de solo lectura + `f360_intel_query` + `f360_intel_cockpit` | commerce_orders_reporting, sales_rec_*, environment_foreign_events (22*), marketing_spend_daily, classify_channel_v1 (21000100) | No |
| 4 | 20261024000400_f360_ai_analyst | `ai_settings` (USD 100, 40/día), `ai_queries` (auditoría), cuotas | 1–3 | No |
| 5 | 20261024000500_f360_intel_f4_f5_h2 | Lista completa y paginada, ROAS solo atribuido, reserva atómica del tope | 3, 4, commerce_woo_attribution | No |
| 6 | 20261024000600_f360_intel_f4b_h1b | Señales con la lista completa; la auditoría conserva las fechas | 3–5 | No |
| 7 | **20261024000700 (por construir)** | Acceso de la contadora sin rol de F360 (ver §4) | 2 | No |

- **Fuera de I5:** 20261017000100 (earn-in tracker) está pendiente en producción, pero es otro módulo y ninguna migración de I5 depende de ella.
- **Forma de aplicarlas:**
  - un pase por migración (`supabase/pase/20261012_i5_N_*.sql` = migración + fila de `schema_migrations` + revisiones posteriores);
  - cada uno con `scripts/f360/prod_sql.sh`: primero ensayo (ROLLBACK) y luego aplicación;
  - si una falla, se detiene la secuencia.

## 2. Compatibilidad con la tabla de aprobadores (descuentos)

En producción hoy:
- La regla de alcances es `CHECK (scope IN ('fx_rate','budget','close','store_discount'))`.
- Hay una sola fila: **Carolina = `store_discount`**.
- RLS activa; permisos solo para `postgres` y `service_role`.
- `f360.can_approve` la usan 4 funciones de descuentos.

Lo que hace I5:
- **Mi migración 1 no redefine la regla.** Crea la tabla `IF NOT EXISTS` (en producción no hace nada) y `COMMENT` con el **mismo** texto que ya tiene.
- **`CREATE OR REPLACE f360.can_approve` es idéntica:** la huella de su definición es la misma en el repo, en staging y en producción (`565a9163…`). No cambia nada.
- `ENABLE RLS`, `REVOKE` y `GRANT` dejan exactamente los permisos actuales.
- **Carga de datos (D3):** `INSERT … ON CONFLICT DO NOTHING` solo de `fx_rate`, `budget` y `close`. **Nunca** se toca ni se borra la fila `store_discount`. La reversión borra solo esos 3 alcances.
- **Verificación en el ensayo de la migración 1:** antes y después, la regla, las filas, los permisos y la definición de `can_approve` deben ser idénticos.
- **Recomendación** para evitar dudas: quitar el `COMMENT` del pase de producción, aunque hoy no cambie nada.

## 3. Componentes que se desplegarían

**Edge Functions** (proyecto `tgzg…`, `--no-verify-jwt`; cada una valida la sesión o el secreto por su cuenta):

| Función | Secretos | Llamadores | Escribe |
|---|---|---|---|
| `f360-fx-rates` | `F360_SYNC_SECRET` (ya existe) | Cron diario 14:00 UTC (Vault) o una dueña | Solo `fx_observations`, propuestas en `fx_rates` y `measurement_runs` |
| `f360-analyst` | `ANTHROPIC_API_KEY` (**nueva, exclusiva de producción**, ver §5); `F360_AI_PROVIDER` opcional | Panel `/inteligencia` con la sesión de la persona | Solo auditoría (`ai_queries`, `ai_inflight`). Los datos los lee con la sesión de la persona |

- `deploy_prod_function.sh` **no** incluye estas dos funciones; el clasificador bloqueó editarlo. Hay que agregarlas a su lista blanca (con autorización) o publicarlas con un comando explícito que tú apruebes.

**RPCs nuevas o reemplazadas:**

| Grupo | Funciones | Quién puede |
|---|---|---|
| Tipo de cambio | `f360_fx_status`, `f360_fx_month_propose`, `f360_fx_observation_manual` | operador/dueña |
| | `f360_fx_rate_approve` | dueña **y** alcance `fx_rate` |
| | `f360_fx_observations_record` | solo service role |
| Presupuesto y metas | `f360_board_budget_*`, `f360_board_goal_set`, `f360_board_goals` | consejo FINANCIAL + segundo factor; aprobar = alcance `budget` |
| Contadora | `f360_close_prep_*`, `f360_finance_commitment_*` | contadora o consejo; aprobar compromisos = consejo |
| Métricas | `f360_intel_query`, `f360_intel_cockpit` | consejo FINANCIAL + segundo factor (bitácora con `actor_kind`) |
| IA | `f360_ai_history`, `f360_ai_usage`, `f360_ai_settings_set` | consejo; cambiar límites = alcance `budget` + motivo |
| | `f360_ai_quota`, `f360_ai_reserve`, `f360_ai_log` | solo service role |

Todas las funciones internas (`f360.intel_*`, `f360.ai_mask`, `can_approve`, `fx_rate_for_report`) quedan sin acceso para `anon` y `authenticated`.

**Pantallas** (panel `fuxia360`): `/direccion`, `/direccion/tipo-de-cambio`, `/direccion/presupuesto`, `/inteligencia` (consejo + segundo factor) y `/cierre-contable` (contadora + consejo). Ya están publicadas (ver §0). En I5 se publicaría un commit **fijo** con las correcciones F1–F5/H1–H3: `d0ca96a` y posteriores.

**Variables:**
- **Panel:** `F360_PUBLISHER_URL` (base de funciones). Ya la usan las acciones de catálogo; hay que verificar que exista en el proyecto de producción **antes** de la etapa 5.
- **Supabase:** `ANTHROPIC_API_KEY` (nueva). Las demás ya existen.

**Cron:** `f360-fx-rates` (nuevo, lo crea la migración 1).

## 4. Autorización definitiva de la contadora: mínimo privilegio
- **Hoy, en staging:** la contadora demo es `viewer` en `f360.user_roles` + `finance_preparers`. **Problema:** `viewer` puede llamar **66** funciones de F360 que piden `require_role('viewer')`, repartidas en 35 migraciones (inventario, productos, etc.). Además, el panel adivina "es contadora" por ser `viewer`.
- **Diseño definitivo** (se construye y prueba en staging antes de I5; migración 7 + cambio del panel):
  1. La contadora **no tiene fila en `f360.user_roles`**. Así no pasa `require_role()` de ningún nivel: ni ventas, ni inventario, ni productos, ni clientas, ni usuarios.
  2. Su identidad financiera es solo `f360_board.finance_preparers` (`can_close` / `can_budget`). Se registra con un script revisado y con evidencia de identidad, igual que el consejo.
  3. Nueva RPC `public.f360_finance_access_state()`, que solo informa el estado de quien llama: `{preparadora, can_close, can_budget, consejo, mfa_requerido}`. El panel la usa para enviarla a `/cierre-contable`. Así desaparece la heurística de "todo `viewer` es contadora".
  4. El grupo de rutas `(contabilidad)` usa solo esa RPC y las `f360_close_prep_*` y `f360_finance_commitment_*`. El resto del panel la manda a `/cierre-contable` **desde el servidor**.
  5. Segundo factor obligatorio, igual que el consejo (`require_aal2`).
  6. Aprobar: nunca. Cierre y compromisos los aprueba el consejo (Mario o Carolina), y nunca quien capturó.
- **Prueba de acceso por usuario y función** (automática, en staging):
  - se recorren **todas** las funciones `public.*` con `EXECUTE` para `authenticated`;
  - con la sesión de la contadora, cada una debe responder "sin acceso" salvo la lista permitida (`f360_finance_access_state`, `f360_close_prep_*` y `f360_finance_commitment_add`/`_event` sin `approved`);
  - mismas pruebas para vendedora, dueña sin consejo y consejo.
  - Además: E2E de redirección desde todas las rutas del panel.

## 5. Llave de Anthropic exclusiva de producción
1. **Mario**, en console.anthropic.com (organización de Fuxia): crea el **workspace `fuxia360-produccion`** con **límite de gasto de USD 100/mes** y dentro una API key `fuxia360-produccion`. Es distinta de la de staging.
2. **Mario la pega directamente** en supabase.com → proyecto de **producción** (`tgzg…`) → Edge Functions → Secrets → `ANTHROPIC_API_KEY`, **en MAYÚSCULAS**. En staging se guardó en minúsculas; la función acepta ambas, pero en producción se usa el nombre estándar. Se pega de navegador a navegador: nunca en el chat, la terminal, un archivo ni un prompt.
3. **Claude** solo verifica que existe, por nombre (`supabase secrets list` muestra nombre y huella, nunca el valor).
4. **Orden:** la llave se pone **después** de publicar la función y de la prueba de humo sin llave, que debe responder 503 "sin configurar". Así nada consume antes de tiempo.
5. **Para apagarlo de inmediato:** borrar el secreto (respuesta 503), o en `/inteligencia` → Consumo poner `enabled = false` (solo Mario, con motivo).

## 6. Límites de consumo y prueba de que no se pueden cambiar sin autorización
**Valores en `f360.ai_settings`** (los pone la migración 4; no hay que configurarlos):
- USD 100 al mes; **aviso al 80%** (`warning`) y **freno al 100%** (`limite_mes`);
- 40 preguntas por persona al día;
- 6 herramientas por pregunta y 1,500 tokens de salida;
- margen de costo antes de cada pregunta (H3) y reserva atómica (H2).
- Segunda barrera independiente: el workspace de Anthropic con límite de USD 100.

**Pruebas** (en producción, con `prod_sql.sh --dry-run`, que siempre termina en ROLLBACK):
- Valores iniciales exactos (A1).
- `f360_ai_settings_set`:
  - como Carolina (sin alcance `budget`) → rechazado;
  - sin motivo → rechazado;
  - con campos fuera de la lista → rechazado;
  - fuera de rango → rechazado.
- `authenticated` y `anon` **no** pueden ejecutar `f360_ai_quota`, `f360_ai_reserve`, `f360_ai_log` ni leer o escribir `ai_settings`/`ai_queries` (A5, A7, R4).
- Todo cambio queda en `ai_settings_changes` (append-only, nadie lo borra).
- Freno: con un presupuesto simulado dentro del ensayo, la segunda reserva se rechaza (R3).

## 7. Despliegue por etapas
Cada etapa tiene: verificación previa → acción → humo → criterio de aceptación. Si falla, se detiene y se revierte esa etapa.

| Etapa | Acción | Humo / aceptación |
|---|---|---|
| E0 Previa | Foto de solo lectura de negocio (pedidos, hash económico Woo, eventos y saldo de inventario, ventas remotas, gasto, costos, cierres, presupuesto, tipos de cambio, alcances) · lista de migraciones · usuarias `viewer` = 0 · `F360_PUBLISHER_URL` presente · ensayo en staging recién copiado de producción con las 7 migraciones en orden | Todo coincide con lo esperado → GO |
| E1 Base | Pases 1→7 con `prod_sql.sh` (ensayo → aplicación), uno por uno | Después de cada uno: revisiones del pase + foto de negocio idéntica + permisos y alcances de descuentos idénticos |
| E2 Tipo de cambio | Publicar `f360-fx-rates` → backfill desde 2026-05-01 (secreto del cron) → proponer meses cerrados | ~230 observaciones; 10 propuestas; cron a las 14:00 UTC responde 200; nada aprobado todavía |
| E3 Datos de gobierno | Alcances `fx_rate`/`budget` = Mario y `close` = Mario + Carolina (sin tocar `store_discount`) · Mario registra la meta de $300,000 **él mismo** en `/direccion/presupuesto` · contadora (si D5) | `f360_fx_status.can_approve` = true solo para Mario; la meta aparece en el cockpit |
| E4 Panel | `deploy_prod_admin.sh` desde un **commit fijo y revisado**. Se revisa antes la lista de commits de otras sesiones que entrarían | Cockpit con 8 tarjetas y sellos; tipo de cambio con botón solo para Mario; contadora redirigida |
| E5 Analista sin llave | Publicar `f360-analyst` | Una pregunta → 503 "sin configurar", auditada; costo 0 |
| E6 Llave | Mario pone la llave (§5) | 1 pregunta ("fuentes") → 200, auditada, costo < USD 0.02 |
| E7 Validación | §11 | Criterios de §11 |

**Monitoreo** durante 7 días (lecturas diarias):
- `ai_queries`: preguntas, costo acumulado contra USD 100, estados `error`/`denegado`/`limite_*` y cifras no verificadas;
- `measurement_runs`: `fx_rates` correcto cada día;
- cron `f360-fx-rates` en 200;
- `access_log`: negaciones inesperadas;
- foto de negocio sin cambios atribuibles a I5.

## 8. Rollback por componente
| Componente | Cómo | Efecto |
|---|---|---|
| Analista | Borrar el secreto `ANTHROPIC_API_KEY` (inmediato, 503) · `supabase functions delete f360-analyst` | Cero consumo |
| Límites | `f360_ai_settings_set({"enabled": false}, motivo)`, solo Mario | Apaga el analista sin desplegar |
| Panel | Vercel → fuxia360 → despliegue anterior (`fuxia360-dlavhb5zj` = el actual) → Promote | Vuelven las pantallas de hoy |
| `f360-fx-rates` | `supabase functions delete f360-fx-rates`; el cron se quita con el down de la migración 1 | Sin lecturas nuevas |
| Migraciones | `.down.sql` en orden inverso 7→1, cada uno en una transacción. Ya ensayados en staging: 0500 y 0600 restauran las funciones previas exactas; 0100 conserva `approval_scopes`/`can_approve` y solo borra los alcances `fx_rate` | Los down se niegan si hay historial (FX, metas, compromisos, auditoría IA) salvo con bandera explícita y después de exportarlo |
| Alcances | `DELETE … WHERE scope IN ('fx_rate','budget','close')` | `store_discount` intacto |

## 9. Evidencia de que no se modifican pedidos, inventario, costos, ventas ni información financiera
- **Por diseño:**
  - Las 7 migraciones son aditivas: tablas nuevas, funciones nuevas o reemplazadas con la misma firma, y una columna generada en tablas con 0 filas en producción.
  - Ninguna tiene `INSERT`/`UPDATE`/`DELETE` sobre `commerce_*`, `inventory_*`, `product_cost_versions`, `remote_sales`, `marketing_spend_*`, `monthly_close_entries`, `budget_*` ni `fx_rates`. Las únicas escrituras en runtime son la bitácora de acceso, la auditoría de IA y, por la función de tipo de cambio, `fx_observations`/propuestas.
- **Probado en staging:**
  - M11: las 13 herramientas y el cockpit solo escriben `access_log`, medido en la transacción.
  - Los ensayos de 0500 y 0600 dieron 0 filas, 0 permisos, 0 RLS, 0 políticas y 0 contratos cambiados.
  - Las tablas de negocio salieron idénticas antes y después de cada corrida del evaluador.
- **En producción:** la foto E0 se repite después de E1, E2, E3 y E6; debe ser idéntica salvo la actividad normal de la tienda, que se separa por fecha.

  Foto de referencia de hoy: commerce_orders 92 · hash Woo `a9d2e024…` · inventory_events 479 · saldo 662 pares · remote_sales 1 · marketing_rows 553 · costos 0 · cierres 0 · presupuestos 0 · fx_rates 0.

## 10. Riesgos y GO / NO-GO
| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| El despliegue del panel arrastra trabajo de otras sesiones | Alta | Medio | Commit fijo y revisado; lista de commits presentada en E0; coordinar con las otras sesiones |
| Pantallas visibles antes de su base (ya ocurre, §0) | Ya ocurre | Bajo | D0 |
| Cambio de `f360_fx_rate_approve`: Carolina ya no puede aprobar FX | Cierta | Bajo (es la decisión de Mario) | Documentado; 0 tasas hoy |
| La contadora obtiene más acceso del debido | Media hoy (`viewer`) | Alto | §4 antes de dar de alta a cualquier contadora en producción |
| Costo de IA | Baja | Medio | Dos barreras de USD 100, reserva atómica, freno, apagado inmediato |
| El analista cita cifras sin trazabilidad | Baja | Medio | F2/F3; validación E7 |
| Datos incompletos que confunden (tienda antes de P0E, costos, GA4) | Cierta | Medio | Sellos FALTA/PARCIAL con quién lo provee |
| Fallo del DOF o de la TRM | Baja | Bajo | Salud ERROR/STALE; propuestas solo con 10 o más días |
| Choque con migraciones de otras sesiones | Media | Medio | Ensayo en staging recién copiado de producción con las 7 en orden, justo antes de E1 |

- **GO:**
  - D0–D8 decididas;
  - E0 limpia;
  - ensayo en staging recién copiado con 0 cambios de negocio, permisos y contratos;
  - §4 construido y probado en staging (si habrá contadora);
  - sin otra sesión aplicando migraciones en producción al mismo tiempo.
- **NO-GO:**
  - cualquier diferencia en la foto de negocio;
  - un ensayo con error;
  - el CHECK o las filas de `approval_scopes` distintos de lo esperado;
  - la llave pegada en un canal que no sea el panel de Supabase;
  - una cifra no verificada en la validación E7.

## 11. Validación posterior (E7)
1. **Las 10 preguntas ejecutivas + las prioridades semanales**, hechas por Mario y Carolina en `/inteligencia` de producción.
   - Por cada respuesta, Claude compara con lecturas de solo lectura de la capa de métricas (las mismas funciones, sin pasar por el modelo) y la califica igual que en I4.
   - Criterio: 100% con fuentes y periodos, 0 cifras inventadas, prioridades con 3 elementos.
2. **Controles de seguridad:**
   - una vendedora y una cuenta sin consejo reciben "no disponible";
   - la contadora solo ve el cierre;
   - las 3 preguntas trampa (SQL, escritura, EBITDA);
   - `f360_ai_settings_set` rechazado para Carolina.
3. **Métricas de negocio:**
   - cockpit contra cifras conocidas: ventas por mercado, $300,000, 662 pares en el ledger, ROAS atribuido de México contra la lectura directa;
   - FX: 10 propuestas, ninguna aprobada hasta que Mario lo haga.
4. **Costo:** la validación completa debe quedar por debajo de USD 2, y el monitoreo de 7 días por debajo de USD 15 (estimado).

## 12. Decisiones que necesitan tu aprobación antes de ejecutar
| # | Decisión | Opciones / recomendación |
|---|---|---|
| D0 | Pantallas ya visibles en producción (§0) | **Recomendado:** ocultarlas con un interruptor de entorno hasta E4 (requiere desplegar el panel de producción, autorización aparte). O dejarlas así hasta I5 |
| D1 | Ejecutar I5 completo | Fecha y hora con poca actividad; sin otras sesiones migrando |
| D2 | Construir primero en staging el acceso definitivo de la contadora (§4, migración 7 + panel) | Recomendado antes de I5 |
| D3 | Alcances de producción: `fx_rate` = Mario, `budget` = Mario, `close` = Mario y Carolina | Confirmar. `store_discount` = Carolina no se toca |
| D4 | Meta $300,000 MXN ecommerce MX | **Recomendado:** la registras tú en `/direccion/presupuesto` (queda con tu firma) |
| D5 | ¿Habrá contadora en producción? ¿Quién (correo)? | Solo después de D2 |
| D6 | Llave de Anthropic de producción | Workspace `fuxia360-produccion`, USD 100, la pegas tú en Supabase de producción |
| D7 | Publicar `f360-fx-rates` y `f360-analyst` | Agregarlas a `deploy_prod_function.sh` o aprobar el comando explícito |
| D8 | Despliegue del panel desde un commit fijo, revisando lo que traiga de otras sesiones | Recomendado |
| D9 | Aprobación de las tasas FX mensuales de mayo a septiembre | Las apruebas tú en `/direccion/tipo-de-cambio` después de E2 |
