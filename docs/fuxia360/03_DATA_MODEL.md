# Target Data Model

This is a conceptual contract. Exact SQL types, constraints and migration order must be proposed after the repository/schema audit.

## 1. Product

### products
Minimum concepts:
- id
- name
- slug / internal identifier
- category
- status
- tier (`A`, `B`, `C`) where appropriate
- brand metadata
- Woo product mapping
- created_at / updated_at

### product_variants
- id
- product_id
- sku
- size
- color
- barcode if used
- cost
- selling price metadata
- Woo variation mapping
- active/status
- `make_to_order_eligible` (whether the variant can be sold with zero physical ATS and produced after the order; see `00_MASTER_SPEC.md` §5.1). Where it lives (variant, product, or a policy table) and who may change it is decided in the Product sprint; changes must be auditable
- timestamps

SKU uniqueness rules must be explicitly decided after auditing existing data.

## 2. Locations

### locations
Represents physical custody/fulfillment locations in Mexico, e.g.:
- central receiving point (where merchandise from Colombia arrives; it is **one of many** fulfillment locations, not the ecommerce stock pool)
- store
- bazaar
- other explicitly approved location types

A seller is **not automatically a location**. Only model seller-held inventory as a location/custody construct if the real operation requires it.

**WooCommerce is not a location.** No `locations` row may represent Woo or "online stock". Woo receives a *derived* availability figure (see §3 and `06_WOOCOMMERCE_SYNC.md` §4).

Each location carries fulfillment eligibility attributes (conceptual; exact flags decided in the Inventory sprint), e.g.:
- counts toward ecommerce ATS (yes/no)
- can ship online orders
- can hand over pickups
- active window (bazaars are temporary)

Existing `channels` must be mapped/migrated compatibly.

## 3. Inventory

### inventory_levels
Conceptual fields:
- variant_id
- location_id
- on_hand
- reserved
- safety_stock
- available_to_sell
- updated_at

Derived values should be derived where practical rather than independently editable.

Keep these concepts distinct (`00_MASTER_SPEC.md` §5.1):
- **on_hand**: physical units per variant+location, changed only by movements.
- **reserved**: physical units committed per variant+location (orders, Reserve & Try, transfers in progress).
- **physical ATS per location**: `on_hand − reserved − safety_stock`, and only where the location is eligible for the channel in question.
- **ecommerce physical ATS per variant**: Σ physical ATS over locations eligible for online fulfillment, across Mexico. **Not** a central-warehouse figure.
- **make_to_order_eligible**: a variant attribute (§1). It does **not** change physical ATS.
- **fulfillment_promise**: derived per variant (and later per customer or zone) as physical ("ships now") vs. production (currently ~5–7 days, configurable).

The exact formulas and safety-stock rules must be approved before customer-facing use (`08_OMNICHANNEL.md` §3).

### inventory_movements
Immutable/auditable movement events:
- id
- variant_id
- from_location_id nullable
- to_location_id nullable
- quantity
- type
- business_reference_type
- business_reference_id
- actor
- reason/notes
- created_at

Movement types can include:
- RECEIPT
- TRANSFER
- SALE
- RETURN
- ADJUSTMENT
- RESERVATION
- RELEASE
- WRITE_OFF

Exact semantics must be documented before implementation.

### inventory_receipts / receipt_items
For merchandise arriving from Colombia or other suppliers.

### inventory_transfers
For location-to-location movement.

### inventory_adjustments
For controlled corrections with reason and approval rules.

## 4. Sales
Existing historical `offline_sales` must be preserved/mapped.

Target sale model should support:
- channel/source
- customer nullable
- location
- staff
- line items referencing canonical variants
- authoritative price/total
- external references
- payment/status as appropriate
- timestamps

A sale that changes inventory and loyalty must be processed through a server-side atomic operation.

## 5. Reservations
### reservations / reservation_items
Required for Reserve & Try and later pickup:
- customer
- location
- variant
- quantity
- status
- expires_at
- fulfilled/cancelled timestamps
- source
- audit data

Reservation creation must affect available-to-sell according to the approved inventory rule.

Online-order allocations are a kind of reservation. They are tied to an order line and a location, and follow the same rule.

## 5.1 Fulfillment (future — Product/Inventory/Omnichannel sprints, not Sprint 0)
Conceptual entities; names and shapes to be proposed when the sprint is planned.

