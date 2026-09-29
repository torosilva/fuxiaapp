# Migration Plan

## Principle
Migrate incrementally. Preserve production behavior and historical references.

## Phase 0 — Audit and hardening
Before new Fuxia 360 features:
- canonical schema audit
- RLS/security audit
- staff auth design
- atomic offline sale design
- Woo integration audit
- database type reconciliation
- backup/rollback strategy

## Phase 1 — Product identity
Introduce canonical `products` and `product_variants`.

Build mappings from existing:
- Woo product IDs
- Woo variation IDs
- SKUs
- `channel_inventory` rows
- purchase item product references where applicable

Do not delete `channel_inventory` during initial migration.

## Phase 2 — Locations and inventory ledger
Introduce target locations and movement model.

Map existing channels to locations where semantically correct.

Do **not** create a location for WooCommerce or "online stock", and do not treat Woo's current stock numbers as the physical on-hand of a central warehouse. Woo stock today is a published figure that isn't reliably tied to where pairs physically are (`00_MASTER_SPEC.md` §5.1).

Opening balances must come from **physical counts per location** (central receiving point, each store, each active bazaar, and any other location that holds pairs), not from Woo stock. Any gap between Σ physical counts and Woo stock is reported as a reconciliation finding, not silently absorbed into one location.

Backfill opening balances from existing inventory with an explicit migration/opening-balance movement or equivalent auditable method.

Validate totals before cutover.

## Phase 3 — Dual-read / controlled cutover
During migration, old screens may temporarily continue to read legacy structures while new structures are validated.

Avoid uncontrolled dual-write. If dual-write is temporarily necessary, define:
- authoritative write path
- reconciliation job/report
- removal date

## Phase 4 — Admin Web
Build receiving/product/inventory workflows on the canonical model.

Carolina acceptance test:
- receive a realistic shipment without technical assistance
- verify totals
- verify stock/location
- verify Woo synchronization behavior

## Phase 5 — Woo inventory cutover
After reconciliation:
- Fuxia 360 calculates approved ecommerce availability: physical ATS across all eligible Mexican locations, plus make-to-order eligibility and fulfillment promise
- Woo stock/availability is synchronized from that derived figure
- webhook orders produce idempotent canonical events. The inventory effect follows allocation to an eligible location (reserve, then a SALE from the confirmed location). The interim rule before the allocation engine exists must be explicitly approved and must not assume a central warehouse

## Phase 5b — Fulfillment paths and Production Tracking Lite
- fulfillment path per order line: PHYSICAL_STOCK or MAKE_TO_ORDER
- online-order allocation to eligible locations with fulfillment tasks
- re-allocation plus inventory discrepancy when a unit can't be physically confirmed
- Production Tracking Lite: partners, requests, lifecycle, events, at-risk signal; received pairs enter through receipt movements
- a customer-facing fulfillment promise (physical vs. production)

Migration note: make-to-order orders that are open at cutover (sold, not yet delivered) must be captured as production requests with their current real status, by manual entry or import, so there's no gap in visibility. Their source today is [UNVERIFIED]: ask how Carolina tracks them now.

## Phase 6 — Omnichannel
Enable store availability first, then reservation/pickup capabilities.

## Phase 7 — Launch/Growth/CRM
Add coordination/intelligence modules after core operational data is reliable.

## Migration safeguards
Every migration plan must specify:
- source table
- target table
- mapping
- duplicate strategy
- orphan strategy
- validation query
- rollback/restore approach
- production cutover step
