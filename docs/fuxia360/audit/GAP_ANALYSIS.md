# Fuxia 360 Audit — Gap Analysis

## 1. Contradictions between the spec and the repository

| # | Spec statement | Repository reality | Impact |
|---|---|---|---|
| C1 | `01_CURRENT_ARCHITECTURE` §6: the RLS TODO means operational tables are readable by authenticated users | True, but incomplete: **`customers.role` is self-writable** (`rls_migration.sql:60-66`), so the role model that all later policies rely on (`my_role()`) can be bypassed | The security baseline is weaker than the spec assumes. S0.0 is required before S0.2 |
| C2 | 01 §3: `staff` has a PIN and `channel_id` | Correct. **There is also a second staff concept:** `customers.role='staff'` (`offline_sales_migration.sql:4`). Device accounts and PIN-staff are two separate identities with no link between them | **Decided (Q1, closed):** sellers use their own phones and individual accounts; each `staff` row is linked 1:1 to the seller's own auth user; shared `role='staff'` identities stop working at cutover (SPRINT_0 plan S0.2) |
| C3 | 01 §5: the seller flow "updates `channel_inventory.sold`" | Confirmed. Repo comments disagree on whether the seller device has a Supabase session (`inventory_approvals_rls_fix.sql:1-3` vs `operational_writes_rls_migration.sql:21-24`, `profile.tsx:352`) | Silent stock-decrement failures are possible (SCHEMA_AUDIT §5.4). The target is decided (Q1): an individual seller session on the seller's own phone, with the sale done server-side (S0.2/S0.3) |
| C4 | 00 §2 / 06 §5: "Woo order paid → webhook creates the Fuxia 360 sale/inventory event" | The webhook is **loyalty-only**. It creates no sale record and no inventory effect | Expected gap (Sprint 4). Nothing records Woo orders in Supabase except loyalty `transactions`, and only for matched customers or `unmatched_orders` |
| C5 | 00 §5 / 03 §2: map existing `channels` to `locations` | There is **no central receiving location** in the data model, and the only online stock figure is Woo's. `channels` includes temporary bazaars with `event_date` and `ON DELETE CASCADE` on inventory. *Clarified 2026-09-24:* online orders can be fulfilled from **any** eligible location in Mexico, and make-to-order exists (`00_MASTER_SPEC.md` §5.1) | ~~Seed a "Bodega/Online" location from Woo stock~~ (**withdrawn**: it would model Woo as a location and make ecommerce ATS equal central stock). Instead, Sprint 2 needs:<ul><li>a central receiving location plus every store/bazaar as locations, each with eligibility flags;</li><li>opening balances from **physical counts per location**, with the Woo-stock gap reported;</li><li>a rule for closed bazaars (Q12, resolved during Inventory design; not a Sprint 0 item).</li></ul> |
| C6 | 05 §4 / 02 §5: Loyalty owned by Fuxia 360 "as explicitly approved" | Rules are hardcoded in 5+ places with **two different threshold sets** (300/900 vs 501/1201 in `calculate-tier`); UI copy promises **annual** tiers (`payments/index.tsx:75`) that no code implements | Loyalty rules need one owner and one implementation (S0.5); annual-window rule needs a decision (Q4) |
| C7 | 07: Admin Web "Today", Customer 360 are future | The mobile app **already has** a Today dashboard (`admin/dashboard-today.tsx`), a Customer 360 (`admin/customer/[id].tsx`), reports and broadcast. Under repo RLS the Customer 360 and reports screens **cannot read other customers' data** (SCHEMA_AUDIT §5) | Either they are broken in production or the live DB has undocumented policies. Resolve in S0.1 |
| C8 | 01 §7: reconcile "generated/manual TS types" | Types are manual, cover 7/~20 tables and are not enforced (`createClient<any>`) | S0.1 |
| C9 | CLAUDE.md rule 4: "inspect all migrations" | Several live objects have **no migration at all** (`wishlists`, `referral_code`, `referred_by`, `transactions.notes/status`, `channel_inventory.image_url`, `pending_credits`, `fx_add_points`, loyalty triggers) | A live schema dump is a hard prerequisite for any DB change |
| C10 | 04 §2 "claim-sale: verify whether scan_qr can be called without staff context" | It can be called **with no context at all**, and item quantities directly determine points | Confirmed and more severe (SECURITY P0-2) |
| C11 | 10_SPRINTS S0.3: "sale + items + inventory consequence + loyalty consequence atomic" | There is no inventory movement ledger yet (Sprint 2). An "inventory consequence" in S0 can only mean updating `channel_inventory.sold`, optionally plus an audit row | **Decided (Q11):** Sprint 0 writes a forward-compatible `inventory_events` audit row for each new sale line |

## 2. Capability gap matrix (target → current → gap)

Legend: ✅ exists and reusable · 🟡 partial / needs hardening · ❌ missing

