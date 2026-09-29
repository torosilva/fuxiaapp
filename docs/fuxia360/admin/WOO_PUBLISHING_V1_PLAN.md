# Fuxia 360 — Product Master + WooCommerce Publishing V1 (PLAN; nothing implemented)

**Status:** for approval. No code, migration, deployment, secret or WooCommerce change was made.
**DW1 resolved (2026-09-24):** canonical shoe sizes are **Colombian sizes** (e.g. `35–40`), exactly as the live Woo catalog uses them. Mexican centimeter equivalents are a later **display/guidance layer only**, never a variant identity. The earlier `22–27` half-size default is **withdrawn** for these products.
**Evidence base (2026-09-24):**
- repo code: `fuxia-native/services/WooCommerceService.ts`, `supabase/functions/woocommerce-{webhook,proxy}`, `app/admin/import-woo.tsx`, f360 migration `20260925010000`, `admin-web/`;
- the Sprint 0 audit and the live reconciliation;
- a **read-only** inspection of the live store through the **public** Store API and public product pages (no credentials, no writes; raw data kept in the session scratchpad, not the repo).

---

## A. Current-state architecture

| Piece | Today |
|---|---|
| Product master | **WooCommerce (manual, by Adrián).** Fuxia 360 (staging) has products/colors/sizes/variants but no commercial fields and no link to Woo |
| Inventory | Fuxia 360 ledger (staging): receipts, balances by variant × location. Legacy `channel_inventory` for stores/bazaars (POS). **Woo: no stock tracking** (see B) |
| Online orders | Woo checkout → `woocommerce-webhook` (HMAC) → **loyalty only**. No inventory effect anywhere (INTEGRATION_AUDIT §2) |
| App catalog | Mobile app reads the public Store API; images can be overridden via `product_image_overrides` |
| Woo access from Supabase | `woocommerce-proxy`: read products/customers + POST customers, called with the **anon key** (P0-7). `my-orders`, `backfill-orders` read orders with server-side keys |
| Storefront | WordPress + **Bricks theme (+ child)**, WooCommerce, SiteGround cache (`sg-cachepress`), Woo Discount Rules, Facebook for WooCommerce, GTM, customer reviews, PayPal, WhatsApp button |
| Admin | Fuxia 360 Admin V1 (`admin-web/`, staging); mobile admin screens (legacy) |

## B. Current Woo product / variation model (observed live)

- **129 products, all `variable`.**
- **One Woo product per color:** the color is in the product name ("Slingback punta afilada **nude**", "Peep toe **topo**"). 128 of 129 vary **only by size**.
- **Size attribute:** global `pa_medida` ("Medida"). **Terms in use: `35, 36, 37, 38, 39, 40` only** (6 variations per product). These are **Colombian sizes, the correct canonical system** (DW1).
- **The real structural problem:** each **color** is a separate Woo product, and sizes are variations inside it (`Macarena Nude` → 35…40; `Macarena Negro` → 35…40). Customers never see one model with a color choice.
- **Color attribute:** global `pa_color` exists (terms Café, Dorado, Negro, Taupe, Verde, Vino). It's used by only 2 products (e.g. "Mules Colectiva": 3 colors × 6 sizes = 24 variations, including stray "any color" variations). One product uses a non-global "Colores" attribute.
- **Stock:**
  - every variation shows `max_qty: ''`, empty `availability_html` and `is_in_stock: true`, and the Store API shows `low_stock_remaining: null`;
  - **so Woo is not managing per-variation stock today** (strongly indicated; confirm in the Woo admin);
  - checkout never runs out; fulfillment is handled manually.
- **Images:**
  - 1–8 images per product (parent gallery);
  - variation images all equal the main image, so **nothing changes by color**.
- **Selectors:** core Woo `variations_form` dropdowns ("Elige una opción"); no swatch plugin.
- **Categories:** Ballerinas (83), Sandalia Alta (22), Sandalia Plana (19), Botas (5). **Tags: none used.** No "collection" taxonomy visible.
- **Prices:** MXN, whole pesos (e.g. 3000); 1 product on sale. SKUs are on 92/129, free-form (`SUE-CUCARRON-TPE-1`). Descriptions: long + short (often identical).

## C. Gap analysis

| Need | Fuxia 360 today | Gap |
|---|---|---|
| Commercial info (description, short description, price, sale price) | — | add |
| Multiple photos **per color** | one `image_path` per color | add a media table |
| Woo category | free-text `category` | map to the 4 real Woo categories |
| Tags / collections | — | **not used in the live catalog. Don't add in V1** |
| Size system | per-product labels; the UI default is still MX `22–27` by halves (Admin V1 D6) | **DW1 resolved:** canonical = Colombian sizes (`35–40`). Change the default size set to 35–40. Mexican cm equivalents are a later display layer (no new inventory identity) |
| Woo IDs, sync state, errors | nullable `wc_product_id`, `wc_variation_id` columns, unused | mapping per Woo environment + job/audit tables |
| Online stock authority | the ledger (Bodega CDMX) | publish ATS to Woo; ingest Woo sales back into the ledger |
| One model, many colors in the store | the store has one product per color | new F360 products are published as **one** variable product (color × size) |
| Color/size swatches, per-color images, disabled sold-out sizes | dropdowns; identical images | a small storefront change (§I) |
| Woo test environment | none | **required before any real Woo write (DW2)** |

