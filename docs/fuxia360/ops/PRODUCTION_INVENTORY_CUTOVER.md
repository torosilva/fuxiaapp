# Fuxia 360 · Pase a producción del inventario (plan maestro)

**Estado:** PLAN. Nada de este documento se ha ejecutado en producción (2026-10-05).
**Decisión de origen:** Mario, 2026-10-05 — opción B (`PASE_A_PRODUCCION_OPCION_B.md`) + instrucción "F0 + F1 en paralelo, no tocar producción".
**Regla de oro:** `stock al cutover = conteo físico aprobado + entradas reales posteriores − salidas reales posteriores ± ajustes aprobados`.
Nunca `stock al cutover = lo contado días antes`. Nunca `opening balance = stock actual de Woo`.

Prohibido hasta aprobación explícita de Mario, fase por fase: aplicar migraciones a producción, desplegar funciones a producción,
copiar balances, conectar webhooks de producción, activar sincronización de stock, modificar Woo producción.

Fuentes de este documento (auditorías de solo lectura del 2026-10-05): repo completo, base actual `faltx…` (solo lectura, con huella),
documentación oficial de WooCommerce. Cada hallazgo cita archivo:línea.

---

## 0. Contradicciones encontradas (leer primero)

| # | Contradicción | Impacto | Qué se necesita |
|---|---|---|---|
| X1 | **El "conteo de Carolina" no está en la sesión de conteo.** La sesión `5b6b86c3…` (Bodega CDMX, `woo_staging4`) sigue en modo **doble**, con 5 tallas contadas una vez (09:07) y 661 pendientes. Carolina está cargando **tienda por tienda con "Recibir mercancía" (RECEIPT) y corrigiendo con "Ajustar" (ADJUSTMENT)**: Polanco 148 pares, Amsterdam 74 (+9 "En camino"), San Jerónimo 48, Bodega 10. Evidencia: `~/fuxia360-respaldos/ledger/2026-10-05T22-1…json`. | El opening candidato es el **ledger por ubicación**, no `opening_counts`. Esas cargas están tipadas como "entrada de mercancía", no como conteo. | Decidir (Mario) si esas cargas por tienda son el conteo real; reclasificarlas al migrar (§7). Preguntar a Carolina si contó físicamente cada tienda o capturó de una lista. |
| X2 | **Bodega CDMX en `faltx…` mezcla datos de prueba**: una SALE del pedido de prueba #3654 de staging4 y la transferencia de prueba de Mario (`INVENTORY_MODEL.md:138-151`). | No puede usarse como opening sin limpiar. | Bodega se cuenta de nuevo o se certifica línea por línea. |
| X3 | **El repo está ligado a PRODUCCIÓN**: `supabase/.temp/project-ref = tgzgiwfzddsghnxgkcqd`, versionado en git. Un `supabase db push` sin `--db-url` aplicaría las 70 migraciones a producción. | **Crítico (proceso).** | Todo comando con `--db-url` explícito y `--dry-run` primero. Recomendado: des-ligar (`supabase unlink`) y sacar `.temp/` de git (cambio aparte, con aprobación). |
| X4 | `PASE_A_PRODUCCION_OPCION_B.md` dice "65 migraciones" y "inventario arranca del conteo real en producción" (F5), y excluye copiar conteos (F4.5). | Hoy son **70** migraciones; la decisión de Mario (conservar el conteo de staging como candidato) cambia F4.5/F5. | Este documento sustituye esas partes. |
| X5 | Regla de existencia en línea: el código usa **Bodega + tiendas − apartados Gold** (`20261007002100_f360_stores_as_warehouses.sql:18-22`, decisión 4 del 2026-10-03, *para staging*). D-4 (`TRACK_D_LEGACY_TAKEOVER.md:13`), `INVENTORY_MODEL.md:69,124`, `06_WOOCOMMERCE_SYNC.md:38` y comentarios en `mapping.ts:3,77`, `sync.ts:17` dicen **solo Bodega**. | Define qué se publica en producción. | Mario confirma la regla para producción; se corrigen los documentos. |
| X6 | Stock 0: P3 dice "0 = agotado" (`TRACK_D:51`, `D3_REPORT.md:136`); la decisión 3 y el código dicen "sigue vendible sobre pedido" (`sync.ts:39` → `backorders:'notify'`). El publicador escribe `backorders:'no'` (`mapping.ts:67-68`, `publisher.ts:169`). | Un modelo recién publicado sobre pedido sale "agotado" hasta el siguiente push. | Unificar (§10). |
| X7 | "Sobre pedido" vive en el **modelo** (`f360.products.make_to_order`, `20261007001500:12`), pero la especificación y una columna sin uso lo ponen en la **talla** (`product_variants.make_to_order_eligible`, `20260925010000:69`; `03_DATA_MODEL.md:30,78`). | Dos fuentes de verdad. | Decidir una (§10). |
| X8 | Tiempo de producción: 10 días hábiles en código y tienda (`20261009000100`, `20261010000700:39`, commit d1ba621); 5–7 días en `00_MASTER_SPEC.md:94`, `08_OMNICHANNEL.md:62` y comentarios SQL. Colombia sin promesa (`20261010000700:43,46`). | Promesa al cliente. | Corregir documentos a 10 días hábiles; definir Colombia. |
| X9 | La reconciliación del conteo **no ve el negocio real**: `f360_opening_reconcile` solo lee `woo_order_lines` del target del conteo (`woo_staging4`, de prueba) y movimientos de `faltx…` (`20261010000400:103-128`), y además cuenta las líneas de prueba (sin filtro `outcome='test'`). | Un conteo puede aprobarse con "0 por recontar" mientras salieron pares reales; y recontar tallas por pedidos falsos. | Reconciliación v2 (§8). |
| X10 | **La "reconciliación" existente escribe en Woo**: `reconcile` empuja stock antes y después (`f360-woo-sync/handler.ts:60-65`) y `f360_reconcile_finish` encola correcciones. En producción (`manage_stock=false` en las 792 variaciones, `D1_DISCOVERY.md:53`) sobrescribiría todo. | No sirve para modo sombra. | Reporte sombra nuevo de solo lectura (§9). |
| X11 | `woo_sku_at_link` se diseñó (`TRACK_D:62-64,97`) pero **no se construyó**; las líneas legacy se resuelven por `variation_id` sin verificar SKU (`20261009000300:106`). | Un SKU cambiado en Woo no se detecta. | El delta de catálogo lo compensa (§6, D3). |
| X12 | `storefront_target` y `f360_storefront_catalog` (anon) aceptan targets de producción con solo `active` (`20261010000700:110-117`, `20261007002200:28-30`), mientras ingesta/sync los rechazan (`target_by_key`, `20260928000100:166-173`). | Un `woo_production` activo se expondría a anon antes de tiempo. | Crear `woo_production` **inactivo** (§4). |
| X13 | El aviso de consentimiento de "Avísame" se siembra `active` sin revisión legal (`20261010000700:20-22`; `000800:16`). | Legal. | Decidir estado en la config de producción. |
| X14 | Lo que pidió Carolina hoy ("borrar si me equivoco") ocurre en **Recibir mercancía / Ajustar**, no en el conteo. La migración `20261010000900_f360_opening_undo` arregla el conteo, no su flujo real. | Su dolor sigue. | Deshacer recepción (evento compensatorio auditado) — unidad aparte. |