### order_allocations
- order line (Woo order reference + canonical variant)
- location
- quantity
- status (`PROPOSED → RESERVED → CONFIRMED → FULFILLED`, or `FAILED` / `CANCELLED`)
- attempt number
- timestamps and actor

A failed physical confirmation produces a new allocation attempt at another eligible location.

### fulfillment_tasks
- the per-location work item (pick/pack/ship or hand-over) for an allocation
- assignee
- status and timestamps
- result (confirmed / unit not found / damaged)

### inventory_discrepancies
- raised when an expected unit isn't physically confirmed (or a count differs)
- variant, location, expected vs. found, source (allocation / count / sale)
- resolution (adjustment movement with reason/approval, per governance §6)

### fulfillment path (per order line)
Each order line records its path: **PHYSICAL_STOCK** (it gets an allocation) or **MAKE_TO_ORDER** (it gets a production request). A line can switch from PHYSICAL_STOCK to MAKE_TO_ORDER when every eligible location has failed to confirm a unit and the variant is eligible. The switch is audited.

## 5.2 Production — Production Tracking Lite (future; core domain, not Sprint 0)
Conceptual. Operational visibility only: **no BOM, MRP, raw-material or capacity planning, or complex procurement** unless separately approved.

### production_partners (workshops / suppliers)
- id, name, type (workshop / supplier), contact, active
- optional: typical lead time (for estimates only, not capacity planning)

### production_requests
Minimum fields:
- id
- source order + order item reference (Woo order id / canonical order line)
- canonical `variant_id`
- quantity
- customer / order reference (canonical customer when resolved)
- `production_partner_id`: the responsible workshop/supplier, when applicable (nullable until ASSIGNED)
- `requested_at`
- `promised_date` / `due_date`: the customer promise, and the internal due date if it differs
- `estimated_completion_at`
- `actual_completion_at`
- `status`
- `exception_reason` / notes
- `created_at`, `updated_at`, and the actor on each change (audit)

Lifecycle (conceptual; exact transitions confirmed when the sprint is planned):

```text
REQUESTED → ASSIGNED → IN_PRODUCTION → READY → QUALITY_CHECK → RECEIVED → FULFILLED
     │           │            │           │            │
     └───────────┴────────────┴───────────┴────────────┴──► BLOCKED (reason) ──► back to prior state
                                                        └──► CANCELLED (reason; e.g. order cancelled)
```

- **QUALITY_CHECK failure** → back to IN_PRODUCTION (rework) or BLOCKED, with a reason. It never becomes RECEIVED.
- **RECEIVED** = the pair physically arrived at a real location. This creates a **RECEIPT inventory movement** into that location (`business_reference_type = production_request`), then a **reservation** for the originating order line.
- **FULFILLED** = the SALE movement from that location for the order line.

### production_request_events
Append-only history: status transitions, date changes (promise/estimate), assignment changes, and exceptions, each with actor and timestamp. It's the basis for "at risk" and for on-time metrics.

### Derived signals (not stored as editable fields)
- **at_risk**: not RECEIVED, and `estimated_completion_at` (or now + typical remaining time) is later than `due_date` or `promised_date`, or the request is BLOCKED. Thresholds are approved before use.
- **overdue**: past `promised_date` and not FULFILLED.

### Invariants
- A MAKE_TO_ORDER order line **never** creates negative on-hand and never reserves units that don't exist.
- One production request can't be RECEIVED twice. Receipt and reservation are idempotent.
- Cancelling the order before RECEIVED cancels the request, with no inventory effect. Cancelling it after RECEIVED leaves the pair as normal on-hand at that location (it becomes regular physical stock), and the reservation is released.

## 6. Launch
### launches
- id
- name
- launch date
- priority
- status
- notes

### launch_products
- launch_id
- product_id
- tier

### launch_gates
- launch/product
- gate type
- owner function
- DRI
- status
- due date
- blocker
- evidence/notes

## 7. Customer 360
Preserve and evolve existing customer/loyalty data. Target concepts:
- canonical customer
- identities (email, phone, app/auth, Woo customer ID)
- consent
- purchases
- loyalty
- preferences such as shoe size where legitimately collected
- lifecycle
- aggregated value metrics
- behavioral events

## 8. Growth
Future modules:
- events
- sessions/identity linkage as appropriate
- campaigns
- touchpoints
- experiments
- attribution outputs
- metric snapshots

Do not implement Growth tables before the event/identity specification is approved.