## D. Proposed Fuxia data-model changes (additive migration; the ledger is untouched)

| Object | Change | Why |
|---|---|---|
| `f360.products` | `+ description text`, `+ short_description text`, `+ regular_price numeric(10,2)`, `+ sale_price numeric(10,2) null`, `+ woo_category_key text` (one of the 4 real categories), `+ lifecycle text` (`draft` / `ready` / `archived`) | the fields the live catalog actually uses |
| `f360.product_media` (new) | `id, product_id, color_id null, storage_path, sort, alt, created_at` | multiple photos per color; the primary image = first photo of the first color |
| `f360.product_variants.sku` | filled deterministically: `F360-{PRODUCT}-{COLOR}-{SIZE}`, e.g. `F360-MACARENA-NUDE-37` (uppercase, accents removed, spaces → `-`). A per-product `sku_code` (default = slugified name, frozen at first publish) keeps SKUs stable if the display name changes | idempotent recovery via Woo `?sku=` lookup |
| `f360.sales_targets` (new) | `id, key` (`woo_test`, `woo_production`), `base_url, fulfillment_location_id` (V1: Bodega CDMX), `active` | the mapping is **per environment**: test-store ids ≠ production ids |
| `f360.woo_product_links` / `woo_variant_links` / `woo_media_links` / `woo_term_links` (new) | f360 id ↔ Woo id per target; variant links also hold `last_pushed_stock`, `last_pushed_at` | deterministic, idempotent re-publishing and stock pushes |
| `f360.publications` (new) | per product × target: `published_hash, last_success_at, last_error, woo_status` | Carolina's states (§H) |
| `f360.sync_jobs` + `f360.sync_job_steps` (new, append-only) | job: kind (`publish` / `stock` / `order`), status, attempts, idempotency key, requested_by, payload hash, diff summary. Steps: object, action, Woo id, result, error | audit: who published, what changed, partial failures |
| `f360.sync_exceptions` (new) | e.g. "online sale with no stock in Bodega", "Woo stock drift" | visible, never silent |
| Ledger | **No new tables.** Online sales use the existing `inventory_events` (`SALE`) + `inventory_movements` | D5: one ledger |

## E. Exact Fuxia → Woo mapping (new F360-managed products only)

| Fuxia | Woo |
|---|---|
| product (model) | **one** `variable` product. `name` = model name ("Macarena"); `slug`; `status` (DW3); `description`, `short_description`; `categories` = mapped category; `images` = all photos, color order; `sku` = `F360-{code}`; meta `_fuxia360_product_id`, `_fuxia360_managed=1` |
| color | term in global `pa_color` (reused if the name matches, e.g. "Negro"; created otherwise); product attribute `pa_color` (`variation: true`, visible) |
| size (canonical Colombian, e.g. `37`) | the **existing** term in global `pa_medida` (35–40 already exist; a new label, e.g. a future `41`, creates the term); product attribute `pa_medida` (`variation: true`). No duplicate size identity for Mexican equivalents |
| variant (color × size) | a variation with `attributes {pa_color, pa_medida}`, `sku` = F360 SKU, `regular_price` / `sale_price` from the product, `image` = the color's primary photo, **`manage_stock: true`, `stock_quantity` = ATS, `backorders: 'no'`** (make-to-order comes later), meta `_fuxia360_variant_id` |
| photo | Woo media item (uploaded once; `woo_media_links` stores the id, and the checksum prevents re-uploads) |
| archived variant / removed size | the variation is set to `private` (never deleted, because orders reference it) |

Idempotency: the stored Woo id is used first; if it's missing, lookup by SKU; only then create. Variations use `products/{id}/variations/batch` (≤ 100 per call) and are matched by SKU.

### E.1 Target structure for NEW F360-managed products (DW1)

```
Macarena                         ← ONE Woo variable product (one model, one page)
  Nude                           ← pa_color term
    35 36 37 38 39 40            ← pa_medida terms (Colombian sizes)
  Negro
    35 36 37 38 39 40
```
- Each **color × size** is one Woo variation with its own SKU (`F360-MACARENA-NUDE-37`) and its own stock.
- Inventory identity stays **model + color + Colombian size + location** (`Macarena / Nude / 37 / Bodega CDMX = 4`); the Woo stock for `F360-MACARENA-NUDE-37` = that Bodega CDMX balance.
- **Legacy products keep one product per color and are not consolidated or migrated in this work.**

## F. Inventory authority model

- **F360-managed products:** **Fuxia 360 ledger = inventory master; Woo = sales channel.**
  - `ATS_online(variant) = on_hand(variant, target.fulfillment_location)`; V1 location = **Bodega CDMX**.
  - No reservations or safety stock yet; the formula is isolated in one function so they can be added later.
  - Stores and bazaars **never** count toward online stock in V1 (D1).
