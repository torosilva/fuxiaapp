# Closed loop: one physical sale → sale + inventory + customer + loyalty + Growth

Status (2026-09-25):
- **S0.5** (`loyalty_apply`): implemented in **STAGING**.
- **S0.3** (legacy branch): implemented in **STAGING**.
- **C3:** implemented in **STAGING** 2026-09-28 (cutover by verified physical count + F360 sale branch): see `C3_CUTOVER.md`. No real location migrated.
- **Production:** nothing.

**Decisions approved 2026-09-25:**
- **D-R1:** keep exactly today's PRODUCTION economics. Store sales add **no** referral bonus; the repo version that adds one is **not** implemented. Referral is a separate future decision.
- **D-E1:** V1 uses a database RPC only. There is **no `pos-sale` Edge Function**.
- **D-K1:** the C3 cutover uses a double-control physical count (one person counts, another verifies, per variant). During the cutover the location cannot sell, receive or transfer.
- **D-P2:** while a location is legacy, its authoritative price is the legacy system price (`channel_inventory.price`). The price source is recorded per sale and line (`price_source`). It stops applying at migration.
- **D-PM:** a payment method is recorded from V1: `cash | card | transfer | other`, plus an optional reference. Card data is **never** stored: a reference with 12 or more consecutive digits is refused.
- **D-S2 (clarified):** a seller MAY record a sale to her own customer identity (the pair did leave). It gets **0 loyalty** and is audited explicitly as `self_sale`.
- **DW4:** returns are out of the first C3. They come later as compensating events; a historical sale is never edited or deleted.
- **Q7 (this flow):** every loyalty credit goes through the authorized, idempotent operation. The app cannot credit points (`loyalty_apply` is not executable by clients).

Built on what exists:
- S0.2 seller session (staging);
- C1 roles/locations/assignments (staging);
- C2 mapping (staging);
- A2 (rehearsed; production pending);
- the single f360 ledger;
- P2.3A (Woo stock sync).

## 0. The loop, in one picture

```
Seller (own account) ── PIN ──► shift session (person + ASSIGNED location)          [S0.2 ✔ staging]
      │ cart: variants + quantities (NO prices)
      ▼
record_store_sale(session, idempotency_key, lines, customer?)                         [S0.3 / C3]
  ONE TRANSACTION:
  1 session → seller + location (never from the request)
  2 price from the system (product master; legacy: channel_inventory.price)   (Q3, D-P1)
  3 lock stock rows; never negative (D-S1)
  4 SALE event + movements in the single ledger → balances                   (D-X1)
  5 store_sales + lines (the sale fact)                                      → Growth / Customer 360
  6 customer (optional): QR → card → D-S2 check → loyalty_apply              [S0.5]
     or claim code (customer claims later with HER OWN session)
  7 if the location feeds Woo: the queue trigger pushes the new stock        [P2.3A ✔]
  any failure → everything rolls back
```

---

## 1. S0.5: `loyalty_apply`, the single loyalty write path

**Goal:** centralize, **not** change economics (Q4).
- 100 points × counted pairs.
- Silver 300 / Gold 900 (`tier_config` + the existing `trg_update_tier`).
- Permanent tiers.

