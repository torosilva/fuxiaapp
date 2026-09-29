# WooCommerce Synchronization Contract

## 1. Role of WooCommerce
WooCommerce remains the ecommerce storefront and order/payment engine. Fuxia 360 must integrate with it rather than replace it.

## 2. Target mastership
### Fuxia 360 target master
- product identity
- variant identity / SKU mapping
- physical inventory
- available-to-sell calculation
- customer 360 / loyalty
- launch metadata

### Woo master
- ecommerce order/payment state
- checkout workflow
- storefront/cart/PDP behavior

## 3. Product synchronization
When an authorized product/variant is approved for ecommerce:
- if not mapped to Woo, create the required Woo product/variation structure
- persist Woo IDs back to Fuxia 360
- synchronize approved fields
- do not create duplicate products on retry
- log sync state/error

Exact field ownership for name, description, price, images, categories and SEO must be finalized in the audit/implementation plan.

## 4. Inventory synchronization
Woo should receive the approved ecommerce `available_to_sell`, not independently become the physical stock master.

**WooCommerce is not a physical location, and ecommerce availability is not central-warehouse stock** (clarification 2026-09-24; see `00_MASTER_SPEC.md` §5.1). What gets published to Woo is derived from:
- **physical ATS summed across every location in Mexico that is eligible for online fulfillment** (central receiving point, stores, bazaars, other approved locations);
- the variant's **MAKE_TO_ORDER_ELIGIBLE** flag. A variant with zero physical ATS may still be sellable online, on the production promise;
- the resulting **FULFILLMENT_PROMISE** (physical vs. production, currently ~5–7 days), which must reach the storefront so the customer sees an honest delivery expectation.

The formula for ecommerce availability is TBD and must consider:
- eligible locations (all of Mexico, per location eligibility flags)
- reservations and allocations
- safety stock
- fulfillment policy
- make-to-order eligibility
- temporary holds
- synchronization lag/error

How make-to-order and the promise are represented in Woo is a Sprint 4 design decision, to be made with the Ecommerce DRI. Options include the backorder setting, a stock status, or meta shown on the PDP. It must not be decided implicitly by writing a large fake stock number.

## 5. Order ingestion
Woo webhook ingestion must be:
- signature/auth validated as appropriate
- idempotent
- status-aware
- mapped to canonical product variants
- linked to canonical customer when possible
- capable of creating the appropriate inventory effect exactly once

Because any eligible location can fulfill an online order, a paid Woo order doesn't decrement a single fixed stock pool. The target sequence (future sprints) is:
1. ingest the order idempotently;
2. **allocate/reserve** a unit at an eligible location and create a fulfillment task;
3. when the task confirms the physical pick, record the SALE movement **from that location**;
4. if the unit isn't found, record an inventory discrepancy and re-allocate to another eligible location;
5. if there's no physical ATS and the variant is make-to-order, create a production request with the matching promise.

Until the allocation engine exists, the interim order→inventory rule must be decided explicitly when Sprint 4 is planned. It must not default to "decrement the central location".

## 6. Refund/cancellation
Refund/cancellation must not blindly add stock. Return-to-stock depends on actual business status where necessary.

Define separate concepts where needed:
- financial refund
- order cancellation before fulfillment
- physical return received
- damaged/non-resellable return

## 7. Failure handling
Every sync should expose:
- status
- last attempt
- error
- retry
- external ID
- idempotency reference

Operators should not need to manually compare Woo and Supabase to discover failures.

## 8. Existing integration
The repository already includes WooCommerce service/proxy/webhook functionality. Reuse and harden it; do not replace it without a demonstrated need.
