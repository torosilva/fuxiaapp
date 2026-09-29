# Track C — MIGRATION PLAN (design only; nothing executed)

No production changes, no data migration, no app changes, no resets are part of this document. Every phase is a separately approved unit, staging first.

## 1. Contradiction to resolve first (CLAUDE.md rule 14)

**Documentation vs reality:** `SPRINT_0_IMPLEMENTATION_PLAN.md` S0.3 designs a **new** `public.inventory_events` table ("audit only", later migrated into the Sprint 2 ledger). That ledger **now exists**: `f360.inventory_events` / `inventory_movements`, live in staging since Admin V1. Building S0.3 as written would create a **second ledger**.

**Proposal (D-X1):**
- S0.3 keeps its security goal: an atomic, server-side, idempotent sale with system price and an individual seller session. That goal fixes P0-2/P0-4 and is urgent.
- But S0.3 does **not** create `public.inventory_events`. Its per-line audit lives in the sale's own item rows (`offline_sale_items`).
- For locations already on `ledger_authority='f360'`, the sale goes through `f360_record_store_sale` and writes the one ledger.

This needs approval because it edits an approved S0.3 detail.

## 2. Prerequisites (blocking)

1. **S0.0A in production:** A2 removes anon access (the `anon_update_inventory_sold`, `anon_read_active_staff` and `anon_*_offline_sales` policies), plus A1 and A3. Today they are applied **only in staging**. Until then, anyone can change store stock and prices directly, so no inventory migration is trustworthy.
2. **S0.2:** individual seller identity plus a server session (Q1/Q2).
3. **S0.5:** an atomic `loyalty_apply`, so a sale and its points are one transaction.
4. Track C decisions D-L1, D-M1, D-P1, D-S1 and D-X1.

## 3. Phases

| Phase | What | Master of store stock | Writes to `channel_inventory` | Writes to the f360 ledger for that location |
|---|---|---|---|---|
| **C0 (today)** | Stores: `channel_inventory`. Bodega CDMX + online: Fuxia 360. **No overlap:** no f360 location corresponds to a channel yet | `channel_inventory` | yes (legacy app) | no |
| **C1: roles and locations (additive)** | `seller` role, `location_assignments`, `seller_sessions`, `f360.locations` rows created **by Mario** for real stores/bazaars with `legacy_channel_id` and **`ledger_authority='legacy'`**. RPCs exist but **refuse** legacy locations | `channel_inventory` | yes | no (refused by the DB) |
| **C2: catalog mapping (read-only analysis)** | `f360.legacy_inventory_map(channel_inventory_id → variant_id, status: mapped / unmapped / ambiguous, reviewed_by)`. Proposed from product name, size, color and SKU; **confirmed by a person**. Unmapped rows are listed per D-M1. Nothing moves | `channel_inventory` | yes | no |
| **C3: pilot location cutover** (one store, chosen by Mario, **physical count**) | At time T, in one transaction: (a) freeze that channel's `channel_inventory` (a guard trigger rejects `stock`/`sold` writes for channels whose location is `f360`); (b) write an `ADJUSTMENT` "saldo inicial" event per variant with the **counted** quantity; (c) set `ledger_authority='f360'`. The seller app for that location uses `pos-sale` → `f360_record_store_sale` | **Fuxia 360** | **no (DB guard)** | yes |
| **C4: location by location** | Repeat C3 per store/bazaar. Bazaars: create the location, **transfer** from Bodega (no separate stock universe), and when the bazaar ends, transfer the remainder back | f360 (migrated) / legacy (not yet) | only non-migrated channels | only migrated locations |
| **C5: retire `channel_inventory`** | When every location is `f360`: revoke all writes; archive the table (read-only history); remove the legacy app paths (with the app release) | Fuxia 360 | none | all |

## 4. `channel_inventory` during the transition, and how double discount / double master is avoided