---

## 1. Arquitectura objetivo

```
                fuxiaballerinas.com (WooCommerce = motor de ecommerce)
                 │  pedidos (webhook firmado)            ▲ stock por variación
                 ▼                                       │ (SOLO en piloto/on, por modelo)
   ┌──────────────────────── Fuxia 360 (Supabase tgzg…, esquema f360) ───────────────────────┐
   │ identidad canónica (modelo→color→talla, SKU F360-…) · homologación legacy_woo_map         │
   │ ledger: inventory_events/movements/balances por ubicación (Bodega, tiendas, En camino)    │
   │ online_ats = regla aprobada (X5) · delivery_promise · made_to_order · stock_intents      │
   │ stock_sync_mode por canal: off → shadow → pilot(modelos) → on   + kill switch            │
   └───────────────────────────────────────────────────────────────────────────────────────────┘
         ▲ ventas de tienda (app vendedora F360, por ubicación con cutover C3)
```

- Woo sigue siendo el motor de pedido/pago (`06_WOOCOMMERCE_SYNC.md` §1-2). F360 es la autoridad de inventario físico.
- La app publicada de clientas (tgzg…) no se toca; las tablas `public.*` que comparte solo reciben cambios aditivos probados (§3).

## 2. F0 · Proteger lo capturado (hecho / en curso)

**Ya existe y corre:** `scripts/f360/backup_master_data.mjs`, instalado con launchd (`~/Library/LaunchAgents/com.fuxia360.respaldo.plist`, diario 23:30).
Solo lectura, rechaza producción, sin datos personales. Exporta catálogo, homologación, ubicaciones, **inventory_events/movements/balances**,
**opening_counts/lines/changes/unlisted**, transferencias, ventas pasadas, más las fotos (incremental). Conserva 30 días.
Último respaldo: `~/fuxia360-respaldos/2026-10-05/` (672 líneas de conteo, 119 eventos, 249 balances).

**Nuevo (2026-10-05), huellas para demostrar integridad:**

| Script | Qué fija | Huellas |
|---|---|---|
| `scripts/f360/f0_count_snapshot.mjs [count_id]` | Sesión de conteo: ubicación, target, estado, modo; por línea: variante, SKU canónico, cantidad final, estado, `counted_at`, `final_at`, quién contó; pares sin ficha; bitácora | `qty_sha256` = (variant_id, sku, final_qty, status) por línea en alcance → lo que sería el opening. `full_sha256` = todo menos la hora de la toma (estable si nada cambió) |
| `scripts/f360/f0_ledger_snapshot.mjs` | Por ubicación: balances ≠ 0 y **cada movimiento** (evento, tipo, actor, `created_at`, variante, SKU, origen, destino, cantidad) | `balance_sha256` por ubicación; `ledger_sha256` por ubicación |

Ambos: `scripts/s00a/run.sh ../f360/<script>`; salida en `~/fuxia360-respaldos/{conteos,ledger}/` con `.sha256` al lado.
Primera toma 2026-10-05 22:14 UTC: conteo `qty_sha256 9c6f35c4…` (5/666), ledger Polanco `63e56ad4…`, Amsterdam `41f4f374…`,
San Jerónimo `7aa51f07…`, Bodega `0ff84696…`, En camino `92291704…`.

**Pendiente de F0 (propuesta, no hecho):** agregar las dos huellas al job diario (mientras haya carga abierta) y conservar las
huellas fuera de la máquina (p. ej. adjuntas a la bitácora diaria). La huella aprobada se congela en la fase FREEZE/SNAPSHOT y
**se vuelve a calcular en producción después de copiar**: si no coincide, no hay carga.

### Procedimiento COUNT → REVIEW → APPROVE → FREEZE/SNAPSHOT → DELTA → CUTOVER → OPENING BALANCE

| Paso | Quién | Qué | Evidencia de salida |
|---|---|---|---|
| COUNT | Carolina / vendedoras | Captura física por ubicación (hoy: Recibir/Ajustar en tiendas; Bodega pendiente). Cada captura queda con hora del servidor | ledger + bitácora |
| REVIEW | Carolina | Revisión por modelo; correcciones solo con ajuste auditado; pares sin ficha resueltos | reporte por ubicación |
| APPROVE | Mario (Bodega), Carolina (tiendas) — a confirmar | Aprobación escrita por ubicación | registro de aprobación + huellas |
| FREEZE/SNAPSHOT | operador | `f0_*_snapshot` → huellas firmadas; desde aquí cualquier cambio exige nueva aprobación | `.sha256` congelado |
| DELTA | operador + Carolina | Movimientos reales posteriores por variante (§8); solo "ciertos" se aplican; ambiguos → reconteo | tabla de deltas aprobada |
| CUTOVER | Mario | Ventana corta (§16): congelar movimientos físicos, ingesta de producción encendida, conteo parcial de ambiguos | acta |
| OPENING BALANCE | operador | Un `OPENING_PHYSICAL_COUNT` por ubicación con las cantidades aprobadas + un evento por delta aprobado; verificar huellas | balances = aprobado ± deltas |

