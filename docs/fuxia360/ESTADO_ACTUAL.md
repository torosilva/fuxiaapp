# Fuxia 360 — Estado actual (fuente única de "¿en qué quedó?")

> **Regla:** antes de contestar sobre cualquier módulo, lee esta página. Si algo pasa a staging o a producción, actualiza su línea **en el mismo commit**.
> **Verificado el 2026-10-27.** Se comparó lo siguiente:
> - las migraciones del repo contra `schema_migrations` de producción (`tgzg…`) y de staging (`faltx…`);
> - las Edge Functions de los dos proyectos;
> - el commit del admin de producción;
> - el registro `~/fuxia360-respaldos/prod-sql.log`.
>
> Cómo volver a verificar: §9.

## 1. Resumen
- **Base de datos:** el repo tiene 144 migraciones. Producción tiene las **144** (27 oct: tipo de cambio, Growth P0, I5 y earn-in) y staging las 144.
- **Admin de producción:** el commit `5520478` (2026-10-27, Growth P0 + I5) está en `~/fuxia360-respaldos/prod-admin-deployed.sha`. Incluye todo lo de `fuxia-360` hasta esa fecha.
  - Se publica con `scripts/f360/deploy_prod_admin.sh` y un `F360_DEPLOY_SHA` fijo.
  - Ojo: `admin-web/.vercel` apunta a **STAGING**.
- **Escrituras a producción:** solo por `scripts/f360/prod_sql.sh` (archivo commiteado, primero dry-run, queda registrado). Para leer: `scripts/f360/prod_read.sh`.
- **WordPress de producción:** se instala con `scripts/f360/deploy_prod_wp.sh` (mu-plugins de `tools/storefront/mu-plugins/produccion/`). El SSH a producción lo corre Mario.
- **Staging:** ⚠ la copia nocturna FALLA desde al menos el 26 oct (pg_dump del respaldo de staging: "server closed the connection"); staging no se está refrescando. Cada noche a las 3:30 se copia producción anonimizada → staging (Supabase + Woo staging4). Detalle en `docs/fuxia360/ops/STAGING_REFRESH.md`. El código va por delante.

## 2. Módulos

Estados:
- **PROD**: en producción.
- **STG**: solo en staging.
- **PROP**: propuesta o diseño; no está aplicado en ningún lado.
- **LISTO**: preparado para producción, pero no instalado.

