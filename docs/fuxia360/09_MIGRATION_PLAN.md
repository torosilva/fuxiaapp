# Migration Plan

## Principle
Migrate incrementally. Preserve production behavior and historical references.

## Phase 0 — Audit and hardening
Before new Fuxia 360 features:
- canonical schema audit
- RLS/security audit
- staff auth design
- atomic offline sale design
- Woo integration audit
- database type reconciliation
- backup/rollback strategy

## Phase 1 — Product identity
Introduce canonical `products` and `product_variants`.

Build mappings from existing:
- Woo product IDs
- Woo variation IDs
- SKUs
- `channel_inventory` rows
- purchase item product references where applicable

Do not delete `channel_inventory` during initial migration.

## Phase 2 — Locations and inventory ledger
Introduce target locations and movement model.

Map existing channels to locations where semantically correct.

Do **not** create a location for WooCommerce or "online stock", and do not treat Woo's current stock numbers as the physical on-hand of a central warehouse. Woo stock today is a published figure that isn't reliably tied to where pairs physically are (`00_MASTER_SPEC.md` §5.1).

Opening balances must come from **physical counts per location** (central receiving point, each store, each active bazaar, and any other location that holds pairs), not from Woo stock. Any gap between Σ physical counts and Woo stock is reported as a reconciliation finding, not silently absorbed into one location.

Backfill opening balances from existing inventory with an explicit migration/opening-balance movement or equivalent auditable method.

Validate totals before cutover.

### Phase 2 · Legacy Woo catalog takeover (Track D, decisiones de Mario 2026-10-02)
- **Opening balance de Bodega CDMX = conteo físico aprobado.** Woo sirve solo como referencia para detectar diferencias: `Woo actual | Conteo físico | Diferencia | Opening balance F360`. Nunca es la fuente del opening balance.
- **Los SKUs legacy de Woo se conservan.** La variante F360 puede tener su SKU canónico `F360-MODELO-COLOR-TALLA`, y el mapping la liga al SKU / variation ID legacy que ya existe en Woo. La adopción no depende de cambiar SKUs (feeds, pedidos históricos e integraciones siguen intactos). Los productos **nuevos** creados desde Fuxia 360 sí usan `F360-{PRODUCT}-{COLOR}-{SIZE}`.
- **No se consolidan todavía los 129 productos legacy** ("un producto por color").
- **Antes del cutover no se escribe ninguna diferencia en Woo producción.**
- "Liberar" = homologación terminada, probada y lista para cutover; no = Woo producción manejado por Fuxia 360.

## Phase 3 — Dual-read / controlled cutover
During migration, old screens may temporarily continue to read legacy structures while new structures are validated.

Avoid uncontrolled dual-write. If dual-write is temporarily necessary, define:
- authoritative write path
- reconciliation job/report
- removal date

## Phase 4 — Admin Web
Build receiving/product/inventory workflows on the canonical model.

Carolina acceptance test:
- receive a realistic shipment without technical assistance
- verify totals
- verify stock/location
- verify Woo synchronization behavior

## Phase 5 — Woo inventory cutover

> **Decisión vigente (Mario, 2026-10-02 · `INVENTORY_MODEL.md` §1 reglas 8–9 y §2.1):** Woo México se alimenta **exclusivamente de Bodega CDMX** (la `fulfillment_location_id` del canal). No se suman automáticamente tiendas físicas, bazares ni "En camino". Que una tienda tenga pares físicamente no significa que Woo pueda venderlos. Colombia también se surte hoy desde Bodega CDMX (**N1**, decisión actual, no bug). Si Colombia tiene inventario propio, su canal apuntará a otra `fulfillment_location` sin cambiar la identidad de las variantes.
>
> El texto original de abajo queda **SUPERSEDED** y se conserva solo como traza. No se borra.

After reconciliation (vigente):
- Fuxia 360 publishes to Woo `online_ats(variant, fulfillment_location)` = on-hand at the channel's source location only (Bodega CDMX for Woo México)
- Woo stock/availability is synchronized from that figure, and only after Mario's explicit cutover approval per environment. **Woo producción no se conecta al envío automático de stock hasta esa aprobación.**
- webhook orders produce idempotent canonical events; the SALE is taken from the channel's `fulfillment_location_id`

~~Original (2026-09-24), SUPERSEDED 2026-10-02:~~
- ~~Fuxia 360 calculates approved ecommerce availability: physical ATS across all eligible Mexican locations, plus make-to-order eligibility and fulfillment promise~~
- ~~Woo stock/availability is synchronized from that derived figure~~
- ~~webhook orders produce idempotent canonical events. The inventory effect follows allocation to an eligible location (reserve, then a SALE from the confirmed location). The interim rule before the allocation engine exists must be explicitly approved and must not assume a central warehouse~~

Multi-location allocation (stores and bazaars fulfilling online orders) stays a possible **future** change (Phase 5b), which would need its own approved decision; it is not the current rule.

## Phase 5b — Fulfillment paths and Production Tracking Lite
- fulfillment path per order line: PHYSICAL_STOCK or MAKE_TO_ORDER
- online-order allocation to eligible locations with fulfillment tasks
- re-allocation plus inventory discrepancy when a unit can't be physically confirmed
- Production Tracking Lite: partners, requests, lifecycle, events, at-risk signal; received pairs enter through receipt movements
- a customer-facing fulfillment promise (physical vs. production)

Migration note: make-to-order orders that are open at cutover (sold, not yet delivered) must be captured as production requests with their current real status, by manual entry or import, so there's no gap in visibility. Their source today is [UNVERIFIED]: ask how Carolina tracks them now.

## Phase 6 — Omnichannel
Enable store availability first, then reservation/pickup capabilities.

## Phase 7 — Launch/Growth/CRM
Add coordination/intelligence modules after core operational data is reliable.

## Migration safeguards
Every migration plan must specify:
- source table
- target table
- mapping
- duplicate strategy
- orphan strategy
- validation query
- rollback/restore approach
- production cutover step
