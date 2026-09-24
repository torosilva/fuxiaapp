# Fuxia 360 Audit — Integration Audit

Covers WooCommerce (all touchpoints), WordPress, Twilio, Expo Push, Resend, FASHN and the Hilo backend. Measured against `06_WOOCOMMERCE_SYNC.md`.

---

## 1. WooCommerce touchpoints

| # | Touchpoint | Direction | Auth | What it does | File |
|---|---|---|---|---|---|
| W1 | WC Store API (`/wp-json/wc/store/v1`) | App → Woo (public) | none | Product lists, product detail, variations for the shop | `services/WooCommerceService.ts:22,275-360` |
| W2 | `woocommerce-proxy` | App → Edge → Woo REST v3 | anon JWT | GET products/variations/categories/attributes/customers; POST customers | `functions/woocommerce-proxy/index.ts` |
| W3 | `woocommerce-webhook` | Woo → Edge | HMAC | Order status → loyalty credit/reverse/re-credit; `unmatched_orders` | `functions/woocommerce-webhook/index.ts` |
| W4 | `my-orders` | App → Edge → Woo | user JWT, server-side customer resolution | Order tracking | `functions/my-orders/index.ts` |
| W5 | `link-orders` | App → Edge | user JWT | Retro-credit from `unmatched_orders` | `functions/link-orders/index.ts` |
| W6 | `backfill-orders` | Operator → Edge → Woo | anon JWT (!) | One-off historical credit | `functions/backfill-orders/index.ts` |
| W7 | Admin "Importar de Woo" | App → W2 → client insert into `channel_inventory` | admin session | Copies Woo name/sku/size/color/price into a channel | `app/admin/import-woo.tsx` |
| W8 | `findOrCreateWCCustomer` | App → W2 | anon JWT | Links a customer to a Woo account at sign-up/login | `useAuth.ts:117-129,247-250`; `WooCommerceService.ts:433` |
| W9 | `product_image_overrides` | App reads Supabase | public | Replaces broken Woo images | `product_image_overrides_migration.sql` |
| W10 | WordPress popup → `loyalty-credit` | WP → Edge | shared secret | Credits popup points by phone | `functions/loyalty-credit` (untracked) |
| W11 | "Comprar en la web" | App opens the Woo PDP | — | Checkout stays in Woo ✔ | BACKLOG #7 |

BACKLOG #22 says **two** Woo webhooks are configured ("Fuxia App — Order Completed" + "Fuxia Loyalty Sync"). If both point at W3, idempotency relies on `transactions.wc_order_id UNIQUE`. A duplicate delivery racing the first one fails the insert and returns 500, then Woo retries, which is fine. **[UNVERIFIED-LIVE]** which topics and URLs they use.

## 2. Webhook (W3) against the 06 contract

| Contract requirement | Current | Verdict |
|---|---|---|
| Signature validation | Mandatory HMAC-SHA256 for order payloads (`:206-210`); pings without orders pass unsigned (`:195-204`) | ✔ (non-constant-time compare, P2) |
| Idempotent | Uses `transactions.wc_order_id` (`:251-259`) + DB UNIQUE | ✔ for loyalty. Card update is read-modify-write (P1-1) |
| Status-aware | Credit: `processing`, `completed`. Reverse: `refunded`, `cancelled`, `failed`. Others skipped. Re-credit after reversal handled (`:261-279`) | Partial: **partial refunds ignored**; `on-hold`→`processing` fine; unmatched-order refunds not handled (P1-2) |
| Mapped to canonical variants | `purchase_items` stores `sku` (falls back to `WC-{line_item_id}`, `:177`), `wc_product_id`, and size/color parsed from meta keys `pa_size/Size/Talla`, `pa_color/Color`. **`variation_id` is received but discarded** (`:43`) | ✘ — no variant identity |
| Linked to canonical customer | Match by normalized phone, then email (`:281-296`). Writes `wc_customer_id` back when null | Partial — phone/email match only, no identity table |
| Inventory movement exactly once | **Not implemented.** The webhook never touches `channel_inventory`. Woo manages its own stock | ✘ (expected; Sprint 4) |
| Failure visibility | `console.log` only. No sync table, no retry queue, no operator view | ✘ |
| Business rule: points per "pair" | `pairs = Σ line_items.quantity` (`:284`), so **accessories, gift cards and shipping-less items all count as pairs** | ⚠ Business decision needed (GAP Q4) |

