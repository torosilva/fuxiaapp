# F1 · Auditoría de migraciones para producción (opción B)

**Fecha:** 2026-10-05 · **Plan:** `docs/fuxia360/ops/PASE_A_PRODUCCION_OPCION_B.md` (fase F1)
**Alcance:** las 65 migraciones posteriores al baseline (`20260924000000_*` y `20260924000001_*`) en `supabase/migrations/`.

**Método:**
- Lectura del repositorio únicamente.
- Sin conexión a producción (`tgzg…`) ni a `faltx…`.
- Sin `db push`.
- Ningún archivo de migración fue modificado.
- Las afirmaciones sobre producción se basan en el baseline (`20260924000000_baseline_live_public_schema.sql`, dump del 2026-09-24). F2 debe confirmar que producción no cambió desde entonces.

---

## 0. Resumen ejecutivo

| # | Hallazgo | Severidad | Dónde |
|---|---|---|---|
| R1 | Con `20261010000100` toda tarjeta nueva que crea la app recibe un QR `FX1-…`, pero el escáner de la app publicada **descarta todo QR que no empiece con `FX-`**. `FX1-` no cumple, así que las clientas nuevas no se pueden escanear en tienda. Afecta al flujo de venta legado y al nuevo. `crm/C1_DELIVERY.md:127` dice "La app no necesita cambios": **contradicción**. | **ALTA** | `fuxia-native/components/QRScanner.tsx:25`; `20261010000100:191-208` |
| R2 | `20261004000100` agrega el trigger `offline_sales_client_guard`. Corre con el rol del cliente y llama a `public.f360_legacy_channel_frozen()`, a la que se le quitó EXECUTE para `anon` (línea 172). En producción **A2 no está aplicado**: el modo "Soy vendedora" antes de iniciar sesión inserta `offline_sales` como `anon` (`app/vendedora/sale.tsx:190`), y esa venta fallaría con *permission denied*. En staging no se vio porque A2 ya estaba aplicado. | **ALTA** (si A2 no va antes) | `20261004000100:156-173,476` |
| R3 | El índice único `customers_phone_normalized_key` aborta la migración si producción tiene la misma clienta escrita en dos formatos. Además, una clienta existente cuyo teléfono no está en E.164 ya **no podrá registrarse en la app**: el login busca el teléfono exacto y el INSERT choca con el índice ("Error creando perfil"). Antes se creaba un duplicado. | **ALTA** (pre-check obligatorio) | `20261010000100:51`; `lib/hooks/useAuth.ts:98-102,271-286`; `whatsapp-otp/index.ts:261-265` |
| R4 | `VALIDATE CONSTRAINT channel_inventory_stock_sane` aborta la migración si alguna fila de producción tiene `sold > stock` o un valor negativo. Después, la app legada que sobrevende ya no descuenta `sold` y **no se entera**: `sale.tsx:161-164` no revisa el error del UPDATE. | **MEDIA-ALTA** | `20261002000300:46-47` |
| R5 | `f360.reservations.customer_id → public.customers ON DELETE RESTRICT`. `delete-account` borra la ficha sin revisar el error, así que una clienta con apartados se quedaría sin poder borrar su ficha. | MEDIA (cuando haya apartados en prod) | `20261007001100:16`; `functions/delete-account/index.ts:76` |
| R6 | `f360.target_by_key()` **rechaza todo target `is_production`**. Lo usan homologación, conteo de apertura, ingestión de pedidos, sync de stock y vínculos. F5 ("conteo real en producción", webhooks reales) **necesita una migración nueva** que habilite producción. Hoy funciona como una salvaguarda deliberada. | Informativo / bloqueo para F5 | `20260928000100:166-173`; usos en 15 archivos |
| R7 | **La lista de "9 migraciones con datos de staging" del plan no coincide con el código:** <ul><li>`20260930000100`, `20261007000100`, `20261007000900`, `20261007001300` y `20261007001400` **no insertan filas**.</li><li>Las que sí traen datos de ambiente son `20261007002500` y `20261007002600` (prefijo `[STAGING] `), `20261009000300` (no-op en prod), `20261010000100` (backfills sobre clientas reales + `pii_viewers` por nombre) y `20261003000100` (fila de sistema "En camino" con un id distinto por proyecto).</li></ul> | Corrección del plan | §2 |
| R8 | **Ningún archivo necesita partirse para producción.** Todas las líneas de ambiente son no-op en prod o se compensan con el script de datos de producción (§5). Recomendación: aplicar los 65 archivos **sin editar** (la historia queda idéntica a staging) y corregir con el script y, para R1 a R5, con decisiones previas o migraciones nuevas. | Recomendación | §4 |

---

## 1. Tabla por migración (orden de aplicación)

**Leyenda de clase:**
- **SCHEMA:** solo DDL, funciones o privilegios.
- **ENV-DATA:** filas propias de un ambiente.
- **MIXED:** ambas.
- **Config** (dentro de SCHEMA): semillas que valen igual en todos los ambientes.

**Tablas de la app:** el esquema `public` que usa la app publicada o sus Edge Functions.

