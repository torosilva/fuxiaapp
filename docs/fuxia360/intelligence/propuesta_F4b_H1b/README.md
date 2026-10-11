# Propuesta F4b · H1b (Centro de Inteligencia) — PENDIENTE DE REVISIÓN Y APROBACIÓN

> 2026-10-11 · **No ejecutada:** ni la migración ni el ensayo. Los archivos están fuera de `supabase/migrations/` para que la copia
> nocturna de staging no la aplique sola. Al aprobarla:
> 1. Corro el ensayo (`ensayo.sh`, una transacción que termina en ROLLBACK) y te muestro su resultado.
> 2. Si sale limpio, la aplico **solo en staging**.
> 3. Repito las pruebas afectadas.

| Archivo | Qué es |
|---|---|
| `20261024000600_f360_intel_f4b_h1b.sql` | SQL completo de las dos correcciones (punto 1) |
| `20261024000600_f360_intel_f4b_h1b.down.sql` | Reversión exacta (punto 5) |
| `test_intel_f4b_h1b.sql` | Pruebas T1–T4 (punto 6) |
| `ensayo.sh` + `ensayo.sql` | Ensayo con evidencia medida (punto 4); termina en ROLLBACK |

## 1. SQL completo
Dos sentencias `CREATE OR REPLACE FUNCTION`, y nada más (revisado en el texto del SQL: 0 INSERT/UPDATE/DELETE, 0 GRANT/REVOKE, 0 ALTER, 0 POLICY, 0 DROP):
- **F4b · `f360.intel_signals_core(date, date)`:** cuerpo idéntico al actual (de 20261024000300) **salvo el bloque `INVENTARIO_BAJA_SALIDA`**, que ahora toma `modelos` y `pares` de `baja_salida_total` (la lista completa) en lugar de contar la muestra de 20.
- **H1b · `f360.ai_mask(text)`:** pasa de `LANGUAGE sql` a `plpgsql`, con la misma firma, el mismo resultado y la misma marca `IMMUTABLE`.
  - Aparta las fechas válidas (`AAAA-MM-DD` con año 19xx/20xx, mes 1–12 y día 1–31, y `DD/MM/AAAA` o `DD/MM/AA`).
  - Aplica la misma regla de siempre: correos → `[correo]`; series de 10 o más dígitos con separadores de teléfono → `[número]`.
  - Devuelve las fechas a su lugar.

## 2. Funciones, esquemas y dependencias afectados
| Objeto | Esquema | Quién lo llama | Permisos |
|---|---|---|---|
| `intel_signals_core(date,date)` | `f360` | Solo `public.f360_intel_query`, herramienta `senales_semana`, que usa el analista para las prioridades | Revocada para PUBLIC/anon/authenticated; `CREATE OR REPLACE` conserva los permisos |
| `ai_mask(text)` | `f360` | Solo `public.f360_ai_log(jsonb)`, que escribe la auditoría del analista | Igual |

- **No se tocan:** el cockpit (`intel_cockpit_core` no usa señales), las demás herramientas, tablas, vistas, RLS y la auditoría (`f360.ai_queries`).
- **Contrato de la señal:** se conservan las claves `codigo`, `area`, `titulo`, `evidencia.modelos`, `evidencia.pares`, `evidencia.ejemplos` y `tipo`. Solo se **agregan** `valor_precio_venta` y `ejemplos_nota`.