## 3. Product/catalog mastership today

- **Woo is the only product master.** Supabase has no `products` table. `channel_inventory` rows are untyped copies (`import-woo.tsx:173-185`) holding name/sku/size/color/price and **no `wc_product_id`/`wc_variation_id`**. Because `import-woo.tsx:115,129` invents SKUs when a variation has none, SKU is not a reliable join key.
- **Price has two masters:** Woo price (web) and `channel_inventory.price` (store), copied at import time and editable afterwards. No reconciliation rule. This contradicts spec constraint "No second independent stock number/price without a reconciliation rule" (`02_TARGET_ARCHITECTURE.md` §3).
- **Stock has N+1 unreconciled numbers:** Woo's stock figure plus one independent number per channel.
  - Nothing in the repo links them: importing into a channel doesn't touch Woo stock, and a Woo sale doesn't touch any channel.
  - *Clarified 2026-09-24:* Woo's figure is **not** a central-warehouse count. Online orders are fulfilled from any eligible location in Mexico (receiving point, stores, bazaars), and make-to-order variants can sell with zero physical stock (`00_MASTER_SPEC.md` §5.1).
  - So Woo stock is effectively a hand-maintained, published availability number, and must never be treated as a location's on-hand. How it's maintained today is still [UNVERIFIED process — Q12]. That isn't a Sprint 0 item; it gets resolved during Product/Inventory/Availability design.
- **Geolocated pricing (WCPBC)** is in use (`WooCommerceService.ts:285`; BACKLOG #29). Any future product sync must preserve per-zone prices, and field ownership for price needs a decision (06 §3).

## 4. Readiness for 06 §3 (product sync)

Nothing exists for Fuxia → Woo writes. The proxy is read-only for products by design (`woocommerce-proxy/index.ts:20-34`). The admin Woo key's permissions (read vs read/write) are **[UNVERIFIED-LIVE]**. Sprint 4 will need a **separate server-only function** with write scope. Do not widen the public proxy.

## 5. Other integrations

| Integration | Where | Notes / risks |
|---|---|---|
| Twilio (OTP SMS/WhatsApp, welcome WhatsApp, staff escalation) | `whatsapp-otp`, `woocommerce-webhook:117-139`, `escalate-to-staff` | `escalate-to-staff` has no auth (P1-4) |
| Expo Push | webhook, `admin-broadcast-push`, `notify-approval-pending` | Broadcasts rate-limited per segment/day and audited in `broadcasts` ✔. No consent/opt-out model (Customer 360 gap) |
| Resend email | `woocommerce-webhook:141-169` | Welcome email only |
| FASHN try-on | `virtual-tryon*` | No auth (P1-5) |
| Hilo chatbot (Railway + Upstash Redis) | `functions/hilo-chat`, `.github/workflows/hilo-keepalive.yml` | External system; not in the audit's core scope |
| WordPress popup | `loyalty-credit` | Untracked code; depends on SQL objects not in the repo (SCHEMA_AUDIT §2) |

## 6. Recommendations (for later sprints; nothing implemented)

1. **Keep W3 as the single entry for Woo orders** and extend it (Sprint 4) to write a `commerce_orders`/`order_lines` record with `variation_id` **before** doing loyalty and inventory, so every downstream effect keys off one idempotent record.
2. Add a `sync_events`/`integration_log` table (status, attempts, last_error, external_id, idempotency_key) and have W3 write to it (06 §7). This can start in Sprint 0 as observability only (optional unit S0.7).
3. Split `woocommerce-proxy` into (a) public catalog reads with a fixed param whitelist and (b) a JWT-scoped `wc-link-customer` function that does find-or-create server-side for the caller's own email only (S0.0).
4. Add `wc_product_id`/`wc_variation_id` to `channel_inventory` at import time (Sprint 1 compatibility step). This makes the Sprint 1 variant mapping largely mechanical for future imports. Existing rows need a match report.
5. Decide the "pair" rule for points (quantity of all lines vs footwear only) before touching the webhook.
6. When Woo order ingestion gains an inventory effect (Sprint 4 / 5C), it goes through **allocation to an eligible location**, then a SALE movement from the confirmed location. It must never be a decrement of a fixed central pool. Make-to-order order lines create production requests, not negative stock.
