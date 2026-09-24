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
- Fuxia 360 calculates approved ecommerce availability
- Woo stock is synchronized
- webhook orders decrement inventory through idempotent canonical events

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
