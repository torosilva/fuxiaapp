# Track C — Physical Operations / Unified Inventory: CURRENT STATE AUDIT

Read-only. Date: 2026-09-25.

Sources:
- app code in `fuxia-native/` (N);
- the production schema snapshot `docs/fuxia360/audit/live/schema.sql` (S, structure only);
- `SECURITY_AUDIT.md` and `SPRINT_0_IMPLEMENTATION_PLAN.md`.

Nothing was changed.

> **Production exposure, still open.** Found again in this audit; it is a blocking prerequisite for Track C. The live schema has these policies:
> - `anon_update_inventory_sold`: UPDATE on `channel_inventory` for **anon**, `USING (true) WITH CHECK (true)` (S:1245). Anyone with the public key can change **any column, including price and stock**.
> - `anon_read_active_staff` (S:1229): exposes seller **PINs** to anon.
> - `anon_insert_offline_sales` / `anon_read_offline_sales` (S:1221, 1237): anon can create sales and read all sales, including customer phones.
> - `fx_add_points` is granted to anon (S:1670).
>
> These are P0-3/P0-4/P0-5 (escalated). The fix (S0.0A-A2) was rehearsed **only in staging**. Production is untouched by this work.

## 1. How a seller logs in

There are two unrelated "logins":

1. **App account:** phone OTP (`onboarding/login.tsx` → `whatsapp-otp`).
   - `verify` signs in with a synthetic email `{phone}@fuxia.app` and a deterministic password `fuxia_{phone}_{OTP_SALT}` (`whatsapp-otp/index.ts:228-229`), and creates the user with `user_metadata.phone`.
   - A review bypass exists (`:14-19, 183-189`).
2. **"Modo Vendedora":** choose a channel, then a 4-digit PIN (`vendedora/index.tsx:77-113`).
   - The PIN is checked **on the client** by querying `staff … eq('pin', entered).eq('channel_id', …)`.
   - The seller id, name and channel then travel as **route params**. No session, no token and no server record.
   - This works **without being logged in**: "Soy vendedora" is shown on onboarding (`onboarding/index.tsx:80-86`), so it runs as `anon`. It also appears in the profile for `customers.role` staff/admin (`profile.tsx:352-361`).

## 2. How identity is determined

- **Customer:** `useAuth.loadCustomerData` finds the customer by `user_metadata.phone` (`useAuth.ts:92-102`), not by `auth_user_id`.
- **Seller:** client-side PIN + channel only. `public.staff` has **no link to `auth.users` or `customers`** (S:689-696). Nothing on the server knows who the seller is.
- **Server checks that exist:**
  - `my_role()` = `customers.role` for `auth.uid()` (S:293-298);
  - phone-based JWT policies `admins_all_*` (S:1197-1217);
  - admin checks in `inventory-approve:118-133` and `admin-points:41-51`.
- **Server checks that don't exist:** `claim-sale` has **no caller authentication** (service role; trusts `staff_id`/`channel_id` from the body, `claim-sale/index.ts:142-217`).

## 3. Roles

- `customers.role ∈ {customer, staff, admin}` (S:466-470). **Editable by the user themself** (P0-1: `customers self update` without a column restriction). A user can make themself admin.
- `public.staff`: `id, name, pin (plaintext), channel_id, active`. There is no role, no hierarchy, and no manager concept.
- Admin screens (`app/admin/*`) have **no role guard**; they are hidden by the UI only (P1-11).
- Fuxia 360 already has its own server-controlled roles: `f360.user_roles` (owner/operator/viewer), checked by `f360.require_role`.

## 4. Store / location concept

- `public.channels(id, name, type ∈ {store, bazar}, location text, event_date, active)` is the only location entity (S:440-449).
- **Referenced by:**
  - `staff.channel_id` (one channel per seller);
  - `channel_inventory.channel_id` (ON DELETE CASCADE);
  - `offline_sales.channel_id`;
  - `inventory_change_requests.channel_id`.
- The seller **picks any active channel** from a list; the PIN query filters by it. The server never checks that sales or stock writes belong to the seller's channel.
- **Fuxia 360** has `f360.locations` (type warehouse/receiving/store/bazaar/workshop/other; `is_authoritative`, `sales_sync_pending`, `legacy_channel_id → channels`). In staging only **Bodega CDMX** exists. It is not linked to any channel.

## 5. How the seller identifies a customer

- There is no customer search or creation in the seller flow.
- **(a) QR scan:** the static `loyalty_cards.qr_code` `FX-{last8}-{base36 ts}-00`. It never rotates, has no signature, and is resolved in `claim-sale`.
- **(b) Typed 10-digit phone:** stored as free text in `offline_sales.customer_phone`, never validated.
- **(c) Skip.** The customer can later **claim** the code in `claim.tsx`. The claim credits the phone sent in the body.

## 6. How a sale is recorded (`vendedora/sale.tsx`)

