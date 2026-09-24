# Omnichannel Specification

## 1. Goal
Turn distributed physical inventory into a conversion advantage.

Customer-facing examples:
- “Disponible para envío inmediato”
- “Tu talla está disponible en Tienda X”
- “Resérvalo y pruébatelo hoy”
- “Compra online y recoge hoy”
- later: “Envío desde tienda”

## 2. Dependency
No public location availability until inventory accuracy and synchronization are reliable enough to avoid sending customers to nonexistent stock.

## 3. Available-to-sell
`available_to_sell` must be an explicit business rule, not simply `stock - sold`.

It may include:
- on_hand
- active reservations
- safety stock
- fulfillment eligibility
- location status
- temporary holds

The formula must be approved before customer-facing launch.

## 4. Store availability
MVP:
- resolve canonical variant from Woo PDP
- query eligible locations
- show availability state
- avoid exposing unnecessary internal quantities if product/business prefers “available / low stock” messaging

## 5. Reserve & Try
Reservation must include:
- customer/contact identity
- variant
- location
- quantity
- creation time
- expiration
- status
- source
- fulfillment/cancellation

Lifecycle:
`ACTIVE → FULFILLED | EXPIRED | CANCELLED`

Expiration must release reserved availability safely and idempotently.

## 6. Pickup
Later:
- online payment/order
- assigned fulfillment location
- pick task
- ready confirmation
- customer notification
- pickup completion

## 7. Ship from Store
Later:
- eligibility rules
- location selection
- pick/pack
- courier/shipping workflow
- stock reservation
- failure/reassignment logic

## 8. Rebalancing intelligence
Future recommendations can use:
- demand by location
- inventory by variant/location
- online interest
- sell-through
- stock age

Recommendations remain suggestions until operational accuracy is proven.