- **Push (Fuxia → Woo):** after any ledger event touching a mapped variant, a `stock` job sets the Woo `stock_quantity`. The value is absolute, with **race protection**:
  - `unsynced_woo_sales = last_pushed_stock − current_woo_stock` (read just before writing);
  - push `max(0, ATS − max(0, unsynced_woo_sales))`.
  
  So a Woo sale that hasn't reached the ledger yet is never "un-sold".
- **Sales back (Woo → Fuxia):** a **new, separate** webhook function (`f360-woo-orders`, its own HMAC secret; the loyalty webhook is untouched):
  - a paid order (`processing` / `completed`) for mapped variations → **`SALE` event** from Bodega CDMX. Idempotency key = UUID derived from `(target, order_id, line_item_id)`;
  - if Bodega has no stock (oversell race) → **no negative stock**: the event is recorded as a `sync_exception` ("Venta en línea sin existencia") for Carolina;
  - cancellations and refunds → **DW4**. V1 proposal: a cancellation *before* shipping creates a compensating `RETURN` event to Bodega; refunds after shipping do **not** restock automatically (a physical return is received manually). This follows 06_WOOCOMMERCE_SYNC §6.
- **Reconciliation:** a scheduled read-only compare (Woo stock vs expected) → `sync_exceptions` drift → shown in Fuxia 360. It never auto-overwrites without a job record.
- **Not in V1:** two-way stock editing (manual Woo stock edits on F360 products are overwritten on the next push and reported as drift), and distributed fulfillment.

## G. Legacy vs F360 coexistence

| | Legacy (the 129 products) | F360-managed (new) |
|---|---|---|
| Created / edited | by Adrián in Woo, as today | only in Fuxia 360 |
| Woo marker | none | meta `_fuxia360_managed=1`, SKU prefix `F360-` |
| Stock | unmanaged, as today (**no change**) | `manage_stock` on, pushed from the ledger |
| Order webhook effect | loyalty only (unchanged) | loyalty (unchanged) **+** `SALE` in the ledger |
| `channel_inventory` / POS | unchanged | not used |

- The ingestion function **only** acts on line items whose variation id is in `woo_variant_links`; everything else is ignored.
- Publishing refuses to touch any Woo product not linked in `woo_product_links` or not carrying `_fuxia360_managed`.
- No mass migration.

## H. Publishing / sync architecture

- **Where Woo credentials live:** a **Supabase Edge Function** `f360-woo-publish` (server-only), with Woo **read/write** keys in function secrets — one set per target: test-store keys on staging, production keys only on production.
  - A **new, dedicated** Woo REST key ("Fuxia 360 publisher"), separate from the proxy's key.
  - Never in the browser, never in Vercel, never through `woocommerce-proxy`.
- **Flow:**
  1. The "Publicar en tienda online" button calls a server action.
  2. The server action calls RPC `f360_request_publish(product, target)`, which checks the role (owner by default, **DW8**) and readiness, and creates a `sync_job` with an idempotency key.
  3. The RPC invokes the function with the user's JWT.
  4. The function re-checks the role via `f360_me`, then runs the steps: **terms → media → parent → variations (batch) → stock → read-back verification**. Each step is written to `sync_job_steps`.
- **All-or-report:** every step is recorded, and the job is `succeeded` only if the read-back matches the intended state (hash). Otherwise it's `partial` / `failed`, with the exact failing step. **A retry resumes idempotently**, because the links and SKUs make every step safe to repeat.
- **Carolina's states** (derived):

| State | Rule |
|---|---|
| Borrador | not ready (missing price, photo, color or size) |
| Listo para publicar | ready and never published |
| Publicando… | a job is running |
| Publicado | the last job succeeded **and** the current content hash = published hash |
| Cambios pendientes | published, but the content hash ≠ published hash (e.g. a new color added) |
| Error de sincronización | the last job is failed/partial. The message is in Spanish, with a "Reintentar" button and detail for Mario |

- **Preview before publishing:** a "Así se verá en la tienda" panel shows the Woo structure: model, color selector with photos, size grid with the stock each variation will carry, price, category.

## I. Storefront color/size UX (smallest safe change)

Target: one model; the color and size selectors swap the images and availability on the same page. Proposed on the **test store first**, applied to production by Adrián once approved (DW7):

1. **Swatches instead of dropdowns** for `pa_color` (color dots / photo thumbnails) and `pa_medida` (size buttons).
   - Preferred: **Bricks' built-in variation swatches**, if the installed Bricks version supports them. That's configuration, not code.
   - Fallback: a well-known swatch plugin.
2. **Color changes the image:** core Woo swaps the main image to the variation's image, and F360 sets each variation's image to its color's primary photo. **A full per-color gallery** (every photo of the color) needs a small mu-plugin, or a gallery-per-variation plugin (V1.5, **DW7**).
3. **Sold-out sizes greyed out:** core Woo only greys out unavailable combinations when a product has ≤ 30 variations (`woocommerce_ajax_variation_threshold`). With Colombian sizes, 3 colors × 6 sizes = 18 is under the limit. A model with **6+ colors** (≥ 36 variations) would exceed it, so a **one-line filter raising the threshold** (e.g. 100) is still recommended as a safeguard.
4. **Cache:** check that SiteGround's cache purges product pages on the REST stock updates (or exclude F360 product pages from full-page cache), so stock state isn't stale.

