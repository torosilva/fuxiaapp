# Target Architecture

## 1. Logical architecture

```text
                         FUXIA 360
               ┌─────────────────────────┐
               │ Shared domain/backend   │
               │ Supabase + Edge/API     │
               └────────────┬────────────┘
                            │
          ┌─────────────────┴─────────────────┐
          │                                   │
   Mobile Application                  Admin Web
 Customers / sellers              Carolina / Mario / Nova
          │                                   │
          └─────────────────┬─────────────────┘
                            │
      ┌─────────────────────┼─────────────────────┐
      │                     │                     │
 Product & Inventory    Customer 360        Growth/Launch
      │                     │                     │
      └───────────────┬─────┴──────────────┬──────┘
                      │                    │
                 WooCommerce       Marketing/CRM systems
```

## 2. Domain modules
### Product
Canonical product identity, variants, SKU, size, color, cost/price metadata, Woo mappings, media metadata and tier.

### Inventory
Locations, on-hand/reserved/available, receipts, transfers, adjustments, sales, returns, reservations, discrepancies and audit trail. Inventory is **distributed**: every eligible physical location in Mexico counts toward sellable availability, not just a central warehouse. WooCommerce is **not** a location (see `00_MASTER_SPEC.md` §5.1).

> **SUPERSEDED 2026-10-02 (decisión de Mario):** Woo México se alimenta **exclusivamente de Bodega CDMX** (la `fulfillment_location` del canal). No se suman tiendas, bazares ni "En camino"; Colombia también se surte hoy de Bodega CDMX (N1). Ver `INVENTORY_MODEL.md` (fuente de verdad) y `09_MIGRATION_PLAN.md` Fase 5. El texto de arriba se conserva como historia.

### Availability
Derives physical ATS per variant/location and for ecommerce (across all eligible Mexican locations), combines it with make-to-order eligibility, and produces the fulfillment promise. This is computed, never a hand-edited stock number.

> **SUPERSEDED 2026-10-02 (decisión de Mario):** Woo México se alimenta **exclusivamente de Bodega CDMX** (la `fulfillment_location` del canal). No se suman tiendas, bazares ni "En camino"; Colombia también se surte hoy de Bodega CDMX (N1). Ver `INVENTORY_MODEL.md` (fuente de verdad) y `09_MIGRATION_PLAN.md` Fase 5. El texto de arriba se conserva como historia.

### Fulfillment (core; future sprints)
Decides the fulfillment path per order line (**PHYSICAL_STOCK** or **MAKE_TO_ORDER**). For physical lines: allocation to eligible locations, fulfillment tasks per location, re-allocation plus discrepancies when a unit can't be confirmed. For make-to-order lines: it hands off to Production.

### Production — Production Tracking Lite (core; future sprints)
Production requests for make-to-order lines: responsible workshop/supplier, promised/due and estimated/actual dates, lifecycle status, exceptions, and the at-risk signal. Operational visibility only. **No BOM, MRP, raw-material or capacity planning, or complex procurement** unless separately approved.

### Commerce
Woo order ingestion plus offline sales. Woo remains the online commerce engine.

### 2.1 Connected domains: Product → Inventory → Availability → Fulfillment → Production

```text
            PRODUCT (canonical variant, make_to_order_eligible)
                 │ variant_id (shared key across all domains)
       ┌─────────┴──────────────────────────────┐
       ▼                                        ▼
   INVENTORY (ledger)                      AVAILABILITY (derived)
   locations, on_hand, reserved,  ───────► physical ATS per location / ecommerce,
   movements, discrepancies                make-to-order eligibility,
       ▲         ▲                         fulfillment promise ──► Woo / PDP
       │         │                                │
       │         │ RESERVATION / SALE             │ order line arrives (Commerce)
       │         │ from confirmed location        ▼
       │         └──────────────────────── FULFILLMENT
       │                                   path decision per order line:
       │                                   PHYSICAL_STOCK → allocation + task
       │                                   MAKE_TO_ORDER  → production request
       │ RECEIPT movement at a real location       │
       │ when the produced pair is received        ▼
       └────────────────────────────────── PRODUCTION (Tracking Lite)
                                           REQUESTED → … → RECEIVED → FULFILLED
```

Integration rules between domains:
- **One variant identity** (`product_variants.id`) is used by inventory, availability, fulfillment, production and order lines.
- **Only Inventory changes on-hand**, and only through movements. Fulfillment and Production *request* movements (reservation, sale, receipt); they never edit stock numbers.
- **Availability is derived** from Inventory, reservations and Product flags. It isn't written by other domains.
- **Production never touches on-hand until physical receipt.** A make-to-order sale reserves nothing physical, and physical inventory never goes negative.
- **Every hand-off is idempotent and traceable** back to the order line: allocation, task, discrepancy, production request, receipt movement and sale movement all reference it.

### Customer
Identity resolution, contact data, consent, purchases, loyalty, preferences, lifecycle and LTV.

### Launch
Launch records, product tier, readiness gates, blockers, dates and owners.

### Growth
Events, campaigns, attribution, experiments, funnel and economics.

## 3. Architectural constraints
- No second independent product catalog.
- No second independent stock number without a reconciliation rule.
- No client authority over privileged totals, loyalty awards or inventory writes.
- No destructive migration without an explicit compatibility and rollback plan.
- Existing IDs must be mapped during migration rather than discarded when they are referenced by historical data.
- Woo synchronization must be idempotent.
- Inventory movement creation must be auditable.
- Public omnichannel availability must use an explicit `available_to_sell` rule.
- Ecommerce availability is derived from **eligible physical inventory across all Mexican locations**, plus the variant's make-to-order eligibility. It is never derived from a single "central warehouse" or from Woo's own stock figure.
- WooCommerce is never modeled as an inventory location.
- A MAKE_TO_ORDER sale must never create negative physical inventory.
- Production scope is tracking and visibility only. No BOM, MRP, raw-material planning, capacity planning or complex procurement without separate approval.

> **SUPERSEDED 2026-10-02 (decisión de Mario):** Woo México se alimenta **exclusivamente de Bodega CDMX** (la `fulfillment_location` del canal). No se suman tiendas, bazares ni "En camino"; Colombia también se surte hoy de Bodega CDMX (N1). Ver `INVENTORY_MODEL.md` (fuente de verdad) y `09_MIGRATION_PLAN.md` Fase 5. La regla "Ecommerce availability…" de esta lista se conserva como historia.

## 4. Web admin
Admin Web should be a first-class operator surface but share backend/domain logic with mobile. The audit should recommend whether the repository should become a monorepo; do not perform a monorepo conversion merely for aesthetic reasons.

## 5. Source-of-truth summary
- Product identity: Fuxia 360 target
- Physical inventory (all locations): Fuxia 360 target
- Ecommerce availability / fulfillment promise published to Woo: derived by Fuxia 360 target
- Online-order allocation and fulfillment tasks: Fuxia 360 target (future)
- Make-to-order production requests and status: Fuxia 360 target (future)
- Ecommerce order/payment state: WooCommerce
- Unified customer: Fuxia 360
- Loyalty: Fuxia 360
- Launch status: Fuxia 360
- Marketing execution: source platform; normalized measurement in Fuxia 360
