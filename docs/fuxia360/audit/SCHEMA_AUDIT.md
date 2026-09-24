# Fuxia 360 Audit — Schema Audit

**Method:** read every file in `database/`, every Edge Function, and every client `.from()`/`.rpc()` call. Then reconstructed the effective schema and compared it to what the code actually uses.
**Limitation:** the live database was not inspected. Section 7 lists the read-only queries a human needs to run to close each **[UNVERIFIED-LIVE]** item.

---

## 1. Migration inventory and inferred order

There is no migration tool: no `supabase/migrations/`, no `config.toml`, no history table in the repo. Files were applied by hand in the SQL Editor. The order below comes from git history plus the dependencies between files.

| # | File | First commit | Creates / changes | Idempotent? |
|---|---|---|---|---|
| 1 | `schema.sql` | 2026-04-21 | `customers`, `loyalty_cards`, `tier_config` (seeded 501/1201), `transactions`, `purchase_items`, `rewards`, `qr_scans`, trigger `update_updated_at` | **No** (plain `CREATE TABLE`) |
| 2 | `otp_migration.sql` | 2026-04 | `otp_verifications`, `delete_expired_otps()`. **No RLS** | No |
| 3 | `avatar_migration.sql` | 2026-04 | `customers.avatar_url`, bucket `avatars` + object policies | Yes |
| 4 | `push_tokens_migration.sql` | 2026-04 | `push_tokens` | Partly |
| 5 | `offline_sales_migration.sql` | 2026-05-18 | `customers.role` (CHECK customer/staff/admin), `channels`, `staff`, `channel_inventory`, `offline_sales` | Yes |
| 6 | `support_tickets_migration.sql` | 2026-05-21 | `support_tickets`, **`DISABLE ROW LEVEL SECURITY`** (`:36`) | Yes |
| 7 | `points_orders_migration.sql` | 2026-07-30 | `tier_config` → 300/900, `transactions.reversed_at/wc_status`, `unmatched_orders`, `otp_verifications.attempts`, indexes | Yes |
| 8 | `rls_migration.sql` | 2026-07-30 | `customers.auth_user_id` + backfill, `my_customer_id()`, `my_phone()`, self-policies, "authenticated read" on operational tables (**re-enables RLS on `support_tickets`**) | Yes |
| 9 | `realtime_loyalty_migration.sql` | 2026-08 | adds `loyalty_cards` to the realtime publication | Yes |
| 10 | `purchase_items_product_id_migration.sql` | 2026-08-18 | `purchase_items.wc_product_id`, `customers.birthday` (the latter "applied by hand in production" first, `:9-12`) | Yes |
| 11 | `product_image_overrides_migration.sql` | 2026-08-19 | `product_image_overrides`, bucket `product-images` | Yes |
| 12 | `operational_writes_rls_migration.sql` | 2026-09-01 | `my_role()`, write policies for admin/staff | Yes |
| 13 | `shoe_size_migration.sql` | 2026-09-16 | `customers.shoe_size` | Yes |
| 14 | `inventory_approvals_migration.sql` | 2026-09-21 | `inventory_change_requests` + RLS | Yes |
| 15 | `inventory_approvals_rls_fix.sql` | 2026-09-21 | replaces the ICR policies (anon insert with a staff id; **`USING (true)` read**) | Yes |
| 16 | `broadcasts_migration.sql` | 2026-09-22 | `broadcasts` | Yes |
| — | `seed_test_customer.sql`, `seed_torosilva.sql` | 2026-05-01 | **A schema change inside a seed:** `ALTER TABLE transactions ADD COLUMN status ... CHECK(...)` (`seed_torosilva.sql:10-13`) | — |

**Order-dependent result:** `support_tickets` ends with RLS **disabled** if #6 is applied after #8, and **enabled with authenticated read** if applied in commit order. **[UNVERIFIED-LIVE]**

## 2. Objects the code uses that no repo SQL creates (drift)

