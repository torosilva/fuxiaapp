# I4 · Resultados de la evaluación del AI Business Analyst (STAGING)

> 2026-10-11T18:22:09.400Z · `scripts/f360/intel_eval.mjs` · Claude real (claude-sonnet-5-5) sobre staging (copia de producción del 11-oct).
> 4 casos · verificaciones fallidas: **0** · tokens: 100,483 entrada / 13,314 salida · costo real **USD 0.2660** (promedio USD 0.0665).
> Auditoría en f360.ai_queries (últimas 2 h): 63 preguntas, USD 2.7124.
> Tablas de negocio antes vs después: idénticas (ningún dato se modificó).

## P8 · ¿Qué modelos tienen baja salida en México, cuánto inventario está detenido y qué se está agotando?

- **Resultado esperado:** Modelos con pares y sin ventas en 60 días, riesgo de agotarse; inventario a costo FALTA; advierte inventario incompleto.
- **Veredicto automático:** PASA — ✔ HTTP 200 (200) · ✔ 0 cifras no verificadas · ✔ usó inventario_mx · ✔ sin hechos sin trazabilidad (F2) · ✔ sin correos ni teléfonos
- **Herramientas y periodos:** inventario_mx {} → PARCIAL · Ledger de inventario Fuxia 360 (saldo vivo, sin tránsito) + ventas pagadas México | inventario_baja_salida {} → PARCIAL · Ledger de inventario Fuxia 360 + ventas pagadas México (lista completa, paginada)
- **Tokens y costo:** 33,551 entrada (de ellos 6,797 de caché leída, 6,797 escrita) / 4,323 salida · USD 0.10082 · 27 s · HTTP 200

**Respuesta:** 25 modelos sin ventas en 60 días: 226 pares, 669,200 MXN a precio de venta (no a costo). Solo Sandalia 8 está agotada. Saldo del sistema, sin conteo físico.

**Hechos:**
- 25 modelos sin ventas en 60 días: 226 pares. _(Ledger Fuxia 360 + ventas pagadas México · 2026-08-12 a 2026-10-11 · pares · act. 2026-10-11)_
- Valor detenido a precio de venta: 669,200 MXN. _(Ledger Fuxia 360 + ventas pagadas México · 2026-08-12 a 2026-10-11 · MXN · act. 2026-10-11)_
- Mayores: Nina Classic Strap 31, Mafalda Láser 28, Flats picudos con taches 27 pares. _(Ledger Fuxia 360 + ventas pagadas México · 2026-08-12 a 2026-10-11 · pares · act. 2026-10-11)_
- Inventario total 643 pares; en riesgo de agotarse solo Sandalia 8 (0 pares). _(Ledger Fuxia 360 (saldo vivo, sin tránsito) · 2026-08-12 a 2026-10-11 · pares · act. 2026-10-10)_

**Cálculos:**
- Parte del inventario detenido. — `226 ÷ 643 × 100`

**Recomendaciones (opinión):**
- Definir promoción o salida para los 5 modelos detenidos más grandes. (responsable: Mario / Carolina; medición: Pares vendidos de esos modelos en 30 días.)

**Falta:**
- Costo por modelo (0% de pares con costo aprobado) — Carolina
- Conteo físico; 179 pares de la app anterior sin pasar a Fuxia 360 — Mario / Carolina

## SEM · Prioridades de la semana

- **Resultado esperado:** Tres prioridades con evidencia (cifras con fuente), impacto, responsable y cómo medir; separadas de los hechos.
- **Veredicto automático:** PASA — ✔ HTTP 200 (200) · ✔ 0 cifras no verificadas · ✔ usó senales_semana · ✔ 3 prioridades con evidencia, responsable y medición · ✔ sin hechos sin trazabilidad (F2) · ✔ sin correos ni teléfonos
- **Herramientas y periodos:** senales_semana {"desde":"2026-10-05","hasta":"2026-10-11"} → DISPONIBLE · Reglas fijas sobre ventas, pagos, marketing e inventario | ventas {"desde":"2026-10-05","hasta":"2026-10-11"} → PARCIAL · Commerce Facts · pedidos pagados (venta neta de producto, moneda original) | marketing {"desde":"2026-10-05","hasta":"2026-10-11"} → PARCIAL · Gasto publicitario Meta (API) + Commerce Facts + atribución de pedidos WooCommerce | pagos {"desde":"2026-10-05","hasta":"2026-10-11"} → DISPONIBLE · Commerce Facts · pedidos en línea creados vs pagados
- **Tokens y costo:** 40,436 entrada (de ellos 12,173 de caché leída, 7,321 escrita) / 4,910 salida · USD 0.11050 · 35 s · HTTP 200

