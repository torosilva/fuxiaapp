# A0 · 06 — Lo que Carolina debe validar o darnos

> Ordenado por **prioridad** para el piloto, para que Carolina invierta su tiempo donde más rinde.
> **Formato:** cada bloque se pasa a **Google Docs** para comentar, una vez que Mario confirme con quién se comparte. No se comparte nada automáticamente.
> **Tiempo estimado total:** ≈ 90 min de respuestas + ≈ 2 h de revisión, que pueden repartirse en 3 sesiones.

## Resumen

| Prioridad | Tema | Bloquea | Tiempo | Tipo |
|---|---|---|---|---|
| **P1** | Conflicto de "media talla" | Microlección 3.2 + preguntas de ajuste chico/grande | 5 min | Decisión |
| **P2** | Revisar las 28 fichas (datos validados y faltantes) | Módulo 2 completo | 40 min | Revisión |
| **P3** | Los modelos sin ficha validada | Si entran o no al curso | 5 min | Decisión |
| **P4** | Revisar las preguntas del banco y las 6 plantillas | Examen | 40 min | Revisión |
| **P5** | Revisar la parte de técnica de venta `[PEDAGOGÍA]` | 3.3, 5.1, 5.2 | 15 min | Revisión |
| **P6** | Beneficios, objeciones y "recomiéndala para…" por modelo | 5.3 y tarjeta 4 de cada modelo | 30 min | Aprobar, editar o rechazar borradores |
| **P7** | Cuidados por material | Módulo 4 | 15 min | Dar el contenido (en la ficha de producto existente) |
| **P8** | Historia, promesa y tono de la marca | Módulo 1 | 15 min | Dar el contenido |
| **P9** | Políticas: cambios, apartados, envíos, descuentos | 5.4 | 15 min | Dar el texto vigente |
| **P10** | Criterios de certificación | Certificar | 5 min | Aprobar (con Mario: dos personas) |

**Con P1–P5 resueltas** sale el piloto "Starter · Parte 1 (Producto)". **Con P1–P10**, el nivel Starter completo.

---

## P1 · Conflicto de "media talla" (decisión)

**Qué pasa:**
- Las fichas usan las etiquetas "Talla chica → *Te recomendamos pedir media talla más de tu talla habitual*" y "Talla grande → *media talla menos*". Ese texto es el que ve la clienta en la tienda en línea (`supabase/migrations/20261010000500_f360_product_knowledge.sql:52-54`).
- Pero las Ballerinas activas solo vienen en tallas **enteras** del 35 al 40.

**Pregunta:**
- ☐ En un modelo de "talla chica", ¿qué le recomienda la vendedora?: ☐ una talla más · ☐ probar su talla y la siguiente · ☐ otra: ____
- ☐ ¿Y en uno de "talla grande"? ____
- ☐ ¿Hay que corregir también el texto de la tienda en línea? (Si sí, es un cambio aparte de Academy.)

## P2 · Revisar las 28 fichas

En `03_FICHAS_BALLERINAS.md` (se completa con Q1). Por cada modelo, Carolina marca:
- ☐ "Correcto".
- ☐ "Corregir: ____". Las correcciones de datos de producto se hacen en la **ficha de producto existente** de Fuxia 360. Academy las toma de ahí y no guarda una copia distinta.

*(Lista de campos faltantes por modelo: se agrega aquí con el resultado de Q1/Q2.)*

## P3 · Modelos sin ficha validada

Según la medición del 11-oct, 27 de 32 Ballerinas tienen ficha validada y 4 están archivadas. Con Q1 sabremos cuáles activas no tienen ficha.
- ☐ ¿Se validan para incluirlas? ☐ ¿Se dejan fuera del curso por ahora?

## P4 · Preguntas del examen

En `04_BANCO_DE_PREGUNTAS.md`:
- Parte A: 33 utilizables.
- Parte B: ≥ 25 por modelo.
- Parte C: 6 plantillas.

Por cada pregunta: ☐ OK · ☐ Corregir · ☐ Quitar. Las **plantillas** se aprueban una vez y valen para todos los modelos.

## P5 · Técnica de venta

Las tarjetas `[PEDAGOGÍA]` de 1.2 (tarjeta 2), 3.3, 5.1, 5.2, 5.3 (tarjetas 1–2) y 5.4 (tarjeta 1).
- ☐ ¿Así atendemos en Fuxia? ☐ ¿Qué cambiarías?

## P6 · Beneficios, objeciones y recomendaciones (borradores)

Por cada modelo, solo cuando hay un dato validado del que partir. Ejemplo de formato:

> **Modelo X.** Horma cómoda `[FICHA v3]` → *beneficio propuesto:* "Pensada para usarse muchas horas." ☐ Aprobar · ☐ Editar: ____ · ☐ Rechazar

Las **objeciones** no se pueden derivar de una ficha.
- ☐ Carolina (y si quiere, las vendedoras) dan las **5 dudas más frecuentes** de las clientas y la respuesta correcta a cada una.

Quedan como **contenido interno de Academy** (decisión 5).

## P7 · Cuidados

- ☐ Por cada material que usan las Ballerinas (lista con Q1): cómo se limpia, qué evitar, cómo guardarlas.
- Se capturan en el campo **Cuidados** de la ficha de producto existente (Productos → ficha), para que la tienda en línea, Hilo y Academy digan lo mismo (decisión 5).

## P8 · Marca

- ☐ La historia de Fuxia en 3 frases.
- ☐ Qué hace distinta a una Fuxia (máximo 3 ideas).
- ☐ Palabras que sí y que no usamos con la clienta.
- ☐ Un saludo ejemplo.

## P9 · Políticas vigentes (solo el texto oficial; no hay borrador)

- ☐ Cambios: plazo, condiciones, excepciones. Dato que ya está en el sistema: "un par vendido con descuento de tienda **no tiene cambio**" (regla de Carolina, BITÁCORA 2026-10-02, `20261025000100_f360_store_discounts.sql:9`). ☐ ¿Se enseña así, con este texto: ____?
- ☐ Apartados: anticipo, plazo, qué pasa al vencer.
- ☐ Envíos: desde tienda, tiempos, costos.
- ☐ Descuentos en tienda: qué puede ofrecer una vendedora y cuándo pedir autorización.

## P10 · Criterios de certificación (con Mario)

En `05_CRITERIOS_CERTIFICACION.md` §7, C1–C5:
- ☐ Carolina propone o aprueba; Mario aprueba o propone. **Dos personas.**
- ☐ Puntos de la variante "Parte 1" (§4): decisión de Mario.
