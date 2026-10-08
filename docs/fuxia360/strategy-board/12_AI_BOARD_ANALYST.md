# 12 · AI Board Analyst

> **SOLO SPEC.** No se construye en SB0–SB7. Se documenta para que el modelo de datos y las RPCs nazcan "citables".

## 1. Estado actual de IA en el repositorio

- `hilo-chat` (Edge Function de la app) **no usa un LLM**: es una base de conocimiento por palabras clave en código (`fuxia-native/supabase/functions/hilo-chat/index.ts:8-…`, arreglo `KB`).
- `f360-hilo-intake` recibe llamadas del backend externo de HiloLabs con secreto compartido (`fuxia-native/supabase/functions/f360-hilo-intake/index.ts:1-3`, `--no-verify-jwt`, Bearer `F360_HILO_SECRET`) y escribe con service role.
- No hay SDK ni llamadas a proveedores LLM en `admin-web/src`, `fuxia-native/supabase/functions`, `scripts`, `tools` (grep `anthropic|openai|gemini` sin resultados).

Conclusión: el analista sería una integración **nueva**. No debe reutilizar el canal HiloLabs → service role (está pensado para la clienta/tienda, no para datos de dirección).

## 2. Preguntas que debe responder

- "¿Cómo vamos contra presupuesto este trimestre y por qué?" (varianza descompuesta por canal/tienda/categoría).
- "¿Qué tiendas están por debajo de forecast en MTD?"
- "¿Qué tan preciso ha sido nuestro forecast a 60 días?" (bias por canal).
- "¿Qué falta para que el gate NEW STORE sea elegible?"
- "Compara escenario BASE vs AGGRESSIVE en caja requerida 2027."
- "¿Qué decisiones aprobadas tienen action items vencidos?"
- "¿En qué se ha desplegado el capital fondeado y con qué resultado?"
- "Prepárame el borrador del resumen ejecutivo del board pack de Q4" (borrador, no emisión).
- "¿Qué datos del cockpit son MISSING o PARTIAL y qué haría falta para completarlos?"

## 3. Restricciones duras

| Restricción | Cómo se garantiza |
|---|---|
| **Solo lectura** | Herramientas = solo RPCs de lectura `f360_board_*` (lista blanca). Ninguna RPC de escritura se expone como herramienta |
| No acciones financieras, no cambios en prod, no aprobaciones, no transferencias, no votos | Igual; además la sesión del analista no puede llamar RPCs de `approve/issue/transition` (servidor valida `x-f360-agent` → rechaza escritura) |
| **Cita la fuente de cada número** | Cada RPC devuelve `sources[]` (tabla/vista, versión, cierre, `as_of`, calidad). El analista solo puede emitir números presentes en respuestas de herramientas; validación posterior: todo número en la respuesta debe aparecer en el payload de herramientas de esa sesión, si no → se marca "no verificado" |
| No inventa | Si la RPC devuelve `MISSING`, la respuesta dice MISSING |
| Mismos permisos | Corre **con la sesión de la usuaria** (Carolina o Mario), por las mismas RPCs owner-only → mismo `require_board_member` y mismo access log (con `actor = 'ai_analyst'` adicional) |
| Sin PII | Las RPCs de Strategy no devuelven PII; el analista no tiene herramientas de CRM |
| Sin secretos | El prompt del sistema no contiene llaves; el proveedor recibe solo agregados |

## 4. Arquitectura sugerida (cuando se apruebe)

Route Handler en `admin-web` (servidor) → valida sesión → llama a las RPCs como la usuaria → envía resultados agregados al proveedor LLM → respuesta con citas. Decisión D11: proveedor, residencia de datos, retención (preferir sin retención de prompts), y si HiloLabs participa.

`ai_analyst_sessions` / `ai_analyst_messages` (append-only): pregunta, herramientas llamadas, ids de fuentes, respuesta, `unverified_numbers[]`. Retención: 12 meses (decisión).

## 5. Pruebas futuras
- Pregunta con dato MISSING → respuesta dice MISSING.
- Intento de inducir escritura ("aprueba la decisión X") → rechazo + log.
- Todos los números de 50 respuestas de prueba presentes en payloads de herramientas.
- Usuario no miembro → 404 en el endpoint.