## 3. F1 · Auditoría de migraciones para producción

**Universo:** 72 archivos en `supabase/migrations/` = 2 baselines + **70** de F360 (no 65). `20261010000900_f360_opening_undo` aún no
está aplicada en ningún ambiente. 61 `.down.sql` + 1 de A2 en `supabase/rollbacks/`. `supabase/pending/` solo tiene A2.

**Principio recomendado:** producción recibe **las mismas 70 versiones, byte por byte** (sin partir ni compactar), para que el historial
sea idéntico al de staging. Las líneas de ambiente son no-ops en un `f360` vacío o se corrigen con **un script de configuración de
producción** fuera de `migrations/`.

### 3.1 Clasificación (resumen; tabla completa por archivo en el anexo A)

| Clase | Migraciones | Veredicto producción |
|---|---|---|
| **SCHEMA** (tablas, índices, vistas) | casi todas; p. ej. `20260925010000`, `20260927010000`, `20261003000100`, `20261007000700`, `20261007001100`, `20261010000500` | Correr tal cual |
| **FUNCTIONS / RPC / TRIGGERS** | todas; 9 son correcciones de otra (`20260928000200/300/400`, `20261001000200`, `20261002000200`, `20261003000200`, `20261004000200/300`, `20261007002000`) | Correr tal cual (sin `.down` propio) |
| **PRIVILEGIOS** | `20260925000100` (A1: revoca RPC de lealtad a anon/authenticated + default ACL) | Primero |
| **REFERENCE DATA** | categorías (`20260926000100:17-19`), "En camino" (`20261003000100:25-26`, id aleatorio), monedas y sugerencias de precio (`20261005000100:23-26,44-45`), propósitos de consentimiento (`20261010000100:131-134`, `20261010000700:18`), reglas de promesa (`20261010000700:37-47`, `000800:13-15`) | Correr tal cual; mapear el id de "En camino" al copiar datos |
| **CONFIGURATION** | 5 jobs cron: `f360-woo-stock-push` (1 min, `20261006000100:22`), `f360-reservations-expire` (1 min, `20261007001100:175`, **corre sin Vault**), `f360-push-retry` (`20261007001300:98`), `f360-email-retry` (`20261007002500:95`), `f360-commerce-poll` (`20261008000100:540`); extensión `pg_net` | Correr; **no cargar secretos de Vault** hasta su fase |
| **BUSINESS DATA (backfill sobre datos de producción)** | `20261010000100:80,116-118` (cumpleaños, verificación de clientas reales), `20261010000600:14-20` (rotación de QR `FX1-`) | Intencionales para producción; **#61 y #66 en el mismo push** |
| **STAGING DATA** | `20261009000300:12,15-16` (UPDATE de `woo_staging4`/`woo_local`) | No-op en producción (0 filas) |
| **ENV-SPECIFIC / SECRETS** | prefijo `[STAGING] ` en destinatarios (`20261007002500:16`, `20261007002600:34`); visores de PII por nombre (`20261010000100:91-92`); `DEFAULT 'woo_staging4'` (`20261007000100:197`, `20261007000900:202`); lectura de Vault `f360_sync_*`, `f360_push_*`, `f360_email_*` | Corregir en el script de config (prefijo `''`, visores por correo); el DEFAULT se pasa explícito |
| **LEGAL GATE** | aviso de consentimiento v1 `active` (`20261010000700:20-22`) | Estado según decisión legal |
| **TEST / DEMO DATA** | ninguna migración; viven en `supabase/staging/` (`lab_seed.sql`, `f360_demo_seed.sql`, 37 `*_tests.sql`) y `scripts/f360/*staging4*` | **Nunca en producción** |

**Tocan tablas de la app publicada** (riesgo de compatibilidad): `transactions` (+4 columnas, `20261002000100`, bajo);
`offline_sales`/`channel_inventory` (+columnas, CHECK+VALIDATE, triggers; `20261002000300`, `20261004000100`, **medio-alto**: R2 anon, R4 validación);
`customers`/`loyalty_cards` (índice único por teléfono normalizado, columnas, triggers, backfill; `20261010000100`, **alto**: R3 duplicados);
`customers` FK RESTRICT desde reservaciones (`20261007001100:16`, R5 rompe `delete-account`). Ninguna migración reemplaza funciones del baseline
ni crea políticas sobre `public.*`.

### 3.2 Nunca en producción
1. Ejecutar los baselines `20260924000000/000001` (solo se registran como aplicados).
2. `supabase db push` sin `--db-url` (X3) o con `fuxia-native/supabase` ligado (`tgzg…`).
3. A2 (`supabase/pending/s00a/…`) por `db push`; solo por `A2_PRODUCTION_RUNBOOK.md`.
4. Rollbacks destructivos una vez haya escrituras reales: `20261010000600…down` (regresa `FX1-`), `20261002000300…down`, `20261002000100…down`,
   `20261010000100…down` (borran columnas/tablas de la app). Después de la ventana, el rollback es respaldo + corrección hacia adelante.
5. Todo `supabase/staging/` y los scripts `woo_staging4_target.mjs`, `publish_staging4.ts`, `carolina_acceptance_restore.mjs`,
   `g1_commerce_backfill.mjs`, `d2_homologation_propose.mjs`, `p23b_readonly_reconcile.mjs`.
6. Secretos de Vault `f360_*` antes de su fase.