| Target capability (spec) | Current | Status | Sprint |
|---|---|---|---|
| Server-authoritative staff auth | Client PIN check | ❌ | S0.2 |
| Atomic offline sale with server price | Client orchestrated | ❌ | S0.3 |
| Role-based RLS (customer/staff/admin/service) | `my_role()` exists, but role is self-writable | 🟡 | S0.0/S0.2 |
| Canonical migration history + types | Hand-applied SQL, drift | ❌ | S0.1 |
| Products / variants | Woo only; `channel_inventory` denormalized rows | ❌ | 1 |
| Woo ID mapping | `purchase_items.wc_product_id`, `product_image_overrides.wc_product_id`; none on inventory | 🟡 | 1 |
| Locations (all fulfillment-capable points in Mexico; Woo is not one) | `channels` (store/bazar); no central receiving location; no eligibility flags | 🟡 | 2 |
| Make-to-order eligibility per variant | None | ❌ | 1 |
| Online-order allocation + fulfillment tasks | None (done by hand today) | ❌ | 5C |
| Inventory discrepancies | None | ❌ | 2/5C |
| Fulfillment path per order line (PHYSICAL_STOCK / MAKE_TO_ORDER) | None | ❌ | 5C |
| Production Tracking Lite (partners, requests, lifecycle, events, at-risk) — **core domain** | None. Make-to-order is tracked outside the system today [UNVERIFIED how] | ❌ | 5D |
| Fulfillment promise (physical vs. production) | None | ❌ | 4/5C |
| Inventory levels | `channel_inventory.stock/sold` | 🟡 | 2 |
| Inventory movements (ledger) | None; `inventory_change_requests` covers only staff requests | ❌ | 2 |
| Receipts from Colombia | Bulk-add / Woo import into a channel (no receipt concept, no draft vs confirmer) | ❌ | 2/3 |
| Transfers | None | ❌ | 2 |
| Adjustments with reason/actor/approval | Staff → approval queue ✅; admin direct edit with no reason/audit | 🟡 | 2 |
| Approvals | `inventory_change_requests` + `inventory-approve` (applies non-atomically: apply then mark, `inventory-approve:173-191`) | 🟡 reusable pattern | 2 |
| available_to_sell | `stock - sold` on client | ❌ | 2/5 |
| Reservations | None | ❌ | 5 |
| Woo order ingestion → canonical record | Loyalty-only `transactions` | 🟡 | 4 |
| Woo product/stock sync (Fuxia → Woo) | None | ❌ | 4 |
| Sync status / retry visibility | Logs only | ❌ | 4 (S0.7 optional) |
| Customer identity | `customers` keyed by phone; `auth_user_id`; `wc_customer_id`; `unmatched_orders` | 🟡 reusable | 7 |
| Consent | None (push tokens only; no opt-out) | ❌ | 7 |
| Loyalty ledger | `transactions` is a partial ledger; balance stored separately, drift possible | 🟡 | S0.5 |
| Launch Center / tiers A/B/C | None | ❌ | 6 |
| Growth / events | None | ❌ | 8 (spec forbids starting early) |
| Admin Web | Mobile admin only | ❌ | 3 |
| Audit trail for staff/admin actions | `broadcasts`, `inventory_change_requests`, `transactions.notes` strings | 🟡 | S0/2 |
| Automated tests / CI | None | ❌ | S0.4 |

## 3. What to preserve (do not rebuild)

- OTP onboarding + `auth_user_id` linkage + self RLS for customer tables.
- The webhook's HMAC, idempotency on `wc_order_id`, reverse/re-credit logic and `unmatched_orders` retro-credit (fix P1-2 only).
- The `inventory_change_requests` request → approve → apply pattern (becomes adjustment approvals in Sprint 2).
- `my-orders` server-side scoping (a good model for other functions).
- `broadcasts` audit + rate limit.
- Seller UX: channel picker → PIN keypad → cart → QR/code. Sprint 0 should change what happens **behind** the "Confirmar" button, not the operator flow (spec rule 15).

## 4. Admin Web / repository layout recommendation

- The repo is **not** a JS monorepo: `fuxia-native/` is self-contained, the SQL lives in root `database/`, and functions live in `fuxia-native/supabase/functions/`.
- **Recommendation:** no monorepo conversion in Sprint 0. In S0.1, create the canonical `supabase/` project at **repo root** (the root `supabase/.temp` is already linked) with `migrations/` + `functions/`. Move functions there in a later, separate unit, keeping the deploy commands the same. When Sprint 3 starts, add `admin-web/` as a sibling app. Only extract a shared `packages/domain` (types generated from Supabase, and the API clients) once two apps actually consume it.
- Framework choice for Admin Web is deferred to Sprint 3. Expo Router web export is possible but not recommended for a table-heavy back-office. Decide then.

## 5. Assumptions that cannot be proven from the repository

1. Which SQL files were applied to production, and in what order (especially `support_tickets` RLS).
2. Whether `authenticated` holds column UPDATE on `customers.role`.
3. Whether `otp_verifications`, `tier_config`, `qr_scans` and `pending_credits` have RLS.
4. The definitions of `trg_update_purchase_stats`, `update_loyalty_tier` and `fx_add_points`, and whether they double-count pairs.
5. Whether `purchase_items.sku` is still NOT NULL (in-store items silently failing).
6. Whether `transactions.channel` CHECK allows `manual`/`popup`.
7. Whether `OTP_SALT` and the `REVIEW_*` secrets are set, and the role of `+525543412939`.
8. Whether `backfill-orders` and `loyalty-credit` are deployed, and how WordPress calls `loyalty-credit`.
9. Which accounts sellers are using in the field today, and with which role. The target is decided (Q1: individual personal-phone identities); this fact only sizes the migration and cutover, and is collected as aggregate counts in S0.1a.
10. How Woo's stock number is maintained today, given that online orders are fulfilled from distributed locations and make-to-order also exists: which pairs it represents, and who changes it and when. Not a Sprint 0 item (Q12); resolved during Product/Inventory/Availability/Fulfillment/Production design.
11. Whether the old Woo REST keys were revoked (BACKLOG #14 says yes).
12. Production data quality: duplicate cards, duplicate inventory rows, oversold rows, duplicate PINs (SCHEMA_AUDIT §7).
