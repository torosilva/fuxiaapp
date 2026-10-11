# A0 · 01 — Temario: Fuxia Starter · Ballerinas

> Primer curso de **Fuxia Sales Academy** (P0). Nivel **Fuxia Starter**. Para vendedoras de tienda, en el teléfono.
> **Estado:** borrador para revisión de Mario y Carolina. Nada está publicado.

## Etiquetas de fuente (se usan en todos los documentos de A0)

| Etiqueta | Significa | ¿Se puede enseñar como dato? |
|---|---|---|
| `[FICHA vN]` | Campo de `f360.product_knowledge` **validado** por Carolina, versión N (vía `product_knowledge_public`) | **Sí** |
| `[CATÁLOGO]` | Dato del catálogo de Fuxia 360: nombre, línea, tallas, colores, fotos | **Sí** |
| `[SISTEMA]` | Texto que ya muestra la tienda en línea (p. ej., las etiquetas "Talla exacta / chica / grande" de `f360.knowledge_labels`) | Sí, **salvo** lo marcado en conflicto |
| `[PEDAGOGÍA]` | Técnica general de atención y venta, sin datos de producto ni políticas | Sí, **después** de que Carolina la revise |
| `[BORRADOR PARA CAROLINA]` | Propuesta derivada de un campo validado (p. ej., un beneficio) | **No**, hasta que Carolina la apruebe |
| `[PENDIENTE CAROLINA]` | Hueco: el dato no existe en ningún sistema | **No** |

## Resumen del curso

| | |
|---|---|
| Para quién | Toda vendedora activa; obligatorio para el nivel Starter |
| Duración | **18 microlecciones** de 2–5 min (≈ 70 min) + examen final de 20 preguntas (≈ 15 min) |
| Ritmo sugerido | 2 microlecciones por día → ≈ 2 semanas |
| Al aprobar | Certificado **Fuxia Starter**, diploma PDF, **100 Puntos Academy** (aprobado por Mario) y XP según la tabla aún en revisión |
| Criterios | `05_CRITERIOS_CERTIFICACION.md` |

## Módulos y microlecciones

| # | Microlección | Objetivo (al terminar, la vendedora puede…) | Min | Fuente principal | Estado |
|---|---|---|---|---|---|
| **M1 · Bienvenida a Fuxia** | | | | | |
| 1.1 | Qué es Fuxia | Contar en 30 segundos qué es Fuxia y qué la hace distinta | 3 | `[PENDIENTE CAROLINA]` | ⏳ Falta historia y promesa de marca |
| 1.2 | Cómo hablamos con la clienta | Usar el tono Fuxia al saludar y al recomendar | 3 | `[PENDIENTE CAROLINA]` + `[PEDAGOGÍA]` | ⏳ Falta el tono de marca |
| **M2 · Conoce las Ballerinas** | | | | | |
| 2.0 | Cómo leer una ficha | Encontrar en una ficha talla, horma, punta, materiales y comodidad, y saber qué significa "validada" o "pendiente" | 3 | `[CATÁLOGO]` + `[SISTEMA]` | ✓ Se puede escribir ya |
| 2.1–2.6 | Modelos, en 6 familias | Reconocer cada modelo por foto y decir su ajuste de talla, horma, punta, material exterior y comodidad | 4 c/u | `[FICHA vN]` + `[CATÁLOGO]` | ✓ Con Q1: **23 modelos publicables**, 5 retenidos (`02`). Lección piloto 2.P con 5 modelos |
| **M3 · Tallas y ajuste** | | | | | |
| 3.1 | Las tallas de las Ballerinas | Saber que las Ballerinas activas vienen del **35 al 40** y revisar disponibilidad por talla en el sistema, no de memoria | 3 | `[CATÁLOGO]` | ✓ (sin equivalencias con otras escalas) |
| 3.2 | Talla exacta, chica o grande | Dar la recomendación de talla de cada modelo según su ficha, y qué hacer "entre dos tallas" | 4 | `[FICHA vN]` | ✓ Con las **notas de Carolina** ("una talla más" en los modelos de talla chica). El texto genérico de la tienda ("media talla") no se usa (`06` P1) |
| 3.3 | Cómo preguntar y probar la talla | Preguntar por la talla habitual, cómo le quedan sus zapatos y probar, sin prometer ajustes que la ficha no dice | 3 | `[PEDAGOGÍA]` | ✓ Borrador para revisión |
| **M4 · Cuidados** | | | | | |
| 4.1 | Cuidados por material | Explicar cómo cuidar cada material | 3 | `care_instructions` (`[FICHA]`) | ⏳ **0/32 modelos** tienen cuidados. Carolina los captura en la ficha de producto existente; Academy los lee |
| 4.2 | Cómo explicarlo al entregar | Dar la recomendación de cuidado al entregar el par, en 2 frases | 2 | `[PEDAGOGÍA]` + 4.1 | ⏳ Depende de 4.1 |
| **M5 · Atención y venta básica** | | | | | |
| 5.1 | Recibir y descubrir | Saludar y hacer 3 preguntas para entender qué busca la clienta (uso, ocasión, comodidad, talla) | 4 | `[PEDAGOGÍA]` | ✓ Borrador para revisión |
| 5.2 | Presentar 2–3 opciones | Elegir 2–3 modelos con la ficha y explicar por qué cada uno le sirve | 4 | `[PEDAGOGÍA]` + `[FICHA vN]` | ✓ Borrador; los beneficios entran cuando Carolina los apruebe |
| 5.3 | Dudas y objeciones | Responder las dudas frecuentes **solo** con respuestas validadas, y saber decir "lo confirmo" cuando no hay respuesta validada | 4 | `[BORRADOR PARA CAROLINA]` + `[PEDAGOGÍA]` | ⏳ Las objeciones y respuestas las aprueba Carolina |
| 5.4 | Cerrar y políticas | Cerrar sin presionar y explicar cambios, apartados, envíos y descuentos **según la política vigente** | 4 | `[PENDIENTE CAROLINA]` + `[PEDAGOGÍA]` | ⏳ Políticas: solo preguntas, sin borrador. Los descuentos de tienda tienen regla aprobada en el sistema (`20261025000100_f360_store_discounts.sql:1-9`), pero se enseñan **solo con el texto que apruebe Carolina** |

**Conteo:** M1 2 + M2 7 + M3 3 + M4 2 + M5 4 = **18 microlecciones**.

## Qué se puede usar en un piloto aunque falten respuestas de Carolina

| Bloque | ¿Piloto? | Condición |
|---|---|---|
| 2.0, 2.1–2.6 (modelos con ficha validada) | **Sí** | Con los datos de Q1; solo modelos con ficha `validado` |
| 3.1 | **Sí** | — |
| 3.2 | **Sí**, con las notas de talla de Carolina por modelo; sin el texto genérico de "media talla" | Q1 mostró que sus notas dicen "una talla más" |
| 3.3, 5.1, 5.2 | **Sí** | Después de que Carolina revise el texto `[PEDAGOGÍA]` |
| M1, M4, 5.3, 5.4 | **No** | Hasta tener su contenido |

Si el piloto sale sin M1, M4 y 5.4, el certificado sería **"Starter · Parte 1 (Producto)"**: certifica producto, no el nivel completo. Ver `05_CRITERIOS_CERTIFICACION.md` §4.
