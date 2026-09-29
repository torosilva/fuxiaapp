# Boundary: Sprint 0 security units (S0.2 / S0.3 / S0.5) ↔ Track C (C1 / C2 / transfers / C3)

Purpose: every security control is built **once**, in exactly one unit, and the other units reuse it. Approved decisions applied: D-L2, D-T1, D-P1, D-S1, D-S2, D-M1, **D-X1**. D-L1 is pending.

## 1. Who owns what

| Concern | Owner unit | Reused by | Notes |
|---|---|---|---|
| **Who a person is** (Supabase Auth account, own phone) | existing OTP login, hardened by S0.0A (A3/A6–A8) | everything | Never `customers.role`, phone or `user_metadata` for authorization |
| **Role** (owner / operator / seller / viewer) | **C1** (`f360.user_roles`, built in staging) | S0.2, S0.3, transfers, admin web | `seller` added by C1 |
| **Where a seller may act** | **C1** (`f360.location_assignments`, `f360.require_location()`, built) | S0.2 (shift start), S0.3 (sale), transfers | Several locations per seller (D-L2). Replaces `staff.channel_id` as the authority |
| **Which system masters a location's stock** | **C1** (`locations.ledger_authority`; receive refuses legacy, built) | S0.3 (routes the sale), transfers, C3 | One master per location |
| **Seller authentication**: PIN hash, lockout, attempts audit, per-shift session | **S0.2** | S0.3, transfers (seller actions) | S0.2 is **re-based on C1**: the session binds `auth user + f360 location`; the allowed locations come from `location_assignments`, not `staff.channel_id` |
| **Legacy `public.staff`** | S0.2 (link `staff.auth_user_id`, hash PIN) | legacy app screens until S0.2c | Kept only for compatibility; not an authorization source after S0.2c |
| **The sale's security layer**: seller JWT + session validation, **reject any price field**, idempotency key, location **from the session** | **S0.3** (`pos-sale` Edge Function), built once | both sale branches | Q1 / Q3 / D-P1 |
| **Sale on a legacy location** (`ledger_authority='legacy'`) | **S0.3**: `pos_record_sale_legacy`, atomic on `channel_inventory` + `offline_sales` + `offline_sale_items` | — | **D-X1: no `public.inventory_events`.** The per-line audit is `offline_sale_items` |
| **Sale on an f360 location** | **C3**: `f360_record_store_sale` (f360 ledger + `store_sales`) | Customer 360 / Growth | Built at C3, behind the same `pos-sale` layer |
| **Loyalty** (atomic points / tier / transactions + purchase_items with a real SKU, idempotent per reference) | **S0.5** `loyalty_apply` | both sale branches | Economics unchanged (Q4). Fixes the silent `purchase_items.sku` failure |
| **D-S2: no points to the seller's own identity** | **S0.3** (the sale RPC knows the seller) | both branches | Reject when the card's `customers.auth_user_id` = the session's `auth_user_id` |
| **D-S1: physical pair but 0 in the system** | S0.3 (legacy) / C3 (f360): the sale is refused | — | An authorized adjustment first. Never negative |
| **Transfers with "en camino"** (D-T1) | **Track C** (after S0.2, since sellers request and confirm) | — | f360 locations only. See `TRACK_C_TRANSFERS.md` |
| **Catalog mapping** + D-M1 gate | **C2** (built in staging) | C3 | Read-only on `channel_inventory` |
| Anonymous access removal | **S0.0A-A2** (production runbook) | prerequisite of all | `A2_PRODUCTION_RUNBOOK.md` |

## 2. What changes in the approved S0 designs (documentation updated)

- **S0.2:**
  - `staff_sessions` becomes `f360.seller_sessions(auth_user_id, location_id, …)`;
  - `staff-login {location_id, pin}` checks `f360.require_location` for the caller;
  - the PIN hash, lockout and audit are unchanged;
  - enrollment still links `public.staff.auth_user_id` for the legacy screens.
- **S0.3 (D-X1):**
  - `public.inventory_events` is **removed** from the design;
  - `pos-sale` routes by `ledger_authority`: legacy → `pos_record_sale_legacy` (channel_inventory); f360 → `f360_record_store_sale` (f360 ledger, C3);
  - `CHECK (sold ≥ 0 AND stock ≥ 0 AND sold ≤ stock)` on `channel_inventory` stays (after the S0.1a aggregate check).
- **S0.5:** unchanged, plus a `reference` (`offline_sale:<id>` / `store_sale:<id>`) as the idempotency key.

## 3. Order

**A2 (production)** → **S0.2 on C1** → **S0.5** → **S0.3** (legacy branch live; f360 branch dormant) → **transfers** → **C3 pilot** (needs D-L1 plus a physical count).

The mobile app changes only in S0.2 R1 and S0.3 R1, as already planned. There are no separate app changes for C1/C2.

## 4. Detailed designs

- S0.2 (implemented in staging): `S0_2_SELLER_SESSION.md`.
- S0.5 `loyalty_apply`, S0.3 legacy sale + claim, and the C3 f360 sale + pilot cutover (design only): **`CLOSED_LOOP_STORE_SALE.md`**.

Open items raised there:
- **D-R1:** the plan says referral is unchanged, but the deployed `claim-sale` has **no** referral bonus.
- **D-E1:** use an RPC only, with no Edge Function.
- **D-K1:** the physical count method.
- **D-P2:** the legacy interim price.
- **D-PM:** capturing the payment method.
