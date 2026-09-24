# Current Architecture — Repository Baseline

This document records what is supported by the repository snapshot reviewed before Fuxia 360 implementation. Claude Code must verify it against the working branch and update discrepancies in the audit rather than silently correcting this file.

## 1. Application stack
The primary application under `fuxia-native/` is:
- Expo / React Native
- TypeScript
- Expo Router
- Supabase JS
- Supabase/Postgres backend
- Supabase Edge Functions
- WooCommerce integration

The repository also contains database SQL/migrations, WordPress-related material, store publishing material and older/mockup assets.

## 2. Existing functional domains
Repository evidence supports:
- customer accounts
- loyalty cards / points
- WooCommerce orders and product reads
- WooCommerce webhook handling
- store/bazaar channels
- staff/sellers
- channel inventory
- offline sales
- inventory approval flows
- admin screens
- seller screens
- product import from WooCommerce into channel inventory
- support/broadcast/push-related capabilities
- Hilo and virtual try-on functionality

## 3. Existing offline operating model
`database/offline_sales_migration.sql` defines:
- `channels` with `store` and `bazar` types
- `staff` with a PIN and `channel_id`
- `channel_inventory`
- `offline_sales`

`channel_inventory` currently stores product/variant-like attributes and stock in the same record:
- product_name
- sku
- size
- color
- price
- stock
- sold

The migration explicitly describes it as **independent from WooCommerce**.

## 4. Existing inventory behavior
Current screens can:
- create/import inventory rows
- import Woo product/variation data into channel inventory
- display inventory per channel
- modify inventory through admin/staff flows
- submit inventory change requests and approve them

This is useful existing behavior but does not yet constitute the target canonical product + inventory ledger architecture.

## 5. Existing offline sale risk to verify
In the reviewed snapshot, `app/vendedora/sale.tsx` updates `channel_inventory.sold` from the client and subsequently creates/claims an offline sale. These operations are not represented as one server-side atomic business transaction in the reviewed code.

The `claim-sale` Edge Function uses the service role and, in its `scan_qr` flow, accepts fields including items, total, channel_id and staff_id from the request. The audit must verify the complete authorization and validation boundary.

## 6. Existing RLS/security note
The reviewed `database/rls_migration.sql` explicitly contains a TODO stating that operational tables are readable by authenticated users and that staff PIN validation should move to an Edge Function with role-restricted policies.

The audit must treat this as a P0 security review item.

## 7. Schema drift
`database/schema.sql` predates multiple later migrations. It must not be treated as the sole schema authority.

The audit must reconcile:
- base schema
- every migration
- Edge Function usage
- client usage
- generated/manual TypeScript database types if present
- actual linked Supabase state where safely accessible

## 8. Architectural conclusion
The existing application is not disposable. It already contains meaningful omnichannel primitives:
- channels
- staff
- offline sales
- loyalty/customer identity
- WooCommerce integration
- inventory operations
- approvals

Fuxia 360 should evolve these capabilities into a coherent domain model rather than replace them wholesale.
