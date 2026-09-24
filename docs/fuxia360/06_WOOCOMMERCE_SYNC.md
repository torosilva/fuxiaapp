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

The formula for ecommerce availability is TBD and must consider:
- eligible locations
- reservations
- safety stock
- fulfillment policy
- temporary holds
- synchronization lag/error

## 5. Order ingestion
Woo webhook ingestion must be:
- signature/auth validated as appropriate
- idempotent
- status-aware
- mapped to canonical product variants
- linked to canonical customer when possible
- capable of creating the appropriate inventory movement exactly once

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
