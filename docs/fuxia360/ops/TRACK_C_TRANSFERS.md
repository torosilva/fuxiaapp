# Track C — Transfers with inventory "en camino" (implemented in STAGING 2026-09-26; not in production)

Decision D-T1: **solicitado → preparado/enviado → en camino → recibido.**
- Owner/operator authorize and send.
- A seller can **request**, and can **confirm receipt** if assigned to the destination.
- A seller never moves stock arbitrarily.

## 1. Core rule: stock is never available in two places, or in the destination early

Every pair is always in exactly **one** place of the single ledger:
- **Before sending:** at the origin.
- **After "Enviar":** at a system location **"En camino"** (`type='transit'`, not sellable, not online, never counted as available).
- **After "Recibir":** at the destination.

The destination **only** gains stock when its receipt is confirmed. Reconciliation (in − out = balance) holds at every step, and "En camino" is visible as its own column.

## 2. Data (additive, f360 schema)

```
f360.locations                 + type 'transit' (one system row "En camino"; created by the migration, not a real place)
f360.transfers                 id, number (T-000123), from_location_id, to_location_id,
                               status: solicitado | cancelado | en_camino | recibido | recibido_con_diferencia | cerrado,
                               requested_by/at, approved_sent_by/at, received_by/at, closed_by/at, note,
                               send_event_id, receive_event_id  (→ f360.inventory_events)
f360.transfer_lines            transfer_id, variant_id, requested_qty, sent_qty, received_qty
f360.transfer_changes          append-only audit of every transition (who, from→to status, when, idempotency key)
```

Constraints:
- `from ≠ to`;
- both locations `ledger_authority='f360'` (no transfers into or out of a legacy location: D-M1, one master);
- `sent_qty ≤ requested_qty` (can be less if not all pairs are available);
- `received_qty ≤ sent_qty`.

## 3. Transitions (each one SECURITY DEFINER RPC, idempotent by key, row-locked, atomic)

| Transition | Who | Ledger effect | Checks |
|---|---|---|---|
| **Solicitar** `f360_request_transfer(key, from, to, lines)` | seller (the destination or the origin must be one of her assignments), operator, owner | none | Locations active and f360; lines > 0 |
| **Cancelar** (only in `solicitado`) | requester, operator, owner | none | — |
| **Preparar y enviar** `f360_send_transfer(key, id, sent_lines)` | **operator/owner** | `TRANSFER` event: origin → En camino, qty = sent | Lock the origin balances `FOR UPDATE` ordered by variant; `on_hand ≥ sent` or reject the whole send; never negative. If the origin is Bodega CDMX, the P2.3A trigger lowers online stock immediately (the pairs left) |
| **Confirmar recepción** `f360_receive_transfer(key, id, received_lines)` | a **seller assigned to the destination**, operator, owner | `TRANSFER` event: En camino → destination, qty = received | `received ≤ sent`. If equal → `recibido`; if less → `recibido_con_diferencia` + an alert in Avisos |
| **Resolver diferencia** `f360_resolve_transfer_gap(key, id, action, reason)` | operator/owner | `RETURN` En camino → origin (found / came back) **or** `WRITE_OFF` from En camino (lost/damaged), with a mandatory reason | Only for the missing quantity; then `cerrado` |

**Not in V1:**
- **Stock reservation at request time.** A request is a wish; availability is checked at **send**. This is a possible later decision.
- **Partial multi-shipment sends.** One send per transfer; the rest becomes a new request.

## 4. Concurrency and idempotency

- The transfer row is locked `FOR UPDATE` in every transition, and the status check happens inside the lock. So two "Enviar" or two "Recibir" clicks give one effect; the second returns the same result by idempotency key.
- Balances are locked in variant order, the same order as sales, so there are no deadlocks between a send and a sale at the same origin.
- A sale at the origin between request and send is fine: the send re-checks `on_hand`.

## 5. What each person sees