## 3. Comportamiento anterior y esperado
| | Anterior (hoy) | Esperado |
|---|---|---|
| Señal de baja salida (base de la 3ª prioridad) | `modelos` = largo de la muestra (20) · `pares` = suma de la muestra (221) | `modelos` = total real (**25**) · `pares` = total real (**226**) · `valor_precio_venta` total · 5 ejemplos con la nota "5 ejemplos de 25 modelos; lista completa en inventario_baja_salida" |
| Auditoría · "¿Cuánto vendimos del 2026-08-01 al 2026-08-31?" | `…del [número] al [número]?` | `…del 2026-08-01 al 2026-08-31?` |
| "entre el 01/08/2026 y el 31/8/26" | igual (la regla no tocaba `/`) | igual |
| Teléfono "+52 55 1234 5678" | `[número]` | `[número]` (sin cambio) |
| Correo | `[correo]` | `[correo]` (sin cambio) |
| Tarjeta "4111 1111 1111 1111" / cuenta de 18 dígitos | `[número]` | `[número]` (sin cambio) |
| "folio 2026-13-45" (mes 13, no es fecha) | `[número]` | `[número]` (sin cambio) |
| "2026-08-01-5512345678" | `[número]` | `2026-08-01-[número]`: la fecha se conserva y el teléfono se tapa |

Las cifras 25 y 226 son las de staging al 11-oct. La prueba compara contra la lista completa del momento (`intel_low_sell_page`), así que sigue siendo válida aunque cambien los datos.

**Nota de coherencia:** la función del analista (código) también conserva las fechas al enmascarar la pregunta antes de enviarla al modelo (H1, ya publicado). En un caso raro, una fecha pegada a un teléfono sin espacio, el código tapa todo y la base conserva la fecha. Las dos opciones son seguras; se pueden igualar después si lo prefieres.

## 4. Evidencia de que no cambia datos, permisos, RLS ni contratos
- **Hoy, revisando el texto del SQL sin ejecutarlo:** solo 2 `CREATE OR REPLACE FUNCTION`, sin DML, DCL, ALTER, POLICY ni DROP. Las dos funciones son internas (sin acceso para `authenticated` ni `anon`).
- **Al aprobarlo, el ensayo lo mide antes del ROLLBACK:**
  - filas cambiadas en cualquier tabla (`pg_stat_xact_user_tables`);
  - permisos y RLS (`relacl`, `relrowsecurity`, `relforcerowsecurity`) de todas las tablas y vistas de `f360`, `f360_board` y `public`;
  - huella de todas las políticas (`pg_policies`);
  - contrato de **todas** las funciones (resultado, `SECURITY DEFINER`, volatilidad, permisos);
  - funciones nuevas y funciones con cuerpo cambiado.
- **Esperado:** todo en 0, y "funciones con cuerpo nuevo" = exactamente `f360.intel_signals_core` y `f360.ai_mask`.

## 5. Reversión exacta
`20261024000600_f360_intel_f4b_h1b.down.sql` restaura los dos cuerpos **copiados textualmente** de 20261024000300 y 20261024000400, y borra la fila de `schema_migrations`. El ensayo la aplica y verifica con la huella de la definición que las 2 funciones quedan idénticas a las de antes.

## 6. Pruebas de regresión (`test_intel_f4b_h1b.sql` + suites existentes)
- **T1, F4b:** la señal reporta los mismos `modelos` y `pares` que la lista completa (hoy, 25 y 226). Imprime los valores. Máximo 5 ejemplos, con nota.
- **T2, H1b:** 9 casos de la tabla anterior. Además, la auditoría real (`f360_ai_log`) guarda "del 2026-08-01 al 2026-08-31, tel [número]" y respeta el límite de 2,000 caracteres.
- **T3:** las prioridades usan el conjunto completo: `f360_intel_query('senales_semana')`, como Mario y con el candado del consejo, devuelve los totales de la lista completa.
- **T4:** las 13 herramientas del analista responden `ok` con `meta`.
- **Regresión:** R1–R4 (F4/F5/H2), M1–M15 (métricas, incluida M11, que prueba que no se escribe nada) y A1–A8 (auditoría, topes y aislamiento entre usuarios).
- **Después de aplicar en staging:** se repite con Claude real **solo** lo afectado: prioridades semanales (SEM), R-F4, R-H1 y P8. Unas 4 preguntas, alrededor de USD 0.25.