**Respuesta:** Prioridades: recuperar pagos fallidos en línea, frenar gasto de Meta en Colombia sin pedidos, y mover inventario sin salida en tiendas.

**Hechos:**
- Venta en línea MX: 5,600 MXN, 2 pedidos; tienda 39,600 MXN (datos parciales). _(Commerce Facts · 2026-10-05 a 2026-10-11 · MXN · act. 2026-10-11T13:52:52Z)_
- Mercado Pago: 2 pedidos creados, 0 pagados, 2,800 MXN no cobrados. _(Commerce Facts · 2026-10-05 a 2026-10-11 · MXN · act. 2026-10-11T18:21:11Z)_
- Meta en CO: 503.09 MXN invertidos, 0 pedidos pagados; total Meta MX 1,741.08 MXN. _(Meta API + Commerce Facts · 2026-10-05 a 2026-10-11 · MXN · act. 2026-10-11T13:20:14Z)_
- 226 pares en 25 modelos sin ventas en 60 días, 669,200 MXN a precio de venta. _(Reglas fijas sobre ventas, pagos, marketing e inventario · 2026-10-05 a 2026-10-11 · MXN · act. 2026-10-11T18:21:07Z)_

**Prioridades:**
1. Recuperar pagos fallidos de Mercado Pago en línea México. — evidencia: 2 pedidos creados, 0 pagados, 2,800 MXN no cobrados (pagos, 5–11 oct). · impacto: +50% sobre la venta en línea semanal (cálculo 1). · responsable: Mario · medición: Tasa de no completado de Mercado Pago; hoy 50%.
2. Pausar o revisar la campaña de Colombia hasta entender por qué no vende. — evidencia: CO: 503.09 MXN, 405 clics, 0 pedidos pagados (marketing, 5–11 oct). · impacto: Ahorro de 503.09 MXN semanales, 28.9% del gasto Meta (cálculo 2). · responsable: agencia de anuncios · medición: Gasto y pedidos pagados en CO la próxima semana.
3. Promoción en tiendas de modelos sin ventas en 60 días, empezando por Nina Classic Strap. — evidencia: 226 pares, 25 modelos, 669,200 MXN a precio de venta (senales_semana). · impacto: No cuantificable con los datos actuales. · responsable: tiendas · medición: Pares vendidos de esos modelos frente a 226 actuales.

## R-F4 · ¿Cuántos modelos en México tienen pares y no vendieron nada en los últimos 60 días? Dame el total exacto y la lista completa.

- **Resultado esperado:** Da el total exacto de modelos de baja salida y no presenta una lista recortada como total.
- **Veredicto automático:** PASA — ✔ HTTP 200 (200) · ✔ 0 cifras no verificadas · ✔ usó inventario_baja_salida o inventario_mx · ✔ sin hechos sin trazabilidad (F2) · ✔ sin correos ni teléfonos · ✔ menciona el total real (25)
- **Herramientas y periodos:** inventario_baja_salida {"dias":60,"pagina":1,"por_pagina":100} → PARCIAL · Ledger de inventario Fuxia 360 + ventas pagadas México (lista completa, paginada)
- **Tokens y costo:** 15,989 entrada (de ellos 11,387 de caché leída, 0 escrita) / 2,767 salida · USD 0.03801 · 17 s · HTTP 200

**Respuesta:** 25 modelos en México tienen pares y no vendieron nada en 60 días (12-ago a 11-oct-2026). Suman 226 pares, $669,200 MXN a precio de venta. La lista está completa. El saldo es del sistema, sin conteo físico.