| Módulo | Estado | Desde | Qué falta | Documento |
|---|---|---|---|---|
| **Growth · War Room** (ventas pagadas por mercado, AOV, embudo, hallazgos) | PROD | 2026-10-11 (`9d8ec4f`) | Las ventas en COP no se convierten porque falta el tipo de cambio en prod (ver I5) | `growth/S-G1_DELIVERY.md` |
| **Growth · Conciliación de ventas** | PROD | 2026-10-11 | — | `growth/SALES_RECONCILIATION_DELIVERY.md` |
| **Growth · gasto de Meta por API** (cron diario 02:30 CDMX, `f360-meta-spend`) | PROD | 2026-10-11 | Corre bien; la última carga fue el 2026-10-27. El token se queda así (Mario). | `growth/META_SPEND_API_DELIVERY.md` |
| **Growth · Campañas** (gasto vs. venta pagada por `utm_id`, ventas por origen) | PROD | 2026-10-14 (`48c01f4`) | COP sin convertir (I5) | migración `20261031000100` |
| **Growth · "Meta dice"** (compras/valor/carritos del pixel junto a lo real) | PROD | 2026-10-24 (`16567a7`) | — (relleno 11–13 oct hecho; el importador diario ya lo trae) | migración `20261102000100` |
| **Historial de pedidos Woo (P0D)** → `f360.commerce_orders` | PROD | 2026-10-11 (83 importados) | Entran solos por el webhook (103 al 2026-10-27). No hay ventas de mayo y casi ninguna de junio | `growth/P0D_PREFLIGHT.md` |
| **GA4 compra desde el servidor** (mu-plugin) | PROD | 2026-10-13 (`cf32dac`) | Verificado 2026-10-27: 8 de 8 ventas pagadas (16–23 oct) están en GA4 con su transaction_id | `growth/GA4_COMPRA_SERVIDOR.md` |
| **Growth P0 · Instagram orgánico + registro de experimentos + Clarity diario** (pestañas Instagram y Experimentos; fuentes `instagram`/`clarity` en Medición; `f360-instagram`, `f360-clarity`) | **PROD** | 2026-10-27 (pases `20261027_growth_p0` + `_clarity`, admin `32cc6d0`, `NEXT_PUBLIC_F360_GROWTH_P0=on`) | Instagram CON datos desde el 28 oct: token de fuxia360-lectura con `instagram_basic` + `instagram_manage_insights` (`INSTAGRAM_TOKEN` en prod, `~/.fuxia-instagram.token`); relleno 30 jun–28 oct (121 días, 74 publicaciones, pase `20261028_instagram_relleno_local`); el `backfill` de 120 días no cabe en una ejecución de la función (se corta), por eso se rellenó en local. Clarity: la API solo da 1–3 días; cron diario `f360-clarity` 06:10 UTC en prod; historial desde el 27 oct (importado de la captura local, que se desinstaló). Reversión: §8 del doc | `growth/P0_INSTAGRAM_EXPERIMENTOS_CLARITY.md` |
| **Análisis web jun–oct** (ventas reales vs GA4, Clarity, ePayco) | Doc | 2026-10-13/19 | — | `growth/ANALISIS_WEB_2026-06_A_2026-10.md` |
| **ePayco Standard** (Colombia) + texto de la titular | PROD | 2026-10-19 (`b5f63c6`, `6ebecd1`) | Medir CO pagados/creados contra la base de 4/9. Nombre y logo de Fuxia en el panel de ePayco (Mario/Carolina). Se revierte con `--revertir` | `growth/ANALISIS_WEB…` §9 |
| **Tipo de cambio oficial diario** (Banxico FIX; COP = FIX ÷ TRM; `f360-fx-rates`) | **PROD** | 2026-10-27 (pases `20261027_fx_diario/relleno/propuestas`) | Cron diario 14:00 UTC; 126 días por moneda desde 2026-05-04; may–sep **propuestos, nada aprobado**. Falta: alcance `fx_rate` para Mario + pantalla para aprobar (está en /direccion, oculta en prod hasta I5) | `intelligence/I5_PLAN_PRODUCCION.md` |
| **Centro de Inteligencia** (Dirección/CEO cockpit, presupuesto, cierre contable, analista IA `f360-analyst`) | **PROD** | 2026-10-27 (pases `20261027_i5_2…7`, `f360-analyst`, `NEXT_PUBLIC_F360_INTEL=on`, admin `5520478`) | Falta: (1) alcances de aprobación `fx_rate`/`budget` = Mario y `close` = Mario + Carolina, que esperan el OK explícito de Mario; (2) la llave `ANTHROPIC_API_KEY` de producción, que Mario pega en Supabase (§5 del plan; sin ella el analista responde 503); (3) la meta de $300,000 la registra Mario en `/direccion/presupuesto`; (4) aprobar las tasas FX may–sep | `intelligence/I5_PLAN_PRODUCCION.md` |
| **Strategy & Board SB0** (acceso, MFA, conflicto de interés) | PROD | — | — | `strategy-board/SB0_DELIVERY.md` |
| **Board · Earn-in tracker** | **PROD** | 2026-10-27 (pase `20261027_earnin`) | — | `strategy-board/SB_EARNIN_DELIVERY.md` |
| **Seguridad P0-6** (`whatsapp-otp` nueva) | PROD | 2026-10-13 (v77) | — | `security/P0-6_REMEDIACION.md` |
| **Seguridad D12** (fase A, interruptor NIP por tienda, cierre de la entrada vieja) | PROD | 2026-10-13 | — | `security/D12_CIERRE_Y_P0-6_PRODUCCION.md` |
| **Fuxia Academy A1** | PROD (base y permisos) | 2026-10-13 (`8d79444`) | Aprobación de contenido por Carolina, licencia de la música, A2 sin empezar | `academy/a1/` |
| **Ventas en tienda, apartados, ventas remotas, descuentos de tienda** | PROD | oct | — | `ops/DESCUENTOS_TIENDA.md`, `omnichannel/APARTADO_GOLD.md` |
| **CRM C1** (ficha de clienta, privacidad vendedora) | PROD | — | Pantallas C2 | `crm/C1_DELIVERY.md`, `crm/CRM_V1_PLAN.md` |
| **Push** (`f360-push`) | PROD | 2026-10-11 | — | — |
| **Bandeja de clientas · seguimiento** (en el menú con contador; "lleva N días" en rojo; link de pago se resuelve solo al pagarse; correos de aviso `f360-email` → info@) | LISTO (staging 7/7) | 2026-10-30 | Pase `supabase/pase/20261030_bandeja_seguimiento.sql`, `deploy_prod_function.sh f360-email`, `prod_email_vault.sh`, admin. Hilo (Backbone): revisar todas sus conversaciones (falta `DATABASE_URL` de Railway) | migración `20261105000300` |
| **Categoría Kids** ligada al term 96 | PROD | 2026-10-24 (`08e4811`) | — | — |
| **Kids · tablero semanal** | PROD (base) | 2026-10-24 (`53f1e05`) | — | migración `20261103000100` |
| **Kids · juegos en la tienda** (`f360-kids-juego.php`) | PROD | 2026-10-27 (`deploy_prod_wp.sh`, respaldo prod-mu/20261027-063707) | URL real: `/mx/categoria-producto/kids/` y `/co/…` (no `product-category`). QA `kids-juego.mjs --base https://fuxiaballerinas.com --no-board` OK | — |
| **Videos en la ficha** (2 por color) | PROD | 2026-10-24 (`ef1209d`); mu-plugin 2026-10-27 | 0 videos cargados | — |
| **QA "hasta la pasarela"** (`tools/qa/hasta-la-pasarela.mjs`, navegador de Instagram, llega a ePayco/Mercado Pago sin pagar; `--pedir` crea pedido de prueba → cancelarlo) | Manual | 2026-10-27 | Programarlo cada hora con alerta (plan del doc de ventas) | — |
| **QA "tienda como clienta"** cada hora | Solo en `origin/main` | 2026-10-08 | No está mergeado en `fuxia-360` | `tools/qa/tienda-como-clienta.mjs` |

