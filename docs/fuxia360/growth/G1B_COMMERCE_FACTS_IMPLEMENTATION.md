# G1-B — Commerce Facts: implementación (STAGING)

**Fecha:** 2026-10-04. **Rama:** `fuxia-360`.

- **Diseño aprobado:** `G1_COMMERCE_FACTS_DESIGN.md`, con las decisiones G1-Q1…Q6.
- **Solo staging:** proyecto Supabase `faltxpkaicwpnlqaxrdu` y tienda `staging4`.
- **No se tocaron:** producción, GTM, Meta / CAPI, Clarity, Campaign 360, FX ni el War Room.

---

## 1. Esquema final

| Objeto | Tipo | Qué es |
|---|---|---|
| `f360.commerce_woo_orders` | tabla | Cabecera económica de cada pedido Woo (última versión). Llave `(target_id, woo_order_id)`. Guarda estado, `created_via`, `business_origin` (inmutable), fechas, `ever_paid` / `first_paid_at` (pegajosos), moneda original, todos los componentes de dinero, la **foto de lo pagado** (`paid_items_total`, `paid_order_total`), método y categoría de pago, `woo_customer_id`, país de facturación (código), mercado y su fuente |
| `f360.commerce_woo_order_lines` | tabla | Líneas de la última versión: cantidad, `subtotal`, `total` e impuestos. `list_price_hint` es dato **secundario** (precio WDR, `list_price_source`) |
| `f360.commerce_woo_refunds` | tabla | Un reembolso por `refund_id`, en positivo, con fecha, moneda, `detail_status` (detailed / header_only), producto / envío / impuesto, líneas, `provenance` y `removed_at` |
| `f360.commerce_woo_attribution` | tabla | **COMMERCE ATTRIBUTION V1 = Woo first-party order attribution.** `provenance = first_party_observed`, `model = woo_order_attribution_last_click_session`. UTMs como valores **opacos**. Del navegador se guarda solo la clase |
| `f360.commerce_woo_status_log` | tabla (solo agregar) | Transiciones de estado: never paid / paid / paid → cancelled / paid → refunded |
| `f360.commerce_sync_state`, `f360.commerce_sync_runs` | tablas | Heartbeat del poll y bitácora de corridas (poll y backfill) |
| `f360.commerce_orders` | vista | **Una fila por venta**, online (Woo) + tienda (`offline_sales` con `created_by_rpc`, **sin copia**). `status_class`, `payment_state`, mercado, moneda original, vínculo de clienta, componentes de dinero, `net_product`, `net_order_total`, `data_quality` + motivos y `provenance` |
| `f360.commerce_order_lines` | vista | Líneas de ambas fuentes. La variante se resuelve **en vivo** (link publicado → link retirado → homologación legacy → sin resolver) |
| `f360.commerce_source_health` | vista | Frescura por fuente: VERIFIED / STALE / UNVERIFIED |
| `f360.commerce_woo_refund_totals` | vista | Suma de reembolsos vigentes por pedido |
| `public.f360_capture_order_economics(target, payload, via)` | RPC (solo service role) | Única puerta de escritura: webhook, poll, backfill y pruebas |
| `public.f360_commerce_run_begin` / `_run_end` | RPC (solo service role) | Abren y cierran una corrida y mueven el cursor |
| `public.f360_commerce_summary(from, to)` | RPC (owner / operator) | Métricas por moneda × mercado × origen × canal, solo pedidos `countable`. Lista aparte lo que no cuenta |
| `public.f360_commerce_facts(limit)` | RPC (owner / operator) | Lista técnica sin PII |
| `public.f360_growth_plan` | RPC redefinida | `require_role('viewer')` → `require_role('operator')` (D-G1-05) |
| cron `f360-commerce-poll` | `*/15 * * * *` | `f360.commerce_poll_tick()` → `f360-woo-sync {action: commerce_poll}` (URL y Bearer desde Vault) |

**Código:**

