# Strategy & Board · Equity Earn-In Tracker · DELIVERY (STAGING ONLY)

> 2026-10-08 · rama `fuxia-360` · pedido de Mario ("Strategy & Board → Ownership: tu acuerdo completo + Equity Earn-In Tracker").
> **Producción: sin cambios.** Base: la "Propuesta al Consejo de Administración de Fuxia Ballerinas S.A. de C.V."
> (https://claude.ai/code/artifact/50e7a032-eea0-44da-95c1-dc9708c3effd).

## 1. Qué es

Una pantalla del consejo, `/estrategia/participacion`, que muestra los **términos propuestos** de la participación de Mario y cómo va cada meta.
Los términos son: 20% inicial, hasta 20% por metas de ventas con un filtro de margen bruto, tope de 40% antes de rondas, Carolina con al menos 60% y Colombia excluida.
Para cada año con meta se ve:

- meta para acciones
- meta de la dirección (plan del consejo)
- pronóstico publicado
- ventas reales
- cumplimiento
- acciones **indicativas**
- estado del filtro de margen
- meses cerrados

**No** es un contrato, un cap table ni una valuación. El spec `07 §4` sigue siendo cierto:

- no se registra dinero comprometido ni fondeado (`NOT_FUNDED`);
- no se valora la tecnología (`PENDING_LEGAL_ASSIGNMENT`);
- no se escribe `ownership_snapshots`;
- el "ganado formal" queda siempre vacío.

## 2. Gobierno (D10B, sin reglas nuevas)

- Cualquier miembro del consejo registra una propuesta (scope `CAP_TABLE`). La propuesta crea una decisión `MARIO_OWNERSHIP` mediante el RPC de decisiones existente.
- Mario queda **RECUSED**. Si intenta aprobar, el intento se rechaza y queda registrado.
- Solo Carolina la acepta. El estado resultante es `ACCEPTED_FOR_TRACKING`, que **no** equivale a firmada.
- Solo puede haber una propuesta pendiente a la vez. Una propuesta nueva, al aprobarse, sustituye a la anterior (`SUPERSEDED`), y el historial conserva todas.
- Los términos y las metas solo admiten inserciones: no se editan ni se borran. Tampoco se pueden agregar metas a una propuesta ya registrada.

## 3. De dónde salen los números

| Dato | Fuente | Si falta |
|---|---|---|
| Ventas reales | `f360.measurement_sales` (S-G0). Ventas pagadas, canales de producción (misma regla que Medición), mercados no excluidos (CO por defecto), venta neta de producto | — |
| Consolidado MXN | `f360.fx_rate_for` (solo tipos de cambio **aprobados**) | Valor `NULL` y `DATA_INCOMPLETE`; se muestra "solo MXN" con la moneda faltante. Nunca se estima |
| Meta de la dirección | `plan_years` (si el año está ligado, se lee `f360.growth_plans` en vivo) | "—" (2028–2031 no están cargados: SB3) |
| Pronóstico | último `forecast_versions` `PUBLISHED`, `revenue_net_product`, MXN | "sin pronóstico publicado" |
| Filtro de margen | `earnin_milestones.gross_margin_min` + `metric_catalog.gross_margin` | `PENDING_DEFINITION` (sin mínimo) / `DATA_INCOMPLETE` (sin COGS) |
| Acciones indicativas | 0 si las ventas están en "desde" o por debajo; el % completo si llegan a la meta; proporcional en medio. Los años futuros dan 0 sobre ventas reales y se muestra aparte el cálculo sobre el pronóstico | — |

## 4. Archivos

| Archivo | Qué |
|---|---|
| `supabase/migrations/20261017000100_f360_board_earnin_tracker.sql` | `f360_board.earnin_terms`, `earnin_milestones`, helpers, `public.f360_board_earnin_propose(uuid, jsonb)`, `public.f360_board_earnin()` |
| `supabase/rollbacks/20261017000100_f360_board_earnin_tracker.down.sql` | Rollback. **Exportar antes** si ya hay propuestas reales; las decisiones quedan |
| `supabase/staging/test_sb_earnin.sql` | Pruebas E1–E10 (una transacción, siempre ROLLBACK) |
| `admin-web/src/lib/board.ts` | Tipos + `getBoardEarnin` |
| `admin-web/src/app/(app)/estrategia/participacion/{page,actions}.tsx/ts` | Pantalla y acciones (registrar propuesta; aceptar, rechazar, posponer o retirar) |
| `admin-web/src/app/(app)/estrategia/page.tsx` | Enlace "Participación · earn-in" |

## 5. Verificación

- Ensayo (migración y pruebas dentro de `BEGIN … ROLLBACK`): **E1–E10 PASS**. Las ventas de 2026 sin Colombia coinciden con `measurement_sales` (MXN 132,688), y un renglón USD sin FX aprobado queda `DATA_INCOMPLETE`.
- Aplicada en staging con `db push` (el dry-run mostró solo esta migración). Pruebas en modo applied: E1–E10 PASS. `sb0_staging_tests.sh applied` dio **ALL PASS**: acceso, historia y flujos de vendedora.
- admin-web: `tsc --noEmit`, `eslint` y `next build` sin errores; la ruta `/estrategia/participacion` se compila.
- **Pendiente:** el recorrido en el navegador. El consejo exige MFA (`aal2`) en staging y no se enroló un factor TOTP en las cuentas demo compartidas.
- **Incidente:** después de aplicarla, staging regresó a `20261015000200`. Una sesión par estaba ensayando el rollback del pase previo a producción, y eso quitó también esta migración. Hay que volver a aplicarla cuando esa sesión termine.

## 6. Contradicciones con los specs (regla 14)

1. Spec `07 §1` dice que no se asume ningún porcentaje. Esta pantalla **sí** guarda porcentajes, pero como *términos propuestos*, ligados a una decisión que aprueba Carolina y etiquetados `PROPOSED` / `ACCEPTED_FOR_TRACKING` / `NOT_SIGNED`. El cap table formal sigue vacío.
2. Spec `07 §4`: "No calcula % de nadie a partir de montos". El tracker calcula un % **indicativo** a partir de ventas contra metas propuestas, no a partir de montos invertidos. Lo formal nunca se calcula.
3. Spec `07 §2.2` (`capital_commitments` con movimientos) no está construido. El monto de efectivo aquí es un *término* de la propuesta, no un movimiento de dinero. Cuando exista `capital_commitments`, el estado `NOT_FUNDED` debe leerse de ahí. No hay dos fuentes de verdad.

## 7. Paso a producción (requiere OK escrito de Mario y de Carolina; NO ejecutado)

Requiere SB0 (`20261015000100–0300`) y S-G0 (`20261014000600`) en producción. Después:

1. Archivo de pase con esta migración y su fila en `schema_migrations`.
2. Desplegar admin-web.
3. Que Carolina registre o acepte la propuesta desde la pantalla. No se precarga nada.
