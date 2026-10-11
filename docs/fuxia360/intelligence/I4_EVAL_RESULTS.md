# I4 · Resultados de la evaluación del AI Business Analyst (STAGING)

> 2026-10-11T17:56:37.468Z · `scripts/f360/intel_eval.mjs` · Claude real (claude-sonnet-5-5) sobre staging (copia de producción del 11-oct).
> 1 casos · verificaciones fallidas: **0** · tokens: 42,406 entrada / 4,981 salida · costo real **USD 0.1152** (promedio USD 0.1152).
> Auditoría en f360.ai_queries (últimas 2 h): 75 preguntas, USD 2.7225.
> Tablas de negocio antes vs después: idénticas (ningún dato se modificó).

## SEM · Prioridades de la semana

- **Resultado esperado:** Tres prioridades con evidencia (cifras con fuente), impacto, responsable y cómo medir; separadas de los hechos.
- **Veredicto automático:** PASA — ✔ HTTP 200 (200) · ✔ 0 cifras no verificadas · ✔ usó senales_semana · ✔ 3 prioridades con evidencia, responsable y medición · ✔ sin hechos sin trazabilidad (F2) · ✔ sin correos ni teléfonos
- **Herramientas y periodos:** senales_semana {"desde":"2026-10-05","hasta":"2026-10-11"} → DISPONIBLE · Reglas fijas sobre ventas, pagos, marketing e inventario | ventas {"desde":"2026-10-05","hasta":"2026-10-11"} → PARCIAL · Commerce Facts · pedidos pagados (venta neta de producto, moneda original) | pagos {"desde":"2026-10-05","hasta":"2026-10-11"} → DISPONIBLE · Commerce Facts · pedidos en línea creados vs pagados | marketing {"desde":"2026-10-05","hasta":"2026-10-11"} → PARCIAL · Gasto publicitario Meta (API) + Commerce Facts + atribución de pedidos WooCommerce | avance_meta {"mes":"2026-10-11"} → DISPONIBLE · Meta registrada por Mario (demo) + Commerce Facts (pedidos pagados)
- **Tokens y costo:** 42,406 entrada (de ellos 12,173 de caché leída, 7,321 escrita) / 4,981 salida · USD 0.11515 · 38 s · HTTP 200

**Respuesta:** Tres prioridades: recuperar el pago fallido de Mercado Pago, revisar la inversión de Meta en Colombia (sin pedidos) y mover el inventario sin salida.

**Hechos:**
- Mercado Pago: 2 pedidos creados, 0 pagados, 2,800 MXN no cobrados. _(Commerce Facts · 2026-10-05 a 2026-10-11 · MXN · act. 2026-10-11T17:56:04Z)_
- Colombia: 503.09 MXN invertidos en Meta y 0 pedidos pagados. _(Meta API + Commerce Facts · 2026-10-05 a 2026-10-11 · MXN · act. 2026-10-11T13:20:14Z)_
- 221 pares en 20 modelos sin ventas en 60 días; el modelo mayor tiene 31 pares (86,800 MXN a precio de venta). _(Reglas fijas sobre ventas e inventario · 2026-10-05 a 2026-10-11 · MXN · act. 2026-10-11T17:56:00Z)_
- Ecommerce México: 5,600 MXN de 300,000 meta (1.9%); ritmo necesario 14,720 MXN diarios. _(Meta de Mario + Commerce Facts · 2026-10-01 a 2026-10-11 · MXN · act. 2026-10-11T17:56:04Z)_

**Prioridades:**
1. Recuperar pagos fallidos de Mercado Pago en México y revisar el proceso de pago. — evidencia: Mercado Pago: 2 pedidos creados, 0 pagados, 2,800 MXN no cobrados (pagos, 5–11 oct). · impacto: Hasta 2,800 MXN, la mitad de la venta en línea semanal (cálculo 1). · responsable: Mario · medición: Pedidos pagados ÷ creados con Mercado Pago la próxima semana.
2. Pausar o revisar la campaña de Meta en Colombia hasta entender por qué no vende. — evidencia: CO: 503.09 MXN invertidos, 405 clics, 0 pedidos pagados (marketing, 5–11 oct). · impacto: Hasta 503.09 MXN semanales sin ventas registradas. · responsable: agencia de anuncios · medición: Pedidos pagados en CO e inversión CO la próxima semana.
3. Promover en tiendas y en línea los modelos sin ventas en 60 días, empezando por los cinco mayores. — evidencia: 221 pares, 20 modelos sin ventas en 60 días (senales_semana, 5–11 oct). · impacto: Cinco modelos suman 352,800 MXN a precio de venta (cálculo 2); lo que se venda no es cuantificable. · responsable: Carolina · medición: Pares vendidos de esos modelos la próxima semana.