- **Seller (destination):** "Pedidos a mi tienda" with *solicitado / en camino* status and a "Recibí" button. Received quantities are prefilled with the sent ones; she edits only if something is missing.
- **Operator:** a queue of requests → "Preparar y enviar" (quantities editable down), plus transfers with differences to resolve.
- **Inventory screens:** a column **En camino** per variant, next to each location. It never counts as available to sell (store or online).

## 6. Tests (to write with the implementation)

- A send moves origin → En camino, and the destination does NOT change.
- A receipt moves En camino → destination. Every step reconciles.
- A seller cannot send; a seller not assigned to the destination cannot receive.
- Two sends with the same key → one event. Two concurrent sends → one wins (status check).
- A send with insufficient origin stock → nothing moves (all lines atomic).
- Receipt with a difference → an alert; resolve by RETURN/WRITE_OFF with a reason.
- A transfer involving a legacy location → refused.
- Origin Bodega CDMX → a Woo push is queued at send; destination Bodega → queued only at receipt.
- `received > sent` → refused.
- Cancel after send → refused.

## 7. Implementation record: STAGING (2026-09-26)

Status:
- Implemented in staging `faltxpkaicwpnlqaxrdu`.
- Nothing is in production.
- No C3, no store migration, and no mobile app change.
- `channel_inventory` is untouched.
- There is no second ledger.

### 7.1 Migrations

| File | Content |
|---|---|
| `supabase/migrations/20261003000100_f360_transfers.sql` | All of the transfers unit: the "En camino" system location, the tables, the transitions, the read models and the updated read surfaces. Details in 7.2–7.4 |
| `supabase/migrations/20261003000200_f360_transfers_safeupdate.sql` | Fix found by the real-concurrency harness: Supabase's `pg_safeupdate` rejects a `DELETE` without `WHERE`, even on the function's own temp table. Changes `DELETE … WHERE true` |
| `supabase/rollbacks/20261003000100_f360_transfers.down.sql` | Restores the exact pre-transfer definitions (dumped from staging before applying). **Refuses** to run while any transfer or "En camino" movement exists: history is never deleted by a rollback |

What `20261003000100` adds:
- **"En camino":**
  - one system location of `type='transit'`, a singleton;
  - CHECKs: not sellable, no legacy channel, `ledger_authority='f360'`.
- **Tables:**
  - `f360.transfers`, numbered `T-000001` onward;
  - `f360.transfer_lines`, with requested / sent / received / returned / written-off quantities per variant;
  - `f360.transfer_changes`, the append-only audit.
- **Guard triggers:**
  - nothing can be deleted;
  - origin, destination and requester are frozen;
  - status moves only forward;
  - sent and received quantities are set once.
- **`f360.ledger_move`:** a movement plus both balances, never negative.
- **The transition RPCs and read RPCs** listed in 7.3.
- **Updated read surfaces:** "En camino" is excluded from them, and in-transit stock is reported apart:
  - `f360_list_locations` (adds `incoming`);
  - `f360_home` (adds `available_pairs`, `in_transit_pairs` and transfer counts);
  - `f360_my_locations`, `f360_inventory_by_location`, `f360_list_products`, `f360_get_product`;
  - `f360.require_location`, `f360.assert_ledger_location`.
- **Trigger:** nobody can be assigned to "En camino".

### 7.2 States (D-T1)

`requested → in_transit → received | with_difference → closed`, plus `requested → cancelled`.

- "Preparar y enviar" is **one** action, exactly as in the design. It validates and commits the stock, and the status becomes `in_transit`. There is no separate stored "prepared" state.
- The `sent_by/sent_at` fields record who sent and when.
- `closed` is used only after a difference is fully resolved.

### 7.3 RPCs and who may call them

Identity always comes from `auth.uid()`. Role and assignment are re-checked live on every call, and anon is revoked everywhere.