## J. Security implications

- **New high-value secret:** a Woo read/write key can modify orders and customers too, since Woo can't scope keys. It lives only in Edge Function secrets, per target. Rotation is documented.
- **Role gate:** publishing is limited to owner (DW8) and enforced **server-side twice** (RPC + function). Audit rows record the actor, time, what changed and the result.
- **Order-ingestion webhook:** a separate HMAC secret; constant-time compare; idempotent; it ignores unmapped items.
- **No change to** `woocommerce-proxy` (P0-7 stays on the S0.0B plan). Publishing never uses it.
- **Dependencies on S0.0A before anything reaches production:**
  - **A1 in production** (hardened function defaults);
  - the f360 core migration approved for production;
  - **A8** strongly recommended (review login; the demo account is an *admin customer*, but has no f360 role, so no direct f360 exposure);
  - S0.0B-B3 (proxy) is independent;
  - the old leaked Woo key revocation (Q13) confirmed before creating the new publisher key.
  
  **Staging/test work has no production dependency.**

## K. Failure / rollback strategy

| Failure | Behavior |
|---|---|
| Image upload fails | step failed → job `partial` → "Error de sincronización: 1 foto no se subió". Retry re-uploads only the missing ones (media links) |
| Variation batch partially fails | per-variation results recorded; verification catches the missing ones; retry creates only those (SKU match) |
| Woo 5xx / timeout mid-job | job `failed` at a known step; nothing is marked published; retry is safe |
| Crash after Woo created the product but before the link was stored | the next attempt finds it by SKU and relinks (no duplicate) |
| Stock push fails | variant links keep the last good value; the job is retried with backoff; drift is reported |
| Oversell race | `sync_exception`, never negative stock |
| Wrong publish | "Ocultar de la tienda" (Woo `draft`/`private`); products are never deleted |
| Schema rollback | the new tables are additive, with a `.down.sql` like the existing migrations; the ledger is never modified |

## L. Automated tests

1. **Pure unit tests (TypeScript):** mapping builders (product / variation payloads), deterministic SKUs, content hash, ATS, the unsynced-sale race formula, state derivation.
2. **Mock Woo adapter** (in-memory Woo semantics: products, variations, terms, media, SKU uniqueness, batch limits, **failure injection**):
   - publish twice → no duplicates;
   - crash-after-create recovery;
   - partial variation failure + retry;
   - image failure + retry;
   - stock push with an unsynced sale.
3. **Real Woo REST contract tests** against a **local Docker WordPress + WooCommerce** (throwaway; default theme): attributes/terms, batch variations, `manage_stock`, SKU lookup, media upload. This proves the adapter against real Woo behavior without touching any real store.
4. **Database tests** (the rolled-back style already used): new RPCs, role gates, readiness, idempotent `SALE` ingestion, no negative stock, exceptions.
5. **Webhook tests:** signed synthetic payloads (mapped / unmapped / replayed / cancelled).

## M. Browser E2E (Playwright)

1. **Admin:** create "Macarena" with 3 colors (Nude, Negro, Rojo), 2 photos each, sizes 35–40, price, category, description → Borrador → Listo para publicar; receive per color/size into Bodega CDMX; preview matches.
2. Publish to the **Woo test store**, see "Publicado"; publish again, and verify via REST that there's still exactly 1 product and 18 variations (3 colors × 6 sizes).
3. **Storefront (test store):** open the product; select Negro → image changes; sizes with 0 stock are disabled; select 37 → add-to-cart allowed up to the stock.
4. Receive more stock in Fuxia → the test store's stock updates (after the cache purge).
5. **Test order** (test payment gateway / manual payment) → the ledger shows the `SALE` from Bodega CDMX → the Woo stock is still consistent.
6. Inject a failure (mock or blocked media URL) → "Error de sincronización" → "Reintentar" → "Publicado".

## N. Files / migrations / functions (planned)

- `supabase/migrations/2026MMDD_f360_product_master_commerce.sql` (+ `.down.sql`): new product fields, `product_media`, deterministic SKU backfill for existing staging variants, `sales_targets`, the `woo_*_links` tables, `publications`, `sync_jobs` / `sync_job_steps` / `sync_exceptions`, RPCs (`f360_update_product`, `f360_add_color`, `f360_add_media`, `f360_publication_status`, `f360_request_publish`, `f360_record_online_sale` (service only), `f360_list_sync_issues`), explicit grants.
- `supabase/functions/f360-woo-publish/` — the publisher (adapter interface + REST implementation).
- `supabase/functions/f360-woo-orders/` — order ingestion webhook.
- `supabase/functions/_shared/woo/` — adapter interface, REST client, mapping builders (shared by both functions and the tests).
- `admin-web/src/app/(app)/productos/…` — extended Nuevo producto / product detail (commercial info, multi-photo per color, add color later), preview panel, publish button, status badges, a sync issues view.
- `admin-web/src/lib/woo-mapping.ts` (pure, testable), `admin-web/e2e/publishing.spec.ts`, `admin-web/test/*.test.ts` (unit + mock adapter).
- `tools/woo-docker/` (docker-compose for local WordPress + WooCommerce contract tests).
- Storefront (test store, via Adrián): swatch config, the threshold filter, and later the per-color gallery mu-plugin.
- **Not modified:** `woocommerce-webhook` (loyalty), `woocommerce-proxy`, `channel_inventory`, legacy Woo products.