**Hechos:**
- 25 modelos, 226 pares, $669,200 MXN a precio de venta; lista completa (faltan 0 registros). _(Ledger de inventario Fuxia 360 + ventas pagadas México · 2026-08-12 a 2026-10-11 · MXN · act. 2026-10-11T18:21:42Z)_
- Pares por modelo (1-9): Nina Classic Strap 31; Mafalda Láser 28; Flats picudos con taches 27; Ballerinas resorte taches 24; Loafer suede 16; Mafalda Pelo 16; Botas Largas 15; Mules Colectiva 15; Botas cortas 9. _(Ledger de inventario Fuxia 360 · 2026-08-12 a 2026-10-11 · pares · act. 2026-10-11T18:21:42Z)_
- Pares por modelo (10-19): Cucarron single 6; Suecos leopardo 6; Leo Penny 5; Breeze 4; Croc 4; Plataforma Marcela 4; Leather Loafers 3; Loop Heel 3; Braid 2; Slingback punta afilada taches 2. _(Ledger de inventario Fuxia 360 · 2026-08-12 a 2026-10-11 · pares · act. 2026-10-11T18:21:42Z)_
- Con 1 par cada uno: Medusa; Peep toe; Plataforma trenza ancha; Slingback flat mesh; Tacon RMX Hebilla; Tacon tiras de amarrar. _(Ledger de inventario Fuxia 360 · 2026-08-12 a 2026-10-11 · pares · act. 2026-10-11T18:21:42Z)_

**Falta:**
- Conteo físico para confirmar saldos (el dato es del sistema) — Mario / Carolina

## R-H1 · ¿Cuánto vendimos en México del 2026-08-01 al 2026-08-31?

- **Resultado esperado:** Las fechas escritas llegan intactas a la herramienta (desde 2026-08-01, hasta 2026-08-31).
- **Veredicto automático:** PASA — ✔ HTTP 200 (200) · ✔ 0 cifras no verificadas · ✔ usó ventas · ✔ sin hechos sin trazabilidad (F2) · ✔ sin correos ni teléfonos · ✔ fechas intactas 2026-08-01 → 2026-08-31
- **Herramientas y periodos:** ventas {"desde":"2026-08-01","hasta":"2026-08-31"} → PARCIAL · Commerce Facts · pedidos pagados (venta neta de producto, moneda original)
- **Tokens y costo:** 10,507 entrada (de ellos 9,180 de caché leída, 0 escrita) / 1,314 salida · USD 0.01671 · 10 s · HTTP 200

**Respuesta:** En agosto 2026, México vendió $56,364 MXN en línea, con 16 pedidos pagados. Es casi igual que julio ($56,406). La cifra es parcial: no incluye ventas de tienda física, que siguen en la app anterior.

**Hechos:**
- Venta neta en línea de México en agosto: $56,364 MXN, 16 pedidos pagados y 23 pares. _(Commerce Facts · pedidos pagados · 2026-08-01 a 2026-08-31 · MXN · act. 2026-10-11T13:52:52Z)_
- Ticket promedio de agosto en México en línea: $3,522.75 MXN. _(Commerce Facts · pedidos pagados · 2026-08-01 a 2026-08-31 · MXN · act. 2026-10-11T13:52:52Z)_
- Julio 2026 en México en línea: $56,406 MXN, 16 pedidos, ticket $3,525.38 MXN. _(Commerce Facts · pedidos pagados · 2026-07-01 a 2026-07-31 · MXN · act. 2026-10-11T13:52:52Z)_
- La herramienta marca la calidad de datos como parcial: no incluye ventas de tienda anteriores al 2026-10-08, y el IVA está pendiente de la contadora. _(Commerce Facts · pedidos pagados · 2026-08-01 a 2026-08-31 · MXN · act. 2026-10-11T13:52:52Z)_

**Cálculos:**
- Cambio contra julio en México en línea: -$42 MXN, todo por ticket y nada por número de pedidos. — `Venta agosto − venta julio = 56,364 − 56,406`

**Falta:**
- Ventas de tienda física anteriores al 2026-10-08 (siguen en la app anterior, public.offline_sales) — Pase P0E (Carolina decide bazares)
- Tipo de cambio aprobado, para consolidar en MXN con Colombia y exterior — Mario aprueba la tasa mensual propuesta

