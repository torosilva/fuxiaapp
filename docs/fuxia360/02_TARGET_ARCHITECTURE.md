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
Locations, on-hand/reserved/available, receipts, transfers, adjustments, sales, returns, reservations and audit trail.

### Commerce
Woo order ingestion plus offline sales. Woo remains the online commerce engine.

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

## 4. Web admin
Admin Web should be a first-class operator surface but share backend/domain logic with mobile. The audit should recommend whether the repository should become a monorepo; do not perform a monorepo conversion merely for aesthetic reasons.

## 5. Source-of-truth summary
- Product identity: Fuxia 360 target
- Physical inventory: Fuxia 360 target
- Ecommerce order/payment state: WooCommerce
- Unified customer: Fuxia 360
- Loyalty: Fuxia 360
- Launch status: Fuxia 360
- Marketing execution: source platform; normalized measurement in Fuxia 360
