# CRO-1 · Ajuste y talla — propuesta para validar con Carolina (D-CRO-06/07)

**Estado:** propuesta. **Sin migraciones** hasta que Carolina confirme. No se inventa ninguna recomendación: si un modelo no tiene dato capturado, la tienda no muestra nada.

## 1. Modelo propuesto (por modelo, en Fuxia 360)

| Campo | Valores | Quién lo captura |
|---|---|---|
| **Calce** | talla exacta · viene reducido · viene amplio · especial / consultar | Carolina |
| **Ancho** | angosto · normal · amplio · adaptable | Carolina |
| **Recomendación** | texto libre (1–2 líneas) | Carolina |
| **Si estás entre dos tallas** | texto libre | Carolina |
| **Notas de comodidad** | texto libre (plantilla, tacón, flexibilidad…) | Carolina |
| **Horma / notas técnicas** | texto libre, **solo si Carolina usa el concepto** (puede ser interno) | Carolina |

En el admin iría una sección **Producto → "Ajuste y talla"**, con botones para Calce y Ancho y campos de texto cortos. En la tienda, junto al selector de talla, saldría por ejemplo "✓ Este modelo viene en talla exacta", más una sección "Ajuste y talla". Todo esto **solo si hay datos**.

## 2. Preguntas para Carolina (sin respuesta todavía)

1. ¿Usas el término **"horma"**? ¿Con clientas (comercial) o solo con el taller (operativo)?
2. ¿Cómo describes hoy que un modelo **viene chico o grande**? ¿Con qué palabras exactas se lo dices a una clienta?
3. ¿Qué recomiendas para **pie ancho**? ¿Depende del modelo?
4. ¿Qué recomiendas cuando la clienta está **entre dos tallas**? (Fuxia no vende medias tallas.)
5. ¿Hay modelos que requieren una **regla especial** (botas, tacón, punta afilada)?
6. ¿Las categorías de Calce y Ancho de la sección 1 te sirven, o cambiarías alguna palabra?

## 3. Inconsistencias encontradas (D-CRO-07)

> **Corrección (2026-10-04):** la app de clientas **no** usa `hilo-chat`. Usa el agente de **HiloLabs** ("Hilo Backbone",
> `https://web-production-8cc5a.up.railway.app/api/v1/chat/web`). `hilo-chat` es una función vieja que nadie llama. Lo que dice Hilo
> sobre tallas en la app depende del conocimiento del agente HiloLabs, que **no** está en este repo y **no** se ha revisado.
> La tabla de abajo describe solo la función vieja.

**Función vieja `hilo-chat`** (`fuxia-native/supabase/functions/hilo-chat/index.ts`, base por palabras clave, **sin uso**):

| Línea | Dice hoy | Estado |
|---|---|---|
| 27 (`talla`, `medir`, `qué talla`) | **Producción:** "La distancia en centímetros corresponde a tu talla mexicana". **Staging:** corregido a la tabla 35 = MX 22 … 40 = MX 27 | Corregido **solo en staging** (commit `aedf45b`). Producción sin cambio |
| 31 (`calce`, `tallan grandes`) | "Las Fuxia tienen un calce fiel a la talla mexicana… Para pies anchos te recomiendo **subir media talla**" | **No validado por Carolina.** Fuxia no vende medias tallas |
| 43 (`pie ancho`) | "Nuestros modelos tienen calce estándar. Para pies anchos… **subir media talla**…" | Mismo problema |
| 55 (`medias`, `calcetines`) | "Si planeas usarlas con medias gruesas… **sube media talla**" | Mismo problema |
| 39 (`equivalencia`) | MX 22 = US 5 … MX 27 = US 10 | Coherente con la regla −13 (sin validar US) |

**Corrección preparada** (solo aplica si se reactiva `hilo-chat`; para la app real hay que revisar el agente HiloLabs):
- La línea 27 ya está corregida y desplegada en staging.
- Las líneas 31, 43 y 55 se reescriben **cuando Carolina responda** las preguntas 2–4: sin "media talla" y con su recomendación real.
- Prueba: `curl` a `hilo-chat` de staging con "qué talla", "pie ancho" y "medias".
- **No** se despliega en producción sin aprobación.

**Guía de tallas:** hoy es una **imagen** (`wp-content/uploads/2026/06/Guia-de-tallas-01-1.jpg`) que muestra centímetros (23, 24, 25, 25.5, 26, 27). En CRO-1B se convierte en tabla de texto con talla tienda, talla MX (−13) y cm. Los **cm por talla** también los confirma Carolina.
