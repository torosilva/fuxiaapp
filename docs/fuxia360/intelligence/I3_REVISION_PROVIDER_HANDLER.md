# I3 · Revisión de `provider.ts` y `handler.ts` y del cálculo de precios con caché

> 2026-10-11 · revisión propia del código de `fuxia-native/supabase/functions/f360-analyst/` (commit `315200c`).
> **Solo documentación: no se cambió código.** Cada corrección espera la aprobación de Mario y se haría en un commit aparte, sin mezclar.

## Resumen
- **Seguridad de datos:** ningún hallazgo permite escribir en la base de datos ni leer datos fuera del permiso del usuario.
  - Las herramientas pasan por `f360_intel_query`, con la sesión del usuario, el candado del consejo y la verificación en dos pasos.
  - La prueba M11 confirma que la única escritura es la bitácora de acceso.
- **Hallazgos:** 3 importantes de control de costo, 4 medios de robustez y 4 menores.
- **Precios con caché:** la fórmula es correcta para el modo de caché que se usa (5 minutos). Hay un detalle de presentación y una mejora de costo (H7).

## Hallazgos

| # | Archivo | Severidad | Problema | Efecto | Corrección propuesta |
|---|---|---|---|---|---|
| H1 | handler.ts → analyst.ts `mask()` | **Importante** | La expresión que tapa teléfonos también tapa **fechas** (`2026-08-01` cumple "dígito + 8 o más dígitos o guiones + dígito"). | Una pregunta con fechas explícitas ("del 2026-08-01 al 2026-08-31") llega al modelo y a la auditoría como `[número]`, y se pierde el periodo. Las preguntas de la evaluación no traen fechas. | No tapar patrones de fecha `\d{4}-\d{2}-\d{2}` ni `\d{1,2}/\d{1,2}/\d{2,4}`; tapar solo cadenas de 10 o más dígitos con separadores de teléfono. Agregar una prueba. |
| H2 | handler.ts | **Importante** | La revisión del tope (`f360_ai_quota`) no está **reservada**: dos preguntas simultáneas pueden pasar el mismo control. | El tope mensual o diario se puede rebasar por las preguntas en curso (≈ USD 0.10 cada una). El límite del espacio de trabajo en Anthropic sigue siendo la barrera dura. | Insertar una fila "en_curso" en la auditoría antes de llamar al modelo (bloqueo por usuario con `pg_advisory_xact_lock`) y cerrarla al final. |
| H3 | handler.ts | **Importante** | Se permite preguntar si lo gastado es menor que el tope, aunque falten centavos. | Una pregunta puede rebasar el tope por su propio costo. | Exigir un margen ≥ costo máximo de una pregunta (máximo de herramientas × tokens máximos) antes de permitirla. |
| H4 | handler.ts | Medio | El tiempo límite (`timeout_seconds`) solo aplica a las llamadas al modelo, no a las herramientas. El límite de la plataforma (≈150 s) puede cortar la función **antes de escribir la auditoría**. | Una pregunta muy lenta podría consumir tokens sin quedar registrada: la auditoría subestimaría el gasto. | Un solo plazo total para modelo y herramientas, y auditoría parcial por turno (o al menos al recibir cada respuesta del modelo). |
| H5 | handler.ts | Medio | El resultado de cada herramienta se corta a 30,000 caracteres **a la mitad del JSON**. | El modelo puede recibir JSON incompleto y malinterpretar una lista larga (p. ej. inventario por modelo). | Recorte estructurado: limitar listas a N elementos y agregar `"recortado": true, "total": n`. |
| H6 | provider.ts / handler.ts | Medio | Si el modelo se detiene por `max_tokens` dentro de `entregar_respuesta`, la respuesta llega incompleta y no se valida su forma. | Faltarían campos (`hechos`, `faltantes`) y la pantalla podría fallar al leer `.length` de algo vacío. | Validar y normalizar la respuesta (listas vacías por defecto). Si `stop = max_tokens`, un reintento con más tokens o marcar "respuesta incompleta". |
| H7 | provider.ts | Medio (costo) | Solo se marcan para caché el catálogo de herramientas y las instrucciones, **no la conversación**. En cada vuelta se vuelven a cobrar completos los resultados de herramientas anteriores. | Con 3 a 5 herramientas por pregunta, la entrada crece en cada vuelta: costo mayor del necesario (estimado +20–40 %). | Marcar `cache_control` en el último bloque del mensaje más reciente (caché incremental): se escribe una vez (1.25×) y se relee a 0.05×. |
| H8 | handler.ts | Menor (costo) | Una dueña que **no** es del consejo (p. ej. Adrián en staging) pasa la revisión de rol, y el modelo se llama antes de que la primera herramienta sea rechazada. | Gasta una vuelta del modelo (≈ USD 0.01) antes del 403. No obtiene datos. | Revisar antes del modelo con `f360_board_access_state` o `f360_intel_query('fuentes')`, que no cuesta. |
| H9 | provider.ts | Menor | No hay reintento ante 429/529 (sobrecarga) o 5xx de Anthropic. | La pregunta falla y se audita como `error`. | Uno o dos reintentos con espera creciente, dentro del plazo total. |
| H10 | analyst.ts (verificador) | Menor | Solo revisa los números de **Hechos**. No revisa el resumen ni la "evidencia" de recomendaciones y prioridades. La tolerancia (0.5 %, o redondeo a entero si es ≥ 100) podría aceptar un número cercano pero distinto. | Una cifra inventada en el resumen o en la evidencia no se marcaría. | Verificar también resumen y evidencia (y marcarlo así). Para montos, tolerancia solo de redondeo, sin el 0.5 %. |
| H11 | Pantalla `/inteligencia` | Menor | "Tokens de entrada" muestra entrada + caché leída, sin la caché escrita. | Presentación; el costo sí es correcto. | Mostrar las tres por separado. |