## O. Sprint breakdown

| Sprint | Scope | Exit |
|---|---|---|
| **P2.1 Product master** (no Woo) | commercial fields, per-color photos, add a color to an existing product, readiness checklist, statuses Borrador / Listo, "Así se verá en la tienda" preview, deterministic SKUs | Carolina builds a complete 3-color model in minutes; preview correct; DB + E2E tests |
| **P2.2 Publisher (test Woo)** | adapter + mock + Docker contract tests, link tables, jobs/steps, `f360-woo-publish`, publish button, all states, retry, idempotency | publish twice = no duplicates; failure injection shows an honest error; retry recovers |
| **P2.3 Stock authority + storefront** | ATS push with race protection, `f360-woo-orders` ingestion, reconciliation + exceptions UI, storefront swatches / threshold / variation image on the test store | the acceptance test below passes in the test environment |
| **P2.4 Production readiness** (gated) | only after A1 in production, the f360 migrations approved, Q13 confirmed, the publisher key created and the webhook registered by the owner | the first real product is published under supervision |

## Final implementation sequence (P2.1 → P2.3)

Every step is **staging / test-store only**, is its own commit, and is verified before the next step. Legacy products, `channel_inventory`, the loyalty webhook and `woocommerce-proxy` are never modified.

### P2.1 — Product master (no WooCommerce)
1. **Size default fix (DW1):** replace the `22–27` default with Colombian `35, 36, 37, 38, 39, 40` in `admin-web/src/lib/format.ts` (still editable per product). E2E: new product defaults to 35–40.
2. **Migration A (additive):**
   - `products` + `description`, `short_description`, `regular_price`, `sale_price`, `woo_category_key`, `lifecycle`, `sku_code`;
   - new `product_media`;
   - deterministic variant SKUs `F360-{PRODUCT}-{COLOR}-{SIZE}` (generated on create; frozen once published);
   - RPCs `f360_update_product`, `f360_add_color` (creates that color's variants for every product size), `f360_add_media` / `f360_reorder_media` / `f360_remove_media`, readiness in `f360_get_product`;
   - explicit grants.
   
   Rolled-back DB tests.
3. **Admin UI:**
   - Nuevo producto keeps its flow and adds a commercial step: price, sale price, category (the 4 real categories), description, short description;
   - product detail gets "Agregar color" and **multiple photos per color** (upload, reorder, remove);
   - status badges **Borrador / Listo para publicar** with a readiness checklist (price, category, ≥ 1 color with ≥ 1 photo, ≥ 1 size).
4. **"Así se verá en la tienda" preview** (read-only): one model, color swatches with photos, the size grid per color with the stock that each variation would carry from Bodega CDMX, price.
5. **Tests:** unit (SKU builder, readiness, content hash), DB, and E2E: create Macarena with Nude / Negro / Rojo, 2 photos each, 35–40 → Listo para publicar → receive stock → preview matches the ledger.

**Exit:** Carolina can build a complete multi-color model in minutes; no Woo involved.

### P2.2 — Publisher to the Woo **test** store (needs DW2; can start on mock/Docker before DW2 lands)
1. **Migration B (additive):** `sales_targets` (`woo_test` → Bodega CDMX), the `woo_product_links` / `woo_variant_links` / `woo_media_links` / `woo_term_links` tables, `publications`, `sync_jobs`, `sync_job_steps` (append-only), `sync_exceptions`; RPC `f360_request_publish` (owner, readiness, idempotency key) and `f360_publication_status`.
2. **Shared Woo library** `supabase/functions/_shared/woo/`: the adapter interface; the **mock adapter** with failure injection; the REST adapter; pure mapping builders (parent / variations / terms / media); the content hash.
3. **Contract tests** of the REST adapter against a local Docker WordPress + WooCommerce (`tools/woo-docker/`): terms, batch variations, SKU lookup, media, `manage_stock`.
4. **Edge Function `f360-woo-publish`:**
   - re-checks the role with the caller's JWT;
   - steps: terms (reuse `pa_medida` 35–40, reuse/create `pa_color`) → media → parent → variations batch → stock → read-back verification;
   - every step is recorded;
   - `succeeded` only when the read-back matches, otherwise `partial` / `failed`;
   - resumable, SKU-based recovery;
   - test-store keys in the staging function secrets only.
5. **Admin UI:**
   - the "Publicar en tienda online" button with a confirmation;
   - the states **Publicando… / Publicado / Cambios pendientes / Error de sincronización**, with "Reintentar";
   - job history (who, when, what changed).
6. **Tests:**
   - mock: publish twice = 1 product / 18 variations; crash-after-create recovery; image failure → retry; partial variation failure → retry;
   - E2E against the test store (if DW2 is ready) or Docker Woo.

**Exit:** idempotent, audited publishing; failures are honest and recoverable.

### P2.3 — Stock authority + order sync + storefront (test store) — split into P2.3A (done locally) and P2.3B (blocked, SiteGround): see `P2_3_STATUS.md`
1. **Stock push:**
   - a `stock` job after every ledger event touching a mapped variant;
   - `ATS = on_hand(Bodega CDMX)` with the unsynced-sale race protection (§F);
   - `manage_stock` on and `backorders: no` for F360 variations only.
2. **Edge Function `f360-woo-orders`:**
   - a new webhook with its own HMAC secret; the loyalty webhook is untouched;
   - mapped paid lines → `SALE` from Bodega CDMX, idempotent per order line;
   - no stock → `sync_exception`, never negative;
   - cancellation / refund per DW4;
   - unmapped (legacy) lines ignored.
3. **Reconciliation:** a scheduled read-only compare of Woo stock vs the ledger → `sync_exceptions`. Admin view: "Avisos de sincronización".
4. **Storefront on the test store (with Adrián, DW7):**
   - swatches for `pa_color` / `pa_medida`;
   - the variation image = the color's primary photo;
   - the variation-threshold filter (safeguard for 6+ colors);
   - a cache purge / exclusion for F360 product pages;
   - optional per-color gallery snippet.
5. **Full acceptance test** (below) automated end to end: admin E2E + storefront E2E on the test store + a test order through the test payment method.

**Exit:** the acceptance test passes in the test environment with no manual WooCommerce edits.

### After P2.3 (gated, separate approval): P2.4 production readiness
A1 in production → f360 migrations approved for production → Q13 confirmed → production publisher key + order webhook created by the owner → first real product published under supervision.

## Decisions recorded (2026-09-24)

| # | Decision |
|---|---|
| DW1 | **Resolved:** Colombian sizes (35–40) are canonical; Mexican cm are a display layer only |
| DW3 | **Approved:** the initial Woo sync creates/updates the product in a **non-public** state; an **owner** explicitly publishes after review |
| DW4 | **Approved principle:** a refund ≠ a physical return. Cancellation-before-fulfillment, fulfilled sale, physical return and refund are separate events; no automatic restock on refund. The minimum state machine is finalized in P2.3 |
| DW5 | **Deferred:** Colombia pricing/display is out of P2.1–P2.3; existing Colombia behavior must not break |
| DW6 | **Approved:** Meta/catalog sync is **off** in the Woo staging environment; production Meta behavior is analyzed before any catalog migration and must not change accidentally |
| DW7 | **Approved direction:** the smallest safe swatch solution compatible with the actual Bricks/Woo versions; no custom swatch system unless required |
| DW8 | **Approved:** only Fuxia 360 **owners** can publish to Woo in V1; operators prepare products, photos and inventory |
| DW9 | **Approved:** SKU = `F360-{PRODUCT_CODE}-{COLOR_CODE}-{SIZE}`. PRODUCT_CODE and COLOR_CODE are **immutable once used for publishing**; display names may change without changing SKU identity |
| Roadmap | The 129 legacy products stay untouched **during P2.1–P2.3 only** (a transition constraint). Target for the **entire** catalog: MODEL → COLOR → COLOMBIAN SIZE → LOCATION; in Woo, ONE model = ONE product with color + size variation dimensions. A separately approved **LEGACY CATALOG RECONCILIATION + MIGRATION** unit follows the Macarena proof and production publishing (URLs/redirects, SEO, images, categories, order history, analytics, Meta references). P2.1–P2.3 build the final canonical model so that migration needs no redesign |

### Decisions recorded at P2.1 approval (2026-09-24)

| # | Decision |
|---|---|
| P-PRICE | **One price per model in V1.** All colors and sizes share the model's regular/sale price. P2.2 sends the same price on every variation. No color/size pricing UI or behavior; the Woo mapping sets price per variation anyway, so a future per-variant override is additive (no redesign). |
| P-STOCK | **Woo online stock = actual sellable stock in Bodega CDMX.** No permanent safety reserve (no −1/−2). `Macarena / Nude / 37 / Bodega CDMX = 4` ⇒ Woo quantity 4. Overselling under concurrency is solved by reservation/commitment semantics designed in **P2.3**, never by a hidden buffer. The §F "unsynced Woo sale" correction is **not** a reserve: it only prevents re-adding units Woo already sold but the ledger hasn't ingested yet (it's 0 when there are no pending sales). |
| P-CAT | **Categories map to stable Woo category IDs per target.** The four F360 categories (Ballerinas, Sandalia Plana, Sandalia Alta, Botas) are exactly the four observed in the live catalog (§B), so they're kept. P2.2 stores `category_key → woo_term_id` per sales target (`f360.woo_category_links`) and checks the ID (and recorded slug) exists before use. The publisher **never creates Woo categories** and never matches by editable name. The production ID mapping is recorded in P2.4 from the production store, not guessed. |
| P-STAGING | A non-production Woo staging target (DW2) is required for the real P2.2 acceptance test. Until then P2.2 is proven only against the in-memory mock + a throwaway local Docker WooCommerce. **No connection or write to production Woo.** |
| P-UNIT | **Future physical-unit traceability** (MODEL → COLOR → SIZE → BATCH → UNIT). Woo sells **variants**; Fuxia 360 will track **physical pairs**. Not implemented in P2.2 (no serialization, QR/labels, production tracking or scanning). Compatibility review below. |
| P-MEDIA | `f360_add_media` only accepts a storage path inside the product's own folder `f360/{PRODUCT_CODE}/{COLOR_CODE}/`, for an object that actually exists in `product-images`, not already attached. |

