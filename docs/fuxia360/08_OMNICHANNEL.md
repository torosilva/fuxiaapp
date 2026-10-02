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
- make-to-order eligibility (for ecommerce sellability, not physical ATS)

The formula must be approved before customer-facing launch.

Physical ATS for ecommerce is summed across **all** eligible locations in Mexico, never just a central warehouse. Make-to-order eligibility can make a variant sellable with zero physical ATS, but it never inflates physical ATS. See `00_MASTER_SPEC.md` §5.1 for the five distinct concepts (on-hand, reserved, physical ATS, make-to-order eligible, fulfillment promise).

> **SUPERSEDED 2026-10-02 (decisión de Mario):** Woo México se alimenta **exclusivamente de Bodega CDMX** (la `fulfillment_location` del canal). No se suman tiendas, bazares ni "En camino"; Colombia también se surte hoy de Bodega CDMX (N1). Ver `INVENTORY_MODEL.md` (fuente de verdad) y `09_MIGRATION_PLAN.md` Fase 5. El texto de arriba se conserva como historia.

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

## 5.1 Online-order allocation & make-to-order (future; not Sprint 0)
This formalizes something that already happens manually today: online orders get fulfilled from wherever a pair physically is.
1. **Physical ATS exists** → allocate/reserve a unit at an eligible location (the allocation rule is to be defined: proximity, stock age, location workload, etc.), and create a fulfillment task for that location.
2. **The location can't physically confirm the unit** → mark the allocation failed, record an **inventory discrepancy**, and try the next eligible location.
3. **No physical unit anywhere, and the variant is MAKE_TO_ORDER_ELIGIBLE** → the line takes the **MAKE_TO_ORDER** path: create a **production request** (Production Tracking Lite, `03_DATA_MODEL.md` §5.2). The customer promise is the production promise (currently ~5–7 days, configurable). No negative inventory is created.
4. **No physical unit, and not make-to-order** → the order shouldn't have been sellable. Flag it as an exception for a human to resolve (this points to a sync/availability failure).

Allocation creates a reservation (§5 rules on idempotency, expiry and release apply). The SALE movement is recorded from the confirmed location on physical fulfillment, not at order time.

## 5.2 Fulfillment promise
- The customer-facing promise distinguishes physical availability ("ships now / available in store X") from production (~5–7 days today).
- Promise values are configuration, not hardcoded.
- Don't show a physical promise until inventory accuracy is sufficient (§2). Until then, the promise shown must be the conservative one.

## 6. Pickup
Later:
- online payment/order
- assigned fulfillment location
- pick task
- ready confirmation
- customer notification
- pickup completion

## 7. Ship from Store
Note: under §5.1, shipping online orders from stores and bazaars is part of the normal ecommerce fulfillment model, not an optional extra. The list below is the capability set; how it's sequenced against Reserve & Try and Pickup is decided when sprints are planned.

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
