# Track C — TARGET ARCHITECTURE (design only; NOT implemented)

Goal: stores and bazaars run on the **same** Fuxia 360 ledger as Bodega CDMX and online sales. The app's seller flow is **kept** and connected; it is **not** replaced by a second POS.

## 0. Principles

1. **One ledger:** `f360.inventory_events` + `f360.inventory_movements` + the `f360.inventory_balances` cache. No second ledger (not `public.inventory_events`, not `channel_inventory`).
2. **One master per location at any moment.** This is enforced in the database, not by convention (see the Migration Plan).
3. **Identity is server-controlled:** authenticated user → role → locations. Nothing from the client body decides who sells or where.
4. **Inventory location and customer identity are separate.** A sale always discounts the seller's location, whether or not a customer is identified.
5. **Prices come from the system** (Q3). The seller never sends a price.
6. **Every stock-changing business event is one transaction:** atomic, idempotent, auditable, never negative.

## 1. Locations

Reuse the existing **`f360.locations`**; no new entity. It already has `type ∈ {warehouse, receiving, store, bazaar, workshop, other}`, `is_authoritative`, `sales_sync_pending` and `legacy_channel_id → public.channels`.

**Additive columns:**

| Column | Why |
|---|---|
| `ledger_authority text CHECK IN ('legacy','f360') DEFAULT 'f360'` | Per-location cutover switch (Migration Plan). Bodega CDMX = `f360`; every location migrated from a channel starts at `legacy` |
| `starts_on date`, `ends_on date` (bazaars) | A bazaar's lifecycle. After it ends, remaining stock must be transferred back |
| `sellable boolean` | A physical sale can be recorded there (true for store/bazaar, false for warehouse) |

**Hierarchy:** bodegas (warehouse/receiving) → tiendas (store) → bazares (bazaar). Real locations are **not invented**: Mario provides the list (D-L1). Existing `public.channels` rows map 1:1 through `legacy_channel_id`.

## 2. Roles and location assignment

**Roles** (`f360.user_roles.role`), with the existing rank extended:

| Role | Scope | Can |
|---|---|---|
| `owner` | all locations | everything, including publishing (DW8), roles, locations, approvals |
| `operator` | all locations (V1) | receive, transfer, adjust with a reason, approve seller requests, resolve alerts |
| `seller` | **only assigned locations** | physical sale, return (policy pending), see stock of assigned locations, *request* adjustments and transfers |
| `viewer` | read only | reports and stock |

- **New table** `f360.location_assignments(auth_user_id, location_id, active, granted_by, granted_at, revoked_at)`, with `UNIQUE(auth_user_id, location_id)`.
  - A seller must have **≥ 1 active assignment**.
  - Several are allowed (D-L2); for example, a seller covering a bazaar.
- **Server rule** used by every seller RPC: `f360.require_location(p_location, 'seller')`.
  - It passes only if the caller's role is owner/operator, **or** the role is seller **and** there is an active assignment to `p_location`.
  - A seller can therefore **never** attribute a sale or a movement to a location they are not assigned to.
- **Identity:**
  - **Auth account:** each seller is an individual Supabase Auth user (their own phone login, as in S0.2 / Q1).
  - **Link to Fuxia 360:** `f360.user_roles(auth_user_id, role='seller')`.
  - **Legacy `public.staff`:** linked by `staff.auth_user_id` for the transition only.
  - **PIN:** stays as the S0.2 per-shift step. It is hashed, checked for **that** seller only, and creates a server session bound to **user + location** (`f360.seller_sessions`). Every sale carries the session; the location comes from the session.
- **Never used for authorization:** `customers.role`, phone, `user_metadata`, route params.

## 3. Move inventory (transfer) on the single ledger

`public.f360_transfer_inventory(p_idempotency_key uuid, p_from uuid, p_to uuid, p_lines jsonb [{variant_id, quantity}], p_note text)`

- **Who:**
  - owner/operator: any pair of locations;
  - seller: only a **request** (`f360.transfer_requests`, approved by an operator). Whether sellers may move stock directly between their own assigned locations is D-T1.
- **One transaction:**
  1. Idempotency: an existing key returns the same event.
  2. Validate `from ≠ to`, both active; the caller is authorized for both (or it is an approved request).
  3. Lock the `from` balances `FOR UPDATE`, **ordered by variant_id** (no deadlocks with concurrent sales).
  4. Check `on_hand(from, variant) ≥ quantity` for every line, otherwise reject the whole transfer.
  5. Insert `inventory_events(TRANSFER)` + one `inventory_movements` row per line (`from_location_id`, `to_location_id`, `quantity`).
  6. `inventory_balances`: from −q, to +q.
  7. The existing trigger queues a Woo stock push if Bodega CDMX changed (P2.3A).
- **In transit** (goods leave the bodega today and arrive tomorrow): V1 proposal is one step. If Mario wants to see "en camino", a two-step `TRANSFER_OUT` → virtual `in_transit` location → `TRANSFER_IN` fits the same ledger (D-T1).
- **Never negative** (`CHECK on_hand ≥ 0` already exists). **Audit:** actor, role, session, note, timestamps; append-only.

## 4. Physical sale from the app (one consistent operation)

