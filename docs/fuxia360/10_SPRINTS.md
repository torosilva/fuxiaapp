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

# Domain dependency map (Product → Inventory → Availability → Fulfillment → Production)
Design every sprint below against these connected domains (see `02_TARGET_ARCHITECTURE.md` §2.1):
- **Sprint 1 (Product)** provides the canonical `variant_id` plus `make_to_order_eligible`, which every later domain uses.
- **Sprint 2 (Inventory)** provides locations, the movement ledger and receipts. Its receipt design must already allow `business_reference_type = production_request`, so produced pairs enter inventory the same way as any receipt.
- **Sprint 4 (Woo)** publishes the Availability result (physical ATS across Mexico, plus make-to-order and promise), and ingests orders with canonical line identity.
- **Sprint 5C (Fulfillment)** decides the path per line.
- **Sprint 5D (Production Tracking Lite)** tracks MAKE_TO_ORDER lines until receipt and fulfillment.
- No sprint may introduce negative physical inventory to represent make-to-order demand.

# Sprint 1 — Product Master
Build canonical product/variant model and mappings.

Also:
- `make_to_order_eligible` per variant (or policy), set by an authorized role, with audited changes

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

Also:
- location eligibility flags (counts toward ecommerce ATS, can ship, can hand over pickups, active window)
- distinct on_hand / reserved / physical ATS per variant+location
- no location represents WooCommerce
- receipt/movement references generic enough to accept future production-request receipts (no Production tables in this sprint)

Acceptance:
- opening balances come from physical counts per location, not from Woo stock; the gap vs. Woo is reported
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
- inventory availability sync: physical ATS across all eligible Mexican locations, plus make-to-order eligibility and fulfillment promise (never central-warehouse-only)
- order ingestion to canonical variant
- an explicitly approved interim order→inventory rule until allocation exists (must not assume a central warehouse)
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

Phase 5C — Fulfillment paths & online-order allocation (see `08_OMNICHANNEL.md` §5.1–5.2):
- fulfillment path per order line: PHYSICAL_STOCK or MAKE_TO_ORDER
- allocation/reservation of online orders to eligible locations
- fulfillment tasks per location
- re-allocation plus inventory discrepancy when a unit isn't confirmed
- fulfillment promise (physical vs. production, configurable)

Phase 5D — **Production Tracking Lite** (core domain; see `00_MASTER_SPEC.md` §5.2, `03_DATA_MODEL.md` §5.2):
- production partners (workshops/suppliers)
- production requests created automatically for MAKE_TO_ORDER lines
- lifecycle REQUESTED → ASSIGNED → IN_PRODUCTION → READY → QUALITY_CHECK → RECEIVED → FULFILLED, plus BLOCKED / CANCELLED
- production request event history (audit)
- at-risk / overdue signals
- receiving a produced pair = RECEIPT movement at a real location + reservation for the originating order line
- operator views (Admin Web "Producción"; a mobile view if a workshop contact or store needs it)
- **explicitly excluded:** BOM, MRP, raw-material planning, capacity planning, complex procurement (need separate approval)

Sequencing notes:
- Because online orders are already fulfilled from stores and bazaars by hand, 5C/5D may need to come before 5A/5B. Decide when Sprint 5 is scoped.
- 5C and 5D ship together, or 5D directly after 5C. A MAKE_TO_ORDER path without production tracking would leave those orders invisible.
- A reduced **5D-manual** option can be considered earlier (production requests created by hand, with no allocation engine) to give visibility before 5C. It still needs Sprint 1 variants and the Sprint 2 receipt movements. Decide at planning.

Later only after validation:
- pickup
- ship from store (overlaps with 5C; to be consolidated at planning)

Acceptance for Reserve & Try:
- reservation reduces available-to-sell
- expiration releases it
- fulfillment consumes it
- double fulfillment impossible
- customer cannot reserve unavailable stock

Acceptance for 5C:
- a paid online order with physical ATS is allocated to exactly one eligible location and creates one fulfillment task
- failed physical confirmation creates a discrepancy and re-allocates without double-reserving
- an order for a variant with zero physical ATS enters a production request only if the variant is MAKE_TO_ORDER_ELIGIBLE
- the customer sees a promise consistent with physical vs. production fulfillment

Acceptance for 5D (Production Tracking Lite):
- every MAKE_TO_ORDER order line has exactly one open production request (idempotent on retry)
- a make-to-order sale **never** produces negative on-hand; physical inventory changes only at RECEIVED (a receipt movement at a real location)
- each request shows source order/item, variant, quantity, customer/order reference, responsible partner, requested/promised/due/estimated/actual dates, status and notes
- every status, date or assignment change is recorded with actor and timestamp
- at-risk and overdue requests are visible without asking anyone
- RECEIVED → FULFILLED links the produced pair to the originating customer order, through the receipt, the reservation and the sale movement
- order cancellation before RECEIVED cancels the request with no inventory effect; after RECEIVED the pair becomes regular stock
- Carolina can see "what sold without stock, what's in production, with whom, due when, and what's late" on one screen

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
- production insights: on-time rate per workshop, variants often sold make-to-order (candidates to stock physically), promise accuracy

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

---

## Parallel tracks (added 2026-09-25)

| Track | Scope | Status |
|---|---|---|
| **A — P2.3 Woo stock + orders** | P2.3A local/staging (done); P2.3B on SiteGround staging | P2.3B **blocked** until the SiteGround staging copy exists — `admin/P2_3_STATUS.md`, `admin/P2_3B_RUNBOOK.md` |
| **B — Customer 360 + CRM + Growth** | Data audit, Customer 360 model, honest Clientes/Growth screens, B4 revenue plan | Customer 360 build **waits for identity decisions D-C1…D-C5** — `growth/DATA_AUDIT.md`, `growth/CUSTOMER_360_MODEL.md` |
| **C — Physical Operations / Unified Inventory** | Stores and bazaars on the single f360 ledger; seller → role → location; transfers; atomic store sale linked to loyalty and Customer 360; retire `channel_inventory` as a master | **Design only.** Audit + target + migration plan in `ops/TRACK_C_*.md`. Blocked by S0.0A-A2 in production, S0.2, S0.3 (re-scope D-X1), S0.5 and decisions D-L1, D-M1, D-P1, D-S1 |
