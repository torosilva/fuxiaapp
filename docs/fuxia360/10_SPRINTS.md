# Fuxia 360 Implementation Sprints

Sprints are implementation boundaries, not permission to code everything at once. Each sprint requires reviewed acceptance criteria before implementation.

# Sprint A — Repository Audit (NO CODE)
Deliver:
- CURRENT_STATE.md
- SCHEMA_AUDIT.md
- SECURITY_AUDIT.md
- INTEGRATION_AUDIT.md
- GAP_ANALYSIS.md
- SPRINT_0_IMPLEMENTATION_PLAN.md

Exit:
- contradictions documented
- P0 risks confirmed/refuted with code references
- proposed Sprint 0 broken into reversible units
- explicit approval to code

# Sprint 0 — Hardening & Canonical Baseline
## S0.1 Schema baseline
- reconcile schema + migrations + code usage
- establish canonical migration history/documentation
- reconcile/regenerate DB types as appropriate

## S0.2 Staff authorization
- server-side staff authentication/authorization
- PIN no longer exposed through broad reads
- role/location relationship enforced
- rate limiting / abuse considerations documented

## S0.3 Atomic offline sale
- one authoritative server-side operation
- inventory validation
- server-derived price/total
- sale + items + inventory consequence + loyalty consequence atomic
- idempotency
- double-submit protection

## S0.4 Regression verification
Critical flows:
- customer login/onboarding
- shop/product
- loyalty
- Woo order sync
- seller login/sale
- admin inventory
- approvals

Exit:
- no known P0 security/integrity blocker for inventory refactor

# Sprint 1 — Product Master
Build canonical product/variant model and mappings.

Acceptance:
- every migrated active inventory item can resolve to a canonical variant or is listed as an explicit migration exception
- Woo IDs/SKUs map without silent duplication
- existing production screens continue working through compatibility layer where required
- no destructive legacy deletion

# Sprint 2 — Inventory Core
Build:
- locations
- inventory levels
- inventory movements
- receipts
- transfers
- adjustments

Acceptance:
- opening balance reconciles to approved legacy totals
- every new receipt creates auditable movement(s)
- transfer conserves total quantity
- adjustment requires actor/reason
- negative availability prevented except by explicitly approved rule

# Sprint 3 — Fuxia 360 Admin Web
MVP:
- Today
- Products
- Receive Merchandise
- Inventory by location
- Transfers/adjustments
- approvals
- sync status

Carolina acceptance:
- receive a realistic Colombia shipment
- quantity matrix by size/color
- total pairs correct
- stock visible in receiving location
- no duplicate manual Woo entry required for approved ecommerce products
- routine flow understandable without developer assistance

# Sprint 4 — Woo Product & Inventory Sync
Build/harden:
- product/variant create/update mapping
- idempotent sync
- inventory availability sync
- order ingestion to canonical variant
- refund/cancellation rules
- sync errors/retry visibility

Acceptance:
- retry does not duplicate product/order/movement
- paid Woo order changes inventory exactly once
- sync failure is visible and recoverable
- Woo does not become an independent physical stock master

# Sprint 5 — Omnichannel MVP
Phase 5A:
- customer-facing store availability

Phase 5B:
- Reserve & Try

Later only after validation:
- pickup
- ship from store

Acceptance for Reserve & Try:
- reservation reduces available-to-sell
- expiration releases it
- fulfillment consumes it
- double fulfillment impossible
- customer cannot reserve unavailable stock

# Sprint 6 — Launch & Creative Center
Build:
- launch
- Tier A/B/C
- Product/Creative/Ecommerce/Demand/CRM readiness
- DRI, due date, blocker
- creative asset checklist
- shooting/production status

Acceptance:
- new priority product cannot appear “fully launched” with missing required gates
- Carolina can see blocker without messaging individual team members
- NovaMktLab can see its own outstanding readiness work

# Sprint 7 — Customer 360 & CRM Foundation
Build on existing customer/loyalty capabilities:
- identity reconciliation
- online/offline purchase timeline
- consent
- lifecycle
- size/preference signals where supported
- CRM segment foundation
- journeys: welcome, browse/cart/checkout recovery, post-purchase, review, back-in-stock, launch, winback as approved

# Sprint 8 — Growth Intelligence
Build:
- event specification
- funnel
- campaigns
- attribution
- experiments
- CAC/MER
- contribution economics
- CRM revenue measurement

Do not implement metric formulas without a written definition/source.

# Sprint 9 — Product & Inventory Intelligence
Examples:
- low stock
- aged stock
- demand without creative
- creative opportunity
- tier promotion suggestion
- transfer/rebalancing suggestion

Recommendations are advisory first.

# Working rhythm for every coding sprint
1. Claude proposes implementation plan.
2. Human reviews plan.
3. Create feature branch.
4. Implement smallest coherent unit.
5. Run tests/verification.
6. Review diff/migration.
7. Commit.
8. Continue only after acceptance.
