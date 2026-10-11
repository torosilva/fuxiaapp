# Propuesta de migración F4 · F5 · H2 (Centro de Inteligencia) — PENDIENTE DE APROBACIÓN

> 2026-10-11 · **No aplicada.** Los archivos están FUERA de `supabase/migrations/` a propósito. La copia nocturna de staging reaplica
> desde GitHub todo lo que haya en esa carpeta, así que ponerla ahí la aplicaría sola antes de tu aprobación.
> Al aprobarla se mueve a `supabase/migrations/` y se aplica **solo en staging**, con psql en una transacción.

Archivos de esta carpeta:
- `20261024000500_f360_intel_f4_f5_h2.sql`: la migración.
- `…down.sql`: rollback.
- `test_intel_f4_f5_h2.sql`: pruebas nuevas R1–R4.
- `ensayo.sh` + `ensayo.sql`: ensayo reproducible, siempre con ROLLBACK.

## ¿Se podía sin migración?
| | ¿Sin migración? | Por qué |
|---|---|---|
| **F4** | No | La lista se recorta a 20 **dentro de la base de cálculos**: ni el analista ni la pantalla pueden saber cuántos faltan. |
| **F5** | No | La separación entre venta en línea, venta de tienda, ingresos atribuidos a Meta (atribución de WooCommerce por UTM) y ROAS se calcula en la base de cálculos. El analista no ve los pedidos uno por uno, y así debe ser. Mientras tanto, la regla 10 de las instrucciones del analista (ya publicada) le prohíbe llamar ROAS a una razón con ventas no atribuidas. |
| **H2** | No | Reservar el tope de forma atómica entre preguntas simultáneas exige un candado y un registro en la base. Mientras tanto, **H3** (ya publicado, solo código) impide empezar una pregunta si no alcanza el presupuesto para una pregunta completa. |

## 1. SQL exacto
Archivo `20261024000500_f360_intel_f4_f5_h2.sql`, en esta carpeta.

## 2. Objetos, funciones y dependencias afectados
| Objeto | Cambio | Quién lo usa | Compatibilidad |
|---|---|---|---|
| `f360.intel_low_sell_page(int,int,int)` | **Nuevo**, solo lectura | `intel_inventory_core`, herramienta `inventario_baja_salida` | — |
| `f360.intel_inventory_core(int)` | Se reemplaza, **misma firma**. Agrega `baja_salida_total` {modelos, pares, mostrados, limitada, faltan} | Tarjeta 6 del cockpit, analista, `intel_signals_core` | Conserva todas las claves anteriores |
| `f360.intel_marketing_core(date,date)` | Se reemplaza, **misma firma**. Agrega `venta_en_linea`, `venta_tienda` (no atribuida), `venta_neta` (combinada, dice qué incluye), `ingresos_atribuidos_meta` (+ MXN), `meta_organico_utm` (aparte, fuera del ROAS), `cobertura_atribucion_pct`, `eficiencia_combinada`, `eficiencia_en_linea`, `cpa_en_linea_mxn` y `mer_definicion`. `roas_atribuido` pasa de "FALTA fijo" a **ingresos atribuidos a Meta pagado ÷ inversión en Meta**: FALTA si no hay inversión o tasa aprobada; PARCIAL si la cobertura de atribución es menor a 80%. Solo suma inversión de Meta (`platform = 'meta'`) | Tarjeta 5 del cockpit, analista, `intel_signals_core` | Conserva claves y su significado; `mer` queda marcado como eficiencia combinada, "NO es ROAS" |
| `public.f360_intel_query(text,jsonb)` | Se reemplaza, **misma firma**. Agrega la herramienta `inventario_baja_salida` (pagina / por_pagina) y devuelve "Argumento no válido" en lugar de un error crudo | Analista | Mismas herramientas anteriores |
| `f360.ai_inflight` | **Tabla nueva** de reservas en curso. No es auditoría: se borra al registrar la pregunta y se ignora a los 10 min | `f360_ai_reserve`, `f360_ai_log` | — |
| `public.f360_ai_reserve(uuid,numeric)` | **Nueva**, solo service role, con candado consultivo | Función del analista (cambio de código posterior, abajo) | — |
| `public.f360_ai_log(jsonb)` | Se reemplaza, **misma firma**. Además libera la reserva `reservation_id` | Función del analista | Sin `reservation_id` se comporta igual que hoy |
| `f360.ai_queries` (auditoría) | **Sin cambios** | | |