### 3.3 Procedimiento reproducible
1. **Congelar el set:** aplicar `20261010000900` + pruebas en staging primero; etiquetar commit; sha256 por archivo.
2. **Precheck de producción** (solo lectura) = `PASE_F1_PRECHECK_PROD.sql` **+** lo que le falta: normalizador idéntico a `f360.normalize_phone`
   (`20261010000100:21-47`: prefijo `00`, +57, +1), historial de migraciones = solo baselines, 0 jobs `f360-%`, 0 secretos `f360_%`, estado de A1,
   colisiones de nombres (columnas, triggers, índices, constraints), conteos de filas para estimar bloqueos, 0 tarjetas `FX1-`, diff de políticas.
3. **Ensayo F2** en un proyecto temporal (nunca producción ni `faltx…`): esquema de producción por `pg_dump --schema-only`, clientas sintéticas
   con casos límite, bucket `product-images`; aplicar los 70 por grupos, config de producción, copia de datos maestros; suites de staging
   (solo ahí) + **suite de compatibilidad de la app** (alta de clienta y tarjeta, duplicado de teléfono, RLS de lectura, venta legacy y sobreventa,
   venta como anon, Edge Functions de lealtad, `delete-account` con y sin reservación, app publicada contra el ensayo); ensayo de rollback.
4. **Ventana por grupos** (la CLI no tiene "hasta versión": carpeta temporal con las migraciones del grupo, `--db-url`, `--dry-run`, push, checkpoint):
   G0 respaldo + precheck · G1 #1 · G2 #2-16 · G3 #17-19 · A2 o GRANT de compatibilidad · G4 #20-25 · G5 #26-60 · G6 **#61 + #66** (con `f360.user_roles` vacío) · G7 #62-65, #67-70.
5. **Script de config de producción** (`supabase/prod/f360_prod_config.sql`, una transacción, con aserciones): prefijo `''`; `user_roles` y visores de PII
   **por correo**; `sales_targets.woo_production` con `is_production=true, is_test=false, active=false, stock_sync_mode='off'`; consentimiento según legal; sin Vault.
6. **Verificación:** 72 versiones = staging; diff de esquema `f360` vacío; 5 jobs, 0 secretos; matriz de privilegios (anon solo 3 funciones de tienda);
   en producción solo pruebas de lectura + una cuenta interna real (login, tarjeta, escaneo).

## 4. Catálogo y homologación (separado del inventario)

| Dato | Tablas | Migra | Condición |
|---|---|---|---|
| PRODUCT | `f360.products` | **Tal cual, mismos ids** | Re-mapear `created_by` por correo; `wc_product_id` dormido = NULL; revisar colisión de `slug` con Woo producción |
| COLOR | `f360.product_colors` | Tal cual | Corregir dato conocido ("Ballerinas puntudo negro" guardado como Verde, `BITACORA_2026-10-02_04.md:132`) |
| SIZE | `f360.product_sizes` | Tal cual | Etiquetas = términos `pa_medida` de producción |
| VARIANT | `f360.product_variants` | Tal cual | `wc_variation_id` = NULL |
| CANONICAL SKU | `product_variants.sku` | Tal cual | Verificar que ningún `F360-*` exista ya en Woo producción |
| IMAGES | `f360.product_media` + bucket `product-images/f360/**` | Tal cual, **archivos primero** | Verificar cada `storage_path` en destino (575); el INSERT directo salta la verificación del RPC |
| PRICE | `products.regular/sale_price`, `f360.product_prices` | Datos tal cual | **Publicarlos cambia precios vivos** → diff de precios aprobado por Mario (regla 13); metas COP/USD verificadas solo en staging4 |
| FIT | `f360.product_knowledge(+_history)` | Tal cual | Re-mapear `validated_by/updated_by`; historial solo INSERT |
| CATEGORY | `f360.categories` / `woo_category_links` | Sembradas / **reconstruir** | Términos de producción verificados (lectura) |
| HOMOLOGATION | `legacy_woo_map(+_log)` | **Copiar como historia del canal staging4; re-anclar a `woo_production` solo filas que pasen el delta** | Requiere RPC nuevo y auditado de re-anclaje (no existe) |
| | `legacy_consolidations` | Solo si Mario aprueba consolidar en producción | Hoy rechazado en producción |
| | `legacy_inventory_map` | **Nunca copiar; reconstruir** | Está atado a `channel_inventory` de laboratorio |
| WOO IDENTITY | `sales_targets` | **Nuevo `woo_production` inactivo**; `woo_staging4` como historia inactiva | X12 |
| | `woo_product_links`, `woo_variant_links`, `woo_media_links` | **Reconstruir** | ids de staging4; modelos publicados por F360 no existen en producción → republicar como borrador con revisión de Carolina |
| | `retired_woo_links`, `legacy_content_pushes`, `woo_visibility_requests`, `sync_jobs*`, `opening_counts*` | **Nunca copiar** al canal de producción | |

Riesgos de código: el publicador, content push, consolidación y vínculos rechazan producción por diseño (`f360-woo-publish/handler.ts:76`,
`publisher.ts:38`, `20261007001400:30`, `20261007001900:46`, `20261007000900:170`); abrirlos es una migración con aprobación propia.
Republicar crea términos `pa_color`/`pa_medida` en producción (escritura no listada hoy). Con `woo_staging4` y `woo_production` activos a la vez,
`f360_store_availability` y `f360_scarcity_state` resuelven por el canal más viejo (`20261007001100:80-83`, `20261007002400:48-50`).
Constantes `woo_staging4` en código a parametrizar: `admin-web/src/app/(app)/actions.ts:89`, `admin-web/src/lib/f360.ts:179,211`,
`conteo/ConteoClient.tsx:28,55`, `f360-store-reserve/handler.ts:61,109`, mu-plugin con guardia de host (`build_storefront_muplugin.py:16`).
Conciliación numérica pendiente: 76 modelos propuestos (D2) → 62 hoy; 792 variaciones legacy − 666 confirmadas = 126 sin confirmar; 894 − 666 = 228 sin homologación.

## 5. Clasificación de migraciones

Ver §3.1 (por clase) y el Anexo A (por archivo).

## 6. Delta de catálogo: Woo producción ↔ Woo staging4 ↔ identidad F360