### Future unit traceability — schema compatibility review (done before P2.2)

**Conclusion: compatible. Adding batches and units later is purely additive; the canonical product/variant identity and the Woo mappings don't change.**

| Question | Finding in the current schema |
|---|---|
| Is the variant identity stable enough to hang units on? | `f360.product_variants.id` is a UUID that's never re-created: `ON DELETE RESTRICT` everywhere, no delete RPC, archival via `status`, `UNIQUE (color_id, size_label)`. Codes/SKUs are frozen once published (P2.1 lock trigger). `inventory_units.variant_id → product_variants.id` is safe. |
| Where do batches come from? | Receipts are `inventory_events` (`RECEIPT`, and `PRODUCTION_RECEIPT` already exists in the event-type CHECK). A future `production_batches (id, code e.g. COL-2026-094, factory, materials…)` can be linked from the receipt event (new nullable `batch_id` on a new receipt-detail table, or on `inventory_units`). No change to existing event rows. |
| Unit-level movements without breaking the append-only ledger? | Quantity movements (`inventory_movements`, `quantity > 0`) stay the commerce/stock truth. Units attach through a **new** append-only table, e.g. `inventory_unit_movements (movement_id → inventory_movements.id, unit_id → inventory_units.id)`: one row per physical pair moved. Existing rows are never updated. For a serialized variant, `count(units at location) = inventory_balances.on_hand` becomes a reconciliation check. Partial serialization during rollout is allowed (`≤`). |
| Order fulfillment ("which pair did this customer get")? | The Woo line stays at variation level (`woo_variant_links` → `variant_id`). The future fulfillment/SALE event gets a unit assignment row. Woo never sees units. |
| Does anything in P2.1/P2.2 block it? | No. Two notes: (1) the legacy columns `products.wc_product_id` / `product_variants.wc_variation_id` from the core migration are single-target and **must stay unused**; P2.2 uses per-target link tables so there's one source of truth. (2) `product_variants.barcode` is a *variant* code (like an EAN), **not** a unit serial; unit serials go in `inventory_units.unit_serial` (unique), never in `barcode`. |
| Does it change Woo mappings? | No. Mappings are `product ↔ Woo product` and `variant ↔ Woo variation` per target; units are internal to Fuxia 360. |

