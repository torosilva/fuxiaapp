# A0 · 05 — Criterios de certificación: Fuxia Starter (Ballerinas)

> **Estado:** propuesta. Todo lo marcado como **criterio** es contenido de tipo `publish_sales_policy`: necesita **dos personas** (una propone y otra aprueba) y **no** admite autoaprobación (diseño §4.1.2).
> Los valores que ya aprobó Mario se indican como tales.

## 1. Requisitos para obtener el certificado

| # | Requisito | Valor | Estado |
|---|---|---|---|
| R1 | Ser alumna activa de Sales Academy | Vendedora `activa` en Vendedoras, o permiso explícito | Diseño aprobado |
| R2 | Completar **todas** las microlecciones obligatorias de la versión publicada del curso | 18; o las de la variante "Parte 1", §4 | Criterio |
| R3 | Aprobar el **examen final** | Nota **≥ 80 / 100** (configurable por curso) | Criterio |
| R4 | Sin prerequisitos | Starter es el primer nivel | Criterio |
| R5 | Sin validación práctica | Se exige a partir de Fuxia Master | Diseño |

El certificado lo emite **solo el servidor**, en la misma operación que califica el examen, cuando se cumplen R1–R3 (diseño §6.3). No hay botón para "emitir" a mano.

## 2. Examen final

| Concepto | Propuesta |
|---|---|
| Número de preguntas | **20**, tomadas al azar del banco aprobado (`04_BANCO_DE_PREGUNTAS.md`) |
| Distribución | Producto/modelos **8** · Tallas y ajuste **5** · Cuidados **2** · Atención **3** · Marca y políticas **2** |
| Repetición | Entre dos intentos seguidos, **≤ 50 %** de preguntas repetidas |
| Calificación | Cada pregunta vale lo mismo; nota = aciertos × 5 |
| Tiempo | Sin límite estricto; se registra la duración |
| Intentos | **3 por día**, con **1 h** de espera entre intentos |
| Retroalimentación | Durante el examen, ninguna. Al cerrar el intento: resultado por pregunta con explicación y fuente |
| Si no aprueba | Se le recomiendan las microlecciones de sus temas débiles; puede volver a intentar al cumplir la espera |
| Preguntas válidas | Solo las del banco **aprobado por Carolina**. Las que dependen de datos `[PENDIENTE CAROLINA]` no entran |

## 3. Al certificarse

| Qué recibe | Valor | Estado |
|---|---|---|
| Certificado Fuxia Starter | Registro con código **no predecible** (10 caracteres aleatorios) | Aprobado (decisión 3) |
| Diploma PDF | Nombre (como está en Vendedoras al emitir), "Fuxia Starter · Ballerinas", fecha, calificación, código y dirección de verificación | Diseño |
| Verificación pública | Solo **nombre e inicial del apellido**, nivel, fecha y estado (vigente o revocado). Sin tienda, teléfono ni calificación. Se puede **apagar** sin revocar | Aprobado (decisión 3) |
| Puntos Academy | **100**, una sola vez por certificado; **sin valor monetario**; **sin canje** | Aprobado (decisión 2) |
| XP | Según la tabla en revisión | **Pendiente** |

## 4. Variante "Starter · Parte 1 (Producto)" (si faltan contenidos de Carolina)

Si al iniciar el piloto todavía no hay contenido aprobado de **marca (M1), cuidados (M4) y políticas (5.4)**:

| Concepto | Propuesta |
|---|---|
| Nombre en el diploma | "Fuxia Starter · Parte 1: Producto Ballerinas" |
| Requisito | Microlecciones 2.0–2.6, 3.1, 3.3, 5.1, 5.2 (y 3.2 si se resolvió el conflicto de "media talla") |
| Examen | 15 preguntas: Producto 9 · Tallas 4 · Atención 2. Nota ≥ 80 |
| Puntos Academy | **Decisión de Mario**: 0, o una parte de los 100. El valor aprobado (100) es para el nivel completo, así que **no lo asumo** para la Parte 1 |
| Paso al nivel completo | Al publicarse M1, M4 y 5.4, la vendedora completa esas lecciones y un examen corto de 8 preguntas, y recibe el certificado completo y sus puntos, con la regla vigente |

## 5. Revocación e invalidación

| Causa | Quién | Cómo |
|---|---|---|
| Error de emisión (falla del sistema o versión equivocada) | Admin pide, Aprobadora aprueba (dos personas, aal2) | `academy_points.certificate_revoke`; reversa automática de los puntos |
| Examen presentado por otra persona (comprobado) | Igual | Igual, con motivo registrado |
| Petición de privacidad de la vendedora | Admin | **Apagar la verificación pública**, sin revocar ni tocar puntos |
| Baja de la vendedora | — | El certificado **sigue vigente** (lo ganó). Ella pierde acceso a Academy |

## 6. Vigencia y actualización

- El certificado **no vence**.
- Cuando entran modelos nuevos de Ballerinas, se publica una **microcertificación** de lanzamiento (50 Puntos Academy, aprobado). No se re-certifica el nivel.
- Si Carolina cambia una ficha validada, las lecciones afectadas pasan a revisión (diseño §9.4). Los certificados ya emitidos no cambian.

## 7. Para aprobar (dos personas)

| # | Criterio | Propuesta |
|---|---|---|
| C1 | Nota mínima | 80 |
| C2 | Preguntas y distribución | 20: 8/5/2/3/2 |
| C3 | Intentos y espera | 3 al día, 1 h |
| C4 | Variante Parte 1 y sus puntos | §4 (puntos: decisión de Mario) |
| C5 | Causas de revocación | §5 |