## 3. Edge Functions (2026-10-27)
- **Solo en staging:** `f360-email`. (`f360-fx-rates`, `f360-analyst`, `f360-instagram` y `f360-clarity` están en prod desde el 27 oct.)
- **Solo en prod:** `f360-meta-spend` y `f360-whatsapp`, más las viejas `backfill-orders`, `calculate-*`, `escalate-to-staff`, `loyalty-credit`, `notify-approval-pending`, `virtual-tryon*` y `woocommerce-proxy`.
- **En prod pero no en el repo:** `send-push` y `birthday-push`.
- **Fuente:** `fuxia-native/supabase/functions/` (no existe `supabase/functions/` en la raíz).

## 4. Decisiones de Mario que siguen vigentes
- La memoria del asistente (`~/.claude/projects/…/memory/`) guarda las reglas operativas: no preguntar lo básico, push después de cada commit, OTA, no inventar reglas de negocio…
- **Growth:** el 2026-10-05 se congeló, pero después se reabrió por partes (War Room, Meta, Campañas, GA4, ePayco). Hoy está activo.

## 5. Pendientes abiertos (orden sugerido)
1. Plan de automatización de Growth (alerta de cero ventas, QA hasta la pasarela cada hora, embudo GA4 y Clarity diarios con historial, precio/cupón por venta, resumen 8:00). Documento: "Fuxia 360 · Ventas en línea y módulo Growth" (claude.ai/artifact/AFScxkzLCdNExEJyGBisGV), 2026-10-27.
2. Aprobación de tipos de cambio por Mario (alcance `fx_rate` + pantalla).
3. Medir ePayco Standard en Colombia contra la base de 4/9.
4. Arreglar la copia nocturna prod → staging (falla el respaldo de staging).

**Julio, reconciliado:** de las 20 ventas pagadas de México del 23 jul al 2 ago, **9** tuvieron último clic en Instagram sin anuncio, 1 en Facebook, 3 en Google, 3 directo y 4 en anuncios de Meta. "16 de 20" = todo lo que no fue anuncio (no "Instagram").

**Hechos verificados 2026-10-27 (no repetir hipótesis):** ePayco SÍ está activo y la compra de Colombia llega a ePayco (el campo REST `enabled=false` es falso). México (probado como clienta en Instagram/Safari/computadora, `tools/qa/pagos-mexico.mjs`): la ÚNICA forma de pago visible es tarjeta Visa/MC/Amex de Mercado Pago con 3 y 6 meses sin intereses (9–24 con intereses); PayPal está activo en Woo pero su botón sale vacío (0×0); OXXO, saldo MP, Mercado Crédito y transferencia están desactivados. México vendió 27 de 32 pares de jul–ago a ≤ $2,380 (precio de julio o cupón familiafuxia 20 %); hoy 2,800–3,000.

## 9. Cómo volver a verificar esta página
- **Migraciones:** `scripts/f360/prod_read.sh <<<"SELECT version FROM supabase_migrations.schema_migrations ORDER BY 1"` y comparar con `ls supabase/migrations`.
- **Funciones:** `supabase functions list --project-ref tgzgiwfzddsghnxgkcqd` (prod) y `faltxpkaicwpnlqaxrdu` (staging).
- **Admin de prod:** `cat ~/fuxia360-respaldos/prod-admin-deployed.sha`.
- **Pases aplicados:** `~/fuxia360-respaldos/prod-sql.log`.