| # | Archivo | Propósito | Clase | ¿Toca tablas de la app? | Riesgo para la app viva | Qué cambia para prod |
|---|---|---|---|---|---|---|
| 1 | `20260925000100_s00a_a1_revoke_public_rpc` | S0.0A-A1: quita EXECUTE (PUBLIC/anon/authenticated) a 6 funciones internas de lealtad/OTP; `ALTER DEFAULT PRIVILEGES` del rol postgres | SCHEMA (privilegios) | Sí, funciones (no tablas): `fx_add_points`, `award_birthday_points`, `award_referral_points`, `check_free_pair_reward`, `run_annual_tier_review`, `delete_expired_otps` (REVOKE; `service_role` conserva) | **Bajo.** La app no las llama como cliente: el único `.rpc` es `loyalty-credit` con service role (`functions/loyalty-credit/index.ts:170`). `fx_aplicar_creditos_pendientes` es definer (baseline l.228). Efecto lateral: toda función que se cree a mano en prod después ya no será ejecutable por anon/authenticated sin un GRANT explícito. | Nada. **No** es parte del runbook A2. Va primero (las migraciones siguientes asumen su default ACL). |
| 2 | `20260925010000_f360_admin_v1_inventory_core` | Esquema `f360`, roles, catálogo, ubicaciones, libro de inventario y RPCs; policy de subida en `product-images` | SCHEMA | Indirecto: FK `f360.locations.legacy_channel_id → public.channels` (`ON DELETE SET NULL`); policy nueva INSERT en `storage.objects` | Ninguno. El bucket `product-images` existe en prod (`audit/SCHEMA_AUDIT.md:26`). | Nada |
| 3 | `20260926000100_f360_p21_product_master` | Modelo/color/talla, códigos y SKU, fotos por color, 4 categorías | SCHEMA + config (`f360.categories`, l.17-19) | No | Ninguno | Nada. La copia de categorías se hace por `key` (upsert). |
| 4 | `20260927000100_f360_p21b_media_path_guard` | Guard de rutas de fotos (verifica `storage.objects`) + único `storage_path` | SCHEMA | Lee `storage.objects` | Ninguno | Nada. Las fotos deben existir en el storage de prod (F4.4). |
| 5 | `20260927010000_f360_p22_woo_publishing` | Targets Woo, links, jobs de publicación | SCHEMA | No | Ninguno. `resolve_target(NULL)` exige **un solo** target activo. | Nada (el target real va en el script, §5) |
| 6 | `20260927010100_f360_p22_job_order` | Orden determinista de jobs (`seq`) | SCHEMA | No | Ninguno | Nada |
| 7 | `20260928000100_f360_p23a_stock_sync_orders` | Cola de stock, pedidos Woo, excepciones, conciliación; `f360.target_by_key` **rechaza producción** | SCHEMA | No | Ninguno | Nada ahora. F5 necesita una migración nueva que habilite el target de producción (R6). |
| 8 | `20260928000200_f360_p23a_fix_refund_check` | Fix de deduplicación de reembolsos | SCHEMA (CREATE OR REPLACE) | No | Ninguno | Nada (sin `.down`: el rollback es la versión anterior) |
| 9 | `20260928000300_f360_p23a_fix_issue_list` | Fix de columna ambigua | SCHEMA | No | Ninguno | Nada (sin `.down`) |
| 10 | `20260928000400_f360_p23a_fix_delivery_dedupe` | Fix de deduplicación de webhooks | SCHEMA | No | Ninguno | Nada (sin `.down`) |
| 11 | `20260929000100_f360_b4_growth_plan` | Plan de crecimiento (supuestos) | SCHEMA | No | Ninguno | Nada |
| 12 | `20260929000200_f360_audit_message` | Mensaje genérico append-only | SCHEMA | No | Ninguno | Nada (sin `.down`) |
| 13 | `20260930000100_f360_c1_locations_roles` | Rol `seller`, `ledger_authority`, asignaciones, `access_changes`, RPCs de dueña | **SCHEMA** (no inserta roles ni ubicaciones: el plan F1 dice lo contrario) | Lee `public.channels` y `auth.users` | Ninguno | Nada. Roles y ubicaciones llegan por el script y la copia. |
| 14 | `20260930000200_f360_c2_legacy_mapping` | Propuesta de mapeo desde `channel_inventory` (solo lectura) | SCHEMA | Lee `channel_inventory` | Ninguno | Nada |
| 15 | `20261001000100_f360_s02_seller_sessions` | Turno de vendedora: PIN bcrypt, sesiones, auditoría | SCHEMA | No | Ninguno. Requiere `pgcrypto` en `extensions` (prod ✔ baseline l.34). | Nada |
| 16 | `20261001000200_f360_s02_persist_denials` | Fix: los rechazos quedan auditados | SCHEMA | No | Ninguno | Nada (sin `.down`) |
| 17 | `20261002000100_s05_loyalty_apply` | Camino único de lealtad `public.loyalty_apply` (solo service) + `public.loyalty_apply_audit` | SCHEMA | **Sí**: `transactions` +4 columnas nulas (`ref_type`, `ref_id`, `idempotency_key`, `actor`) + índice único parcial; tabla nueva `public.loyalty_apply_audit` (RLS sin políticas, REVOKE) | **Bajo.** Aditivo; el índice es sobre una columna nueva (todo NULL), así que no puede fallar. Las Edge Functions de prod (`claim-sale`, `loyalty-credit`, `woocommerce-webhook`) siguen insertando como hoy. | Nada |
| 18 | `20261002000200_s05_loyalty_apply_search_path` | `search_path` de `loyalty_apply` | SCHEMA | No | Ninguno | Nada (sin `.down`) |
| 19 | `20261002000300_s03_store_sale_legacy` | Venta atómica en tienda legada (RPC), `public.offline_sale_items`, reclamo atómico, CHECK de existencias | SCHEMA | **Sí**: `offline_sales` +10 columnas (aditivas) + índice único parcial; tabla nueva `offline_sale_items`; **CHECK + VALIDATE en `channel_inventory`** | **MEDIO-ALTO (R4).** <ul><li>El VALIDATE aborta si hay filas inválidas.</li><li>Cambio de conducta: la sobreventa legada ya no descuenta y el error se ignora en `sale.tsx:161-164`.</li><li>FKs nuevas a `f360.locations` y `auth.users`: aditivas.</li></ul> | Sin editar. Pre-check P-3 (§3). Si hay filas inválidas, Carolina las corrige antes de F4. |
| 20 | `20261003000100_f360_transfers` | Traslados + ubicación de sistema "En camino" | **MIXED**: `INSERT` de "En camino" con `gen_random_uuid()` (l.25-26) | No | Ninguno para la app. **Riesgo de copia:** el id de "En camino" es distinto en cada proyecto (índice `locations_single_transit`), así que la copia "mismos ids" choca. | No partir (la fila es necesaria). En F4: alinear el id con el de `faltx…` antes de copiar (§5.8). |
| 21 | `20261003000200_f360_transfers_safeupdate` | Fix `pg_safeupdate` | SCHEMA | No | Ninguno | Nada (sin `.down`) |
| 22 | `20261004000100_f360_c3_cutover_and_f360_sale` | Corte legacy→f360 por conteo, rama F360 de la venta, congelamiento legado | SCHEMA | **Sí**: trigger `channel_inventory_freeze` (BEFORE I/U/D, definer); trigger `offline_sales_client_guard` (BEFORE INSERT, **invoker**); +`offline_sale_items.variant_id`, +`offline_sales.sale_event_id` | **ALTO si A2 no está aplicado (R2).** <ul><li>El congelamiento no tiene efecto hasta que una ubicación ligada a un `channel` real entre en corte. Desde ese momento la app legada no puede vender en esa tienda: es el diseño.</li><li>`claim-sale` inserta como `service_role`, así que el guard no lo afecta.</li></ul> | Sin editar. Antes de este grupo: **A2 por su runbook**, o el GRANT de compatibilidad de §5.9. |
| 23 | `20261004000200_f360_c3_count_reopens` | Fix de conteo en verificación | SCHEMA | No | Ninguno | Nada (sin `.down`) |
| 24 | `20261004000300_f360_c3_complete_alias_fix` | Fix de alias | SCHEMA | Lee `channel_inventory` | Ninguno | Nada (sin `.down`) |
| 25 | `20261004000400_f360_c3_sales_read_model` | Vista de ventas (lee `offline_sales`, `transactions`, `customers` con teléfono enmascarado) | SCHEMA | Solo lectura | Ninguno | Nada |
| 26 | `20261005000100_f360_currency_prices` | Precios por moneda; semillas MXN/COP/USD y sugerencias de Mario | SCHEMA + config (l.23-26, l.44-45) | No | Ninguno | Nada. Las cifras de `price_suggestions` son de negocio y valen igual en prod. La copia es por clave natural. |
| 27 | `20261006000100_f360_woo_stock_schedule` | `CREATE EXTENSION pg_net`; cron `f360-woo-stock-push` cada minuto (Vault `f360_sync_*`) | SCHEMA + cron | No | **Bajo:** instala `pg_net` (nuevo en prod) y un tick por minuto que no hace nada sin secretos | Nada. **No** cargar `f360_sync_url`/`f360_sync_secret` hasta F5 (D-1). |
| 28 | `20261006000200_f360_n2_fulfillment_location_guard` | Un canal no puede salir de "En camino" (bloque DO de verificación + trigger) | SCHEMA | No | Ninguno | Nada |
| 29 | `20261007000100_f360_d2_legacy_homologation` | Homologación del catálogo Woo legado; **`DEFAULT 'woo_staging4'`** en `f360_legacy_homologation` (l.197) | SCHEMA (default de staging) | No | Ninguno para la app. En prod la pantalla falla con un target de producción (R6). | Sin editar. El admin debe pasar la clave explícita: hoy `admin-web/src/lib/f360.ts:179` usa `'woo_staging4'`. Decidir cómo se re-ancla la homologación (Q4). |
| 30 | `20261007000200_f360_d2_legacy_channel_links` | Reglas para variaciones legadas adoptadas | SCHEMA | No | Ninguno | Nada |
| 31 | `20261007000300_f360_d2_legacy_sources` | Fuentes legadas por color (excluye targets de prod) | SCHEMA | No | Ninguno | Nada |
| 32 | `20261007000400_f360_color_hex` | Muestra de color manual | SCHEMA | No | Ninguno | Nada |
| 33 | `20261007000500_f360_product_archive` | Archivar/reactivar un modelo | SCHEMA | No | Ninguno | Nada |
| 34 | `20261007000600_f360_inventory_adjustment` | Ajuste manual auditado | SCHEMA | No | Ninguno | Nada |
| 35 | `20261007000700_f360_d3_opening_count` | Conteo de apertura (`f360_opening_start` usa `target_by_key`, **rechaza prod**) | SCHEMA | No | Ninguno | Nada ahora. F5 ("conteo real en producción") requiere habilitarlo (R6). |
| 36 | `20261007000800_f360_catalog_tidy` | Quitar color, lista de modelos | SCHEMA | No | Ninguno | Nada |
| 37 | `20261007000900_f360_d4_opening_load_links` | Carga del conteo, vínculos legados, visibilidad; **`DEFAULT 'woo_staging4'`** en `f360_legacy_channel_state` (l.202) | SCHEMA (default de staging) | No | Ninguno | Igual que la fila 29: `admin-web/src/lib/f360.ts:211` y `conteo/ConteoClient.tsx:28` fijan `woo_staging4`. |
| 38 | `20261007001000_f360_stores_rename_color` | Renombrar color; canales legados disponibles (lee `channels` y `channel_inventory`) | SCHEMA | Solo lectura | Ninguno | Nada |
| 39 | `20261007001100_f360_reservations` | Apartado Gold; cron `f360-reservations-expire` cada minuto; `f360_store_availability` para anon | SCHEMA + cron | **Sí (FK):** `f360.reservations.customer_id → customers ON DELETE RESTRICT` | **MEDIO (R5)** en cuanto exista el primer apartado en prod | Fix-forward (nueva migración o ajuste de `delete-account`) antes de habilitar apartados en prod |
| 40 | `20261007001200_f360_reserve_web` | `f360_gold_check` (solo service; teléfono exacto) | SCHEMA | Solo lectura | Ninguno | Nada |
| 41 | `20261007001300_f360_reservations_app` | Push a vendedoras (outbox), cron `f360-push-retry`, Vault `f360_push_*` | SCHEMA + cron | Lee `push_tokens` y `customers` | Bajo (no-op sin Vault) | Nada. **No inserta datos** (el plan F1 lo lista por error). |
| 42 | `20261007001400_f360_legacy_content_push` | Contenido F360 → productos Woo legados; **rechaza targets de prod** (l.30) | SCHEMA | No | Ninguno | Nada. **No inserta datos.** En prod queda bloqueado por diseño hasta que haya una aprobación aparte. |
| 43 | `20261007001500_f360_make_to_order` | Sobre pedido | SCHEMA | No | Ninguno | Nada |
| 44 | `20261007001600_f360_make_to_order_resend` | Re-encola los links activos (una sola vez) | MIXED (operacional) | No | Ninguno (en prod hay 0 links: no-op) | Nada |
| 45 | `20261007001700_f360_get_product_make_to_order` | `f360_get_product` + sobre pedido | SCHEMA | No | Ninguno | Nada |
| 46 | `20261007001800_f360_custom_requests` | Pedidos a la medida | SCHEMA | No | Ninguno | Nada |
| 47 | `20261007001900_f360_legacy_consolidation` | Un producto Woo por modelo (rechaza prod) | SCHEMA | No | Ninguno | Nada |
| 48 | `20261007002000_f360_consolidation_retry` | Reintento de consolidación | SCHEMA | No | Ninguno | Nada |
| 49 | `20261007002100_f360_stores_as_warehouses` | Tiendas como bodega en línea + re-encolado (una sola vez) | MIXED (operacional) | No | Ninguno (no-op en prod) | Nada |
| 50 | `20261007002200_f360_storefront_catalog` | Catálogo para la tienda (anon, definer; lee `offline_sale_items`) | SCHEMA | Solo lectura | Ninguno | Nada. La Edge Function `f360-store-reserve/handler.ts:61,109` fija `woo_staging4` (código, F5). |
| 51 | `20261007002300_f360_storefront_searches` | Búsquedas más frecuentes | SCHEMA | No | Ninguno | Nada |
| 52 | `20261007002400_f360_scarcity_guard` | Escasez solo con inventario certificado | SCHEMA | No | Ninguno | Nada |
| 53 | `20261007002500_f360_email_outbox` | Correos (outbox, cron `f360-email-retry`, Vault `f360_email_*`) + **`notification_recipients('custom_request', info@…, '[STAGING] ')`** (l.16) | **MIXED (ENV-DATA)** | No | Bajo: en prod los asuntos saldrían con "[STAGING]" | Sin editar. Script de prod: prefijo `''` (§5.6) |
| 54 | `20261007002600_f360_customer_cases` | Bandeja de clientas + **`notification_recipients('customer_case', …, '[STAGING] ')`** (l.34) | **MIXED (ENV-DATA)** | No | Igual que la fila 53 | Igual que la fila 53 |
| 55 | `20261008000100_f360_g1_commerce_facts` | Hechos comerciales (vistas sobre `transactions`, `loyalty_cards`, `offline_sales`), cron `f360-commerce-poll` cada 15 min | SCHEMA + cron | Solo lectura | Ninguno. `commerce_source_health` excluye targets de prod (l.455). | Nada (no-op sin Vault) |
| 56 | `20261008000200_f360_g1_paid_value_unknown` | Fix de vista | SCHEMA | Solo lectura | Ninguno | Nada |
| 57 | `20261008000300_f360_g2_identity_resolution` | Vistas de identidad canónica | SCHEMA | Lee `offline_sale_items` | Ninguno | Nada |
| 58 | `20261009000100_f360_mto_ten_business_days` | Promesa de 10 días hábiles | SCHEMA | No | Ninguno | Nada |
| 59 | `20261009000200_f360_pay_links` | Link de pago (service) | SCHEMA | No | Ninguno | Nada |
| 60 | `20261009000300_f360_test_targets` | `is_test`; **UPDATE `woo_staging4`/`woo_local`**; cancela los "sobre pedido" de staging4 (l.12, l.15-16) | **MIXED (ENV-DATA)** | No | Ninguno: en prod afecta 0 filas | Sin editar (no-op). Si se copia el target `woo_staging4`, llega con `is_test = true`. |
| 61 | `20261010000100_f360_crm_c1_customer_profile` | CRM C1, en detalle: <ul><li>teléfono normalizado e índice único;</li><li>columnas de perfil;</li><li>verificación, consentimiento, token QR y retención de puntos;</li><li>RPCs de vendedora y de admin.</li></ul>**Datos:** backfill `UPDATE customers` (l.80), backfill de verificaciones (l.116-118), `consent_purposes` (config), **`customer_pii_viewers` por `display_name`** (l.91-92) | **MIXED** | **Sí, de forma amplia:**<ul><li>`customers`: +6 columnas, 3 CHECK, **índice único normalizado**, triggers `customers_birthday_sync` y `customers_on_verified`, UPDATE masivo.</li><li>`loyalty_cards`: trigger BEFORE INSERT `loyalty_cards_server_token`.</li></ul> | **ALTO (R1, R3).**<ul><li>Puntos: el trigger fuerza 0/bronze, que es lo mismo que la app ya manda (`useAuth.ts:292-298`). Sin cambio económico.</li><li>`trg_aplicar_creditos_pendientes` (AFTER INSERT) sigue aplicando créditos pendientes.</li><li>`trg_update_tier` corre después (por orden alfabético) y da bronze.</li><li>En el UPDATE masivo, `customers` no tiene triggers previos en el baseline: bloqueo breve.</li><li>`pii_viewers` por nombre: en prod `user_roles` está vacío, así que es un no-op silencioso.</li></ul> | Sin editar. Antes: pre-checks P-1 y P-2; decisión Q1 (formato de token). Después: `pii_viewers` por correo (§5.4). **No rotar** las tarjetas legadas (`cards_with_legacy_token`): hoy todas las de prod son `FX-…` y funcionan con el escáner. |
| 62 | `20261010000200_f360_historical_sales` | Ventas históricas (resúmenes) | SCHEMA | Lee `offline_sales` | Ninguno | Nada |
| 63 | `20261010000300_f360_exec_dashboard` | Panel ejecutivo (lee `customers` y `loyalty_cards`; `incl_test` depende de que exista un target `is_production`) | SCHEMA | Solo lectura | Ninguno | Nada |
| 64 | `20261010000400_f360_opening_single_count` | Conteo de apertura en modo simple | SCHEMA | No | Ninguno | Nada |
| 65 | `20261010000500_f360_product_knowledge` | Ficha "Ajuste y talla" por modelo | SCHEMA | No | Ninguno | Nada |

