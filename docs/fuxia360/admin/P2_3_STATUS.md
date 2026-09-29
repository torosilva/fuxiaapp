# P2.3 — Stock authority + Woo orders (status)

P2.3 is split in two:

- **P2.3A: DONE**, proven with Supabase **staging** plus the throwaway **local Docker WooCommerce**.
- **P2.3B: DW2 resolved** — the real staging is `https://staging4.fuxiaballerinas.com/` (isolated clone of production, confirmed by Adrián 2026-09-28).
  - Both technical blockers are resolved (Authorization header: SiteGround; Supabase download: 200 / 200 / 256 MB).
  - Staging key created by Mario (dedicated Shop manager user).
  - **Macarena published to staging4 as a DRAFT** (Woo id 3621, 18 variations, 6 photos, stock from Bodega CDMX; not public) on 2026-09-29, `P2_3B_STAGING4_PREFLIGHT.md` §4.7.
  - Orders, webhooks and stock-sync for staging4 have not started.
  - Nothing in P2.3B has been published, written or marked as passed.

## P2.3A — what exists

Flow: Fuxia 360 → Bodega CDMX stock → Woo → paid order → webhook → SALE in Fuxia 360 → the correct variant is discounted → Woo stock reconciled → history and alerts.

### Stock authority (Fuxia → Woo)
- Bodega CDMX is the only source of online stock for F360 products (P-STOCK, no reserve).
- Every balance change at the target's fulfillment location, for a linked variant, enqueues a push. This is done by a trigger on `inventory_balances` into `f360.stock_sync_queue`.
- A worker drains the queue. In P2.3A this is the local runner every 3 s; when deployed, `f360-woo-sync` is called by a scheduler.
- Woo quantity = `stockToPush(ATS, expected, current)`: ATS, minus sales Woo already made that the ledger has not ingested yet. It is never a buffer.
- Failures back off (10 s, 20 s, 40 s… up to 10 min). After 3 failures an alert opens; it resolves itself on the next success.
- Every attempt is logged in `f360.stock_sync_log`, which is append-only.

### Orders (Woo → Fuxia)
- Separate webhook `f360-woo-orders` with its own HMAC secret. The loyalty webhook (`woocommerce-webhook`) is **not touched**.
- Signature: base64 HMAC-SHA256 of the raw body, compared in constant time. An invalid signature → 401, plus a logged `webhook_rejected` alert.
- **No customer PII is stored.** The order is minimized to id, status, dates, refund ids and line items (id, product, variation, SKU, qty) before anything reaches the database. A DB test also checks that the tables have no customer columns.
- `public.f360_ingest_woo_order` is atomic, runs as service_role only, and is serialized per order with an advisory lock.
- **Idempotency** at three levels:
  - delivery: (delivery id + order + topic);
  - order version: (`date_modified_gmt`, status, refunds);
  - line: each Woo line affects stock at most once, ever. The SALE `idempotency_key` = md5(target:order:line).
- **Out of order:** an older `date_modified_gmt` than the stored one → `stale`, ignored.
- **Only paid statuses** (`processing` / `completed`) create sales. `pending` / `on-hold` → no stock effect.
- **Mapping is exact:** Woo variation id → `woo_variant_links` → variant, and the SKU must match `F360-{PRODUCT}-{COLOR}-{SIZE}`. Outcomes:
  - unknown F360 SKU → alert `unknown_sku`;
  - SKU differs from the linked variant → alert `sku_mismatch`;
  - legacy (non-F360) product → recorded as `legacy`, ignored, no alert.
- **Never negative:** the Bodega balance row is locked `FOR UPDATE`. If stock is insufficient, nothing moves and an `oversell` alert opens: "Venta en línea sin existencia … Hay que decidir cómo surtirlo".
- Each sale is a SALE event (actor "Tienda en línea", reference `woo_order`) plus a movement out of Bodega CDMX. It appears in the product history as "Tienda en línea vendió 1 par de Bodega CDMX · Pedido en línea #N".

### Reconciliation
- `f360-woo-sync` `{action:"reconcile"}` compares every linked variation (Woo `stock_quantity` vs Bodega ATS).
- Differences open `stock_drift` alerts and queue a correction. When the next comparison is in sync, the alert resolves itself.
- Each run is stored in `f360.reconciliation_runs` (append-only).
- Carolina runs it with **Revisar ahora** on the Avisos screen.

### "Avisos de sincronización" (`/avisos`)
- Sections:
  - Fuxia ↔ tienda status and the last check;
  - pending updates to the store;
  - pending alerts in plain Spanish, with product and order;
  - resolved alerts (who, when, note);
  - received orders and their result;
  - stock updates, including failures.
- Owners and operators can mark alerts as resolved; a note is mandatory. Viewers only read.
- Navigation: an **Avisos** item with a red counter (desktop), a dot on **Más** (phone), and an entry inside "Más".