**Function** (public schema, SECURITY DEFINER, EXECUTE only for `service_role` and the sale RPCs' owner; never for clients):

```
loyalty_apply(p_card_id uuid, p_lines jsonb, p_amount numeric, p_channel text, p_ref_type text, p_ref_id text,
              p_idempotency_key text, p_actor jsonb, p_notes text DEFAULT NULL) → jsonb
```

1. **Idempotency.** New columns on `transactions`: `ref_type`, `ref_id`, `idempotency_key UNIQUE`. The same key returns the stored result (`replayed: true`).
2. **Lock the card** with `SELECT … FOR UPDATE`. This fixes P1-1 (lost updates).
3. **Pairs** = `loyalty_pairs_for_lines(p_lines)`. The **only** place that decides what counts; today it returns Σ quantity (Q4 category hook).
4. **Points** = pairs × `loyalty_points_per_pair()` (= 100, one place).
5. **INSERT `transactions`:** channel, server-computed amount, points, pairs, status `completed`, ref, idempotency key, actor.
   - The existing trigger `trg_purchase_stats` updates `purchases_this_year`, `total_pairs_count`, `last_purchase_at` exactly as today.
6. **INSERT `purchase_items`** with a **real SKU**. This fixes P1-14: today every store item insert fails silently. For legacy lines without a SKU, use a deterministic surrogate `LEGACY-<channel_inventory_id>`, so the NOT NULL is satisfied and traceable.
7. **UPDATE `loyalty_cards`** with **relative** increments `total_points = total_points + x`, `pairs_count = pairs_count + y`. `trg_update_tier` recalculates the tier as today.

Plus:
- `loyalty_reverse(p_ref_type, p_ref_id, p_idempotency_key, p_actor, p_reason)`: the same shape with negative deltas and a link to the original transaction, for refunds/returns once DW4 is decided.
- **Referral: see decision D-R1 (§6).** No bonus is paid by `loyalty_apply` until it is decided.
- **Callers migrated one by one:** claim/pos (this doc), webhook, link-orders, admin-points (`manual`, Q15). Each is its own unit.
- **Verification:**
  - a balance-vs-ledger drift report **before** and **after** (aggregate only);
  - existing drift is reported, never auto-corrected.

## 2. S0.3: the store sale, legacy branch (stores not yet migrated)

`pos_record_sale_legacy(p_token text, p_idempotency_key uuid, p_lines jsonb [{channel_inventory_id, quantity}], p_customer jsonb)`

It is SECURITY DEFINER, granted to `authenticated`; all authority is inside.

1. `s := f360.require_seller_session(p_token)`. The location must be `ledger_authority='legacy'`, and its `legacy_channel_id` is the channel. **No location or channel is accepted from the request.**
2. **Idempotency:** `offline_sales.idempotency_key UNIQUE`. A replay returns the same sale.
3. **Lock** the `channel_inventory` rows `FOR UPDATE`, ordered by id. Every row must belong to the session's channel, and `stock − sold ≥ qty`, otherwise refuse (**D-S1**: never negative; the seller requests an adjustment).
4. **Price** = `channel_inventory.price` as read **inside the transaction**. The request has **no price fields**; the RPC signature has none, and a price key in the lines → refused. This is the interim system price for legacy rows (Q3). Mapped products move to the master price at C3 (D-P1).
5. **INSERT `offline_sales`:**
   - `seller_auth_user_id`, `location_id`, `session_id`, and `staff_id` NULL (legacy column);
   - `total` computed by the server;
   - `code` from `gen_random_bytes` (not `Math.random`).
   
   **INSERT `offline_sale_items`** (new): one row per line with a product/size/color snapshot, `channel_inventory_id`, unit price, qty. This is the per-line audit (D-X1).
6. `UPDATE channel_inventory SET sold = sold + qty` (relative, under the lock).
7. **Customer (optional):**
   - **QR:** resolve `loyalty_cards.qr_code` server-side → card.
     - **D-S2:** if the card's customer `auth_user_id` = the seller's `auth_user_id` → refuse the loyalty part (the sale still completes, with no points).
     - Otherwise `loyalty_apply(card, lines, total, 'store', 'offline_sale', id, 'offline_sale:'||id, actor = seller)`, and mark the sale claimed.
   - **No QR:** the sale is complete and anonymous. Its claim code can be claimed later.
8. **Cutover S0.3c** (separate, after adoption):
   - staff UPDATE on `channel_inventory` and staff INSERT/UPDATE on `offline_sales` are revoked (only the RPC writes);
   - `claim-sale scan_qr` → 410.

**Claim later** (`claim_store_sale_v2(p_code)`): the customer's **own** JWT; customer = `auth.uid()`'s customer (never a phone in the body).
- **Atomic:** `UPDATE offline_sales SET claimed_at = now(), customer_id = … WHERE code = p_code AND claimed_at IS NULL RETURNING …`. A double claim is impossible.
- Then `loyalty_apply`, in the same transaction.
- **D-S2:** the claimer cannot be the sale's seller.

**Edge Function or RPC?** Recommendation: **RPC-only** (D-E1). Identity comes from `auth.uid()`, the location from the session, the price from the system, idempotency from a key, and there are no price parameters. So a separate `pos-sale` Edge Function adds a network hop without adding control. The approved S0.3 text names an Edge Function; this is a proposed simplification to confirm.

## 3. C3: the store sale on the single ledger (migrated locations)

`f360_record_store_sale(p_token text, p_idempotency_key uuid, p_lines jsonb [{variant_id, quantity}], p_customer jsonb)`

1. The session → seller + location (`ledger_authority='f360'`, sellable).
2. Idempotency: `f360.store_sales.idempotency_key UNIQUE`.
3. **Lock** `inventory_balances(variant, location)` `FOR UPDATE`, ordered by variant (the same order as transfers, so there are no deadlocks). `on_hand ≥ qty`, otherwise refuse (D-S1).
4. **Price** = the product master price (`sale_price` if set, else `regular_price`; one price per model, P-PRICE / D-P1), **snapshotted** per line.
5. **Ledger:** `inventory_events(SALE, actor = seller, actor_role = seller, reference store_sale:<id>)` + one `inventory_movements` row per line **from the location** + balances −q.
   - The P2.3A trigger queues a Woo push **only** if this location is a Woo fulfillment location (V1: Bodega CDMX). Store sales do not change online stock.
6. **Sale fact** (new, f360):
   ```
   f360.store_sales       id, number, location_id, seller_auth_user_id, seller_name, session_id, idempotency_key,
                          subtotal, total, currency, customer_card_id NULL, customer_id NULL, claim_code, claimed_at,
                          inventory_event_id, loyalty_transaction_id NULL, created_at
   f360.store_sale_lines  sale_id, variant_id, sku, product/color/size snapshot, unit_price, quantity, line_total
   ```
   Append-only, except the claim fields (set once, atomically).
7. **Customer and loyalty:** the same as §2.7 (QR → D-S2 → `loyalty_apply` with ref `store_sale:<id>`; or a claim code). **The identity of the customer is optional and separate from inventory.**
8. **No dual write.** A migrated location does **not** also write `offline_sales`. The app's "ventas de hoy" for f360 locations reads `store_sales` (C3 app release).

### What each consumer gets

| Consumer | From this sale | Reliability |
|---|---|---|
| Inventory | SALE event + movements; balances; history "Carolina vendió 1 par en Tienda X" | Confiable |
| Woo | a stock push only if the location is a Woo fulfillment location | Confiable (P2.3A) |
| Loyalty | one `transactions` + `purchase_items` (real SKU) + card increments, idempotent | Confiable (S0.5) |
| Customer 360 | `store_sales.customer_id` when identified by QR/claim, verified by the member's own session (never by a typed phone) | Confiable for identified members; anonymous otherwise (D-C5) |
| Growth | `store_sales` + lines: server price, variant (model/color/size/category), location, seller, time | **Confiable from each location's cutover date** (the store channel moves from "parcial" to "confiable" in `DATA_AUDIT.md`) |

## 4. C3 cutover procedure for the pilot (executed only after approval; nothing is invented)

**Preconditions:**
1. D-L1: the real pilot store exists as an f360 location (`legacy_channel_id` set, `ledger_authority='legacy'`).
2. C2 `catalog_ready = true` for it (D-M1).
3. A2, S0.2, S0.5 and S0.3 live in that environment.
4. The C3 app release is adopted by that store's sellers.
5. A physical count is scheduled with the store closed.

**Dormant pieces, created beforehand (additive):**
- `f360.stock_counts` / `stock_count_lines`: a count sheet by variant, entered by two people, or one counts and one verifies (D-K1).
- A guard trigger on `public.channel_inventory` that refuses `stock`/`sold` changes when the channel's location is `ledger_authority='f360'`. It has no effect until a location switches.
- A read-only compatibility view of `channel_inventory` for migrated channels, computed from `f360.inventory_balances` via C2 mappings, for legacy admin screens.

**At time T,** `f360_cutover_location(p_location, p_count_id, p_idempotency_key)` runs as owner in **one transaction**:
1. re-check: catalog ready; count complete and reviewed; no seller session open at that location;
2. insert one `ADJUSTMENT` event, "Saldo inicial (conteo físico)", with a movement per counted variant into the location;
3. set `ledger_authority='f360'`, which immediately activates the guard trigger;
4. store a cutover record: counts, legacy snapshot totals and their difference (aggregate), who, when.

**After:**
- a test sale (a real one, by a seller);
- the ledger reconciles;
- a `channel_inventory` write for that channel is refused (proved);
- the compatibility view equals the balances.

**Rollback, before the first f360 sale:** compensating `ADJUSTMENT` out (append-only; nothing is deleted) + `ledger_authority='legacy'` + unfreeze. After f360 sales, the rollback is a new count.

## 5. Tests (to write with each unit)

- **S0.5:**
  - 2 concurrent credits on the same card → no lost update;
  - a replayed key → 1 transaction;
  - `purchase_items` rows actually saved (P1-14);
  - tier as today (300/900);
  - economics identical on a fixture set (before/after comparison);
  - reversal symmetric.
- **S0.3 legacy:**
  - 2 simultaneous sales of the last pair → 1;
  - a price key in the request → refused;
  - the recorded price = `channel_inventory.price`;
  - an item from another channel → refused;
  - no session / expired / revoked / another person's token → refused;
  - a location in the request is ignored/refused;
  - a failure mid-way → nothing changes;
  - QR → points exactly once;
  - the seller's own card → sale ok, **no points** (D-S2);
  - double claim → one success;
  - claim by the seller → refused.
- **C3:**
  - all of the above, on balances;
  - the SALE event + movements reconcile;
  - no Woo push for a store, a push for Bodega;
  - `store_sales` lines carry the master price;
  - cutover: legacy writes refused afterwards, opening balance = count, compatibility view = balances, rollback before the first sale restores legacy.
- **End to end (the loop):** one sale with a QR → stock −1 at the location, SALE in history, `store_sales` row, loyalty +100/pair with a `purchase_items` SKU, the customer's card updated (realtime), Growth store revenue includes it, Customer 360 shows it on that member.

## 6. Decisions needed

| # | Decision | Recommendation |
|---|---|---|
| **D-R1 ✔ decided** | **Contradiction found:** the Sprint 0 plan says "referral unchanged: in-store first purchase credits the referrer 1×", but the **deployed** `claim-sale` v14 has **no referral bonus** (LIVE_RECONCILIATION). "Unchanged" must mean production behavior | **No referral bonus in store** (what runs today). Referral stays a later, separate decision |
| **D-E1 ✔ decided** | `pos-sale` Edge Function vs **RPC-only** | **RPC-only** (implemented: `public.f360_record_store_sale`) |
| **D-K1 ✔ decided** | Physical count method for cutover | Double control: one counts, one verifies; per variant; no selling/receiving/transferring during cutover |
| **D-P2 ✔ decided** | Legacy branch price = `channel_inventory.price` until the store migrates | Accepted; recorded as `price_source = 'legacy_channel_inventory'` per sale and line |
| **D-C5** (Track B) | Store sales without a customer = anonymous revenue | Yes (the design already supports it) |
| **D-PM ✔ decided** | Payment method on store sales | Required on the RPC: `cash\|card\|transfer\|other` + optional reference (≤64 chars, 12+ consecutive digits refused: never card data) |
| **DW4 ✔ decided** | Store returns / exchanges / refunds | **Out of this unit.** Later, as compensating events; history is never edited or deleted |
| **Q7 ✔ decided** | Who may credit loyalty | Only `loyalty_apply` (idempotent, authorized). The app can never credit points (EXECUTE revoked from anon/authenticated). The `loyalty-credit` caller migration is still a separate step |

## 7. Order to close the loop

1. **A2 production:** app release (b) adopted + (a) accounts.
2. **S0.2 production:** deploy Fuxia 360 core + C1 + S0.2; turn the app flag on.
3. **S0.5.**
4. **S0.3 legacy branch:** every store gets the safe, atomic sale while still on legacy stock.
5. **D-L1 + C2 review** for the pilot store.
6. **Transfers** (implemented in STAGING 2026-09-26: `TRACK_C_TRANSFERS.md` §7). **C3 dormant pieces + app release.**
7. **Pilot cutover** (count at T).
8. **The first real closed-loop sale.**

## 8. Implementation record: STAGING (2026-09-25)

Nothing here is in production. There are no commits. C3 is dormant.

### 8.1 Migrations (applied to staging `faltxpkaicwpnlqaxrdu`)

| File | What it adds | Rollback |
|---|---|---|
| `supabase/migrations/20261002000100_s05_loyalty_apply.sql` | `transactions` gains `ref_type`, `ref_id`, `idempotency_key` (partial UNIQUE) and `actor jsonb`. New `public.loyalty_apply_audit` (append-only, RLS on, no client access). New `loyalty_pairs_for_lines(jsonb)`, `loyalty_points_per_pair()` = 100, and `loyalty_apply(...)` | `supabase/rollbacks/20261002000100_s05_loyalty_apply.down.sql` |
| `supabase/migrations/20261002000200_s05_loyalty_apply_search_path.sql` | Adds `public` to `loyalty_apply`'s `search_path`. The existing trigger `trg_update_purchase_stats` references `loyalty_cards` unqualified, and that trigger is **not** modified | (same down file) |
| `supabase/migrations/20261002000300_s03_store_sale_legacy.sql` | `offline_sales` gains `idempotency_key` (partial UNIQUE), `seller_auth_user_id`, `location_id`, `session_id`, `payment_method`, `payment_reference`, `price_source`, `self_sale`, `loyalty_transaction_id` and `created_by_rpc`. New `public.offline_sale_items` (append-only, FK RESTRICT). New CHECK `channel_inventory_stock_sane` (`stock≥0, sold≥0, sold≤stock`). New `f360_record_store_sale`, `f360_claim_store_sale` and the view `f360.store_sale_facts` | `supabase/rollbacks/20261002000300_s03_store_sale_legacy.down.sql` |

### 8.2 RPC contracts

- **`public.loyalty_apply(p_card_id uuid, p_lines jsonb, p_amount numeric, p_channel text, p_ref_type text, p_ref_id text, p_idempotency_key text, p_actor jsonb DEFAULT '{}', p_notes text DEFAULT NULL) → jsonb`**
  - SECURITY DEFINER. EXECUTE is granted **only to `service_role`**; the only other callers are the definer RPCs below.
  - Order of operations: key → replay (returns the first result and audits `replayed`) → card `FOR UPDATE` → self-sale check (0 points, audited `self_sale`) → pairs > 0 → `transactions` row (same shape as claim-sale v14) → `purchase_items` → relative increments of `total_points` / `pairs_count` → audit `applied`.
  - The tier comes from the existing trigger (300/900, permanent). **No referral** (D-R1).
- **`public.f360_record_store_sale(p_token text, p_idempotency_key uuid, p_lines jsonb, p_payment_method text, p_payment_reference text DEFAULT NULL, p_customer_qr text DEFAULT NULL) → jsonb`**
  - Granted to `authenticated` and `service_role`; anon is revoked.
  - Seller, location and channel come from `require_seller_session`. The location must be legacy with a `legacy_channel_id`; an f360 location raises the C3 message.
  - Lines accept **only** `channel_inventory_id` and `quantity` (1–99, at most 50 lines); any other key is refused.
  - Rows are locked `FOR UPDATE` in id order, must belong to the shift's channel, and need `stock − sold ≥ qty`. The price comes from `channel_inventory.price`.
  - An optional QR leads to `loyalty_apply` inside the same transaction. An unknown QR, or any failure, rolls back everything.
  - Returns `{ok, replayed, sale_id, code?, total, lines, points, self_sale, claimed, location, seller, payment_method}`.
- **`public.f360_claim_store_sale(p_code text) → jsonb`**
  - The customer comes from `auth.uid()`. The claim is atomic: `UPDATE … WHERE claimed_at IS NULL AND created_by_rpc`.
  - Loyalty is credited with the actor set to the sale's seller, so a seller claiming her own sale gets 0.
- **`f360.store_sale_facts`**
  - One row per RPC sale (`source = 'store_legacy'`), carrying units, total, customer, seller, location, payment method and self-sale.
  - Growth and Customer 360 read this view. There is no client access.

### 8.3 Evidence

- **S0.5 economics BEFORE vs AFTER:** `docs/fuxia360/audit/s00a_results/s05_economics.json`.
  - Script: `scripts/f360/s05_economics.mjs`. BEFORE = the deployed claim-sale `scan_qr`; AFTER = `loyalty_apply`.
  - **Identical in all 6 scenarios:** points, pairs, tier (including crossing 300 and 900, staying gold, and a line without quantity), `total_pairs_count`, `purchases_this_year`, `last_purchase_at`, and the tx amount/channel/status/currency.
  - **The one difference:** `purchase_items` saved. BEFORE saved 0 in every scenario (a silent `sku NOT NULL` failure); AFTER saved all of them.
- **S0.3 BEFORE vs AFTER:** `docs/fuxia360/audit/s00a_results/s03_before_after.txt`.
  - Probe: `supabase/staging/f360_s03_before_after_probe.sql` via `scripts/f360/s03_before_after.mjs`, rolled back.
  - Legacy staff on the current client path **can**: record a $1 sale of a $2,800 pair; decrement stock with no sale; rewrite the price; and double-tap into 2 sales.
  - The RPC refuses every one of those.
- **Rolled-back DB suite:** `supabase/staging/f360_s05_s03_tests.sql`, **37/37 PASS**. All 8 suites pass (209 checks).
- **Real concurrency** (committed synthetic fixtures, then removed): `scripts/f360/s03_concurrency.mjs` → `s00a_results/s03_concurrency.txt`, **7/7 PASS**.
  - Two parallel sales of the last pair: exactly one wins.
  - Two parallel sales to the same card: exactly 200 points.
  - Ten parallel `loyalty_apply` calls: exactly +1000.
  - A double tap with the same key in flight: 1 sale, and both calls get it.
  - Growth facts: one per sale.

### 8.4 Behavior changes (RPC path only; the legacy path is unchanged until S0.3c)

1. `purchase_items` are now actually saved. SKU-less lines get a surrogate: `LEGACY-<channel_inventory_id>-<n>`.
2. A self-sale earns 0 points and is audited as `self_sale`. Before, it earned points like any other sale.
3. An unknown customer QR fails the **whole** sale. Before, stock was already decremented when the claim-sale call failed.
4. The payment method is required.
5. `channel_inventory` can no longer hold `sold > stock` or negative values, **on every path**, the legacy one included. That is the CHECK.
6. The claim code is 8 hex characters generated by the server. Before, it was 6 characters generated by the client.

### 8.5 Open items that are NOT part of this unit

- **S0.5 remainder:**
  - Q15 `manual` channel + `admin-points` through `loyalty_apply`;
  - Q5 `link-orders` / webhook reversal;
  - migrating the `loyalty-credit` caller;
  - migrating the web/Woo webhook to `loyalty_apply`.

  Today only the store paths call it.
- **S0.3c cutover:** revoke the legacy client write paths on `offline_sales` / `channel_inventory` and retire claim-sale `scan_qr`.
- **The cleanup of synthetic concurrency fixtures** lifts the append-only trigger on `offline_sale_items` **only** inside its own staging transaction, and only for its own synthetic channel. The audit tables (`loyalty_apply_audit`, seller events) keep their synthetic rows by design.