### P2.2 — local implementation status (2026-09-25) and what SiteGround staging must validate

Implemented and proven ONLY against the in-memory mock and a throwaway local Docker WooCommerce (WordPress 7.1.2, WooCommerce 11.1.2, theme Twenty Twenty-Five). No external store was connected. The Edge Function `f360-woo-publish` is **not deployed**.

Repository reality vs this plan: Edge Functions live in `fuxia-native/supabase/functions/` (not `supabase/functions/`), so the publisher is `fuxia-native/supabase/functions/f360-woo-publish/` and the library is `.../_shared/f360-woo/`. Tables `publications` and `sync_exceptions` were not created: `woo_product_links` carries the published hash, and exceptions belong to P2.3. The `woo_term_links` cache was not needed, because terms are resolved by name/slug on every run.

Differences found between local Woo and the real Woo/Bricks store, to validate on SiteGround staging (DW2):

| # | Finding (local) | Why it matters / what to check on SiteGround |
|---|---|---|
| L1 | Options of a **global** attribute come back in the attribute's term order (alphabetical here: Negro, Nude, Rojo), not the order sent | The storefront color order is a `pa_color` setting (Products → Attributes → sort order). Check what the live `pa_color` uses; decide whether the Nude/Negro/Rojo order matters |
| L2 | The standard `variations_form` offers **all** sizes for a color, including 0-stock ones; only after choosing does it say out of stock. They are greyed/hidden only if "Hide out of stock items" is on | Contradicts the §I assumption. Sold-out sizes must be unselectable → P2.3 storefront work (swatches plugin / Bricks setting / small snippet). Check the live Woo inventory settings and Bricks' variation swatches |
| L3 | Selecting a color swaps the main image to that color's main photo ✔ (variation image); the product gallery holds all 6 photos from every color | A per-color full gallery still needs a snippet/plugin (DW7). Check how Bricks renders the variation image and the gallery |
| L4 | WordPress downloads each photo from the public Supabase Storage URL (sideload) | Check that SiteGround's outbound requests and max upload size allow it, and that security plugins don't block `*.supabase.co` |
| L5 | A new store starts in WooCommerce "Coming soon" mode; the local one also has an mu-plugin allowing a test image host | Local-only artifacts; must not exist on SiteGround |
| L6 | Local price shows `$2,800.00` (default 2 decimals) | Live shows whole pesos (store setting). The publisher sends "2800". Verify display on SiteGround |
| L7 | Local auth = WordPress application password over http (`WP_ENVIRONMENT_TYPE=local`) | SiteGround uses a dedicated Woo REST key (ck/cs) over HTTPS. Same Basic header; verify SiteGround/Cloudflare pass the `Authorization` header |
| L8 | Local has no caching | SiteGround Dynamic Cache and any CDN must not serve stale stock on product pages (§I.4) — P2.3 |
| L9 | Local has no Meta / Facebook for WooCommerce, no WCPBC, no email | On SiteGround staging, Meta sync must be OFF (DW6) before the first publish; check that WCPBC (DW5) doesn't break a draft F360 product |

