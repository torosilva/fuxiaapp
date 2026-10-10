# S-G1 · Growth War Room — entrega en STAGING (2026-10-10)

> Producción NO tocada (solo lecturas agregadas con `prod_read.sh`). Staging: `fuxia360-staging.vercel.app/growth` (pestaña **War Room**).

## 1. Qué existía y qué se construyó
**Existía:** S-G0 (Commerce Facts con pedidos pagados y atribución de WooCommerce por pedido, salud de fuentes, gasto por CSV, FX, IVA pendiente), pestaña Medición, Plan 2027. La pestaña principal de `/growth` era un aviso "sin datos suficientes".

**Se construyó** (migración `20261021000100_f360_growth_cockpit.sql`, solo lectura, sin tablas):
- `f360.classify_channel_v1()` — canal a partir de la atribución de WooCommerce (Meta pagado, Meta UTM no pagado, Instagram/Facebook orgánico, búsqueda orgánica, directo, WhatsApp, email, otro sitio, sin atribución).
- `f360.growth_market_block()` + `public.f360_growth_cockpit(desde, hasta)` (operator+): por mercado **MX (MXN) / CO (COP) / ROW (USD)**, periodo y periodo anterior de igual duración:
  ingresos pagados (venta neta de producto), pedidos pagados, ticket promedio, pares; conversión por sesión (GA4) y por clic (anuncios) **separadas**; gasto, CPC, CTR, CPM, CPA, ROAS, MER — cada KPI con `status` (OK / DATA_INCOMPLETE / NOT_CONFIGURED / STALE), `source` y nota; embudo (sesiones → producto → carrito → pedido creado → pagado); pedidos por método de pago (creados / pagados / sin pago); desgloses por canal, campaña (UTM del pedido + gasto si existe) y producto; hallazgos con evidencia y confianza; frescura de pedidos; consolidado bloqueado sin FX aprobado.
- UI: `admin-web/src/app/(app)/growth/GrowthCockpit.tsx` (pestaña **War Room**, principal), `lib/growth-cockpit.ts`; la tabla "qué falta" queda debajo.
- Backlog #60: Fuxia Academy (parking lot, sin implementar).

## 2. Lo que dice hoy (staging, 1 jun – 10 oct 2026, datos de staging4)
| | México (MXN) | Colombia (COP) |
|---|---|---|
| Ingresos pagados | $130,690 | COP 8,051,300 |
| Pedidos pagados / creados | 38 / 57 | 17 / 30 |
| **Pedidos sin pago** | **17 (30%)** | **13 (43%)** |
| Peor método | "sin método" 4/5; Mercado Pago tarjeta 11/49 | **ePayco 11/26 sin pago** |
| Canal #1 en ventas | Directo (12), Meta pagado (6) | Meta pagado (6), Meta UTM (6) |
Hallazgos de confianza ALTA: pedidos que llegan al pago y no se pagan (MX 30%, CO 43%, ROW 80%); 1 venta MX sin origen. SIN DATOS: dónde se cae el tráfico antes del pedido (falta GA4) y qué campañas gastan sin vender (falta gasto).

## 3. Métricas reales vs faltantes
- **Disponibles:** ingresos pagados, pedidos, ticket, pares, embudo pedido→pago, fallas por método de pago, canal/campaña/producto por pedido pagado.
- **Faltan:** sesiones, vistas de producto, carrito, conversión por sesión (GA4); gasto, CPC/CTR/CPM/CPA/ROAS/MER (Meta/Google); consolidado (FX); margen (COGS).

## 4. Pruebas (todas en staging, con rollback)
- `supabase/staging/test_sg1_cockpit.sql` C1–C10: permisos (anon/seller/viewer rechazados), mercados y monedas separados, cifras = Commerce Facts (pagados; cancelados/no pagados/revertidos fuera), KPIs sin insumo nunca en 0, canales suman el total (sin doble conteo), lectura idempotente, periodo vacío sin división entre cero, gasto en otra moneda = DATA_INCOMPLETE, periodo inválido, reglas de canal — **ENSAYO OK**.
- Regresión: `db_tests.mjs` 1018/0 · `preprod_staging_tests.sh` todas · `sb0_staging_tests.sh applied` todas · node f360-woo 63/0 · admin-web 15/0 · `tsc`, eslint, `next build` OK.
- Responsive: Playwright en staging, 1440 px y 390 px, sin desbordamiento horizontal. Capturas (locales, no versionadas): `admin-web/e2e-screenshots/sg1/` — desktop/mobile de Todos, México y Colombia.

## 5. Producción — recomendación
**NO-GO todavía para mostrarlo en producción**: en producción Commerce Facts tiene **1 pedido** (el corte fue el 8 oct) — sin el historial (gate **P0D**, 84 pedidos jun–oct) el War Room estaría vacío. Orden propuesto: P0D (historial) → pase de esta migración + publicar el panel. Rollback: `supabase/rollbacks/20261021000100_f360_growth_cockpit.down.sql` (3 DROP FUNCTION) y volver el panel.

## 6. Pendiente de personas
- **Mario:** aprobar P0D; accesos GA4 (service account), Meta Ads (token ads_read o CSV), confirmar si hay Google Ads; fuente de FX.
- **Carolina:** costos por modelo (para margen); revisar los pagos con ePayco que no se completan.
- **Goyo / Adrián (agencia):** acceso a la cuenta publicitaria real de Meta; revisar el checkout de Colombia (ePayco) y los pedidos "sin método".