`scripts/f360/d2_prod_delta.mjs` (Store API pública, solo GET) comparó producción vs staging4 **en vivo** el 2026-10-02 (129/792 vs 130/810, 0 diferencias salvo Macarena).
**Ya no sirve tal cual:** staging4 dejó de ser copia limpia (content push, consolidación con productos privados, push de stock, mu-plugins);
no verifica contra F360; no ve SKU propio de variación, borradores/privados, fechas, metas de precio ni `manage_stock`; no valida lectura completa.

**Base de comparación:** S = foto congelada de staging4 (`d1_catalog_staging4.json`, 2026-10-02 19:36Z + columnas de `legacy_woo_map`), no staging4 vivo.

| # | Verificación | Fuente | Severidad |
|---|---|---|---|
| D1 | Cada `legacy_woo_map.woo_variation_id` existe en producción | Store API | BLOQUEA |
| D2 | Mismo padre, talla y color que en el mapa | Store API | BLOQUEA |
| D3 | SKU padre = `woo_parent_sku` (compensa X11) | Store API / REST | REVISIÓN → BLOQUEA |
| D4 | Nombre, slug, categoría = S | Store API | REVISIÓN |
| D5 | Productos/variaciones nuevos en producción después de la copia (~2026-09-24) | Store API / REST `date_created` | BLOQUEA hasta homologar |
| D6 | Del mapa que ya no están en producción | Store API / REST | BLOQUEA si confirmado |
| D7 | Estado/visibilidad | REST | REVISIÓN |
| D8 | Multicolor / "cualquier color" | Store API | BLOQUEA sin decisión humana |
| D9 | Precios MXN + metas COP/USD vs F360 | Store API / REST | REVISIÓN (regla 13) |
| D10 | Categorías (4 claves) | Store API | BLOQUEA |
| D11 | Atributos `pa_color`/`pa_medida` y términos | Store API / REST | REVISIÓN |
| D12 | Colisión de SKU `F360-*` | Store API / REST | BLOQUEA |
| D13 | Colisión de slug | Store API | REVISIÓN |
| D14 | Modelos solo-F360 ausentes en producción → lista de republicación | F vs P | INFO |
| D15 | Integridad F360 (dormidos NULL, 1 variante ↔ 1 variación) | F | BLOQUEA |
| D16 | Estado de control de stock en producción (`manage_stock`, `backorders`, umbral) | REST | INFO (foto "antes") |

Necesita una **llave REST de solo lectura** de producción para D3, D5, D7, D9, D11, D16 (P1 autorizó solo Store API pública → decisión de Mario).
Salida: `docs/fuxia360/audit/trackd/d5_delta_<UTC>.json` (nunca se sobrescribe) + CSV para Carolina + resumen para Mario.
**Pasa** solo con: lectura completa (totales = `x-wp-total`, dos corridas iguales), 0 BLOQUEA, toda REVISIÓN cerrada por escrito, corrida < 24 h antes de re-anclar y otra justo antes de webhooks/stock, y solo filas exactas se re-anclan.

## 7. Tratamiento de lo capturado por Carolina

**Hecho (X1):** el inventario capturado está en el ledger de `faltx…` como RECEIPT/ADJUSTMENT por tienda, con hora del servidor por movimiento.
`counted_at(v, ubicación)` = hora del último movimiento de captura de esa variante en esa ubicación (no la hora del primer ajuste).

**Propuesta (no autorizada aún):**
1. Seguir capturando en `faltx…`; F0 diario + huellas.
2. Por ubicación, Carolina declara "terminé" → REVIEW → APPROVE → huella congelada.
3. Al migrar, **no** se copian los eventos RECEIPT como recepciones: se genera en producción un `OPENING_PHYSICAL_COUNT` por ubicación con
   las cantidades aprobadas (respeta "una apertura por ubicación", `20261004000100:24-25`) y con referencia a la huella y a los eventos de origen.
   Luego un evento por cada delta aprobado (§8).
4. Bodega CDMX: no usar lo actual (X2); contar en la sesión de conteo (modo simple) o certificar línea por línea.
5. Opción de lugar de carga (decisión Mario): **(a)** aprobar en `faltx…` y cargar en `tgzg…` en el cutover (recomendado; requiere revisar F4.5,
   re-anclar `target_id` y abrir `target_by_key`) o **(b)** cargar en `faltx…` y espejar cada movimiento real hasta copiar (semanas de doble captura).

## 8. Movimientos entre la captura y el cutover (P0)

**Problema central:** hoy el negocio real opera en producción (Woo real, app/vendedoras sobre `tgzg…`, papel/WhatsApp), mientras la captura vive en `faltx…`.
Nada de lo real llega a `faltx…`. Además, la hora de pago no ordena eventos contra la captura: contado 10:00, pagado 9:50, empacado 11:00 = ambiguo.

| Tipo | Dónde queda hoy | Identidad mapeable | Ubicación | Hora física | Veredicto |
|---|---|---|---|---|---|
| Venta ecommerce | Woo producción (pedidos); `transactions/purchase_items` en `tgzg…` (sin `variation_id`) | `variation_id` → `legacy_woo_map` si el delta pasa | **No registrada** (Bodega/tienda/bazar/sobre pedido) | pago sí; envío no (salvo que `completed` = enviado) | Identidad y pago **ciertos**; salida de una ubicación **PARCIAL** sin bitácora de envíos |
| Cancelación / reembolso | Woo (financiero) | por línea | — | reembolso ≠ regreso físico | Financiero cierto; **regreso físico NO reconstruible** |
| Venta en tienda | `offline_sales.items` en `tgzg…` (app legacy) → `channel_inventory` → `legacy_inventory_map` (hoy solo de laboratorio) | Parcial (texto) | tienda | `created_at` ≈ venta | **PARCIAL**; afecta las tiendas que Carolina capturó en `faltx…` |
| Apartado Gold | Solo `faltx…` (pruebas); en la realidad WhatsApp | — | tienda | — | No mueve existencias; ¿pares apartados físicamente se contaron? (pregunta) |
| Transferencia Bodega ↔ tienda/bazar | No hay flujo en producción; ediciones directas de `channel_inventory` o `inventory_change_requests` | Parcial | solo destino | solo escritura | **NO reconstruible** desde sistemas |
| Entrada del taller | papel/remisión, o "Recibir" en `faltx…` | en F360 cierta | Bodega/tienda | registro | En F360 **cierta**; en papel **PARCIAL** |
| Ajuste (daño, hallazgo) | `f360_adjust_inventory` en `faltx…`; real: no se registra | — | — | — | **NO reconstruible** salvo bitácora |
| Cambio de talla/modelo | sin flujo | — | — | — | **NO reconstruible** |
| Sobre pedido (llegada/envío) | Woo no distingue | — | puede estar en Bodega esperando envío | — | **NO reconstruible**: riesgo de contar un par ya comprometido |
| Bazares | `channels`/`channel_inventory` legacy | Texto | bazar | — | **NO reconstruible** del lado de Bodega |