## Pending decisions for Mario (NOT invented)

| # | Decision | What the system does today |
|---|---|---|
| **DW4a** | **Cancellation after a recorded sale:** does the pair go back to Bodega automatically, only when physically confirmed, or never? | Alert `cancel_after_sale` "decisión pendiente". **No automatic restock** in Fuxia. Woo re-adds the unit itself on cancel; the next reconciliation sets Woo back to Bodega (Fuxia is canonical), so the store never shows a pair Bodega doesn't have |
| **DW4b** | **Refund (total or partial):** does it mean a physical return? | Alert `refund_after_sale`. Refund ≠ return, no restock (principle already approved) |
| **OV1** | **Online sale with no stock (oversell):** who decides and how is it fulfilled (production / transfer from a store / cancel and notify the customer)? | Alert `oversell` with order and variant. Stock never goes negative; the Woo order stays as it is |
| **SY1** | Reconciliation frequency when deployed (e.g. every 15 min / hourly / nightly) | Manual ("Revisar ahora"), plus the automatic push on every stock change |

## Findings that matter for SiteGround

1. **Woo `X-WC-Webhook-Delivery-ID` is not unique per delivery.** It is hash(webhook id + current second), so two orders in the same second share it. This was found in the local E2E. Fixed: a replay requires the same delivery id **and** order **and** topic. Order version and line keys remain the real guarantees.
2. **Woo reduces stock itself** when an order is paid, and adds it back when an order is cancelled. The push formula accounts for the first (`expected` drops by the ingested quantity). The second is corrected by reconciliation.
3. **The local store delivers webhooks synchronously** (mu-plugin, because WP-Cron is disabled locally). **The real store delivers them asynchronously via Action Scheduler / WP-Cron.** On SiteGround, deliveries depend on cron running: verify real cron or the SiteGround cron setting.
4. **WooCommerce disables a webhook after 5 consecutive failed deliveries.** Our endpoint returns 5xx only for transient database errors (so Woo retries). If it gets disabled, orders stop arriving: monitoring is needed (P2.3B/P2.4).

## P2.3B — checklist (BLOCKED until SiteGround staging exists)

Nothing below has been run.

- [ ] **Environment:**
  - a SiteGround staging copy of the real store: real Bricks, same plugins, not indexed;
  - emails to customers OFF; payments in test mode.
- [ ] **Meta / Facebook for WooCommerce disabled** on staging before any publish (DW6); confirm no catalog sync fires.
- [ ] **REST API over HTTPS:**
  - a dedicated Woo REST key (read/write) for the publisher, used only on that target;
  - verify SiteGround / Cloudflare pass the `Authorization` header;
  - verify rate limits / WAF don't block batch calls.
- [ ] **Webhooks over HTTPS:**
  - `order.created` and `order.updated` → the deployed `f360-woo-orders` (staging, `--no-verify-jwt`), with its own secret;
  - WP-Cron / Action Scheduler actually runs (asynchronous delivery);
  - measure the delay from payment to delivery.
- [ ] **Attributes:** global `pa_color` and `pa_medida` exist with the expected slugs; decide the color term order (L1); size terms 35–40 reused, not duplicated.
- [ ] **Categories:** record the real category IDs for the 4 categories on staging (and later on production), never by name.
- [ ] **Bricks product template:**
  - Macarena renders as ONE product with a color selector and size selector;
  - the page never navigates to another product.
- [ ] **Swatches (DW7):** is Bricks' built-in variation swatch available in the installed version? If not, choose the smallest plugin.
- [ ] **Photos per color:**
  - selecting a color swaps the main image to that color;
  - decide the full per-color gallery (snippet / plugin) (L3).
- [ ] **Sold-out sizes:**
  - out-of-stock sizes must be unselectable, not only "agotado" after choosing (L2);
  - check the "Hide out of stock items" setting / the swatch plugin behavior / the variation threshold (≤ 30 variations → AJAX-less availability).
- [ ] **Cache:**
  - SiteGround Dynamic Cache / Memcached / CDN must not show stale stock on F360 product pages after a push;
  - purge on REST stock update, or exclude those pages.
- [ ] **Real plugins in the order path:** WCPBC (Colombia pricing, DW5), Discount Rules, loyalty webhook, analytics.
  - Confirm they don't break F360 orders or double-process stock.
- [ ] **Full acceptance on the test store:**
  - Macarena / Negro / 37 = 2 in Fuxia and Woo;
  - a real test-mode checkout of 1 pair → Fuxia 1, Woo 1, one SALE;
  - resend → no change;
  - reconciliation in sync.
- [ ] **Visual behavior:** Carolina validates desktop and phone on the real theme (selector, photos, sold-out sizes, price).
- [ ] **Monitoring:** alert if the Woo webhook becomes disabled or no deliveries arrive for N hours.
