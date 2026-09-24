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

## 10. Definition of success
Fuxia 360 succeeds when:
- Carolina can receive and manage product without operating a difficult ERP.
- online sales do not require manual re-entry.
- inventory is traceable and trustworthy.
- customer identity crosses online/offline channels.
- a customer can discover where her size is available.
- launches cannot silently stall between product, creative, web and demand.
- Mario can measure funnel/economics without becoming the manual middleware.
- NovaMktLab has clear operational ownership.