| RPC | owner / operator | seller | viewer |
|---|---|---|---|
| `f360_request_transfer(key, from, to, lines, note, send_now)` | yes; `send_now` = request + send in one transaction | only if origin **or** destination is an active assignment of hers; never `send_now` | no |
| `f360_cancel_transfer(key, id, reason)` | yes, while `requested` | only her own request, while `requested` | no |
| `f360_send_transfer(key, id, lines?)` | **yes** | **no** | no |
| `f360_receive_transfer(key, id, lines?)` | yes | only with an active assignment to the **destination** | no |
| `f360_resolve_transfer_difference(key, id, lines[{variant_id, quantity, action: return\|write_off}], reason)` | yes; the reason is mandatory; only the outstanding quantity | no | no |
| `f360_list_transfers(view)`, `f360_get_transfer(id)`, `f360_transfer_locations()` | all | only transfers touching her assigned locations | all (read) |

Lines accept only `variant_id` and `quantity`. Location, role, actor and price are never taken from the client.

### 7.4 Ledger effects

All effects go through the single ledger, `f360.inventory_events` + `f360.inventory_movements`.

| Step | Event | Movement |
|---|---|---|
| Request / cancel | none | none |
| Send | `TRANSFER` (ref `transfer`, number) | origin → En camino. Origin balances are locked `FOR UPDATE` in variant order; one short line refuses the whole send |
| Receive | `TRANSFER` | En camino → destination (received qty) |
| Resolve: return | `RETURN` (reason in the note) | En camino → origin |
| Resolve: write-off | `WRITE_OFF` (reason in the note) | En camino → nothing |

**Idempotency:**
- Every call carries a key. A replay returns the first result.
- The same key used concurrently is serialized by an advisory lock, then replayed.
- A key reused by another person or action is refused.

**Differences:**
- The missing pairs stay in "En camino", attributed to the transfer (`outstanding` = sent − received − returned − written off).
- They are listed under "Con diferencia" until an owner or operator resolves them explicitly.

**Online store:**
- A send **from** the online bodega queues a Woo push at send.
- A send **to** it queues a push only at receipt, through the existing P2.3A trigger.

### 7.5 Tests

| Suite | Result | How |
|---|---|---|
| `supabase/staging/f360_transfers_tests.sql` | **86/86 PASS** (`s00a_results/transfers_db_tests.txt`) | Rolled back; synthetic fixtures only |
| `scripts/f360/transfers_concurrency.mjs` | **10/10 PASS** (`s00a_results/transfers_concurrency.txt`) | Real concurrency through PostgREST |
| `admin-web/e2e/transfers.spec.ts` | **PASS** | UI flow; 19 screenshots in `admin-web/e2e-screenshots/transfers/` |

What the concurrency harness covers:
- two sends racing for the last pair;
- a simultaneous double-click on send and on request;
- simultaneous receipts.

Synthetic fixture handling:
- **What they are:** locations `ZZ PRUEBA T *`, the role `ZZ PRUEBA Vendedora` given to lab user C1/S1, and stock of the staging test product "Paula".
- **Cleanup:** `scripts/f360/transfers_cleanup.mjs` → `transfer_fixtures.mjs`. It refuses to run if a synthetic transfer or event touches a real location. It lifts the append-only guards only inside its own transaction.
- **What stays:** `f360.access_changes` rows about the fixtures remain (append-only audit).

Regression:
- all 9 DB suites pass (294 checks);
- S0.3 concurrency 7/7 and S0.2 seller flow pass;
- read-only web smoke of every screen passes;
- `tsc`, `eslint` and `next build` are clean.

### 7.6 Found, not changed

`f360.online_location()` picks the first active authoritative warehouse by `sort, created_at`.
- Today Bodega CDMX has `sort=1`, and a new warehouse gets `sort=0`, so creating one changes which location the product page labels as "online".
- It is display only: Woo sync uses `sales_targets.fulfillment_location_id`.
- It needs a decision before real locations are created (D-L1).