**Funciones que usan la app y las Edge Functions de producción:**
- Ninguna migración F360 hace `CREATE OR REPLACE` de una función que exista en el baseline. Se verificó: las únicas funciones `public.*` no-`f360_*` que se crean son `loyalty_apply`, `loyalty_pairs_for_lines`, `loyalty_points_per_pair`, `channel_inventory_freeze_guard` y `offline_sales_client_guard`, y todas son nuevas.
- `my_customer_id()`, `my_role()` y `my_phone()` (helpers de RLS) **no se tocan**.
- Ninguna política RLS de `public.*` cambia: el único `CREATE POLICY` es sobre `storage.objects`.
- `claim-sale` sigue igual: escribe con service role, hace la búsqueda por `qr_code` exacto y no valida el formato (`functions/claim-sale/index.ts:174-178`).
- La app publicada (`lib/sellerSession.ts`) ya llama a `f360_me`, `f360_my_locations` y `f360_start_seller_shift`. Si esa versión está publicada, hoy esas llamadas fallan en prod y empezarían a responder tras F4. Confirmar la versión (Q8).

---

## 2. Correcciones al plan F1 (contradicciones encontradas)

1. **"9 traen datos de staging":**
   - **No insertan filas:** `20260930000100` (solo esquema), `20261007000100` y `20261007000900` (solo un `DEFAULT 'woo_staging4'` en la firma), `20261007001300` y `20261007001400` (solo esquema; la segunda incluso **rechaza** producción).
   - `20261005000100` trae semillas de **configuración** válidas para prod.
   - **Faltaban en la lista:** `20261003000100` (fila de sistema "En camino"), `20261007002500` y `20261007002600` (prefijo `[STAGING] `), y `20261007001600` y `20261007002100` (re-encolados de una sola vez, no-op en prod).