| Archivo | Cambio |
|---|---|
| `fuxia-native/supabase/functions/_shared/f360-woo/commerce.ts` (nuevo) | `orderEconomics` (lista blanca), `orderAttribution`, `browserClass`, `refundDetail`, `commerceWoo` (solo GET), `commercePoll` |
| `fuxia-native/supabase/functions/f360-woo-orders/handler.ts` + `index.ts` | Después de la ingesta de inventario (sin cambios): lee el detalle de reembolsos si hay y captura la economía. Si la captura falla, responde 5xx y Woo reintenta |
| `fuxia-native/supabase/functions/f360-woo-sync/handler.ts` | Acción `commerce_poll` |
| `scripts/f360/g1_commerce_backfill.mjs` (nuevo) | Backfill de staging4 (GET de Woo → captura con `via = backfill`) |
| `admin-web`: `Shell.tsx`, `mas/page.tsx`, `growth/page.tsx`, `growth/CommerceFacts.tsx` (nuevo), `clientes/page.tsx`, `lib/f360.ts` | Growth y Clientes solo para owner / operator, con redirección en el servidor. Pestaña técnica "Commerce Facts" de solo lectura |

---

## 2. Por qué este modelo (con evidencia del esquema real)

1. **La tienda no se copia.**
   - `public.offline_sales` + `offline_sale_items` ya son el registro autoritativo: append-only, con idempotencia y precio del maestro (`20261002000300…`, C3).
   - Convertirlas en una tabla analítica rompería su función operativa. La vista `commerce_orders` las lee tal cual.
2. **La economía en línea va en tablas propias, no en `f360.woo_orders`.** Desviación consciente de G1-A §O:
   - `woo_orders` es el **estado de procesamiento de inventario** de `f360_ingest_woo_order`, que lo usa para decidir `duplicate` / `stale`.
   - Si un backfill escribiera ahí la versión actual de un pedido, el webhook posterior de esa misma versión saldría como `duplicate` **y no descontaría el par**.
   - Separar evita ese riesgo y deja intacta la ingesta de inventario: **no se redefinió `f360_ingest_woo_order`**.
3. **Una venta = una fila de origen:**
   - en línea, `commerce_woo_orders`;
   - en tienda, `offline_sales`.
   
   `woo_orders` y `woo_order_lines` siguen siendo solo inventario: no guardan dinero, así que no compiten como verdad comercial. `public.transactions` (loyalty) se usa solo para enlazar clientas, nunca como fuente de dinero.
4. **`f360.sales_facts` no se tocó.** La pantalla Ventas suma `total` sin moneda. Meter ahí pedidos en COP o USD mezclaría monedas (D-G1-03). La venta en línea se ve en `commerce_orders` / `f360_commerce_summary`, siempre agrupada por moneda.

---

## 3. Migraciones (aplicadas en staging con `supabase db push --db-url $STAGING_DB_URL`, nunca `--linked`; dry-run previo)

| Versión | Contenido | Rollback |
|---|---|---|
| `20261008000100_f360_g1_commerce_facts.sql` | Todo lo de §1 | `supabase/rollbacks/20261008000100_f360_g1_commerce_facts.down.sql`. **Ensayado** dentro de una transacción deshecha: 0 tablas / funciones / cron después del *down*, `f360_growth_plan` vuelve a `viewer`, inventario intacto; tras el `ROLLBACK`, todo restaurado |
| `20261008000200_f360_g1_paid_value_unknown.sql` | Corrección hallada con el backfill: un pedido pagado y visto **ya cancelado** (sin foto de lo pagado) queda PARTIAL `paid_value_unknown` y no VERIFIED. Solo cambia la expresión de calidad | `…000200…down.sql` (restaura la vista de 000100) |

Funciones Edge desplegadas en staging:
- `f360-woo-orders` v7 (`--no-verify-jwt`);
- `f360-woo-sync` v12 (`--no-verify-jwt`).

---

## 4. Backfill de los 82 pedidos de staging4

`scripts/s00a/run.sh ../f360/g1_commerce_backfill.mjs`, dos veces:

| Corrida | fetched | inserted | updated | unchanged | errores | hechos antes → después | inventario |
|---|---|---|---|---|---|---|---|
| 1 (run 5) | 82 | **82** | 0 | 0 | 0 | 0 → 82 | intacto (`inventory_events`, `woo_orders` y `woo_order_lines` sin cambios) |
| 2 (run 6) | 82 | 0 | 0 | **82** | 0 | 82 → 82 | intacto |