| Object | Used by | Consequence |
|---|---|---|
| table `wishlists` | `lib/WishlistContext.tsx:30-58`; RLS in `rls_migration.sql:115-120` | Created outside the repo |
| `customers.referral_code`, `customers.referred_by` | `useAuth.ts:100,251-281`, `referral.tsx:48-57`, `claim-sale:104-110`, `rls_migration.sql:57` | Created outside the repo |
| `transactions.notes` | `claim-sale:128`, `admin-points:131`, `loyalty-credit:161`, `admin/customer/[id].tsx:102` | Created outside the repo |
| `transactions.status` | `loyalty-credit:160`; the seed files only | Created by a seed file |
| `transactions.channel` values `'manual'`, `'popup'` | `admin-points:131`, `loyalty-credit:159` | `schema.sql:44` CHECK allows only `web/store/app`. Either the live CHECK was changed, or **these inserts fail silently**. `admin-points` updates the card *before* the insert and ignores the insert error (`:124-132`), so a manual adjustment could leave **no audit row** |
| `channel_inventory.image_url` | `import-woo.tsx:184`, `bulk-add.tsx:110`, `inventory-approve:71`, `vendedora/inventory.tsx:54` | Created outside the repo |
| table `pending_credits` | `loyalty-credit:108-205` | Not in the repo |
| function `fx_add_points(p_card_id, p_points)` | `loyalty-credit:170` | Not in the repo. The comment points to a missing `loyalty-credit-setup.sql` |
| triggers `trg_update_purchase_stats`, `update_loyalty_tier` | Described in `loyalty-credit:24-32` as live, "verified 20 Sep 2026" | Not in the repo. **If `trg_update_purchase_stats` increments `pairs_count` when `pairs_in_order > 0`, then the webhook (`:339-341`), `claim-sale` (`:80-85`), `link-orders` and `backfill-orders` — which also add `pairs_count` by hand — would double-count pairs.** **[UNVERIFIED-LIVE — high priority]** |
| `purchase_items.sku` NOT NULL (`schema.sql:52`) vs `claim-sale` inserting `sku: null` (`claim-sale:65`) | In-store purchase items | Unless the live column is nullable, **every in-store `purchase_items` insert fails** and the error is ignored (`claim-sale:62-73`) |

## 3. Integrity constraints that are missing but the code relies on

| Table | Missing | Risk |
|---|---|---|
| `loyalty_cards` | `UNIQUE(customer_id)` | The client inserts cards (`useAuth.ts:292-298`); duplicates break `.single()` everywhere |
| `customers` | unique email; `role` protected from self-update | See SECURITY_AUDIT P0-1 |
| `channel_inventory` | `UNIQUE(channel_id, sku, size, color)`; `CHECK(stock >= 0, sold >= 0, sold <= stock)` | Duplicate rows after repeated imports; negative or oversold stock is possible |
| `channel_inventory` | any Woo ID column (`wc_product_id`, `wc_variation_id`) | Mapping to Woo is only by free-text SKU/name. `import-woo.tsx:115,129` makes up `WC-{id}` SKUs when the variation has none |
| `staff` | `UNIQUE(channel_id, pin)` | Two sellers sharing a PIN make `.maybeSingle()` error out, so login fails (`vendedora/index.tsx:82-88`) |
| `offline_sales` | idempotency key, `status`, line-item table, FK from items to inventory | Items live only as client JSON (`sale.tsx:151-158`) |
| `channel_inventory.channel_id` | `ON DELETE CASCADE` (`offline_sales_migration.sql:30`) | Deleting a channel **destroys its inventory rows**. `inventory_change_requests` also cascades (`inventory_approvals_migration.sql:21`) |
| `transactions` | `UNIQUE(wc_order_id)` exists (`schema.sql:39`) ✔ | This is the only real idempotency guarantee in the loyalty system |

## 4. RLS matrix (effective, per repo; live state [UNVERIFIED-LIVE])

| Table | RLS | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|---|
| customers | on | self, or rows I referred | **self (any columns, incl. `role`)** | **self (any columns, incl. `role`)** | — |
| loyalty_cards | on | self | **self (any `total_points`/`tier`)** | — | — |
| transactions / purchase_items / rewards | on | self | — | — | — |
| wishlists / push_tokens | on | self | self | self | self |
| channels / staff | on | **any authenticated (incl. `staff.pin`)** | admin | admin | admin |
| channel_inventory | on | any authenticated | admin/staff | **admin/staff (any row, any column)** | **admin/staff** |
| offline_sales | on | any authenticated | admin/staff | admin/staff | — |
| support_tickets | **order-dependent** (§1) | any authenticated, or anon if disabled | — | client updates it anyway (`admin/index.tsx:147-150`) | — |
| inventory_change_requests | on | **anyone, incl. anon (`USING (true)`)** | admin/staff, **or anon with any active `staff.id`** | — | — |
| unmatched_orders | on | — | — | — | — |
| broadcasts | on | admin | — | — | — |
| product_image_overrides | on | public | — | — | — |
| otp_verifications | **not enabled in repo** | **[UNVERIFIED-LIVE]** | | | |
| tier_config, qr_scans, pending_credits | **not enabled in repo** | [UNVERIFIED-LIVE] | | | |

