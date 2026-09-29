# S0.1a — Live Reconciliation

**Unit:** S0.1a Live Schema Snapshot. **Read-only.** No production data, schema, RLS, function or config was modified.
**Project:** `tgzgiwfzddsghnxgkcqd` (fuxiaballerinas)
**Date:** 2026-09-24
**Status:** ✅ **Complete for everything provable from schema, deployed code and secret names.** Nine items need a count-only SQL Editor run or a dashboard check by the owner (§9). They don't block S0.0 planning, though a few adjust S0.0 details.

## 0. Artifacts and method

| Artifact | Source | Committed? |
|---|---|---|
| `live/schema.sql` | `supabase db dump --linked` (schema-only, `public`), run by the project owner | ✅ After review: no secrets, credentials, emails, phones, URLs or row data |
| `live/storage_policies.sql` | Extract of the `storage` schema dump (policies and RLS flags only) | ✅ The rest of `storage` is Supabase-managed internals, deliberately not committed |
| Deployed function sources | `supabase functions download` (21 functions) into a scratchpad outside the repo | ❌ Not committed. Diffed against the repo; secret scan clean |
| Secrets | `supabase secrets list` (names/dates used; values never read) | ❌ Names only, recorded in §2 |

"Repo" below means `database/*.sql` plus `fuxia-native/supabase/functions/*` at commit `b1b4171`.

---

## 1. Deployed Edge Functions vs repo

| Function | Ver. | verify_jwt | Repo vs deployed |
|---|---|---|---|
| admin-broadcast-push | v1 | true | identical |
| admin-points | v5 | true | identical |
| **backfill-orders** | v8 | true | identical. **Deployed and active** (Q8) |
| **birthday-push** | v15 | true | **NOT IN REPO** |
| calculate-points | v29 | true | differs (deployed = old amount+pairs hybrid) |
| calculate-tier | v28 | false | identical (501/1201 legacy) |
| **claim-sale** | v14 | true | **differs: deployed has NO referral bonus**; scan_qr/claim_code otherwise identical |
| delete-account | v9 | true | identical |
| escalate-to-staff | v11 | true | identical |
| hilo-chat | v20 | false | differs: FAQ copy states a different points rule |
| inventory-approve | v1 | true | identical |
| link-orders | v9 | true | identical |
| **loyalty-credit** | v3 | **false** | identical to the untracked local copy. **Deployed** (Q7) |
| my-orders | v6 | true | identical |
| notify-approval-pending | v2 | true | differs (logging only) |
| **send-push** | v15 | true | **NOT IN REPO** (service-role substring auth; writes `push_campaigns`) |
| virtual-tryon / -status | v23 / v17 | true | differ (deployed uses Replicate / FitRoom; repo uses FASHN) |
| whatsapp-otp | v50 | true | identical |
| woocommerce-proxy | v32 | true | identical |
| woocommerce-webhook | v45 | false | identical |

## 2. Secrets (names only)

- **Set:** `OTP_SALT` (2026-04-17), `WC_CONSUMER_KEY/SECRET` (2026-06-24), `WC_WEBHOOK_SECRET`, `FUXIA_CREDIT_SECRET`, `TWILIO_*` (except the two below), `RESEND_API_KEY`, `REPLICATE_API_TOKEN`, `FITROOM_API_KEY`, `SUPPORT_STAFF_WHATSAPP`, and the platform `SUPABASE_*` secrets.
- **Not set:** `REVIEW_BYPASS_PHONE`, `REVIEW_BYPASS_CODE`, `REVIEW_DEMO_PHONE`, `TWILIO_SMS_FROM`, `TWILIO_WELCOME_CONTENT_SID`, `FASHN_API_KEY`.

---

## 3. P0 verdicts (live)

### Confirmed