2. **"Las pruebas de compatibilidad ya existen en staging":** se corrieron con **A2 ya aplicado** en `faltx…` (`A2_PRODUCTION_RUNBOOK.md`, tabla de ensayo). El camino `anon` de la app (pre-login) **no** está cubierto por esas pruebas (R2).
3. **`crm/C1_DELIVERY.md:127`, "La app no necesita cambios":** es falso para el escáner de la vendedora (R1).
4. **F5, "el inventario arranca del conteo real en producción":** hoy es imposible sin una migración nueva, porque `f360_opening_start` rechaza targets de producción (R6).

---

## 3. Pre-checks de producción (solo lectura, antes de F2/F4)

Todos dentro de `BEGIN READ ONLY; … ROLLBACK;`. Devuelven conteos o ids, nunca teléfonos ni nombres.

| Id | Qué | Consulta (resumen) | Debe dar |
|---|---|---|---|
| P-1 | Duplicados por teléfono normalizado (R3) | Expresión equivalente a `f360.normalize_phone` para MX sobre `customers.phone`: <ul><li>quitar lo que no sea dígito;</li><li>`521`+10 → `+52`+10;</li><li>`52`+10 → `+52`+10;</li><li>`044`/`045`+10 → `+52`+10;</li><li>10 dígitos sin `+` → `+52`+10.</li></ul>Luego `GROUP BY norm HAVING count(*) > 1`. | 0 grupos. Si hay alguno, la migración 61 aborta: lista de ids para decisión D-C4 |
| P-2 | Clientas con teléfono guardado fuera de E.164 (R3) | `count(*) WHERE phone !~ '^\+\d{8,15}$'` | 0. Si hay, esas clientas no podrán darse de alta en la app tras la migración 61: normalizarlas antes (decisión) |
| P-3 | Existencias inválidas (R4) | `count(*) FROM channel_inventory WHERE stock < 0 OR sold < 0 OR sold > stock` | 0. Si no, la migración 19 aborta |
| P-4 | Colisiones de nombres | <ul><li>`to_regnamespace('f360')`</li><li>`to_regclass('public.offline_sale_items')` y `to_regclass('public.loyalty_apply_audit')`</li><li>funciones `public.f360_%`, `public.loyalty_apply`</li><li>columnas nuevas ya existentes: `customers.source`, `customers.postal_code`, `customers.birthday_day`, `offline_sales.idempotency_key`, `transactions.idempotency_key`</li></ul> | Todo NULL o 0 |
| P-5 | Deriva de esquema contra el baseline | Dump de esquema de prod comparado con `20260924000000_*` (F2) | Sin diferencias en `customers`, `loyalty_cards`, `offline_sales`, `channel_inventory`, `transactions` y en sus triggers y políticas |
| P-6 | Historia de migraciones | `supabase migration list --linked` (solo lectura) | Solo `20260924000000` y `20260924000001` aplicadas |
| P-7 | Extensiones y cron | `pg_extension` (`pg_cron`, `pgcrypto` en `extensions`, `supabase_vault`, `pg_net` disponible) y `cron.job` (nombres `f360-*` libres) | `pg_net` instalable; ningún job `f360-*` |
| P-8 | Bucket | `storage.buckets WHERE id = 'product-images'` y conteo de objetos `f360/%` | Existe, 0 objetos `f360/` |
| P-9 | Tarjetas | `count(*) FROM loyalty_cards WHERE qr_code NOT LIKE 'FX-%'` | 0 (confirma que todo QR actual pasa el escáner) |
| P-10 | Estado de A2 | Consulta P4 del runbook A2 (políticas `anon_*`) | Define la ruta de §4 (G4) |

