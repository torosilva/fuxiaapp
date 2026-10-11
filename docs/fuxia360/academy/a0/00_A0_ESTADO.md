# A0 · Estado — Fuxia Starter · Ballerinas

> Autorizado por Mario el 2026-10-11: **solo los ocho documentos** de `00_FUXIA_ACADEMY_DISENO.md` §18.
> Sin migraciones, código, despliegues ni cambios en producción o staging. **A1 no está autorizado.**

## Archivos

| # | Archivo | Estado |
|---|---|---|
| 1 | `01_TEMARIO.md` | ✓ Escrito: 5 módulos, 18 microlecciones, etiquetas de fuente, qué sirve para el piloto |
| 2 | `02_MICROLECCIONES.md` | ◐ Escritas 2.0, 3.1, 3.3, 5.1, 5.2 y la parte general de 5.3 y 5.4 · ⚠ 3.2 con conflicto · ⏳ 2.1–2.6 esperan **Q1** · ⏳ M1, M4 y políticas esperan a Carolina |
| 3 | `03_FICHAS_BALLERINAS.md` | ◐ Plantilla y reglas · ⏳ 28 fichas esperan **Q1** |
| 4 | `04_BANCO_DE_PREGUNTAS.md` | ◐ Parte A: 43 preguntas (33 utilizables, 10 bloqueadas) · Parte C: 6 plantillas · ⏳ Parte B (≥ 25) espera **Q1** |
| 5 | `05_CRITERIOS_CERTIFICACION.md` | ✓ Escrito (criterios C1–C5 para aprobar con dos personas) |
| 6 | `06_VALIDACION_CAROLINA.md` | ◐ P1–P10 priorizadas · ⏳ detalle por modelo espera **Q1** |
| 7 | `07_CONSULTAS_SOLO_LECTURA.md` | ✓ Q1, Q3 y Q4 **preparadas, no ejecutadas**; Q2 se calcula de Q1 |
| 8 | `00_A0_ESTADO.md` | Este archivo |
| — | `../P0-6_ACCESO_VENDEDORAS_PROPUESTA.md` | ✓ Propuesta separada de seguridad (no forma parte de los 8) |

## Hallazgos de A0 hasta ahora

1. **Conflicto de "media talla":**
   - El texto de ajuste que ya usa la tienda en línea recomienda "media talla más/menos" (`20261010000500_f360_product_knowledge.sql:52-54`).
   - Las Ballerinas activas solo vienen en tallas enteras del 35 al 40.
   - No se enseña hasta que Carolina decida (`06` P1). Puede afectar también a la tienda en línea; ese cambio sería **aparte** de Academy.
2. **P0-6 sigue abierto** y afecta más que a la cuenta de revisión: la contraseña derivada permite entrar como **cualquier** cuenta por teléfono, incluidas las de las dueñas.
   - Consecuencia para Academy: **toda** aprobación y administración de Academy exige segundo factor, también `publish_sales` (diseño §4.1.2, actualizado).
   - Los canjes siguen bloqueados.
3. **Regla existente de descuentos:** "un par con descuento de tienda no tiene cambio" ya está en el sistema (`20261025000100_f360_store_discounts.sql:9`). Se enseña solo con el texto que confirme Carolina (`06` P9).

## Criterios de salida de A0 (§18.6 + pedido de Mario)

| # | Criterio | Estado |
|---|---|---|
| 1 | Los ocho documentos completos | ◐ Faltan las partes que dependen de Q1 |
| 2 | Resumen de contenido validado y pendiente | ◐ Por módulo en `01`; por modelo con Q1 |
| 3 | Lista priorizada de preguntas para Carolina | ✓ `06` (P1–P10) |
| 4 | % de fichas con información suficiente para publicar | ⏳ Q1 (`03`, resumen) |
| 5 | Banco con respuestas y fuentes | ◐ Parte A lista; Parte B con Q1 |
| 6 | Recomendación de contenido para el primer piloto | ◐ `01` (tabla del piloto); se cierra con Q1 |
| 7 | Riesgos abiertos, especialmente P0-6 | ✓ Arriba + `P0-6_ACCESO_VENDEDORAS_PROPUESTA.md` |
| 8 | Ninguna afirmación de producto sin etiqueta de fuente | ⏳ Revisión automática del texto al cerrar |

## Siguiente paso

Mario revisa `07_CONSULTAS_SOLO_LECTURA.md` y autoriza o no la ejecución de Q1, Q3 y Q4.