## Decisions needed (not invented)

| # | Decision |
|---|---|
| ~~DW1~~ | **RESOLVED:** Colombian sizes (`35–40`) are canonical for Fuxia 360 and Woo; Mexican centimeters are a later display-only equivalence; no duplicate inventory identities |
| **DW2** | **(still open — blocks the real P2.2 acceptance test)** **Woo test environment.** Recommended: a **SiteGround staging copy** of the live store (real Bricks theme and plugins, payments in test mode, emails/Meta sync disabled, not indexed), created by the owner/Adrián, with its own REST keys. Without it, only the mock + local Docker Woo are possible, and the storefront UX can't be validated |
| DW3 | Publish = immediately visible, or created hidden (draft) with a "Mostrar en tienda" step? |
| DW4 | Inventory rules for Woo cancellation / refund (proposal in §F) |
| DW5 | Country pricing (WCPBC / Colombia) for F360 products: automatic conversion or manual zone prices? |
| DW6 | Should new products flow automatically to the Meta catalog (Facebook for WooCommerce)? |
| DW7 | Swatches: Bricks built-in vs plugin; per-color full gallery in V1 or V1.5 |
| DW8 | Who may publish: owner only (proposed), or also operator? |
| DW9 | SKU convention `F360-{PRODUCT}-{COLOR}-{SIZE}` (e.g. `F360-MACARENA-NUDE-37`), matching the examples given with DW1; confirm |

## What Adrián still does after V1 (and why)

- **One-time:**
  - create the test-store copy (DW2);
  - create the Woo REST keys (test and production) and register the order webhook — a WordPress admin action with credentials that shouldn't be delegated to code;
  - configure swatches, the variation-threshold filter and cache rules in Bricks/WordPress (theme access);
  - later, install the per-color gallery snippet.
- **Ongoing for F360 products:** none of product creation, variations, sizes, colors or stock. He's left with **merchandising and site work** (home/banners, landing pages, SEO polish, promotions in Woo Discount Rules), and support if a sync error needs WordPress-side investigation.
- **Legacy products:** unchanged (still manual) until a separately approved catalog migration.

## Acceptance test

> Carolina creates a completely new shoe in Fuxia 360 with multiple colors and sizes, receives inventory, publishes it, and sees the correct product, photos, color selector, sizes and stock in a WooCommerce test environment, without anyone manually editing WooCommerce.

Concretely, and all automated where possible:
1. In Fuxia 360: create **"Macarena"** with colors **Nude, Negro, Rojo** (2+ photos each), sizes **35–40**, price $2,800, category Ballerinas, description. The status goes Borrador → **Listo para publicar**.
2. Receive into **Bodega CDMX**: Nude 35 = 4, 37 = 4, 39 = 4; Negro 37 = 2; Rojo: nothing.
3. Open "Así se verá en la tienda": 1 model, 3 colors, 6 sizes each (35–40), stock matching step 2.
4. Press **Publicar en tienda online** → "Publicando…" → **"Publicado"**. Press again → still exactly **1 Woo product and 18 variations** (verified via the test store's REST API).
5. On the **test storefront** product page:
   - selecting **Nude** shows Nude photos;
   - only 35, 37 and 39 are selectable (each allows up to 4), and the page stays on Macarena (no navigation to another product);
   - selecting **Negro** shows Negro photos; only 37 is selectable (up to 2);
   - selecting **Rojo** shows every size unavailable;
   - price $2,800.
6. Receive 1 more Nude 37 in Fuxia → the storefront allows up to **5**.
7. Place a **test order** for Nude 37 × 1 (variation `F360-MACARENA-NUDE-37`) → Fuxia 360 shows "Venta en línea: 1 par de Bodega CDMX" in the history, Bodega shows 4, and the storefront shows 4.
8. At no point does anyone open the WooCommerce admin to edit the product, its variations, sizes, colors or stock.