1. **Read** `channel_inventory` rows of the channel with `stock − sold > 0` (`:83-98`).
2. **Cart and totals on the client:** `total = Σ price·qty` using the price read when the screen loaded (`:133-135`).
3. **Stock is decremented first:** from the client, `update({ sold: it.sold + qty })`, with a stale `sold`, in parallel, **errors ignored** (`:160-164`).
4. **QR path:** `claim-sale scan_qr` with `{qr_code, items, total, channel_id, staff_id}` from the client. The server then:
   - inserts an already-claimed `offline_sales`;
   - `creditPoints`: `transactions` (channel `store`), `purchase_items`, `loyalty_cards` read-modify-write, and a referral bonus.
5. **Code path:** the client inserts `offline_sales` directly (as anon) with a `Math.random` 6-character code. The customer claims it later.
6. `qr_scans` is **never written**.

**Not atomic and not idempotent:**
- stock can be decremented with no sale;
- a double tap duplicates the sale and the points;
- concurrent claims can both succeed (P0-2, P0-4).

## 7. `channel_inventory`

- **Columns:** `id, channel_id, product_name NOT NULL, sku, size NOT NULL, color, price NOT NULL, stock, sold, image_url, updated_at` (S:422-434). There is no unique key per (channel, product, size, color), no `CHECK (sold ≤ stock)`, no triggers, and no variant/Woo id.
- **Writers:**
  - the sale (client, `sold`);
  - admins directly: `vendedora/inventory.tsx`, `inventory/bulk-add.tsx`, `admin/channel/[id].tsx`, `admin/import-woo.tsx` (sku `v.sku || WC-{id}-{vid}`), `admin/bazar-template.tsx`;
  - `inventory-approve` (service role; adjust clamped ≥ `sold`, `bulk_add`, delete).
- **Seller adjustments** create `inventory_change_requests` rows that an admin approves via `inventory-approve`. That is not atomic: the change is applied, then the request is marked approved.
- **RLS:** anon SELECT **and anon UPDATE of all columns** (S:1233, 1245); `inventory staff write` FOR ALL by role (S:1329); `GRANT ALL` to anon and authenticated.
- **Stock identity** is free text (`product_name`, `size`, `color`). It is a **separate inventory universe** from Woo and from Fuxia 360.

## 8. Loyalty effects

- **Points** = `pairs × 100` from the client's quantities (`claim-sale:42-43`); the amount is ignored.
- **Card update:** read-modify-write of `total_points`, `pairs_count`, `tier` (`:76-85`). DB triggers then:
  - recompute the tier (`trg_update_tier`, 300/900);
  - bump `purchases_this_year`, `total_pairs_count`, `last_purchase_at` (`trg_purchase_stats` on `transactions`).
- **Rewards:** the store flow creates none. Unused calculators exist with **different** thresholds (`calculate-tier`: 501/1201).
- **No transaction:** lost updates under concurrency (P1-1).

## 9. Product / color / size / price stored per sale

- **`offline_sales.items` (jsonb)** = `{inventory_id, product_name, size, color, quantity, unit_price}` plus `total`, **all from the client**. The server never re-reads the price.
- **`purchase_items`:** inserted with `sku: null`, but `sku` is **NOT NULL** (S:595). The insert fails and the error is ignored, so **store sales never have purchase items**.
- **Not captured:** SKU, variant, Woo id, payment method, discount.

## 10. What relies on editable phone or on `customers.role`

- **Phone:**
  - the OTP identity (synthetic email/password);
  - `useAuth` customer load;
  - `claim_code` credits the phone **from the request body**;
  - `offline_sales.customer_phone`;
  - `tracking` lookup;
  - RLS `admins_all_*`, `customers_read_own_sales`, `offline_sales own by phone` (`my_phone()`), push tokens.
  - `customers.phone` is user-editable (P0-1). `user_metadata` may be user-editable (A6/A7).
- **Role:**
  - the UI gates;
  - `my_role()` policies;
  - `inventory-approve`, `admin-points`.
  - `customers.role` is user-editable (P0-1).

## 11. Documented risks that hit this flow

| Id | Risk |
|---|---|
| P0-1 | Any customer can set `role='admin'` / change phone |
| P0-2 | `claim-sale`: no auth; points minted from any QR string; double claim |
| P0-3 | Plaintext PINs readable by anon; client-side PIN check; staff identity not bound |
| P0-4 | Client-orchestrated, non-atomic sale; stale `sold`; errors ignored; client price; no idempotency; staff can bypass approvals |
| P0-5 | Anon read of `offline_sales`, `staff`, `channel_inventory`; anon insert of ICRs |
| P0-6 | Deterministic password / review bypass (pre-auth takeover vectors) |
| P1-1 | Loyalty read-modify-write without a transaction |
| P1-11 / P1-12 | Admin screens gated by UI only; no actor audit for stock edits |
| New (this audit) | `purchase_items.sku NOT NULL` makes every store-sale item insert fail silently; the `fx_add_points` RPC is executable by anon |

## 12. What already exists and should be preserved

- **The seller UX:** channel → PIN → cart → QR / code / skip. Short and familiar for sellers.
- **Channels as a concept**, including bazaars with dates.
- **The approval workflow** for seller stock changes (ICR → admin approval).
- **Loyalty** economics and triggers.
- **The S0.2/S0.3 designs:** individual seller identity, hashed PIN as a per-shift step, server session, atomic `pos_record_sale`, system price only (Q1/Q2/Q3).