**Algoritmo:** por variante `v` y ubicación `L`, con `OBS_LAST(v,L)` = última captura y `CUTOVER_AT` = inicio del registro completo en producción:
- **Cierto:** pedido Woo pagado después de `OBS_LAST` **con** evidencia de que salió de `L` (bitácora de envíos/guía) y no cancelado antes de envío → −qty;
  venta de tienda en `offline_sales` después de `OBS_LAST` con variante mapeada → −qty; recepción/transferencia/ajuste firmado con hora física posterior.
- **Ambiguo** (nunca por aritmética): hora física desconocida; dentro de la ventana de captura; pagado antes y enviado a hora desconocida; pedido sin origen;
  devoluciones y cambios → **reconteo de `v` en `L`** dentro del congelamiento final (reinicia `OBS`).
- **Irrelevante:** pedidos de prueba de staging4, apartados (no mueven), ventas de tienda de pares de la tienda para Bodega.
- `opening(v,L) = cantidad aprobada + Σ deltas ciertos aprobados en (OBS_LAST, CUTOVER_AT]`. La carga se bloquea con cualquier ambiguo abierto.

**Evidencia requerida:** exportación de solo lectura de pedidos de producción (id, estado, `date_paid_gmt`, `date_completed_gmt`, líneas, `variation_id`, reembolsos, país; sin datos de clientas) — **requiere aprobación de Mario**;
`offline_sales` de producción por tienda desde la primera captura (solo lectura); bitácora de salidas/entradas de Bodega y tiendas desde hoy (Carolina); guías de envío; remisiones del taller.

**Diseño de datos (propuesta):** tabla append-only `f360.opening_deltas` (ubicación, variante, fuente, referencia externa, `t_paid`, `t_phys`, base de la hora, qty con signo,
`cierto|ambiguo`, evidencia, `propuesto|aprobado|rechazado|resuelto_por_reconteo`, aprobó); `opening_blockers` agrega ambiguos abiertos;
reconciliación v2 ignora `outcome='test'`, usa hora de pago y la primera observación. Al cargar, cada delta aprobado es un evento honesto
(`SALE` con la misma llave idempotente que la ingesta, `md5('woo-sale:woo_production:{pedido}:{línea}')`; `RECEIPT`/`TRANSFER`/`ADJUSTMENT` con nota "corte").

**Marca de agua (crítica):** antes de encender la ingesta, pre-registrar en `woo_order_lines` de `woo_production` toda línea pagada antes de `CUTOVER_AT`
(`sold` si tiene delta aprobado; `pre_cutover` sin evento). Sin esto, un pedido viejo que pase a `completed` después descontaría otra vez o descontaría un par nunca contado.

**Conclusión honesta:** con lo que existe hoy, **solo** las ventas Woo con bitácora de envío y las ventas de tienda mapeadas se pueden reconstruir.
Transferencias, ajustes reales, cambios, sobre pedido y bazares **no**. Por eso se necesita: bitácora operativa desde hoy + **congelamiento corto final** + **reconteo parcial** de toda talla tocada.

## 9. Modo sombra

**Bloqueo previo:** `f360.target_by_key()` rechaza todo target de producción (`20260928000100:171`), así que incluso la ingesta en sombra requiere una migración aprobada (Q12).

```
Woo producción ──pedidos (webhook firmado)──▶ F360 (ledger)        F360 ──✗──▶ Woo stock
                ◀──GET solo lectura (reporte diario)──
```

**Garantías de no escritura (en capas, cada una basta):** llave REST de Woo con permiso **Read** (no contraseña de aplicación) en un secreto con nombre propio;
`stock_sync_mode='shadow'` en DB (claims vacíos); adaptador que lanza `WRITE_BLOCKED` si el modo no permite escribir o si `F360_WOO_WRITES≠'on'`;
sin secretos Vault de push; acción `reconcile` y "Revisar ahora" deshabilitadas fuera de piloto/on (X10); prueba con el adaptador simulado que exige 0 llamadas de escritura.

**Efectos a apagar en sombra:** la ingesta hoy crea avisos de envío a tiendas, tareas sobre pedido y excepciones de sobreventa → en sombra se registran con `shadow=true`, sin notificaciones.
Decisión de Mario: si el ledger descuenta en sombra (recomendado: sí, es lo que se está probando).

**Reporte diario** (`shadow_report`, 07:00 CDMX, tabla append-only `f360.shadow_report_runs`, CSV). Encabezado obligatorio:
*"Woo NO es la fuente de verdad. Hoy Woo producción no controla stock. Este reporte detecta comportamiento y errores; las diferencias contra Woo no son errores de inventario."*

| VARIANT | WOO OBSERVED STATE | F360 CALCULATED STOCK | PHYSICAL/CERTIFIED STOCK | DELTA | EXPLANATION | STATUS |
|---|---|---|---|---|---|---|
| SKU · modelo · color · talla | `manage_stock`/`stock_status`/`stock_quantity`/`backorders` tal cual | `online_ats` + sobre pedido → lo que F360 publicaría | on-hand en ubicaciones certificadas + # no certificadas | Δa F360 − certificado; Δb publicaría vs observado | códigos | OK / EXPECTED / WATCH / ACTION / BLOCKER / UNVERIFIED |

