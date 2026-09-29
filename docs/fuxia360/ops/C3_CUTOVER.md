# C3: Location cutover (legacy → f360) and the F360 store sale

**Status:** implemented and tested in **STAGING** (2026-09-28).
- No real location, count or sale.
- Nothing in production.
- No app release.

## 1. Migrations

| File | Content |
|---|---|
| `supabase/migrations/20261004000100_f360_c3_cutover_and_f360_sale.sql` | The whole unit (7 parts, below) |
| `…000200_f360_c3_count_reopens.sql` | Fix: a size can be counted (or recounted) from `verification` / `ready`; this reopens the count |
| `…000300_f360_c3_complete_alias_fix.sql` | Fix found by the suite: an alias collided with a PL/pgSQL variable, so completion failed. The failure was safe: rolled back and audited |
| `supabase/rollbacks/20261004000100_f360_c3_cutover_and_f360_sale.down.sql` | **Refuses** to run once any cutover, opening count or F360 sale exists |

What `20261004000100` contains:
1. Tables `f360.location_cutovers`, `f360.cutover_counts`, `f360.cutover_changes`, and the event type `OPENING_PHYSICAL_COUNT`.
2. Invariant triggers.
3. The legacy freeze.
4. The cutover RPCs.
5. The F360 branch of `f360_record_store_sale`.
6. `f360_shift_catalog`.
7. The `online_location` fix.

## 2. Cutover states

`preparing → counting ⇄ verification → ready → completed`, and `cancelled` from any state that is not final.

| From | To | When |
|---|---|---|
| `preparing` | `counting` | The first count line is entered |
| `counting` | `verification` | `finish_count`. Every size with legacy units must have a line (0 allowed) |
| `verification` | `ready` | Every line is verified by someone other than its counter, and the numbers match |
| `verification` | `counting` | Any line mismatches. That line must be recounted |
| `verification` / `ready` | `counting` | A size is added or recounted. It needs a fresh double control |
| `ready` | `completed` | `complete`, in one transaction |

There is no persisted `failed` state. A failed completion is rolled back entirely, recorded as `complete_failed` in the audit (with the reason), and the cutover stays `ready`, so the cause can be fixed and completion retried.

## 3. RPCs

| RPC | Who |
|---|---|
| `f360_start_cutover(key, location, note)` | owner / operator |
| `f360_cutover_count(cutover, [{variant_id, quantity}])` | owner / operator / seller assigned to the location |
| `f360_cutover_finish_count(cutover)` | same |
| `f360_cutover_verify(cutover, [{variant_id, quantity}])` | same, **≠ the counter of each line** (also a CHECK) |
| `f360_get_cutover(cutover)` | same. **Blind:** each person sees only her own number, until a line mismatches or the cutover is ready |
| `f360_cancel_cutover(cutover, reason)` | owner / operator |
| `f360_complete_cutover(key, cutover)` | owner / operator |
| `f360_record_store_sale(...)` | same signature; branch chosen by `ledger_authority` |
| `f360_shift_catalog(token)` | seller on shift: what she can sell at her location (ledger + master price, or legacy rows) |

## 4. Completion: one transaction

1. **C2 gate, live:** every legacy row of the store with units must be `confirmado`. `catalog_ready` must also hold. The gate result is stored as evidence.
2. **Double control complete:** every line is verified, verifier ≠ counter, and every required size is counted.
3. **No ledger history** at the location: no second opening balance.
4. **The event:** an `OPENING_PHYSICAL_COUNT` event plus one movement per counted size. The quantities come **only** from the verified count, never from `channel_inventory`.
5. **Check:** `inventory_balances == count`, exactly.
6. **Switch:** cutover → `completed`, then `ledger_authority` legacy → f360.
7. **Freeze:** legacy writes for that store are now frozen by triggers.

**Idempotency and uniqueness:**
- The same key replays the result; another key gets "ya se ejecutó".
- There is one completed cutover per location, and one opening event per location (unique indexes).

## 5. Invariants (enforced by the database, not by the UI)

**While a cutover is open:**
- the legacy branch refuses to sell;
- `channel_inventory` cannot be written at all, even by privileged code, because a trigger blocks it;
- a client cannot insert a sale for that store;
- receipts and transfers are refused.