- **One writer per location, enforced by the database:**
  - `ledger_authority` on the location decides which system may change stock there.
  - A BEFORE UPDATE/INSERT trigger on `channel_inventory` rejects stock changes for channels whose location is `f360`.
  - `f360_record_store_sale` / `f360_transfer_inventory` reject locations still `legacy`.
  - So a location can **never** be decremented in both systems.
- **No dual-write, no sync between the two.**
  - We do **not** mirror sales from one system to the other: mirroring is how double discounts happen.
  - During C1–C2 the legacy system is the only master for stores. At C3 the switch is atomic at time T.
- **The opening balance comes from a physical count, not from copying `channel_inventory`.**
  - Today's `channel_inventory` can be wrong: the sale decrement is non-atomic, errors are ignored, and anon could edit it.
  - A comparison report (count vs legacy numbers) is produced for Mario, **aggregate by default**, and archived as evidence of the difference.
- **Idempotency across the boundary:**
  - sales started before T on the legacy path finish on the legacy path;
  - the app version decides the path **per location** from the server (`ledger_authority`), not from a local flag;
  - a stale app hitting a migrated location gets a clear error ("actualiza la app"), never a silent legacy write.
- **Readers of `channel_inventory`** (admin screens, dashboards) keep working through a **read-only compatibility view** for migrated locations, computed from `f360.inventory_balances`, until the app release replaces them.
- **Unmapped legacy products (D-M1 — APPROVED 2026-09-25: every product physically in a location must exist/be mapped in Fuxia 360 before its cutover; no two masters inside a location. The temporary exception below is therefore REJECTED; C2's `f360_location_migration_readiness` is the gate):** if Mario chooses to keep them in `channel_inventory` until the legacy catalog migration, a location has **two masters for disjoint sets of products**. The guard applies per (location, product). This is allowed only as a documented temporary exception with an end condition. The recommended alternative: create those models in Fuxia 360 before the location's cutover.

## 5. Data migration rules (when approved)

- **Nothing is deleted:** legacy rows are frozen and archived.
- **Mappings are reviewed by a person.** Ambiguous rows are never auto-assigned. Unmapped stock is reported, not guessed.
- **Historical `offline_sales`** stay as history. They can feed Growth later as a **separate** source (`source='store_legacy'`, flagged "parcial": client-built prices, no SKU), never mixed with the new store sales as if equivalent.
- **Validation per cutover:**
  - Σ opening `ADJUSTMENT` = counted pairs;
  - after the first day, the ledger reconciles (in − out = balance);
  - no `channel_inventory` stock change after T for that channel (the trigger and the test prove it).

## 6. Rollback

- **C1 / C2:** additive; drop the objects.
- **C3 (per location), before any f360 sale there:** set `ledger_authority='legacy'` and unfreeze. After f360 sales there, the rollback is a **new count** plus re-enabling legacy. The ledger is never edited (append-only), so no history is lost.

## 7. Tests (to write when implementing)

- a seller with no assignment → cannot sell anywhere;
- a seller assigned to A tries B → rejected even with a forged body;
- 2 simultaneous sales of the last pair → one succeeds;
- same idempotency key twice → one sale, one event;
- a price field in the request → 400;
- a sale with no customer → stock discounted;
- a sale with a QR → points exactly once;
- a transfer with insufficient stock → nothing moves;
- a transfer is atomic across all its lines;
- a legacy location → the f360 RPC refuses it;
- a migrated location → a `channel_inventory` write is refused by the trigger;
- the compatibility view equals the f360 balances;
- the ledger reconciles after each scenario.

## 8. Order relative to other tracks

S0.0A-in-production (A2) → S0.2 → S0.3 (re-scoped per D-X1) + S0.5 → **C1 → C2 → C3 (pilot) → C4 → C5**.

Track C also unblocks, for Track B, a **reliable** store-sales source (`store_sales`, with location, seller, variant and price).