Códigos: `MATCH`, `WOO_UNMANAGED_EXPECTED`, `MTO_WOULD_BACKORDER`, `ZERO_NOT_MTO_WOO_SELLS`, `F360_POSITIVE_WOO_OUTOFSTOCK`, `UNCERTIFIED_LOCATION`,
`LOCATION_IN_CUTOVER`, `GOLD_HOLD`, `STORE_STOCK_INCLUDED`, `PENDING_INGEST`, `MTO_OPEN`, `OVERSOLD_OPEN`, `CANCEL_REFUND_NO_RESTOCK_DW4`,
`WOO_NEGATIVE_STOCK`, `BACKORDERS_SETTING_MISMATCH`, `MISSING_IN_WOO`, `UNKNOWN_SKU`, `SKU_MISMATCH`, `UNLINKED_VARIANT`, `PARTIAL_LINE_SPLIT`.
Salida de sombra a piloto por modelo: 0 BLOCKER, todas sus variantes certificadas, N días limpios (N lo fija Mario).
`p23b_readonly_reconcile.mjs` no sirve tal cual (atado a staging4, solo Bodega, una página).

## 10. Stock 0 / sobre pedido

**Capacidades verificadas de Woo** (docs REST + código core): por variación `manage_stock`, `stock_quantity`, `backorders` (`no|notify|yes`);
con stock administrado **Woo calcula `stock_status` solo** (`abstract-wc-product.php` `validate_props`): > umbral → `instock`; si no, `onbackorder` si backorders ≠ `no`; si no, `outofstock`.
Con `notify` la línea del pedido recibe la meta "Backordered" (cantidad sin existencia) y la PDP muestra la clase `available-on-backorder`, que la tienda ya usa para "a la medida".
Requisito global: `woocommerce_manage_stock = yes` y umbral de agotado = 0 (verificado en staging4, **pendiente en producción**). No hay plugin de lista de espera: "Avísame" es propio (`f360.stock_intents`, `20261010000700:79-178`), hoy solo en staging4.

**Representación propuesta** (por variación; el padre queda sin control de stock; **nunca escribir `stock_status`**):

| Caso | manage_stock | stock_quantity | backorders | Woo deriva | Tienda muestra |
|---|---|---|---|---|---|
| Stock > 0 | true | ATS real | `notify` si sobre pedido, si no `no` | `instock` | promesa de entrega física |
| Stock = 0 y sobre pedido | true | **0** | `notify` | `onbackorder` (comprable) | "Producción: 10 días hábiles · a la medida" |
| Stock = 0 y no sobre pedido | true | 0 | `no` | `outofstock` | "Agotada · Avísame cuando llegue" |

Sin stock ficticio, sin apagar el manejo de inventario. Es lo que `sync.ts:31-39` ya hace; faltan: el publicador con la misma regla (X6) y una sola fuente del flag (X7).

**Señal de demanda:** vive en F360 (`made_to_order`, líneas `sobre_pedido`, `stock_intents`, excepciones `oversold`, `f360_stock_demand`), no en el negativo de Woo.

**Brechas de la ingesta a corregir antes del piloto:** (1) línea parcial todo-o-nada (Bodega 1, piden 2 → toda la línea sobre pedido; decisión: partir la línea o no);
(2) Woo queda en negativo tras un pedido sobre pedido y el siguiente push publica de menos → encolar push y usar `lastPushed − max(0, currentWoo)`;
(3) el par fabricado para un pedido queda vendible para otra → ligar la recepción al `made_to_order` y apartarlo; (4) cancelar no cancela la orden de producción;
(5) opcional: guardar la cantidad "Backordered" de Woo por línea.

## 11. Piloto (5–10 modelos)

**No se seleccionan todavía: no hay evidencia suficiente** (sin conteo certificado de Bodega, sin delta de producción, sin bitácora de envíos).
Criterios para elegir, en orden: homologación limpia (D1–D3 exactas, sin multicolor, sin consolidación); conteo certificado en todas las ubicaciones que suman a `online_ats`;
identidad Woo verificada (D16 conocido); ventas suficientes (≥ N pedidos/semana en `historical_sales` o Woo); mezcla de modelos con existencia y con tallas en 0 sobre pedido;
y uno no-sobre-pedido para probar "Agotada + Avísame". Se proponen con datos cuando existan el delta y el reporte sombra.

## 12. Kill switch / feature flag

**Hoy no existe** un interruptor por canal ni por modelo; las únicas paradas son quitar secretos de Vault, `active`, `is_production`, desprogramar el cron o revocar la llave.

**Diseño mínimo, aditivo:**
- `sales_targets.stock_sync_mode` `off|shadow|pilot|on` (DEFAULT `off`; staging4/local se migran a `on` para no cambiar su comportamiento).
- `f360.stock_sync_scope(target_id, product_id, enabled, …)` = lista piloto por canal y modelo.
- `f360.stock_sync_mode_changes` append-only (trigger, incluso para cambios por SQL directo) con motivo obligatorio.
- `f360.stock_sync_allowed(target, variant)`; RPC solo dueña `f360_set_stock_sync_mode(target, mode, motivo, confirmación=clave del canal para pilot/on en producción)` (apagar nunca pide confirmación) y `f360_set_stock_sync_product(...)`.
- **Se hace cumplir en la base** (claims de stock y visibilidad devuelven vacío; `reconcile_finish` no encola), en el tick (no llama si nadie está en pilot/on), en la función Edge (puerta antes de cada lote; adaptador de solo lectura) y en Woo (llave Read en sombra).
- **Detener ya:** `off` aplica al confirmar; a lo más termina el lote en curso (un producto). La cola se conserva y al reencender se recalcula.
  "Apagado" congela Woo en los últimos valores con `manage_stock=true`; **devolver el control a Woo** (`manage_stock=false`) es una acción aparte de la dueña (decisión de Mario).