## 5. Code that cannot work under the repo's RLS (evidence the live DB differs)

These reads would return empty or fail under the policies in the repo. Either the screens are broken in production or the live DB has extra policies. **Resolve before writing any new policy.**

1. `app/admin/customer/[id].tsx:94-110` reads another customer's `customers`, `loyalty_cards` and `transactions` with the user client. Repo RLS allows self only.
2. `app/admin/reports.tsx:64-65` and `admin/dashboard-today.tsx:100` read all transactions and a count of all customers.
3. `lib/hooks/useAuth.ts:253-257` looks up the referrer by `referral_code`. Self-only RLS blocks that, so referrals would silently never attach.
4. `inventory_approvals_rls_fix.sql:1-3` says the seller "enters /vendedora with PIN **without a Supabase Auth session**". But `/vendedora` is only reachable from the profile tab of a logged-in `staff`/`admin` account (`profile.tsx:352-357`), and `sale.tsx:161-164` needs an admin/staff session to update `channel_inventory`. Under RLS an UPDATE that matches no permitted row returns **no error**, and `sale.tsx` does not check `.error` or the row count. **If any store device is logged in as a plain `customer`, in-store sales have silently not decremented stock.** [UNVERIFIED-LIVE]

## 6. TypeScript types

`fuxia-native/lib/database.types.ts` is hand-written, covers 7 tables and omits `role`, `birthday`, `shoe_size`, `referral_code`, `reversed_at`, `wc_status`, `notes` and all operational tables. It is not enforced because of `createClient<any>` (`lib/supabase.ts:10`). **Recommendation (S0.1):** generate types with `supabase gen types typescript` from the reconciled baseline and switch to `createClient<Database>` step by step, screen by screen, so the app build isn't broken.

## 7. Read-only verification queries (a human must run these against production)

```sql
-- 1. Actual tables/columns (compare with §2)
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns where table_schema='public' order by 1, ordinal_position;
-- 2. Policies
select tablename, policyname, cmd, roles, qual, with_check from pg_policies where schemaname='public' order by 1,2;
-- 3. RLS flags
select relname, relrowsecurity, relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and relkind='r' order by 1;
-- 4. Column/table grants (is customers.role updatable by authenticated?)
select grantee, table_name, column_name, privilege_type from information_schema.column_privileges
where table_schema='public' and table_name in ('customers','loyalty_cards','staff') and grantee in ('anon','authenticated');
select grantee, table_name, privilege_type from information_schema.role_table_grants
where table_schema='public' and grantee in ('anon','authenticated') order by 2,1;
-- 5. Triggers and functions not in repo
select event_object_table, trigger_name, action_timing, event_manipulation, action_statement
from information_schema.triggers where trigger_schema='public';
select p.proname, pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public';
-- 6. CHECK constraints (transactions.channel, customers.role, tier)
select conrelid::regclass, conname, pg_get_constraintdef(oid) from pg_constraint
where connamespace='public'::regnamespace and contype in ('c','u','f') order by 1;
-- 7. Data-quality facts needed before Sprint 1
select count(*), count(distinct customer_id) from loyalty_cards;
select role, count(*) from customers group by 1;
select channel_id, sku, size, color, count(*) from channel_inventory group by 1,2,3,4 having count(*)>1;
select count(*) filter (where sold>stock) oversold, count(*) filter (where stock<0 or sold<0) negative from channel_inventory;
select channel_id, pin, count(*) from staff group by 1,2 having count(*)>1;
select channel, count(*) from transactions group by 1;
-- 8. Pair-count drift check (trigger double counting?)
select lc.id, lc.pairs_count, coalesce(sum(t.pairs_in_order) filter (where t.reversed_at is null),0) ledger_pairs
from loyalty_cards lc left join transactions t on t.loyalty_card_id=lc.id group by 1,2
having lc.pairs_count <> coalesce(sum(t.pairs_in_order) filter (where t.reversed_at is null),0);
-- 9. Points drift check (balance vs ledger)
select lc.id, lc.total_points, coalesce(sum(t.points_earned) filter (where t.reversed_at is null),0) ledger_points
from loyalty_cards lc left join transactions t on t.loyalty_card_id=lc.id group by 1,2
having lc.total_points <> coalesce(sum(t.points_earned) filter (where t.reversed_at is null),0);
```

The safest way to capture all of this in one go is `supabase db dump --schema-only` (or `pg_dump --schema-only`) run by the project owner. Its output becomes the S0.1 baseline.
