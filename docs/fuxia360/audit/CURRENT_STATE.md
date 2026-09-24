# Fuxia 360 Audit — Current State

**Audit date:** 2026-09-24
**Branch audited:** `fuxia-360` @ `b1ee0d5` (identical to `main` except the spec commit)
**Scope:** repository only. **The live Supabase project (`tgzgiwfzddsghnxgkcqd`) was not queried.** Every statement about production state is marked **[UNVERIFIED-LIVE]** where the repo cannot prove it.
**Working-tree notes at audit time (not touched by this audit):**
- `.gitignore` has an uncommitted change (IntelliJ block duplicated twice).
- `fuxia-native/supabase/functions/loyalty-credit/` is **untracked** — it exists locally but has never been committed. It is audited here because it may already be deployed.

---

## 1. Repository layout

| Path | What it is | Status |
|---|---|---|
| `fuxia-native/` | Expo 54 / React Native 0.81 / Expo Router 6 / supabase-js 2 app (customers + sellers + admin in one binary) | Production (App Store + Play) |
| `fuxia-native/supabase/functions/` | 19 Deno Edge Functions (18 tracked + `loyalty-credit` untracked) | Deployed manually via CLI |
| `database/` | 15 hand-applied SQL files + 2 seed files + `RUNBOOK-fase0.md` | Applied by hand in the SQL Editor |
| `supabase/.temp/`, `fuxia-native/supabase/.temp/` | Two committed CLI link caches, both pointing at `tgzgiwfzddsghnxgkcqd` | No `config.toml`, no `supabase/migrations/` |
| `mobile-mockup/` | Vite/React prototype | Not production |
| `wordpress/page-privacy.php` | One WP template | Not related to the loyalty flow |
| `.github/workflows/hilo-keepalive.yml` | Pings the external Hilo backend on Railway | Only CI workflow; no tests or build CI |
| `store/`, `*.md`, PDFs, PNGs | Store listings, manuals, backlog | Documentation |

**No tests.** `fuxia-native/package.json` has no `test` or `lint` script; the only test is the Expo template `components/__tests__/StyledText-test.js`. There is no CI for app or functions.

**Releases:** JS changes ship over the air with EAS Update (`fuxia-native/app.json` `updates`/`runtimeVersion`). Implication for Sprint 0: **older app binaries/OTA bundles stay in the field**, so server-side hardening must either keep old client call patterns working for a while or be paired with a forced update.

## 2. Functional domains found