---

## 5. Conteos (sin PII)

**Por estado y moneda:**

| Woo status | Moneda | status_class | payment_state | Pedidos |
|---|---|---|---|---|
| completed | MXN | countable | paid | 34 |
| completed | COP | countable | paid | 17 |
| completed | USD | countable | paid | 1 |
| processing | MXN | countable | paid | 2 |
| cancelled | MXN | cancelled | never_paid | 6 |
| cancelled | COP | cancelled | never_paid | 13 |
| cancelled | USD | cancelled | never_paid | 4 |
| cancelled | MXN | **reversed** | **paid_cancelled** | 1 (DQ-02: total editado a 0; queda PARTIAL `paid_value_unknown`) |
| failed | MXN | not_paid | never_paid | 4 |

**Ventas contables (moneda original, nunca sumadas entre monedas):**

| Moneda | Pedidos | Pares | Bruto (subtotal) | Descuentos | **Ventas de producto** | Envío | **Total de pedidos** | **AOV producto** | **Promedio por pedido** |
|---|---|---|---|---|---|---|---|---|---|
| MXN | 36 | 51 | 131,460 | 7,770 | **123,690** | 400 | **124,090** | **3,435.83** | **3,446.94** |
| COP | 17 | 22 | 8,767,000 | 715,700 | **8,051,300** | 75,000 | **8,126,300** | **473,605.88** | **478,017.65** |
| USD | 1 | 3 | 450 | 0 | **450** | 15 | **465** | **450.00** | **465.00** |

