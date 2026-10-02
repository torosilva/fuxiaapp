# Fuxia 360 — Master Specification

**Status:** Architecture contract v1  
**Purpose:** Evolve the existing Fuxia mobile application into Fuxia 360 without rebuilding working capabilities.

## 1. Product vision
Fuxia 360 is the omnichannel operating system for Fuxia Ballerinas.

It must answer five questions:
1. **Customer 360:** Who is this customer, what does she want, and what has she done?
2. **Product & Inventory:** What do we sell, how many units exist, and where are they physically?
3. **Launch & Creative:** What are we launching and is every launch actually ready?
4. **Growth:** Which traffic, campaign, CRM action and experiment produces profitable sales?
5. **Omnichannel:** How can any available pair become a sales opportunity regardless of whether it is in warehouse, store, bazaar or another eligible location?

## 2. Core operating principle
A physical or digital business event is entered **once** at its natural point of origin.

Examples:
- Product arrives from Colombia → receipt is confirmed in Fuxia 360.
- WooCommerce order is paid → webhook creates the corresponding Fuxia 360 sale/inventory event automatically.
- Store sale occurs → seller flow creates the sale and inventory movement atomically.
- Refund occurs → system processes the corresponding return/reversal workflow.
- Product launch is created → Launch Center coordinates Product, Creative, Ecommerce, Demand and CRM/Data readiness.

No routine event should require duplicate manual capture.

## 3. System boundaries

### Fuxia 360 owns
- canonical product identity and variant mapping
- physical locations
- inventory ledger and availability
- receipts, transfers, adjustments, reservations
- availability, fulfillment allocation and fulfillment promise
- make-to-order production tracking (Production Tracking Lite)
- offline sales operational record
- customer identity / Customer 360
- loyalty and lifecycle rules as explicitly approved
- launch readiness
- creative metadata/readiness
- CRM orchestration metadata
- growth measurement and experiments
- operational audit trail

### WooCommerce remains
- ecommerce storefront
- PDP/cart/checkout
- ecommerce payment/order engine
- ecommerce order status workflow
- ecommerce presentation of price/catalog/stock as synchronized from approved master data

### External marketing systems remain execution channels
Examples: Meta, GA4, ManyChat/email/WhatsApp providers. Fuxia 360 ingests identifiers/events/metrics as needed; it does not recreate their entire functionality.

## 4. Operator surfaces
### Mobile app
Primary for:
- customers
- sellers/store staff
- QR/loyalty
- lightweight store operations

### Fuxia 360 Admin Web
Primary for:
- Carolina
- Mario
- authorized NovaMktLab users
- product master
- receipts from Colombia
- inventory/location management
- launches/creative readiness
- approvals
- growth scorecards
- CRM/customer intelligence
- operational administration

Both surfaces use the same backend/domain model.

## 5. Product/inventory philosophy
The current repository contains `channel_inventory`, explicitly created as independent from WooCommerce. This was appropriate for the MVP but is not the target model.

Target:
`products → product_variants → inventory_levels / inventory_movements → locations`

Inventory is not merely an editable number. Material changes must be explainable through business events/movements.

### 5.1 Distributed fulfillment and make-to-order (clarification, 2026-09-24)
- **Online orders aren't fulfilled only from a central warehouse.** Any eligible physical pair anywhere in Mexico can fulfill an ecommerce order: the central receiving point, a store, a bazaar, or another eligible location.

> **SUPERSEDED 2026-10-02 (decisión de Mario):** Woo México se alimenta **exclusivamente de Bodega CDMX** (la `fulfillment_location` del canal). No se suman tiendas, bazares ni "En camino"; Colombia también se surte hoy de Bodega CDMX (N1). Ver `INVENTORY_MODEL.md` (fuente de verdad) y `09_MIGRATION_PLAN.md` Fase 5. El texto de arriba se conserva como historia.

- **Today that distributed inventory isn't reliably synchronized.** Carolina knows roughly where stock is, but there's no trustworthy per-variant, per-location record.
- **Fuxia also sells make-to-order.** A sellable variant with no physical stock in Mexico can still be sold online and produced after the order. The current delivery expectation for that is about 5–7 days.
- **WooCommerce is not a physical inventory location.** Woo's stock figure is a published, derived number, not a place where pairs exist.

Fuxia 360 must therefore keep these five concepts explicitly separate:

| Concept | Meaning |
|---|---|
| **PHYSICAL ON_HAND** | Units that physically exist, per variant and location |
| **RESERVED** | Physical units already committed (to an order, a Reserve & Try, a transfer, etc.) |
| **PHYSICAL AVAILABLE_TO_SELL (ATS)** | Eligible physical units that can fulfill a *new* order. This is derived from on-hand, reservations, safety stock and location eligibility; it is not a stored editable number |
| **MAKE_TO_ORDER_ELIGIBLE** | Whether a variant with zero physical ATS may still be sold (produced after the order) |
| **FULFILLMENT_PROMISE** | The delivery promise shown to the customer: physical availability ("ships now") vs. production (currently ~5–7 days). The promise values are configuration, not hardcoded |