| Domain | Evidence | Notes |
|---|---|---|
| Customer auth (phone OTP → Supabase Auth) | `functions/whatsapp-otp/index.ts`, `lib/hooks/useAuth.ts` | Auth user is `{phone}@fuxia.app` with a password **derived deterministically** from phone + `OTP_SALT` (`whatsapp-otp/index.ts:228-229`) |
| Customer profile | `customers` (+ `role`, `auth_user_id`, `avatar_url`, `birthday`, `shoe_size`, `referral_code`, `referred_by`) | `referral_code`/`referred_by` are **not created in any repo SQL** |
| Loyalty card / points / tiers | `loyalty_cards`, `transactions`, `purchase_items`, `rewards`, `tier_config` | Points = 100 per unit in the order; tiers Silver 300 / Gold 900 (`database/points_orders_migration.sql:4-17`) |
| Woo → loyalty | `functions/woocommerce-webhook` | Credits on `processing`/`completed` and reverses on `refunded`/`cancelled`/`failed`. **Does not touch inventory at all** |
| Pre-registration Woo orders | `unmatched_orders`, `functions/link-orders`, `functions/backfill-orders` | Credits past orders after sign-up |
| Customer order tracking | `functions/my-orders` | Server-side, JWT-scoped |
| Product catalog in app | `services/WooCommerceService.ts` → public WC Store API + `woocommerce-proxy` | Woo is the only product catalog |
| Product image overrides | `product_image_overrides` + bucket `product-images` | Keyed by `wc_product_id` |
| Stores/bazaars | `channels` (`store`/`bazar`, optional `event_date`) | `database/offline_sales_migration.sql:7-15` |
| Sellers | `staff` (name, **plaintext 4-digit PIN**, one `channel_id`) | `offline_sales_migration.sql:18-25` |
| Per-channel stock | `channel_inventory` (name/sku/size/color/price/stock/sold per row) | Described as "independent from WooCommerce" (`offline_sales_migration.sql:27`) |
| In-store sale | `app/vendedora/sale.tsx` + `offline_sales` + `functions/claim-sale` | Built on the client, not atomic (see SECURITY_AUDIT §P0-4) |
| Inventory change approvals | `inventory_change_requests`, `functions/inventory-approve`, `functions/notify-approval-pending`, `app/admin/inventory-approvals.tsx` | Staff requests go to a queue; admin approves |
| Admin (mobile) | `app/admin/*` — Today dashboard, reports, channels, staff, Woo import, bazaar template, points adjust, customer 360, broadcast push, approvals | Admin menus are gated **only in the UI** (`app/(tabs)/profile.tsx:352-367`) |
| Push | `push_tokens`, `functions/admin-broadcast-push`, `broadcasts` | Expo push |
| Support / Hilo chatbot | `functions/hilo-chat`, `functions/escalate-to-staff`, `support_tickets` | Hilo backend is on Railway |
| Virtual try-on | `functions/virtual-tryon*` (FASHN API) | No auth check |
| Popup points (WordPress) | `functions/loyalty-credit` (**untracked**) | Relies on `pending_credits`, `fx_add_points()` and triggers that are **not in the repo** |

## 3. Actors and how they authenticate today

| Actor | How they authenticate | Where authorization is enforced |
|---|---|---|
| Customer | OTP → Supabase session | RLS "self" policies (`database/rls_migration.sql`) |
| Admin (Carolina/Mario) | Same customer login, with `customers.role = 'admin'` | RLS via `my_role()` (`operational_writes_rls_migration.sql:33-37`), plus Edge Functions that check `customers.role` |
| Seller | 1) The device must be logged in as **some** customer account; the "Vendedora" button only shows when that account's role is `staff`/`admin` (`profile.tsx:352`). 2) Choose a channel, then enter a 4-digit PIN that is **checked on the client** (`app/vendedora/index.tsx:82-88`). 3) The staff id travels as a **route param** (`index.tsx:98-106`) | DB writes run under the device's Supabase session role, **not** under the seller's identity. Repo comments contradict each other on whether the device has a staff session (see SCHEMA_AUDIT §5). **Target (Q1, decided):** each seller uses their own phone and individual account, with a server-verified identity and session; no shared store identities. Prices can't be changed by sellers (Q3). |
| WooCommerce | HMAC on `woocommerce-webhook` | Function code |
| WordPress popup | `x-fuxia-secret` header (`loyalty-credit`) | Function code |
| Anyone holding the anon key (it ships in the app bundle) | — | Only whatever RLS and function code enforce |

## 4. Inventory flows today

