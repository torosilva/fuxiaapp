# P0D · Conciliación previa a la importación del historial (SOLO LECTURA)

> Generado 2026-10-10T20:44:46.871Z con `scripts/f360/p0d_preflight.mjs --since 2026-06-01`. WooCommerce producción: solo GET con campos sin datos personales.
> Fuxia 360 producción: SELECT de solo lectura. **Nada se importó.** Corte de tiempo real (orders_since_id): 5351.

## Resumen por país, moneda y estado

| País | Moneda | Estado Woo | Pedidos | Con pago | Total | Reembolsos | P0D importaría |
|---|---|---|---|---|---|---|---|
| CO | COP | cancelled | 14 | 0 | COP 5,451,000 | COP 0 | 14 |
| CO | COP | completed | 17 | 17 | COP 8,126,300 | COP 0 | 17 |
| MX | MXN | cancelled | 9 | 2 | MXN 26,520 | MXN 0 | 8 |
| MX | MXN | completed | 34 | 34 | MXN 119,050 | MXN 0 | 34 |
| MX | MXN | failed | 4 | 0 | MXN 11,400 | MXN 0 | 4 |
| MX | MXN | processing | 1 | 1 | MXN 2,240 | MXN 0 | 1 |
| ROW | USD | cancelled | 4 | 0 | USD 405,795 | USD 0 | 4 |
| ROW | USD | completed | 1 | 1 | USD 465 | USD 0 | 1 |

**Totales:** 84 pedidos en Woo desde 2026-06-01 · 83 los importaría P0D · 1 ya están en producción · 0 posteriores al corte.
**Pagado neto aproximado por moneda (pagados no cancelados − reembolsos; referencia, no es la métrica de Growth):** COP 8,126,300 · USD 465 · MXN 121,290
**Comparación con la copia de staging4:** 83 iguales · 0 distintos · 1 no están en staging.

> País por moneda (MXN→MX, COP→CO, USD→resto). Commerce Facts además usa la ruta de la tienda; si difieren, el import lo marca como "market_conflict".

## Pedido por pedido