Target online-order behavior (**future sprints, not Sprint 0**):
1. **Physical ATS exists** → allocate and reserve a unit at an eligible location, and create a **fulfillment task** for that location.
2. **The allocated unit can't be physically confirmed** → try another eligible location, and record an **inventory discrepancy** against the first one.
3. **No physical unit can fulfill the order, and the variant is MAKE_TO_ORDER_ELIGIBLE** → the order enters a lightweight **production request** workflow, with the matching delivery promise.
4. **No physical unit and not make-to-order** → not sellable online (availability published as zero).

### 5.2 Two fulfillment paths and Production Tracking Lite (core, 2026-09-24)
Fuxia has two legitimate fulfillment paths, and both are first-class:

| Path | When | What happens |
|---|---|---|
| **PHYSICAL_STOCK** | An existing physical unit is available at an eligible location in Mexico | Allocate/reserve the unit, fulfill from that location (§5.1) |
| **MAKE_TO_ORDER** | No physical unit is available **and** the variant is eligible for production | Create a **production request**; fulfill the order after production |

**Production Tracking Lite is a core domain of Fuxia 360**, not an optional add-on. Its purpose is **operational visibility**:
- what sold without physical stock;
- what needs to be produced;
- who is responsible (workshop/supplier);
- when it was promised;
- whether it's at risk;
- when it became physically available;
- which customer order it fulfills.

Rules:
- **A MAKE_TO_ORDER sale never creates negative physical inventory.** The order line is linked to a production request, not to on-hand. The produced pair enters inventory through a normal receipt movement at a real location when it's physically received. Only then is it reserved and fulfilled against the order.
- **Out of scope unless separately approved:** manufacturing ERP/MRP functionality (bills of materials, raw-material planning, production capacity planning, complex procurement).
- Product, Inventory, Availability, Fulfillment and Production are **connected domains** that share one canonical variant identity and one inventory ledger (see `02_TARGET_ARCHITECTURE.md` §2.1).

## 6. Receiving merchandise from Colombia
Carolina or a delegated authorized operator must be able to:
1. find or create product
2. define color/size variants
3. enter quantity by variant
4. enter/confirm cost and selling price according to permissions
5. optionally attach media / creative metadata
6. select initial launch tier A/B/C
7. confirm receipt
8. create inventory movements into the receiving location
9. trigger approved WooCommerce product/variant creation or synchronization
10. create/update Launch Center readiness where applicable

Routine target: a normal receipt should require minimal training and no duplicate WooCommerce entry.

## 7. Product tiers
### Tier A — Hero
Full creative investment: PDP assets, lifestyle, vertical video, UGC where appropriate, paid assets, CRM and launch plan.

### Tier B — Commercial
Strong PDP, selective lifestyle/AI/video, organic and paid based on commercial signal.

### Tier C — Catalog
Correct catalog/PDP presence with lightweight asset production; promote to higher tier if data supports it.

Tier is a planning tool, not a permanent product attribute. Changes must be auditable.

## 8. Launch readiness
Every priority launch can include these gates:
- Product Ready — Carolina/Product
- Creative Ready — NovaMktLab / Goyo DRI
- Ecommerce Ready — NovaMktLab / Adrián DRI
- Demand Ready — NovaMktLab / Goyo DRI
- CRM/Data Ready — Mario
- GO / exception decision

A product being uploaded is not equivalent to being launched.

## 9. Omnichannel roadmap
In order:
1. reliable location inventory
2. available-to-sell
3. store availability on PDP
4. Reserve & Try
5. Buy Online / Pickup
6. Ship from Store
7. intelligent transfer/rebalancing recommendations

Do not promise location availability publicly until inventory accuracy is sufficient.

Note (2026-09-24): some online orders are already fulfilled from stores and bazaars, but the process is manual (§5.1). Online-order allocation, fulfillment tasks and the make-to-order production request formalize that practice. Items 6 ("Ship from Store") and the allocation engine are therefore core ecommerce fulfillment capabilities, not just an omnichannel extra. Where they sit in the sprint sequence is a planning decision for the Product/Inventory/Omnichannel sprints; see `10_SPRINTS.md`.

## 10. Definition of success
Fuxia 360 succeeds when:
- Carolina can receive and manage product without operating a difficult ERP.
- online sales do not require manual re-entry.
- inventory is traceable and trustworthy.
- customer identity crosses online/offline channels.
- a customer can discover where her size is available.
- an online order is allocated to a real physical pair wherever it is in Mexico, or sent to production with an honest delivery promise.
- every make-to-order sale is visible from order to production to receipt to fulfillment, with a responsible party, a due date and an at-risk signal, and without ever creating negative inventory.
- launches cannot silently stall between product, creative, web and demand.
- Mario can measure funnel/economics without becoming the manual middleware.
- NovaMktLab has clear operational ownership.