**Otros conteos:**
- **Origen:** storefront 81 (`store-api`) · api_integration 1 (`rest-api`, el pedido de prueba #3654, incluido en MXN).
- **Mercado:** MX 47 · CO 30 · ROW 5. **0 conflictos** entre la moneda y la ruta de entrada.
- **Clienta:** guest 55 · registered 27. Socias de loyalty enlazadas: 0, porque `transactions` de staging es sintético.
- **Resolución de producto (108 líneas):** 55 por link retirado (modelos unidos) · 48 por homologación legacy · 5 sin resolver.
- **Rebaja implícita WDR:** 30 líneas, MXN 13,020, guardada **solo** como `list_price_hint`. El revenue **no** se reconstruye desde ahí.

**Estas cifras son ACTUAL de una muestra de staging (clon, 2026-06 → 2026-09), no un reporte de negocio.**

---

## 6. Pruebas

| Suite | Resultado |
|---|---|
| `supabase/staging/f360_g1_commerce_tests.sql` (nueva) | **47 / 47 PASS** |
| Suite completa `scripts/f360/db_tests.mjs` (27 archivos) | **750 / 750 PASS** (703 existentes + 47 nuevas), corrida después de la migración 000200 |
| Node `_shared/f360-woo/test/*` (sync, content, publisher y commerce, nueva) | **41 / 41 PASS** (8 nuevas de commerce) |
| admin-web `tsc --noEmit` + `eslint` (archivos tocados) | OK |
| admin-web `growth-model.test.ts` | 5 / 5 |

**Casos pedidos, todos con fixture sintético** (ids `99100…`, fechas 2099, en una transacción que se deshace):
- **Estados:** processing pagado, completed, pending, on-hold, failed, cancelado sin pagar, pagado → cancelado (con y sin foto de lo pagado).
- **Reembolsos:** parcial, total, repetido (idempotente), solo cabecera → PARTIAL, detalle → VERIFIED sin degradarse, reembolso eliminado en Woo.
- **Dinero:** cupón, rebaja implícita WDR, envío, comisiones, totales que no cuadran → UNVERIFIED.
- **Moneda:** MXN, COP, USD, y conflicto entre moneda y ruta.
- **Atribución:** sin atribución, completa, inmutable.
- **Origen:** pedido por API, manual, desconocido; origen inmutable.
- **Idempotencia:** webhook duplicado, webhook fuera de orden, backfill dos veces, cambio de estado sobre el mismo hecho.
- **Separación:** la captura nunca toca inventario; la venta de tienda aparece sin copiarse.
- **Resumen:** separado por moneda; AOV de producto ≠ promedio por pedido; solo cuentan los `countable`.
- **Frescura:** nunca sincronizado → UNVERIFIED; poll con 0 pedidos → VERIFIED; polls fallidos → STALE.
- **Permisos:** ver §11.

**No ejecutado:**
1. **Smoke de Playwright = TEST ENVIRONMENT BLOCKER. NO es una prueba aprobada.**
   - Se agregaron `/growth?vista=plan` y `/growth?vista=commerce` a `e2e/smoke-readonly.spec.ts`, pero no se pudo ejecutar.
   - El servidor local de admin-web responde 500 en `/login` porque `next/font/google` no resuelve la fuente en este entorno, incluso fuera del sandbox.
   - No pertenece a G1 y no se modificó la aplicación para resolverlo.
   - Pendiente: correrlo en el entorno de Mario o contra Vercel staging.
2. **Reembolsos reales en staging4:** cancelado por decisión de negocio (§8), no por falta de tiempo.

---

## 7. Idempotencia

| Situación | Comportamiento | Prueba |
|---|---|---|
| Mismo pedido y misma versión | `unchanged` (hash de la economía), una fila, una línea | ✓ |
| Versión más vieja después de una nueva | `stale`: no sobrescribe | ✓ |
| Cambio de estado (processing → completed → cancelled) | Actualiza **el mismo** hecho y agrega una entrada al log de estados | ✓ |
| Mismo reembolso dos veces | Una fila por `refund_id` | ✓ |
| Backfill dos veces | 82 → 82, la segunda vez todo `unchanged` | ✓ (real) |
| Poll programado (cron `*/15`) | Run 9, 18:00 UTC: 1 pedido leído en la ventana de traslape, `unchanged`, ok → fuente VERIFIED | ✓ (real) |
| Webhook + poll + backfill del mismo pedido | Misma función y misma llave: un solo hecho | ✓ (por diseño + pruebas de `via`) |
| Falla de captura en el webhook | 5xx → Woo reintenta. La ingesta de inventario contesta `duplicate` y la captura se repite | ✓ (Node) |

---

## 8. Reembolsos: SOPORTE TÉCNICO / EXCEPCIÓN, **NO** es flujo de negocio de Fuxia

**Decisión (Mario, cierre de G1-B, 2026-10-04): Fuxia no opera con devoluciones de dinero. Opera con CAMBIOS.**
- Ya estaba en la bitácora (decisión #7 de Carolina): "no hay devoluciones de dinero; sí se puede cambiar". G1-A/G1-B debieron aplicarla desde el inicio.
- El flujo real es **VENTA → (opcional) CAMBIO**, no VENTA → REEMBOLSO.

**Qué queda y con qué alcance:**
- **Se conservan como representación defensiva** de un evento que Woo técnicamente puede enviar:
  - `f360.commerce_woo_refunds`;
  - la vista `commerce_woo_refund_totals`;
  - los campos `refund_total`, `refund_product`, `net_product` y `net_order_total` de `commerce_orders`;
  - los `payment_state` `paid_refunded_*`.
  
  Clasificación: **TECHNICAL / EXCEPTION SUPPORT · NOT FUXIA BUSINESS FLOW**.
- **Fuera del alcance funcional:**
  - **no** se crean reembolsos de prueba en staging4 (cancelado el plan anterior de esta sección);
  - **no** hay pruebas de reembolso real, parcial ni total contra Woo;
  - **no** hay UI de reembolsos: se quitó la columna "Reembolsos" de la vista técnica, y esos estados se rotulan "excepción técnica";
  - **no** se desarrolla más lógica.
- Las pruebas SQL de reembolso que ya existen (fixtures sintéticos en una transacción que se deshace) se conservan **solo** como garantía de que un evento técnico no rompe ni duplica nada. **No** validan un flujo de negocio.
- **Ninguna métrica de negocio de Fuxia asume reembolsos.** En `f360_commerce_summary`, `refunds` y `net_product_sales` son campos técnicos: hoy valen 0 y cualquier valor ≠ 0 es una **excepción a revisar**, no "revenue perdido".
- Lo que nunca se verificó con datos de Woo queda **UNVERIFIED** y así se queda:
  - el signo de `refunds[].total`;
  - si cambia `order.total`;
  - qué webhook dispara un reembolso;
  - `_refunded_item_id`.

**Pagado → cancelado (1 caso en staging4) = EXCEPCIÓN DE NEGOCIO / PARTIAL:**
- `status_class = reversed`, `payment_state = paid_cancelled`, `data_quality = PARTIAL` (`paid_value_unknown`).
- **No** se infiere devolución de dinero desde el estado de Woo.
- **No** se trata como revenue perdido.
- Se queda así hasta saber qué ocurrió realmente.

### 8.1 Track futuro (NO implementado): COMMERCE EXCHANGES / CAMBIOS

El modelo de cambios deberá contemplar:
- la venta original, que **no desaparece**;
- la variante que regresa y la variante que sale;
- la ubicación donde ocurre el cambio;
- los movimientos de inventario (entrada de la que regresa, salida de la nueva);
- la diferencia económica, si existe;
- clienta, loyalty, vendedora, motivo, timestamps y auditoría.

**Decisión de negocio pendiente (no se decide aquí):** qué ocurre cuando el producto nuevo vale **más** o **menos** que el original. También hay que alinearlo con la política de cambios (bitácora #7: pares con descuento sin cambio; envío "mitad y mitad") y con DW4.

## 9. Cobertura de atribución (81 filas = los 81 pedidos del checkout)

| Campo | Filas | Cobertura |
|---|---|---|
| source_type, utm_source, session_entry_path, session_start_at, session_pages, session_count, device_type, browser_class, os_class | 81 | 100% |
| referrer_host | 65 | 80% |
| utm_medium | 61 | 75% |
| utm_content | 47 | 58% |
| utm_campaign, utm_term, utm_id | 23 | 28% (solo `utm` + `paid`) |

- **Tipos:** utm / paid 23 · typein 20 · utm / social 18 · organic 14 · referral 6.
- **Navegador:**
  - Instagram IAB 35 (iOS 29, Android 6);
  - Safari 24 (iOS 20, macOS 4);
  - Chrome 16 (Android 7, Windows 5, macOS 3, iOS 1);
  - Facebook IAB 5;
  - Firefox 1.
- El pedido por API (#3654) no tiene atribución (correcto: `unknown`).
- **No se guarda** ninguna meta de Meta.

---

## 10. Calidad del dato

| Estado | Cuándo (calculado en la vista; sin columnas de estado guardadas) |
|---|---|
| **VERIFIED** | El total cuadra (`order_total = items_total + cart_tax + shipping + shipping_tax + fees + fees_tax`), el descuento cuadra (`subtotal − total = discount_total`), no hay reembolsos sin detalle, no hay conflicto de mercado y el origen es conocido |
| **PARTIAL** | `refund_without_line_detail` · `market_conflict_currency_vs_path` · `origin_unknown` · `paid_value_unknown` |
| **UNVERIFIED** | `total_does_not_reconcile` · `discount_does_not_reconcile` (tienda: `total_does_not_match_lines`) |
| **STALE** | De la **fuente**, no del pedido: `commerce_source_health` = STALE si no hay un poll exitoso en 60 min (el poll corre cada 15). Recibir 0 pedidos **no** la vuelve STALE (probado) |

- **Staging hoy:** 81 VERIFIED + 1 PARTIAL (`paid_value_unknown`). Fuente `woo_staging4` = VERIFIED.
- **Tienda:** VERIFIED con nota `currency_implied_mxn`, porque la venta de tienda no guarda moneda.
- **Mecanismos reutilizados, sin duplicar:** el vocabulario de G1-A §M. `data-audit.ts`, `reported_figures` y CRO-5a no se tocaron; el mapeo queda documentado para Growth.
- **ACTUAL / TARGET / FORECAST / SCENARIO:**
  - `f360_commerce_summary` devuelve `kind = 'ACTUAL'`;
  - el Plan 2027 (TARGET / SCENARIO) **no se conectó** y vive en sus propias tablas.
- **Meta:** `meta_purchase_signal = UNVERIFIED_CONFLICTED (DQ-01)` va fijo en el resumen. No se usa para pedidos, revenue, AOV, CPA ni ROAS.

---

## 11. Permisos

| Quién | Commerce summary / facts | Growth Plan | Tablas / vistas directas | Captura |
|---|---|---|---|---|
| owner | ✓ | ✓ (edita) | ✗ | ✗ |
| operator | ✓ | ✓ (lee) | ✗ | ✗ |
| seller | ✗ | ✗ (**antes sí**) | ✗ | ✗ |
| viewer | ✗ | ✗ (**antes sí**) | ✗ | ✗ |
| anon | ✗ | ✗ | ✗ | ✗ |
| service role | — | — | ✓ | ✓ |

- **admin-web:** Growth y Clientes salen del menú para seller y viewer, y las páginas redirigen en el servidor.
- **Fuera de G1:** `fuxia-native/app/admin/_layout.tsx` sigue sin control de rol (ya reportado en G0).

---

## 12. Regresiones e incidentes

- **Inventario:**
  - `f360_ingest_woo_order`, `woo_orders`, `woo_order_lines`, `minimizeOrder` y `sales_facts` **no cambiaron**;
  - 703 pruebas previas pasan;
  - prueba explícita de que la captura no escribe inventario.
- **INCIDENTE (staging, corregido en 2 minutos):**
  - **Causa:** al desplegar `f360-woo-sync` sin `--no-verify-jwt`, la función quedó con `verify_jwt = true`. El cron de stock (Bearer `F360_SYNC_SECRET`, que no es un JWT) recibió **401 a las 17:47 y 17:48 UTC**.
  - **Corrección:** se redesplegó con `--no-verify-jwt` (v12). Desde las 17:49 responde 200.
  - **Impacto:** ninguno. La cola estaba vacía (`claimed 0`) y es persistente.
  - **Lección:** `f360-woo-sync` **siempre** se despliega con `--no-verify-jwt`.
  - **Corregido en el cierre:**
    - runbook `admin/P2_3B_RUNBOOK.md` §3 con el invariante, la verificación, el smoke, el rollback y la evidencia;
    - wrapper único `scripts/f360/deploy_woo_functions.sh`;
    - guard `scripts/f360/check_woo_functions.mjs`: hoy da OK; con `--at=2026-10-04T17:48:30Z` reproduce el FAIL 401 y con `--at=2026-10-04T17:51:30Z` da OK.
- `scripts/f360/publisher_local.ts` usa `handleOrders`. Contra la base local necesitará esta migración aplicada (solo afecta el laboratorio local).

---

## 13. Siguiente paso

G1 se cierra aquí. Por decisión de Mario **no** se adelanta Campaign 360 (G3). El orden estratégico sigue con **G2 · Measurement**. Lo que se puede preparar sin GTM está en el reporte de cierre de la sesión.

**Producción:** nada de esto está en producción. Llevarlo requiere F360 en producción, A2 y su propia aprobación.

## 14. Cierre de G1-B (correcciones del 2026-10-04)

| Corrección | Estado |
|---|---|
| Reembolsos = soporte técnico de excepción, no flujo de negocio; sin reembolsos de prueba; sin UI | ✓ §8 y vista técnica sin columna de reembolsos |
| Cambios = flujo futuro de Fuxia (track registrado, sin implementar) | ✓ §8.1 |
| Pagado → cancelado = excepción PARTIAL, sin inferir devolución | ✓ §8 (ya implementado en `20261008000200`) |
| Invariante JWT del deploy | ✓ `admin/P2_3B_RUNBOOK.md` §3 + `scripts/f360/deploy_woo_functions.sh` (wrapper) + `scripts/f360/check_woo_functions.mjs` (guard post-deploy; detecta el incidente con `--at`) |
| Playwright | **TEST ENVIRONMENT BLOCKER**, no aprobado (§6) |