| ID | Finding | Live evidence (`live/schema.sql` line) | Change vs audit |
|---|---|---|---|
| **P0-1** | Any authenticated customer can set their own `customers.role` (e.g. `admin`) | Policy `customers self update` has no column restriction (1308); `GRANT ALL ON customers TO authenticated` (1770); **no trigger on `customers`** (triggers are only on `loyalty_cards` and `transactions`, 1043-1055) | Confirmed |
| **P0-1b** | Customers can insert their own loyalty card with any balance; the tier is derived automatically from points | `cards self insert` checks only `customer_id` (1279); `trg_update_tier` BEFORE INSERT sets tier from `total_points` (1055, 358-369); **no `UNIQUE(customer_id)`** (835-841) | Confirmed |
| **P0-2** | `claim-sale` unauthenticated point minting (`scan_qr`) and claiming to any phone (`claim_code`) | Deployed source is identical in these paths | Confirmed in production |
| **P0-3** | Staff PINs exposed | **Worse than the audit:** `anon_read_active_staff` = **anonymous** SELECT on active `staff` rows, **including `pin`** (1229). Also `auth read staff` / `staff_read_own` (1261, 1417) | **Escalated:** anyone on the internet with the anon key can read every active seller's PIN |
| **P0-4** | Client-orchestrated offline sale; inventory writable outside the approval flow | **Worse:** `anon_update_inventory_sold` = **anonymous UPDATE of any `channel_inventory` row and any column (stock, sold, price)** (1245). `anon_insert_offline_sales` = anonymous sale inserts (1221). Plus `inventory staff write` (1329) and `admins_all_inventory` (1203) | **Escalated:** anonymous inventory and price tampering |
| **P0-5** | PII readable beyond need | **Worse:** `anon_read_offline_sales` / `anon_read_own_sales` = **anonymous** read of all in-store sales, including customer phones (1237, 1241). `support_tickets`: RLS **enabled** (1421), readable by any authenticated user (1265). `icr read open` (1325) | **Escalated** (anonymous) for `offline_sales` |
| **P0-6.3** | App Store review bypass active in production with hardcoded defaults | `REVIEW_*` secrets unset (§2) | Confirmed. Target account role pending (§9, Q-A) |
| **P0-7** | `woocommerce-proxy` exposes Woo customer listing/creation | Deployed = repo | Confirmed |
| **P0-8** | `backfill-orders` callable with the anon key; returns customer PII; can write | Deployed v8 = repo | Confirmed |

### New P0 (not in the original audit)