---

## 4. Secuencia de aplicación recomendada en producción

Las migraciones dependen unas de otras en orden cronológico; no se reordenan. Los grupos son **puntos de control** dentro de un mismo `db push` (o de varios pushes con `--dry-run` previo, según la regla de la casa).

**A2 no es una de las 65:** vive en `supabase/pending/s00a/` y se aplica **solo por su runbook** (`docs/fuxia360/ops/A2_PRODUCTION_RUNBOOK.md`, pegando SQL; P5 del runbook), nunca con `db push`.

| Grupo | Archivos | Punto de control |
|---|---|---|
| **G0** | — | <ul><li>Pre-checks P-1 a P-10.</li><li>Respaldo completo de prod (PITR + dump).</li><li>Respaldo F0 de `faltx…`.</li><li>Decisiones Q1 a Q3 cerradas.</li></ul> |
| **G1** | #1 A1 | Las Edge Functions `loyalty-credit` y `birthday` siguen acreditando (R12 de `S0_0A_TEST_REPORT.md`) |
| **G2** | #2 a #16 (`20260925010000` → `20261001000200`) | Solo esquema `f360` + una policy de storage. La app no se entera. |
| **G3** | #17 a #19 (`s05`, `s03`) | Primer contacto con `public`: `transactions`, `offline_sales` y CHECK de `channel_inventory`. Smoke test de la app (ver la tarjeta, reclamar un código, venta legada logueada). |
| **A2** | por runbook | **Antes de G4**, si Mario elige la ruta A (§5.9). |
| **G4** | #20 a #25 (traslados y C3) | Triggers en `channel_inventory` y `offline_sales`. Smoke test: venta legada (logueada; y como anon si A2 no se aplicó y se usó el GRANT de compatibilidad). |
| **G5** | #26 a #60 (`20261005000100` → `20261009000300`) | Solo `f360`, `pg_net` y 5 jobs cron (no-op sin Vault). Verificar que `cron.job` tiene los 5 `f360-*`. |
| **G6** | #61 CRM C1 (+ la migración nueva de Q1, si se decide) | Alta de una clienta de prueba controlada **en F2, no en prod**. En prod: login de una clienta existente y escaneo de una tarjeta nueva (requiere Q1 resuelto). |
| **G7** | #62 a #65 | Panel, ventas históricas, ficha de ajuste |
| **G8** | Script de datos de producción (§5) | Conteos y `f360_me` de Carolina, Mario y Adrián |
| **G9** | Copia de datos maestros (§6) + fotos | Conteos origen = destino; cada `storage_path` existe |