- Respaldo de emergencia: `UPDATE … SET stock_sync_mode='off'` → `cron.unschedule('f360-woo-stock-push')` → borrar Vault `f360_sync_url` → revocar llave en WP.
- Pantalla: tarjeta "Sincronización de stock: Apagada / Solo observar / Piloto (N modelos) / Encendida" con botón "Detener ya".

## 13. Rollback

| Fase | Cómo se revierte |
|---|---|
| Migraciones (antes de escrituras reales) | `.down.sql` del grupo en orden inverso, ensayado en F2 |
| Migraciones (después) | restaurar respaldo/PITR de G0 + corrección hacia adelante; **nunca** los down destructivos (§3.2) |
| Datos maestros copiados | borrar por ids copiados (lista de la copia) en una transacción; fotos se dejan |
| Opening balance | eventos compensatorios auditados (no se borra el ledger) y `ledger_authority` no regresa a legacy (C3) |
| Ingesta en sombra | `stock_sync_mode='off'` + quitar webhook en Woo; el ledger se conserva para análisis |
| Piloto / on | kill switch; si hace falta, acción explícita para regresar `manage_stock=false` en el alcance |

## 14. Criterios GO / NO-GO

**GO a instalar F360 en producción (Fase 1):** precheck verde; F2 ensayado con suite de compatibilidad verde; respaldo G0; X3 neutralizado; aprobación escrita de Mario del grupo.
**GO a catálogo (Fase 2):** delta D1–D16 sin BLOQUEA y revisiones cerradas; huellas de fotos verificadas; diff de precios aprobado.
**GO a opening (Fase 3):** cada ubicación con APPROVE + huella; tabla de deltas sin ambiguos abiertos; huella recalculada en producción = aprobada; marca de agua cargada.
**GO a sombra (Fase 4):** migración de puertas aprobada; llave Read; 0 escrituras en prueba; efectos de staff apagados.
**GO a piloto (Fase 5):** N días de sombra sin BLOCKER en los modelos piloto; umbral de agotado = 0 y manejo global de stock activo en producción; publicador y push con la misma regla de backorders; brechas §10 cerradas; kill switch probado.
**GO a catálogo completo (Fase 6):** piloto ≥ N días sin incidentes y reconciliación limpia.
**NO-GO automático:** cualquier diferencia de huella; un BLOQUEA abierto; una escritura detectada en sombra; reconciliación con diferencias sin explicar.

## 15. Responsables (propuesta)

| Rol | Quién | Qué |
|---|---|---|
| Aprobación por fase | Mario | cada GO, decisiones abiertas (§17), llave REST de solo lectura |
| Operación e inventario | Carolina | captura, REVIEW, homologación, bitácora de movimientos, reconteos |
| Ejecución técnica | operador (equipo dev) | scripts, migraciones por grupos, verificación, reportes |
| Tienda en línea | dueño de WordPress/Woo | ajustes de inventario de Woo, llaves, webhooks |
| Legal | por definir | aviso de consentimiento de "Avísame" |

## 16. Checklist del día de cutover (por ubicación o global)

1. T−24 h: delta de catálogo fresco (0 BLOQUEA); huellas recalculadas = aprobadas; deltas aprobados; marca de agua lista; aviso a Carolina y tiendas.
2. T−2 h: respaldo PITR + `pg_dump`; congelar recepciones/transferencias/ajustes en `faltx…`; snapshot final + huellas.
3. T0: **congelamiento físico corto**: Bodega/tiendas no despachan ni reciben; Woo sigue tomando pedidos (no se envían).
4. Reconteo parcial de toda talla con movimiento o ambigüedad desde su captura.
5. Cargar en producción: `OPENING_PHYSICAL_COUNT` por ubicación + eventos de deltas; verificar `balances = aprobado ± deltas`.
6. Pre-registrar la marca de agua de pedidos anteriores.
7. Activar `woo_production` (todavía `stock_sync_mode='off'` → `shadow`); conectar webhook firmado; prueba con un pedido real interno.
8. Cutover C3 de cada tienda: vendedoras pasan a la app F360; `channel_inventory` queda congelado.
9. Levantar el congelamiento físico; primer reporte sombra.
10. Acta: horas exactas (`CUTOVER_AT`), huellas, quién aprobó.

## 17. Decisiones abiertas para Mario

1. ¿Las cargas de Carolina por tienda (RECEIPT/ADJUSTMENT) son el conteo real? ¿Bodega se cuenta de nuevo? (X1, X2)
2. Lugar de carga: (a) aprobar en `faltx…` y cargar en producción en el cutover, o (b) cargar y espejar. (§7)
3. Llave REST de **solo lectura** de producción y exportación de pedidos (sin datos de clientas). (§6, §8)
4. Duración aceptable del congelamiento físico final. (§8, §16)
5. Política de deltas: solo "ciertos"; ambiguos se recuentan. Marca de agua `pre_cutover`. (§8)
6. Regla de existencia en línea para producción: solo Bodega o Bodega + tiendas − Gold. (X5)
7. "Sobre pedido" por modelo o por talla; partir líneas parciales o no. (X7, §10)
8. Si el ledger descuenta durante sombra; días limpios N para pasar a piloto. (§9)
9. Qué hace "apagar": congelar Woo o devolverle el control. (§12)
10. Consolidar o no en producción los 7 modelos consolidados en staging4. (§4)
11. Promesa para Colombia y resto del mundo. (X8)
12. Des-ligar el repo de producción y sacar `supabase/.temp/` de git. (X3)

---

## Anexo A · Clasificación por archivo

Ver el informe de auditoría F1 del 2026-10-05 (tabla de 72 filas: archivo, categorías, evidencia, veredicto, tablas de la app) — se incorpora
al repo como `docs/fuxia360/ops/PASE_F1_MIGRATIONS_AUDIT.md` actualizado (pendiente: hoy ese documento cubre 65 y le faltan #66-#70).
Resumen de veredictos: 2 nunca se ejecutan (baselines, ya registrados); 1 primero (A1); 4 "tal cual + config" (`20261003000100`, `20261007002500`,
`20261007002600`, `20261010000100`); `20261010000700` con puerta legal; `20261010000900` primero en staging; el resto tal cual.