Lo que **no** se considera problema:
- Que las herramientas reciban texto de terceros, como nombres de modelo o de campaña. Las instrucciones dicen que los datos no son órdenes y no hay ninguna herramienta que escriba; las pruebas adversariales lo comprueban.
- Las dos marcas de caché, en el catálogo y en las instrucciones. Son válidas, y el prefijo pasa del mínimo cacheable.

## Cálculo de precios con caché
- **Fuente:** platform.claude.com/docs/en/about-claude/pricing, consultada el 2026-10-11. Precios de Claude Sonnet 5.5 en USD por millón de tokens:

  | Concepto | USD por millón |
  |---|---|
  | Entrada | 2 |
  | Escritura de caché de 5 minutos | 2.50 (1.25×) |
  | Escritura de caché de 1 hora | 4 (2×) |
  | Lectura de caché | 0.10 (0.05×) |
  | Salida | 10 |

- **Cómo cobra Anthropic:** `input_tokens` cuenta **solo** la entrada no cacheada, después del último punto de caché. La caché leída y la escrita vienen aparte (`cache_read_input_tokens`, `cache_creation_input_tokens`).
- **Fórmula de Fuxia 360** (`f360_ai_log`, calculada por la base de datos y no por el cliente):

  `costo = (entrada × 2 + salida × 10 + caché_leída × 0.10 + caché_escrita × 2.50) ÷ 1,000,000`

  Es correcta porque la función usa el caché por defecto de 5 minutos. Si algún día se usa el de 1 hora, `price_cache_write_mtok` debe cambiarse a 4.
- **Precios guardados** en `f360.ai_settings`, con su fuente. Un cambio de precios es un cambio auditado (`f360_ai_settings_set`, solo Mario, con motivo).
- **Corrección al diseño:** el documento de diseño estimaba USD 3 / 15. Los precios vigentes son USD 2 / 10, así que el consumo estimado baja aproximadamente un tercio.

## Orden sugerido si se aprueban
1. **H1, H2 y H3**, que afectan la exactitud del periodo y el control de gasto.
2. **H6 y H7**, por robustez y costo.
3. **H4, H5, H8, H9, H10 y H11.**

Cada uno va con su prueba, primero en staging.