| ID | Finding | Evidence | Verdict |
|---|---|---|---|
| **P0-9** | **`fx_add_points(p_card_id, p_points)` is `SECURITY DEFINER` and EXECUTE is granted to `anon` and `authenticated`.** Anyone can call `POST /rest/v1/rpc/fx_add_points` and add (or subtract) any number of points on any card. A logged-in customer can read their own card id, so self-inflation is trivial | 208-221 (SECURITY DEFINER, no auth check); 1670-1672 (GRANT to anon/authenticated) | **CONFIRMED** (from definition + grants; no exploit executed) |
| **P0-10** | **Authorization trusts `auth.jwt() → user_metadata.phone`, which users can edit themselves** (`supabase.auth.updateUser({ data })`). Affected:<ul><li>**RLS:** `admins_all_channels`, `admins_all_inventory` (admin/staff, ALL), `admins_all_staff` (admin, ALL), `admins_staff_all_sales` (ALL, incl. DELETE), `customers_read_own_sales`, `Users manage their own push tokens`. A user who writes an admin's or staff member's phone into their metadata inherits that role in these policies.</li><li>**Edge Functions:** `delete-account` resolves the customer **only** by `user_metadata.phone`, so a user who sets another customer's phone and calls it **deletes that customer's loyalty data and profile**. `my-orders` and `link-orders` fall back to `user_metadata.phone` when the caller has no linked customer (leaks the victim's order list; mis-credits orphans).</li></ul> | Policies 1189-1217, 1312; `delete-account/index.ts:38-49,51-77`; `my-orders/index.ts:56-65`; `link-orders/index.ts:53-61` | **CONFIRMED** (by design: Supabase `user_metadata` is user-writable; no exploit executed) |
| **P0-11** | **Default privileges give every future `public` table and function to `anon`/`authenticated`**, so any new SECURITY DEFINER function becomes a public RPC by default. This is how P0-9 happened | 1895-1918 (ALTER DEFAULT PRIVILEGES … GRANT ALL ON FUNCTIONS/TABLES TO anon, authenticated) | **CONFIRMED** (structural; every S0 migration must REVOKE explicitly) |

> **Correction (staging lab, 2026-09-24; see `S0_0A_TEST_REPORT.md` §4):** the **RLS part** of P0-10 is **not exploitable** as deployed. The `admins_*` / push-token policies check the spoofed phone through a subquery on `customers`, which runs under the caller's `customers` RLS (self-only), so the policy evaluates false (T15/T16 NOT REPRODUCED). The **function part is confirmed**: `delete-account` deleted a victim's loyalty data (T17) and an email-only stranger deleted the **admin's** customer record (T26); `link-orders`/`my-orders` act on the spoofed identity (T18). The policies remain a latent risk and break wishlist writes (R13).

### Refuted or downgraded

| ID | Audit claim | Live result |
|---|---|---|
| P0-6.1 | `otp_verifications` may be readable (no RLS in repo) | **REFUTED.** RLS enabled, no policies (1361), so clients can't read it |
| P0-6.2 | `OTP_SALT` may fall back to `'salt'` | **REFUTED.** Secret is set. The design risk (all passwords derived from one secret) stays P1 |
| (SCHEMA §2) | `trg_update_purchase_stats` may double-count `pairs_count` | **REFUTED.** The trigger updates a *different* column (`total_pairs_count`) plus `purchases_this_year`/`last_purchase_at` (340-352). But there are now **two pair counters**: `pairs_count` (app-maintained) and `total_pairs_count` (trigger-maintained). See D-7 |
| Invoker RPCs | `award_birthday_points`, `award_referral_points`, `run_annual_tier_review`, `check_free_pair_reward` are EXECUTE-granted to anon | **Not exploitable today.** They are `SECURITY INVOKER`, so RLS applies: there's no client UPDATE policy on `loyalty_cards` and `birthday_rewards`/`referrals`/`free_pair_rewards` have RLS with no policies, so the call errors out or does nothing. **Fragile:** it becomes P0 if any of them is changed to SECURITY DEFINER. Revoke in S0.0 |
| SCHEMA §5.4 | In-store sales might silently fail to decrement stock | **Mostly refuted, for a bad reason.** `admins_all_inventory` and the anon UPDATE policy make the update succeed for almost any session. A device logged in as a plain `role='customer'` with no metadata trick would still silently fail. Field accounts are counted in §9 |

---

## 4. P1 / integrity findings (live)

| ID | Finding | Evidence | Verdict |
|---|---|---|---|
| **P1-3** | `admin-points` inserts `transactions.channel = 'manual'`, which **violates** `transactions_channel_check` (web/store/app). The balance is updated first and the insert error is ignored, so **manual adjustments leave no audit row** | 747; `admin-points/index.ts:124-132` | **CONFIRMED** (Q5 fix approved) |
| **P1-13 (new)** | **`loyalty-credit` / pending popup credits are broken by the same CHECK.** Existing customers: the insert with `channel='popup'`, `status='completed'` fails, so the function returns 500 and no points are added. New customers: the credit is stored in `pending_credits`. Then trigger `trg_aplicar_creditos_pendientes` (AFTER INSERT on `loyalty_cards`, SECURITY DEFINER) inserts `channel='popup'`, which fails, **so the card insert itself is rolled back**. `useAuth.createProfile` ignores the card-insert error, so **those customers end up with no loyalty card** | 227-265, 747, 1047; `useAuth.ts:292-298` | **CONFIRMED** from schema. Impact count pending (§9, Q-C) |
| P1-14 (new) | `purchase_items.sku` is `NOT NULL`; `claim-sale` inserts `sku: null`, so **in-store purchase items are never saved** (error ignored) | 595; `claim-sale/index.ts:62-73` | **CONFIRMED** |
| P1-15 (new) | `run_annual_tier_review()` exists: it **downgrades Gold → Silver** when `purchases_this_year < 3`, and resets the counter. That contradicts the Q4 decision "tiers are permanent", **if it's scheduled**. `pg_cron` is installed; no code calls the function | 304-334; line 16 (pg_cron) | **UNRESOLVED:** schedule check (§9, Q-B) |
| P1-16 (new) | `birthday-push` has no internal auth (verify_jwt accepts the anon key). Anyone can trigger birthday pushes (spam). Points are idempotent per year (`birthday_rewards` UNIQUE(customer_id, year), 786) | deployed source; 55-113 | CONFIRMED (spam); points are safe |
| P1-17 (new) | Tier logic in the DB is **hardcoded 300/900** in `update_loyalty_tier` and fires on every `total_points` change, so `tier_config` isn't actually authoritative for the stored tier (functions read it, but the trigger overrides) | 358-369, 1055 | CONFIRMED (the values agree today) |
| P1-18 (new) | **Admin Customer 360, reports and referral lookup can't read other customers.** Live policies on `customers`, `loyalty_cards` and `transactions` are self-only, with no admin read policy. So `admin/customer/[id].tsx`, `admin/reports.tsx` and the `useAuth` `referral_code` lookup return only the caller's own rows, and **new sign-ups never get `referred_by` set** | 1304, 1283, 1430 | **CONFIRMED** (explains SCHEMA_AUDIT §5.1-5.3) |

---

## 5. Live RLS matrix (effective)

| Table | RLS | anon | authenticated | Notes |
|---|---|---|---|---|
| customers | on | — | self R/I/U (**any column**) | metadata/phone not used here |
| loyalty_cards | on | — | self R, self **I (any points)** | no UPDATE policy ✔ |
| transactions / purchase_items / rewards | on | — | self R | |
| wishlists | on | — | self ALL (+ a dead policy comparing phone with auth email) | |
| push_tokens | on | — | self ALL; **plus a metadata-phone policy (P0-10)** | |
| channels | on | **R active** | R; admin ALL; **admin/staff ALL via metadata (P0-10)** | |
| staff | on | **R active incl. `pin`** | R; admin ALL (my_role + metadata) | P0-3 |
| channel_inventory | on | **R all, U all** | R; admin/staff ALL (my_role + metadata) | P0-4 |
| offline_sales | on | **R all, I** | R all; own by phone; admin/staff I/U; admin/staff ALL via metadata | P0-5 |
| inventory_change_requests | on | **R all** (`USING true`); I with any active staff id | same | |
| support_tickets | on | — | **R all** | P0-5 |
| broadcasts | on | — | admin R | |
| product_image_overrides | on | R | R | intended |
| otp_verifications, pending_credits, unmatched_orders, tier_config, qr_scans, birthday_rewards, free_pair_rewards, referrals, push_campaigns | on | — | — | service role only ✔ |

All tables have `GRANT ALL` to anon and authenticated (1745-1885), so RLS is the only barrier.

## 6. Live objects vs repo (drift)

| # | Object | In repo? | Used by | Note |
|---|---|---|---|---|
| D-1 | tables `birthday_rewards`, `free_pair_rewards`, `referrals`, `push_campaigns`, `pending_credits` | ❌ | birthday-push, send-push, loyalty-credit; **`referrals` / `free_pair_rewards`: no code caller** | `referrals` is a second, unused referral model (the app uses `customers.referred_by`) |
| D-2 | table `wishlists` (UNIQUE customer+product) | ❌ (RLS only) | app | |
| D-3 | `customers.referral_code` (UNIQUE), `referred_by` | ❌ | app, claim-sale | |
| D-4 | `transactions.status` (CHECK), `notes` | seed file only | several | the CHECK blocks `manual`/`popup` (P1-3, P1-13) |
| D-5 | `channel_inventory.image_url` | ❌ | app, inventory-approve | |
| D-6 | functions `fx_add_points`, `fx_aplicar_creditos_pendientes`, `award_birthday_points`, `award_referral_points`, `check_free_pair_reward`, `run_annual_tier_review`, `trg_update_purchase_stats`, `update_loyalty_tier` | ❌ | see §3/§4 | `award_referral_points` and `check_free_pair_reward` have no caller |
| D-7 | `loyalty_cards.total_pairs_count`, `purchases_this_year`, `last_purchase_at` | ❌ | triggers only | there are two pair counters (`pairs_count` vs `total_pairs_count`) |
| D-8 | triggers `trg_aplicar_creditos_pendientes`, `trg_purchase_stats`, `trg_update_tier` | ❌ | — | |
| D-9 | policies: all `anon_*`, `admins_*`, `customers_read_own_sales`, `staff_read_own`, `read_inventory`, `read_active_channels`, `Users manage their own push tokens`, `users own their wishlist` | ❌ | — | created outside the repo; the source of P0-3/4/5/10 |
| D-10 | extensions `pg_cron`, `supabase_vault` | ❌ | ? | job list pending (§9) |
| D-11 | functions `birthday-push`, `send-push` deployed; `claim-sale`, `calculate-points`, `hilo-chat`, `virtual-tryon*`, `notify-approval-pending` differ | ❌ / ≠ | | the repo must be synced from deployed code before editing |
| D-12 | `support_tickets` RLS: **enabled** (the repo's own migration disables it; `rls_migration.sql` re-enabled it) | ≈ | | ordering question resolved: enabled |
| D-13 | Referral bonus in repo `claim-sale` | repo only | | **not live** |
| D-14 | Hilo FAQ tells customers "100 first purchase, then 50/purchase, +50 referral, +50 birthday" | deployed only | customers | differs from the applied rules (100/pair; no referral credit live; +50 birthday live) |

Matches between repo and live: the base tables and columns in `schema.sql` plus the later migrations; `unmatched_orders`, `broadcasts`, `inventory_change_requests`, `product_image_overrides` and the self-RLS policies from `rls_migration.sql`; `operational_writes_rls_migration.sql`; the storage avatar policies; the `wc_order_id` uniques.

## 7. Constraints of note (live)

- ✔ `transactions.wc_order_id` UNIQUE; `unmatched_orders.wc_order_id` UNIQUE; `pending_credits.idem_key` UNIQUE; `birthday_rewards (customer_id, year)` UNIQUE; `customers.phone` / `referral_code` UNIQUE; `loyalty_cards.qr_code` UNIQUE.
- ✘ **Missing:**
  - `loyalty_cards.customer_id` UNIQUE;
  - any CHECK on `channel_inventory` (stock/sold ≥ 0, sold ≤ stock);
  - `channel_inventory (channel, sku, size, color)` UNIQUE;
  - `staff (channel_id, pin)` UNIQUE;
  - `offline_sales` idempotency/status;
  - `customers.email` unique.
- `transactions_channel_check` = web/store/app only (blocks admin-points and loyalty-credit).
- `channel_inventory.channel_id` and `inventory_change_requests.channel_id` are `ON DELETE CASCADE`.

## 8. Status of [UNVERIFIED-LIVE] items (GAP_ANALYSIS §5)

| # | Item | Result |
|---|---|---|
| 1 | Applied SQL / order | ✅ Reconstructed in §6. Live = repo migrations **plus** a large set of out-of-repo objects |
| 2 | `customers.role` self-updatable | ✅ **Yes** (P0-1) |
| 3 | RLS on otp_verifications / tier_config / qr_scans / pending_credits | ✅ All enabled, no client policies |
| 4 | Loyalty triggers / `fx_add_points` | ✅ Defined (§3, §4); `fx_add_points` publicly executable (P0-9) |
| 5 | `purchase_items.sku` NOT NULL | ✅ Yes (P1-14) |
| 6 | `transactions.channel` CHECK | ✅ web/store/app only (P1-3, P1-13) |
| 7 | OTP_SALT / REVIEW_* | ✅ Salt set; bypass defaults active; **demo account is ADMIN** (G3) |
| 8 | backfill-orders / loyalty-credit deployed | ✅ Both deployed. loyalty-credit caller type ⏸ (Q7) |
| 9 | Seller accounts in the field | ⏸ Q-C (counts) |
| 11 | Old Woo key revoked | 🟡 New keys since 2026-06-24; WordPress revocation needs a human (Q13) |
| 12 | Data quality | ⏸ Q-C (counts) |

---

## 9. Owner actions still needed (read-only; nothing is exported except counts)

**Q-A / Q-B / Q-C: run once in the Supabase SQL Editor and paste the single result row back.** It returns **only counts and booleans**: no names, phones, PINs, ids or command text.

```sql
select
  -- Q-A: review-bypass target account
  (select count(*) from customers where phone = '+525543412939' and role = 'admin')  as demo_is_admin,
  (select count(*) from customers where phone = '+525543412939' and role = 'staff')  as demo_is_staff,
  -- Q-B: scheduled jobs (no command text returned)
  (select count(*) from cron.job)                                                   as cron_jobs,
  (select count(*) from cron.job where active and command ilike '%run_annual_tier_review%') as cron_annual_review_active,
  (select count(*) from cron.job where active and command ilike '%birthday%')       as cron_birthday_active,
  (select count(*) from cron.job where command ~* '(bearer|service_role|apikey|eyJ)') as cron_jobs_with_embedded_credential,
  -- Q-C: roles / seller identities
  (select count(*) from customers)                                                  as customers_total,
  (select count(*) from customers where role = 'admin')                             as role_admin,
  (select count(*) from customers where role = 'staff')                             as role_staff,
  (select count(*) from customers where auth_user_id is null)                       as customers_unlinked_auth,
  (select count(*) from staff where active)                                         as staff_active,
  (select count(*) from staff where active and channel_id is null)                  as staff_active_no_channel,
  (select count(*) from (select 1 from staff where active group by channel_id, pin having count(*) > 1) d) as staff_dup_pin_groups,
  (select count(*) from (select 1 from staff where active group by channel_id having count(*) > 1) d)      as channels_multi_seller,
  -- loyalty integrity
  (select count(*) from loyalty_cards)                                              as cards_total,
  (select count(*) from (select 1 from loyalty_cards group by customer_id having count(*) > 1) d)           as customers_multi_card,
  (select count(*) from customers c where not exists (select 1 from loyalty_cards l where l.customer_id = c.id)) as customers_without_card,
  (select count(*) from pending_credits where applied_at is null)                   as pending_credits_unapplied,
  (select count(*) from (select lc.id from loyalty_cards lc left join transactions t on t.loyalty_card_id = lc.id and t.reversed_at is null
     group by lc.id, lc.total_points having lc.total_points <> coalesce(sum(t.points_earned),0)) d)        as cards_points_drift,
  (select count(*) from (select lc.id from loyalty_cards lc left join transactions t on t.loyalty_card_id = lc.id and t.reversed_at is null
     group by lc.id, lc.pairs_count having lc.pairs_count <> coalesce(sum(t.pairs_in_order),0)) d)          as cards_pairs_drift,
  (select count(*) from loyalty_cards where pairs_count <> total_pairs_count)       as cards_two_counters_differ,
  (select count(*) from loyalty_cards where tier = 'gold')                          as cards_gold,
  (select count(*) from transactions where channel = 'store')                       as tx_store,
  (select count(*) from transactions t where channel = 'store' and not exists (select 1 from purchase_items p where p.transaction_id = t.id)) as tx_store_without_items,
  (select count(*) from unmatched_orders where matched_at is null)                  as orphans_open,
  (select count(*) from unmatched_orders where matched_at is null and wc_status in ('refunded','cancelled','failed')) as orphans_open_reversed,
  (select count(*) from referrals)                                                  as referrals_rows,
  (select count(*) from free_pair_rewards)                                          as free_pair_rows,
  -- inventory / sales
  (select count(*) from channel_inventory)                                          as inv_rows,
  (select count(*) from (select 1 from channel_inventory group by channel_id, sku, size, color having count(*) > 1) d) as inv_dup_groups,
  (select count(*) from channel_inventory where sold > stock)                       as inv_oversold,
  (select count(*) from channel_inventory where stock < 0 or sold < 0)              as inv_negative,
  (select count(*) from offline_sales)                                              as sales_total,
  (select count(*) from offline_sales where claimed_at is null)                     as sales_unclaimed,
  (select count(*) from offline_sales where staff_id is null)                       as sales_no_staff,
  (select count(*) from support_tickets)                                            as tickets_total;
```

### §9 results (owner-supplied, count-only, recorded 2026-09-24; authoritative)

| Gate | Result |
|---|---|
| G1 (the §9 row) | ✅ **PASSED** (executed and supplied by the owner) |
| G2 | `admin_without_auth_link = 0`, `staff_without_auth_link = 0` |
| G3 / Q-A | `demo_is_admin = 1`, `demo_is_staff = 0`. **The review login resolves to an ADMIN account**, so P0-6.3 is a **public admin login** |
| G4 | `customers_multi_card = 0` |
| G6 / Q-B | `cron_jobs = 0`, `cron_annual_review_active = 0`, `cron_birthday_active = 0`. No schedules; `run_annual_tier_review` isn't scheduled; tiers stay permanent (Q16). This also means **`birthday-push` isn't invoked by `pg_cron`**; its trigger mechanism, if any, is outside the database |

| G5 / Q-D | **Email provider = ON** ("Allow email-based sign up and log in"; confirmed in the dashboard). **Any stranger can obtain an `authenticated` session without a phone.** Every "any authenticated user" finding (P0-1, P0-1b, P0-5 authenticated part, P0-10) is reachable **without OTP**. New related finding: **Q17** derived-email squatting (lockout) |

Recording note: only the values above were provided in writing in this session. The remaining §9 columns (Q-C data-quality counts) are **not recorded in this repository**. They can be added here, verbatim, if and when they're shared. No rerun is requested.

**Q-D (dashboard check, no export):** Authentication → Providers. Is **email sign-up** enabled, and is "Confirm email" on? If email sign-up is open, anyone can get an `authenticated` session without an OTP, and every "any authenticated user" finding (P0-1, P0-1b, P0-5, P0-10) needs **no phone at all**.

**Q13 (WordPress):** confirm that the pre-June Woo REST key is revoked.

---

## 10. Implications for S0.0 (planning input only; not implemented)

1. There are more P0s, and each is a **live** problem: P0-9 (public `fx_add_points`), P0-10 (user_metadata trust, including arbitrary account deletion), and the anonymous policies behind P0-3/4/5.
2. The current app always runs with a user session. No app screen needs the `anon_*` policies (every staff and admin screen sits behind login, and anonymous claim/QR flows go through Edge Functions). Dropping them should be compatible. Verify on staging/logs before cutover.
3. The `my_role()`-based policies already cover what the `admins_*` metadata policies grant, **except** that `admins_all_channels` gives *staff* write on channels (probably unintended). Dropping the metadata policies should be compatible.
4. **Live behavior to preserve (Q4):** there is **no referral credit** today. S0.0/S0.5 must not accidentally deploy the repo's referral bonus. The repo must be synced from deployed code before any function edit.
5. Every S0 migration must explicitly `REVOKE ... FROM anon, authenticated`, because of P0-11.
6. New decision needed (not invented here): **Q15.** Should `transactions_channel_check` gain `manual` and `popup`? For `manual`, this is what makes the approved Q5 fix (b) work. For `popup`, fixing it would **start crediting popup points that currently fail**, and would **let those customers' cards be created**. That's an economics/behavior change and needs approval.
7. New decision needed: **Q16.** Is `run_annual_tier_review` intended? (Only relevant if Q-B shows it's scheduled; Q4 says tiers are permanent.)