**Otros puntos:**
- La migración 63 lee las columnas de la 61 (`customers.source`, `birthday_month`, `customer_pii_viewers`), así que **la 61 no se puede saltar** sin saltar también la 63.
- Si se decide diferir CRM, el corte natural es aplicar G1 a G5 y dejar G6 y G7 para otra ventana.
- Rollback: los 56 archivos `.down.sql` en `supabase/rollbacks/`, en orden inverso. Nueve fixes no tienen `.down` (#8-10, 12, 16, 18, 21, 23, 24): su rollback es la versión de la migración previa, y deshacer la migración "madre" los cubre.
- El rollback real de una ventana es el **respaldo de G0**.

---

## 5. Script de "datos de producción" (descrito, no ejecutado)

Corre una sola vez después de G7, como `service_role` o `postgres`, en una transacción. Los usuarios se ligan **por correo** (`auth.users.email`), nunca por id de staging.

1. **Ubicaciones:** no se crean aquí. Llegan con la copia (§6), con los mismos ids.
2. **Target real.** `INSERT f360.sales_targets` con estos valores:
   - `key = 'woo_production'`, `name = 'Tienda en línea'`, `base_url = 'https://fuxiaballerinas.com'`;
   - `is_production = true`, `is_test = false`;
   - `fulfillment_location_id` = id de "Bodega CDMX" (el copiado);
   - `active` según Q3.

   Mientras `target_by_key` rechace producción (R6), el target no se puede usar en sync, homologación ni conteo. Es intencional hasta F5.
3. **Categorías Woo reales.** `INSERT f360.woo_category_links` para `woo_production` con los `term_id` **verificados en fuxiaballerinas.com** (como `scripts/f360/woo_staging4_target.mjs:32-34`, pero contra la tienda real y solo lectura).
4. **Personas.**
   - `f360.user_roles` por correo: Carolina, Mario y Adrián, con el rol que decida Mario (Q5).
   - `f360.customer_pii_viewers` por correo: **solo Carolina y Mario** (decisión del 2026-10-05; sustituye la línea 91-92 de la migración 61, que en prod no inserta nada).
5. **Vendedoras:**
   - `user_roles` con rol `seller` y `location_assignments` por correo;
   - PIN con `f360_set_seller_pin` (RPC, lo hace una dueña).

   Nunca se copia `seller_credentials`.
6. **Correos:** `UPDATE f360.notification_recipients SET prefix = '' WHERE kind IN ('custom_request', 'customer_case');` y confirmar el destinatario `info@fuxiaballerinas.com`.
7. **Vault:** **nada en F4.** En F5, con aprobación aparte:
   - `f360_sync_url` / `f360_sync_secret`
   - `f360_push_url` / `f360_push_secret`
   - `f360_email_url` / `f360_email_secret`
8. **"En camino":** antes de copiar `f360.locations`: `UPDATE f360.locations SET id = '<id de En camino en faltx…>' WHERE type = 'transit';`. Es seguro solo mientras ninguna fila la referencie, es decir, justo después de G7.
9. **Compatibilidad con la app sin A2** (solo si se elige la ruta B en Q2): `GRANT EXECUTE ON FUNCTION public.f360_legacy_channel_frozen(uuid) TO anon;`.
   - La función es definer y devuelve solo `'migrada'`, `'en_corte'` o NULL.
   - Se revoca al aplicar A2.
10. **Verificación:**
    - `f360_me()` funciona con cada cuenta;
    - `SELECT count(*) FROM f360.sales_targets WHERE active` = lo esperado;
    - `cron.job` muestra 5 jobs `f360-*`.

**Fuera de las migraciones, pero bloqueante para F4/F5 (código):**
- `admin-web/src/lib/f360.ts:179,211`, `admin-web/src/app/(app)/conteo/ConteoClient.tsx:28` y `admin-web/src/app/(app)/actions.ts:89` fijan `woo_staging4`.
- `fuxia-native/supabase/functions/f360-store-reserve/handler.ts:61,109` fija `woo_staging4`.
- El guard de entorno del admin (F4.7).

Hay que parametrizar todo esto con una variable de entorno.

---

## 6. Datos maestros: qué se copia con los mismos ids y qué nunca

**Reglas comunes:**
- Copiar en orden de FKs, en una transacción, después del script §5.
- **Columnas que apuntan a `auth.users` de staging:**
  - con FK: `products.created_by`, `product_media.created_by`, `legacy_woo_map.decided_by`, `growth_plan_changes.by_user`, `sync_jobs.requested_by`, `opening_counts.approved_by`;
  - sin FK: `*_by`, `actor_auth_user_id`, `by_user` en las tablas de historial.

  Hay que **remapearlas por correo** (tabla temporal `staging_uid → prod_uid`) o ponerlas en NULL. Con FK, un id de staging **viola la FK**; sin FK, queda una atribución colgante.
- **`f360.locations.legacy_channel_id`** apunta a `public.channels` de staging (canales de laboratorio). Hay que remapearlo **por nombre** a los canales reales de prod o dejarlo en NULL. El trigger `locations_guard_ledger_authority` rechaza un INSERT con `ledger_authority = 'f360'` y un canal ligado: decidir antes (Q6).

| Copiar con los mismos ids | Notas |
|---|---|
| `f360.categories`, `f360.currencies`, `f360.price_suggestions`, `f360.consent_purposes` | Ya existen por semilla: hacer upsert por clave natural |
| `f360.products`, `product_sizes`, `product_colors`, `product_variants` | Núcleo del catálogo (62 modelos y 894 variantes, según el plan). Los códigos y SKU son inmutables tras publicar. |
| `f360.product_media` + archivos `product-images/f360/**` | Verificar cada `storage_path` en destino (575 fotos) |
| `f360.product_prices`, `price_changes`, `product_status_changes`, `catalog_changes` | Historial: remapear usuarios |
| `f360.product_knowledge`, `product_knowledge_history` | Fichas de "Ajuste y talla" |
| `f360.locations` (8) | Remapear `legacy_channel_id`; alinear "En camino" (§5.8) |
| `f360.legacy_woo_map`, `legacy_woo_map_log` (666 confirmados) | **Solo si se decide Q4**: llevan el `target_id` de `woo_staging4`, así que exigen copiar ese target como histórico (`active = false`, `is_test = true`) o re-anclarlos a `woo_production` tras la verificación 1:1 de F5 |
| `f360.historical_sales`, `historical_sales_log` (las reales) | Excluir las de prueba con Carolina |
| `f360.growth_plans`, `growth_scenarios`, `reported_figures`, `growth_plan_changes` | Si Mario las quiere en prod |

| **Nunca copiar** | Por qué |
|---|---|
| `f360.user_roles`, `location_assignments`, `customer_pii_viewers`, `seller_credentials`, `seller_sessions`, `seller_auth_events`, `access_changes` | Ids de `auth.users` de staging: se recrean por correo (§5) |
| `f360.sales_targets` (salvo lo que decida Q4), `woo_category_links`, `woo_product_links`, `woo_variant_links`, `woo_media_links`, `retired_woo_links`, `legacy_consolidations`, `legacy_content_pushes`, `woo_visibility_requests`, `sync_jobs`, `sync_job_steps` | Son ids de **staging4**. Los modelos publicados en staging4 no existen en la tienda real (F5) |
| `f360.inventory_events`, `inventory_movements`, `inventory_balances`, `opening_counts*`, `location_cutovers`, `cutover_*`, `transfers*`, `legacy_inventory_map` | El inventario arranca del conteo real (F5). `legacy_inventory_map` apunta a `channel_inventory` de staging. Ver Q7 si Carolina capturó inventario real. |
| `f360.woo_orders`, `woo_order_lines`, `woo_webhook_deliveries`, `sync_exceptions`, `stock_sync_queue`, `stock_sync_log`, `reconciliation_runs`, `made_to_order`, `online_store_shipments`, `commerce_*` | Pedidos de prueba de staging4 |
| `f360.reservations`, `push_outbox`, `email_outbox`, `custom_requests`, `customer_cases`, `storefront_searches` | Prueba o PII (Q6 del plan maestro) |
| `f360.customer_verifications`, `customer_consent_events`, `card_token_events`, `loyalty_holds`, `customer_access_log` | Se derivan de las clientas de prod (la migración 61 hace el backfill) |
| `public.customers`, `loyalty_cards`, `transactions`, `purchase_items`, `offline_sales`, `offline_sale_items`, `channels`, `channel_inventory`, `staff`, … | Prod es la fuente; staging tiene 6 clientas de prueba |
| `public.product_image_overrides` | Está en el respaldo F0, pero **prod tiene sus propios datos** (tabla de la app, por `wc_product_id`). No sobrescribir: comparar y decidir (Q9). |
| Cualquier fila `ZZ…` o `is_test` | Regla F4.5 |

---

## 7. Prerrequisitos y extensiones

| Requisito | Estado en prod (baseline) | Usado por |
|---|---|---|
| `pgcrypto` en `extensions` | ✔ l.34 | `extensions.crypt`, `gen_salt`, `gen_random_bytes`, `digest` (#15, 16, 19, 22, 39, 61) |
| `pg_cron` | ✔ l.16 | 5 jobs:<ul><li>`f360-woo-stock-push` (1 min)</li><li>`f360-reservations-expire` (1 min)</li><li>`f360-push-retry` (1 min)</li><li>`f360-email-retry` (5 min)</li><li>`f360-commerce-poll` (15 min)</li></ul> |
| `pg_net` | ✘. Lo crea la #27 (`CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions`) | ticks de sync, push, correo y comercio |
| `supabase_vault` | ✔ l.41 | 6 secretos `f360_*` (vacíos hasta F5: los ticks no hacen nada) |
| Bucket `product-images` (público) | ✔ (SCHEMA_AUDIT #11) | policy "f360 operators upload product images" (#2), `f360_add_media` (#4) |
| Cuentas `auth.users` de Carolina, Mario y Adrián en prod | Existen como cuentas de la app (F3) | `user_roles`, `customer_pii_viewers` |
| Edge Functions `f360-*` con sus secretos (`WOO_TARGET_KEY`…) | — | F5, no F4 |

**Objetos que guardan ids de `auth.users` de staging:**
- FK: `user_roles`, `location_assignments`, `seller_credentials`, `seller_sessions`, `customer_pii_viewers`, `push_outbox`, `products.created_by`, `product_media.created_by`, `inventory_events.actor_auth_user_id`, `sync_jobs.requested_by`, `sync_exceptions.resolved_by`, `growth_plan_changes.by_user`, `access_changes.by_user`, `transfers.requested_by`, `legacy_woo_map.decided_by`, `opening_counts.approved_by`, `public.offline_sales.seller_auth_user_id`.
- Sin FK: los campos `*_by` y `actor_*` de los historiales.

Ninguna **migración** fija un uuid de usuario. La única referencia por persona es `display_name IN ('Carolina', 'Mario')` (#61, l.91-92).

---

## 8. Preguntas abiertas para Mario

| # | Pregunta | Por qué importa |
|---|---|---|
| Q1 | ¿Cómo resolvemos el QR? Tres opciones: <ul><li>**(a)** Una migración nueva, igual en staging y prod antes de G6, que genere tokens `FX-` + hex aleatorio, compatibles con el escáner publicado. Ajusta también la vista `cards_with_legacy_token`.</li><li>**(b)** Publicar una versión de la app que acepte `FX1-` y esperar a que se adopte antes de G6.</li><li>**(c)** No crear el trigger del token en prod hasta (b).</li></ul> | R1: sin esto, las clientas nuevas no se pueden escanear en tienda |
| Q2 | ¿A2 se aplica por su runbook **antes** de G4, con la versión que oculta "Soy vendedora" ya adoptada y cuentas de vendedora con `role = 'staff'`? ¿O se usa el GRANT de compatibilidad (§5.9) hasta A2? | R2: la venta pre-login fallaría |
| Q3 | ¿`woo_production` se crea **activo** o **inactivo** en F4? Activo hace que `online_location()` y `resolve_target()` lo usen, aunque `target_by_key` lo bloquee. | Comportamiento de las pantallas del admin |
| Q4 | Homologación: <ul><li>¿se copian los 666 confirmados ligados al target `woo_staging4` (copiado como histórico, `is_test`, inactivo)?</li><li>¿o se re-anclan a `woo_production` tras la verificación 1:1 de F5?</li></ul> | FK `legacy_woo_map.target_id`; la pantalla de homologación necesita la clave |
| Q5 | Roles en prod: ¿Carolina es owner u operator? ¿Adrián es owner? | §5.4 |
| Q6 | Ubicaciones con tienda legada: <ul><li>¿se ligan a los `channels` reales de prod, por nombre?</li><li>¿con `ledger_authority = 'legacy'` hasta su corte?</li></ul>Ligar una tienda real y cortarla **congela la venta legada de la app en esa tienda**. | Trigger de congelamiento (#22) |
| Q7 | ¿El inventario que Carolina capturó en `faltx…` es real (para llevarlo) o se reemplaza por el conteo real de F5? Según el plan, el conteo. Confirmar. | §6 |
| Q8 | ¿Qué versión de la app está publicada? ¿Incluye `lib/sellerSession.ts` (llamadas a `f360_*`) y el escáner con el filtro `FX-`? | R1 y la tabla §1 |
| Q9 | `public.product_image_overrides`: ¿los cambios de staging se llevan a prod o se respeta lo de prod? | Tabla de la app con datos reales |
| Q10 | Pre-checks P-1, P-2 y P-3 con resultado distinto de 0: ¿quién decide cómo se corrigen las fichas duplicadas, los teléfonos sin formato y las existencias imposibles? Carolina con Mario, en lista por id. | La migración aborta o la app cambia de conducta |
| Q11 | `delete-account` frente a los apartados (R5): ¿se borra el apartado con la clienta, o se anonimiza la ficha? Hace falta una migración o un cambio de función antes de abrir los apartados en prod. | Derecho de borrado |
| Q12 | Habilitar producción en `target_by_key` y en `f360_opening_start` (R6): ¿va en F5 como una migración propia con aprobación aparte (D-1)? | El conteo real y los webhooks en prod lo requieren |