| Pedido | Fecha (UTC) | País | Moneda | Estado | Con pago | Total | Reembolso | Método | Creado por | En staging | Acción P0D |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2082 | 2026-06-12 | CO | COP | cancelled | no | COP 405,000 | — | epayco | store-api | igual | P0D lo importaría |
| 2095 | 2026-06-19 | ROW | USD | cancelled | no | USD 405,000 | — | ppcp-gateway | store-api | igual | P0D lo importaría |
| 2225 | 2026-06-21 | MX | MXN | failed | no | MXN 3,000 | — | ppcp-card-button-gateway | store-api | igual | P0D lo importaría |
| 2227 | 2026-06-22 | MX | MXN | cancelled | no | MXN 3,000 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2228 | 2026-06-23 | MX | MXN | completed | sí | MXN 3,000 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2256 | 2026-07-16 | CO | COP | cancelled | no | COP 425,000 | — | epayco | store-api | igual | P0D lo importaría |
| 2379 | 2026-07-23 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2385 | 2026-07-23 | ROW | USD | cancelled | no | USD 165 | — | ppcp-gateway | store-api | igual | P0D lo importaría |
| 2386 | 2026-07-23 | ROW | USD | cancelled | no | USD 315 | — | ppcp-card-button-gateway | store-api | igual | P0D lo importaría |
| 2490 | 2026-07-26 | MX | MXN | completed | sí | MXN 9,520 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2491 | 2026-07-27 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2493 | 2026-07-27 | MX | MXN | completed | sí | MXN 4,760 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2517 | 2026-07-27 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2538 | 2026-07-27 | MX | MXN | completed | sí | MXN 4,760 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2539 | 2026-07-28 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2540 | 2026-07-28 | MX | MXN | completed | sí | MXN 4,760 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2541 | 2026-07-28 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2542 | 2026-07-28 | MX | MXN | completed | sí | MXN 4,760 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2543 | 2026-07-29 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2546 | 2026-07-30 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2552 | 2026-07-31 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2573 | 2026-07-31 | MX | MXN | completed | sí | MXN 2,142 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2588 | 2026-07-31 | MX | MXN | completed | sí | MXN 4,284 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2614 | 2026-08-01 | MX | MXN | cancelled | no | MXN 4,760 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2615 | 2026-08-01 | MX | MXN | cancelled | no | MXN 4,760 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2616 | 2026-08-01 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2627 | 2026-08-02 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2628 | 2026-08-02 | MX | MXN | completed | sí | MXN 2,142 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2632 | 2026-08-03 | MX | MXN | completed | sí | MXN 2,380 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2636 | 2026-08-03 | MX | MXN | completed | sí | MXN 2,142 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2747 | 2026-08-04 | MX | MXN | cancelled | no | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2758 | 2026-08-05 | MX | MXN | cancelled | no | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2759 | 2026-08-05 | MX | MXN | cancelled | no | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2761 | 2026-08-06 | MX | MXN | failed | no | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 2766 | 2026-08-07 | CO | COP | completed | sí | COP 321,300 | — | epayco | store-api | igual | P0D lo importaría |
| 3040 | 2026-08-09 | CO | COP | cancelled | no | COP 370,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3044 | 2026-08-09 | CO | COP | completed | sí | COP 333,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3049 | 2026-08-09 | CO | COP | cancelled | no | COP 400,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3056 | 2026-08-11 | CO | COP | completed | sí | COP 378,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3090 | 2026-08-14 | MX | MXN | completed | sí | MXN 2,520 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3097 | 2026-08-15 | CO | COP | cancelled | no | COP 420,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3101 | 2026-08-15 | CO | COP | completed | sí | COP 420,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3103 | 2026-08-15 | CO | COP | completed | sí | COP 1,053,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3108 | 2026-08-16 | MX | MXN | completed | sí | MXN 11,200 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3109 | 2026-08-16 | CO | COP | completed | sí | COP 378,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3113 | 2026-08-16 | CO | COP | completed | sí | COP 820,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3117 | 2026-08-17 | MX | MXN | completed | sí | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3133 | 2026-08-17 | CO | COP | cancelled | no | COP 333,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3134 | 2026-08-17 | CO | COP | completed | sí | COP 370,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3138 | 2026-08-19 | MX | MXN | cancelled | sí | MXN 0 | — | — | store-api | igual | P0D lo importaría |
| 3142 | 2026-08-19 | CO | COP | completed | sí | COP 378,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3143 | 2026-08-19 | CO | COP | cancelled | no | COP 400,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3144 | 2026-08-19 | CO | COP | completed | sí | COP 360,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3148 | 2026-08-19 | MX | MXN | completed | sí | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3149 | 2026-08-19 | MX | MXN | completed | sí | MXN 5,600 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3151 | 2026-08-20 | ROW | USD | completed | sí | USD 465 | — | ppcp-gateway | store-api | igual | P0D lo importaría |
| 3152 | 2026-08-20 | ROW | USD | cancelled | no | USD 315 | — | ppcp-gateway | store-api | igual | P0D lo importaría |
| 3157 | 2026-08-20 | CO | COP | completed | sí | COP 360,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3165 | 2026-08-21 | MX | MXN | completed | sí | MXN 2,240 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3169 | 2026-08-21 | MX | MXN | completed | sí | MXN 2,240 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3173 | 2026-08-22 | CO | COP | completed | sí | COP 400,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3177 | 2026-08-23 | MX | MXN | processing | sí | MXN 2,240 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3178 | 2026-08-23 | MX | MXN | failed | no | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3182 | 2026-08-23 | CO | COP | completed | sí | COP 952,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3201 | 2026-08-24 | CO | COP | completed | sí | COP 360,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3208 | 2026-08-26 | MX | MXN | completed | sí | MXN 2,240 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3212 | 2026-08-26 | MX | MXN | completed | sí | MXN 2,240 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3217 | 2026-08-27 | MX | MXN | completed | sí | MXN 4,480 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3223 | 2026-08-30 | MX | MXN | completed | sí | MXN 6,720 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3224 | 2026-08-31 | MX | MXN | failed | no | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3250 | 2026-09-01 | CO | COP | cancelled | no | COP 370,000 | — | ppcp-card-button-gateway | store-api | igual | P0D lo importaría |
| 3453 | 2026-09-04 | MX | MXN | completed | sí | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3460 | 2026-09-07 | CO | COP | cancelled | no | COP 370,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3464 | 2026-09-07 | CO | COP | cancelled | no | COP 360,000 | — | ppcp-card-button-gateway | store-api | igual | P0D lo importaría |
| 3468 | 2026-09-07 | CO | COP | cancelled | no | COP 400,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3511 | 2026-09-08 | CO | COP | completed | sí | COP 403,000 | — | ppcp-card-button-gateway | store-api | igual | P0D lo importaría |
| 3515 | 2026-09-08 | CO | COP | cancelled | no | COP 403,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3525 | 2026-09-12 | CO | COP | completed | sí | COP 445,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3529 | 2026-09-12 | CO | COP | cancelled | no | COP 425,000 | — | epayco | store-api | igual | P0D lo importaría |
| 3565 | 2026-09-16 | MX | MXN | completed | sí | MXN 2,720 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 3593 | 2026-09-24 | CO | COP | completed | sí | COP 395,000 | — | ppcp-card-button-gateway | store-api | igual | P0D lo importaría |
| 3615 | 2026-09-28 | CO | COP | cancelled | no | COP 370,000 | — | epayco | store-api | no está | P0D lo importaría |
| 5347 | 2026-10-08 | MX | MXN | cancelled | no | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | P0D lo importaría |
| 5351 | 2026-10-08 | MX | MXN | cancelled | sí | MXN 2,800 | — | woo-mercado-pago-custom | store-api | igual | ya está en producción (sin cambio) |