**Server function** `public.f360_record_store_sale(p_session uuid, p_idempotency_key uuid, p_lines jsonb [{variant_id, quantity}], p_customer jsonb NULL)`. It is called only by an Edge Function (`pos-sale`) that validates the seller's own JWT **and** the seller session, as in S0.3. It is **not** callable directly by clients.

**Inside one transaction:**
1. **Idempotency:** the same key returns the same sale (double tap, network retry).
2. **Session → seller + location:** the location comes from the **session**, never from the body. The location must be `sellable`, `ledger_authority='f360'`, and the seller assigned to it.
3. **Price from the system only:** today the model's `regular_price`/`sale_price` (P-PRICE: one price per model). A request containing any price field → 400. Location-specific prices would be a separate decision (D-P1).
4. **Stock:** lock the balances at the seller's location `FOR UPDATE` (ordered), and require `on_hand ≥ qty` for each line. **Never negative.** Selling a pair the system says doesn't exist is D-S1.
5. **Ledger:** `inventory_events(SALE, actor = seller, reference = store_sale:<id>)` + movements `from = location` + balances −q.
6. **Commercial record:** `f360.store_sales` + `f360.store_sale_lines` (variant, SKU, model/color/size snapshot, unit price, qty, line total, location, seller, session).
   - This is the **sale fact** used by Customer 360 and Growth (`source='store'`), kept separate from Woo orders.
   - It replaces client-built `offline_sales.items`. A compatibility row in `offline_sales` can be written during the transition so existing screens keep working.
7. **Customer (optional; never required to discount stock):**
   - **QR:** resolved server-side to a loyalty card/customer. The card id is stored on the sale.
   - **Claim code** generated with `gen_random_bytes`; the customer claims it later with **their own JWT** (not a phone in the body).
   - **No customer:** the sale is complete and anonymous (revenue without a customer, D-C5).
8. **Loyalty (existing economics unchanged, Q4):** when a card is known, call one atomic DB function (`loyalty_apply`, S0.5) with reference `store_sale:<id>`. It is idempotent per reference, and replaces the Deno read-modify-write. `transactions` / `purchase_items` rows are written there with real SKUs.
9. **Customer 360 / Growth:** fed from `store_sales` (the location, seller, variant, price and optional customer link are all present). No extra writes.

**A failure at any step rolls everything back:** no stock change, no sale, no points.

## 5. Returns / exchanges in store (design hook only)

A `RETURN` event into the seller's location, referencing the original `store_sale`. Refund, exchange and restock policy follow DW4 (**pending Mario**).

## 6. Future traceability (batch → physical pair)

Nothing changes in this design. Every quantity movement already references `variant_id` + `location`. Later:
- `RECEIPT` events get a `batch_id`;
- a unit table links a `unit_serial` to a variant/batch;
- sales and transfers add **unit assignment rows** pointing at the movement id (P2.2 compatibility review).

Store sales would simply scan the pair.

## 7. What changes for the seller (UX)

Almost nothing: open the app → **"Modo Vendedora"** → choose among **their assigned** locations (usually one, so skipped) → PIN → cart → QR / code / skip → done.

**Differences:**
- they must be logged in with their own account;
- the cart shows Fuxia 360 models (model → color → size) instead of free-text rows;
- if they have more than one location, it shows only theirs.

## 8. Decisions (updated 2026-09-25)

**Approved:**
- **D-L2:** several locations per seller; she chooses among her assignments at the start of a shift.
- **D-T1:** transfers go solicitado → enviado → en camino → recibido (`TRACK_C_TRANSFERS.md`).
- **D-P1:** the master price per product; no per-location prices in V1.
- **D-S1:** block the sale and require an authorized adjustment; never negative.
- **D-S2:** no points to the seller's own identity.
- **D-M1:** every product physically in a location must be in / mapped to the F360 catalog before its cutover; no two masters inside one location.
- **D-X1:** no `public.inventory_events`; the store sale writes the single f360 ledger.

**Pending:** D-L1 (real list of locations). The original decision table follows for reference.

### Original decision table

| # | Decision |
|---|---|
| **D-L1** | The real list of locations (stores, bazaars, bodegas). Nothing is invented |
| **D-L2** | Can a seller be assigned to several locations (e.g. store + bazaar)? The design allows it |
| **D-T1** | Transfers: one step, or with "en camino"? May sellers move stock themselves, or only request it? |
| **D-P1** | Store price = the same model price as online, or per-location prices? (Today `channel_inventory.price` is per row) |
| **D-S1** | A pair physically in the store but 0 in the system: block the sale and request an adjustment (recommended), or allow it with an alert? |
| **D-S2** | Can a seller credit loyalty points to their own card? (Noted in S0.2, undecided) |
| **D-M1** | Legacy (non-F360) products in stores: create their models in Fuxia 360 before cutover, or keep them in `channel_inventory` until the legacy catalog migration? Directly affects "no two masters" (Migration Plan §4) |
| **D-X1** | **Contradiction in S0.3** (see Migration Plan §1): drop the planned `public.inventory_events`, since the Fuxia 360 ledger now exists |
| DW4 / D-C* | Returns/refund policy; customer identity decisions (Track B) |