**Cambio de código que acompaña a la migración** (solo después de aplicarla; no está publicado):
- el analista usa `f360_ai_reserve` en lugar de `f360_ai_quota` y manda `reservation_id` al registrar;
- se agrega la herramienta `inventario_baja_salida` a `DATA_TOOLS`.

## 3. Evidencia de que no cambia datos de negocio ni permisos
Medido en el ensayo, dentro de la transacción y antes del ROLLBACK:
- **Filas modificadas por la migración** en cualquier tabla (`pg_stat_xact_user_tables`, antes vs. después): **0**.
- **Permisos cambiados** de todas las tablas, vistas y funciones existentes en `f360`, `f360_board` y `public` (`relacl`/`proacl`, antes vs. después): **0**.
- **Objetos nuevos:** `ai_inflight`, `f360_ai_reserve` e `intel_low_sell_page`. Sin acceso para `anon` ni `authenticated`; solo service role (prueba R4).
- **Prueba M11:** las herramientas siguen sin escribir nada salvo la bitácora de acceso.

## 4. Rollback
`20261024000500_f360_intel_f4_f5_h2.down.sql`:
- restaura **exactamente** las 4 funciones anteriores, copiadas de 20261024000300 y 20261024000400;
- borra la tabla y las 2 funciones nuevas, y borra la fila de `schema_migrations`.

El ensayo lo aplica y verifica: **4 de 4 funciones idénticas** a las originales (hash de su definición) y la tabla nueva eliminada. No hay datos de negocio que respaldar; las reservas en curso solo liberan cupo.

## 5. Pruebas de regresión (todas pasan en el ensayo)
- **Nuevas (`test_intel_f4_f5_h2.sql`):**
  - **R1 (F4):** total y "faltan" coherentes; la paginación devuelve cada modelo una sola vez.
  - **R2 (F5):** en línea + tienda = combinada; atribuidos ⊆ en línea; ROAS = atribuidos ÷ inversión; ROAS ≤ eficiencia en línea ≤ eficiencia combinada; etiquetas "NO es ROAS" / "NO atribuida"; Colombia sin tasa aprobada → sin ROAS.
  - **R3 (H2):** con cupo para una sola pregunta, la segunda reserva se rechaza; la reserva se libera al registrar; las reservas viejas se ignoran; el tope diario cuenta las preguntas en curso.
  - **R4:** permisos.
- **Regresión:** M1–M15, A1–A8, N1–N6 y X1–X8 pasan con la migración aplicada.
  - M7 se actualizó: antes exigía ROAS siempre vacío; ahora exige "vacío **o** exactamente atribuidos ÷ inversión".
  - La versión actualizada de M7 también pasa **sin** la migración.

## 6. Solo en staging
- Se aplicaría con `psql` contra `$STAGING_DB_URL`. El guion aborta si la URL no es `faltxpkaicwpnlqaxrdu`.
- **No** existe en producción, y la función del analista **no está** en producción.
- No hay ningún despliegue a producción en este paso.

## Después de aprobarla
1. Mover los archivos a `supabase/migrations/` y `supabase/rollbacks/`, aplicar en staging y registrarla en `schema_migrations`.
2. Publicar el cambio de código del analista (reserva + herramienta nueva) en staging.
3. **Reevaluación completa:** las 19 pruebas originales + regresiones F1–F5 y H1–H3. Comparación antes/después.
