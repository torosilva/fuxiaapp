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
- timestamps

SKU uniqueness rules must be explicitly decided after auditing existing data.

## 2. Locations

### locations
Represents physical custody/fulfillment locations, e.g.:
- warehouse
- store
- bazaar
- other explicitly approved location types

A seller is **not automatically a location**. Only model seller-held inventory as a location/custody construct if the real operation requires it.

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