**Switching `ledger_authority`:**
- legacy → f360 is possible only with a completed, verified cutover;
- f360 → legacy is impossible. Corrections are compensating ledger events.

**After the cutover:**
- `channel_inventory` of the store is frozen forever, and the C2 evidence is frozen too;
- a client can never forge an RPC-only sale row.

## 6. F360 sale (C3.2)

The same guarantees as S0.2 / S0.3 / S0.5:
- seller shift and live assignment;
- location from the shift;
- lines accept only `{variant_id, quantity}`;
- payment method required;
- idempotency key;
- an unknown QR rolls the whole sale back;
- loyalty through `loyalty_apply`, where a self-sale gets 0.

What is new for an f360 location:
- **Stock:** balances are locked in variant order, and the sale is refused if `on_hand < qty`.
- **Price:** the master price, `coalesce(sale_price, regular_price)`. A product without a price cannot be sold.
- **One transaction produces:**
  - one `offline_sales` row (`sale_event_id`);
  - its `offline_sale_items` (`variant_id`, `price_source`);
  - one `SALE` event with movements location → out;
  - the balance update;
  - loyalty, when a customer is given;
  - one `f360.store_sale_facts` row (`source = 'store_f360'`).
- `channel_inventory` is never touched.

Legacy locations use the legacy branch, unchanged.

## 7. online_location

`f360.online_location()` is now the active sales target's `fulfillment_location_id` (production target first). It is the same relation Woo sync already uses, so there is no new source of truth.

Creating or reordering warehouses can no longer change it.

## 8. Tests

| Suite | Result | How |
|---|---|---|
| `supabase/staging/f360_c3_tests.sql` | **87/87** (`s00a_results/c3_db_tests.txt`, including the BEFORE/AFTER snapshots) | Rolled back |
| `scripts/f360/c3_concurrency.mjs` | **12/12** (`s00a_results/c3_concurrency.txt`) | Real concurrency |

The concurrency harness covers:
- simultaneous completions;
- the last pair sold by two sellers at once;
- a double tap with the same key;
- two sales to one customer at once.

Its cleanup is `c3_fixtures.mjs`. It is strictly scoped to the fixtures, and it refuses to run if anything touches a real location or card.

## 9. C3.3: Ventas in Fuxia 360 Web

It is a **read model** of the sales the RPC already records. There is no second sales model.

| Piece | What it is |
|---|---|
| `supabase/migrations/20261004000400_f360_c3_sales_read_model.sql` | `f360.sales_facts` (one row per sale, `channel='store'` today); `f360_list_sales(from, to, location, seller, channel)` and `f360_get_sale(id)`. Rollback: `.down.sql`, which drops only read objects |
| `admin-web/src/app/(app)/ventas/` | List and detail pages; "Ventas" in the navigation, owner/operator only |

**What is included:**
- Only sales created by the RPC (`created_by_rpc`), from both branches, legacy and f360.

**What is excluded:**
- sales written by the old client path (client prices, no idempotency);
- manually reported figures (B4);
- returns (DW4).

**List:**
- Filters: date (Mexico City days), location, seller, and channel. "En línea" is shown but disabled until P2.3B.
- Summary for the filtered period: revenue, number of sales, pairs, average ticket.
- Each row: customer or "Sin identificar", pairs, total, payment method, status.

**Detail:**
- items (model / color / size / quantity / price);
- the related inventory movement (the ledger `SALE` event, or "descontado del sistema anterior" for a legacy sale);
- loyalty credited, or the reason it was not: self-sale, or a claim code still pending;
- a masked phone;
- support ids (sale, idempotency key, claim code, session, ledger event, loyalty transaction and audit).

**P2.3B** will add online orders as a `UNION ALL` into `f360.sales_facts` (`channel='online'`). The same screen and the same filters then show both, with no new dashboard.

**Tests:**
- 13 checks in `f360_c3_tests.sql` (100/100 in total);
- E2E `admin-web/e2e/c3-closed-loop.spec.ts`. Fixtures come from `scripts/f360/c3_e2e_prepare.mjs` and are removed with `c3_cleanup.mjs`. The E2E follows one sale: sale through the app's RPC → inventory −1 → loyalty → Customer 360/Growth fact → the same sale in Ventas. Screenshots are in `admin-web/e2e-screenshots/c3/`.