1. **Load stock into a channel:** admin runs `import-woo.tsx:165-196` (copies Woo product/variation name/sku/size/color/price, but **not** the Woo IDs), `bazar-template.tsx:127`, `channel/[id].tsx:110` or `inventory/bulk-add.tsx:114`. All of these insert straight into `channel_inventory` from the client.
2. **Adjust stock:** admin writes directly from the client (`vendedora/inventory.tsx:89-100`). Staff create an `inventory_change_requests` row (`:103-121`), and `inventory-approve` applies it with the service role.
3. **Sell in store:** the client sets `channel_inventory.sold = <value read at screen load> + qty` for each row (`sale.tsx:161-164`). Then it either calls `claim-sale` `scan_qr` (QR path) or inserts `offline_sales` with a random code that the customer claims later (`sale.tsx:166-201`).
4. **Online sale:** Woo decrements its own stock. The Supabase side records loyalty only; **no Fuxia inventory is affected**.
5. **Locations for online fulfillment:** the data model has no central receiving location and no concept of online-order fulfillment location. The only "online stock" figure is WooCommerce's own stock number.
   - *Clarified 2026-09-24:* online orders are **not** fulfilled only from a central warehouse. Any eligible pair anywhere in Mexico (central receiving point, store, bazaar) can fulfill an online order, and Fuxia also sells **make-to-order** (~5–7 days) when no physical pair exists.
   - Woo's stock number is therefore not a physical location and isn't reliably tied to where pairs are. Nothing in the repo models allocation, fulfillment tasks, discrepancies or production requests (see `00_MASTER_SPEC.md` §5.1).
6. **Returns / refunds in store:** **no flow exists.**
7. **Transfers between channels:** **no flow exists.** Stock would have to be deleted in one channel and re-added in another.
8. **Movement history:** **none.** `channel_inventory.stock`/`sold` are mutable counters. `inventory_change_requests` is the only audit trail, and it covers staff requests only; admin direct edits and sales leave no audit row.

## 5. Loyalty flows today

Points are changed in **seven** places, each doing its own read-modify-write on `loyalty_cards.total_points`:

| Writer | File | Tier logic used |
|---|---|---|
| Woo webhook credit / reverse / re-credit | `woocommerce-webhook/index.ts:218-341` | `tier_config` table |
| In-store QR / claim code | `claim-sale/index.ts:26-140` | Hardcoded 300/900 (`:20-24`) |
| Retro-credit | `link-orders/index.ts:101-108` | `tier_config` |
| Backfill | `backfill-orders/index.ts:171-176` | `tier_config` |
| Admin manual adjust | `admin-points/index.ts:116-133` | Hardcoded 300/900 |
| WordPress popup | `loyalty-credit/index.ts:152-182` | DB function `fx_add_points` + trigger `update_loyalty_tier` (not in repo) |
| Referral bonus (in-store only) | `claim-sale/index.ts:98-137` | Hardcoded |

Also present:
- An unused `calculate-tier` function with the **old** 501/1201 thresholds and "points OR pairs" logic (`calculate-tier/index.ts:11-15,31-38`).
- Copy in `app/payments/index.tsx:75` that promises tiers based on "**annual** accumulated purchases". No code resets or windows points by year.

## 6. Documentation state

| Document | Accuracy |
|---|---|
| `README.md` | Lists only 4 SQL files (`README.md:34-37`); out of date |
| `database/RUNBOOK-fase0.md` | Accurate for the July 2026 hardening. Its "known gap" (§ line 95-97) is still open |
| `BACKLOG.md` | Says Woo keys were rotated (#14). The old keys are still in git history (commits `de22cc3`, `bd6e3df`); **whether they were revoked is [UNVERIFIED-LIVE]** |
| `docs/fuxia360/01_CURRENT_ARCHITECTURE.md` | Mostly correct. Omissions and contradictions are listed in GAP_ANALYSIS §1 |
| `fuxia-native/lib/database.types.ts` | Covers 7 of about 20 tables and is out of date. The client is built as `createClient<any>` (`lib/supabase.ts:10`), so the types are never enforced |

## 7. Headline conclusion

The app already has the omnichannel building blocks the spec lists (channels, staff, per-channel stock, offline sales, approvals, loyalty, Woo integration), and they are worth keeping. The **security boundary around them is not sound**, though:
- any logged-in customer can very likely make themselves admin;
- in-store points can be minted without authentication;
- staff PINs are readable and checked on the client;
- the store sale is a series of separate client writes.

These are Sprint 0 items and must be closed before building an inventory ledger on top. See SECURITY_AUDIT.md.
