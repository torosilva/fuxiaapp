# Sprint 0 — Hardening & Canonical Baseline: Implementation Plan

> **Status: ARCHITECTURE APPROVED IN PRINCIPLE — IMPLEMENTATION NOT STARTED.**
> The audit has been reviewed. The Sprint 0 architecture is approved in principle, with the business decisions recorded in §0 below. **No code, migration, function or config has been changed.** Implementation must not begin until an explicit go-ahead is given. Each unit still needs its own approval before it is implemented (CLAUDE.md; 10_SPRINTS "Working rhythm"). Units blocked by open questions are marked **⛔ BLOCKED (Qn)**.

## 0. Decision log

### Decided

| # | Decision | Effect on this plan |
|---|---|---|
| Q1 | **CLOSED.** Sellers use their **own personal mobile phones**. Each seller must have an **individual identity and session**. **Shared store identities are not acceptable.** Every staff action must be attributable to the individual seller **and** the location. Keep the current seller UX as much as possible (channel/location → seller authentication/PIN → cart → sale), but the identity and authorization underneath must be individual and server-authoritative. | S0.2 is redesigned around individual identity: each `staff` row is linked 1:1 to the seller's own Supabase Auth user, and the PIN is verified for **that** seller. Sessions are bound to seller + auth user + channel. Shared `role='staff'` accounts lose operational access at cutover. S0.0-d is no longer blocked; its ICR part is **sequenced** into S0.2c. S0.3 derives `staff_id` only from the individual session. |
| Q2 | Staff PINs will be hashed. **Existing PINs will never be shown again.** Admins can reset them. PINs stay **4 digits** for now, protected by rate limiting, lockout and an audit trail. | S0.2: `pin_hash`, reset-only admin UI, lockout plus `staff_auth_events`. The PIN display in `admin/staff/*` is removed in R1. |
| Q3 | **CLOSED.** Sellers may **not** discount or override prices. The **authoritative selling price comes from the system.** Centrally approved promotions may be supported separately in the future; seller-entered prices are not allowed. | S0.3 go-live is no longer blocked. The sale request carries **no price fields**: the price comes only from the system (today `channel_inventory.price`), and a request that includes a price is rejected. There is no discount path and there are **no discount permission thresholds** (none invented). Promotions are out of Sprint 0 and will be a separate, centrally administered capability. |
| Q4 | **Loyalty economics do not change in Sprint 0.** Loyalty logic is centralized so that product-category rules can be added later. **Tiers stay permanent**, not annual. The annual-tier copy (`payments/index.tsx:75`) gets corrected later, outside Sprint 0. The legacy 501/1201 `calculate-tier` can be retired once it's confirmed to have no callers. Referral should eventually work across all channels, but **referral behavior does not change in Sprint 0**. | S0.5: one `loyalty_apply` path, same rules as today (100 points × total line quantity, 300/900 from `tier_config`, in-store-only first-purchase referral bonus). The pairs calculation sits behind one function so category rules can be added later without touching callers. `calculate-tier` / `calculate-points` are retired only after a caller check (repo grep and function invocation logs). |
| Q5 | **Both loyalty integrity fixes are approved:** (a) refunded, cancelled or failed orphan orders must not be credited later by `link-orders`, and the webhook reversal branch must record their status; (b) `admin-points` must write its audit row atomically with the balance change. | S0.5: these are no longer [RULE]-pending. |
| Q6 | Mario or the project owner may run a **schema-only** production dump. **No production customer data may be exported.** | S0.1a is unblocked, with owner-run, schema-only scope. The data-quality queries in SCHEMA_AUDIT §7 must return **aggregate counts only** (no rows containing PII). See the revised S0.1a. |
| Q9 | A **staging environment** will be created or used before any destructive or cutover testing of S0.2/S0.3. | Staging is a hard prerequisite for S0.2/S0.3 testing and for every cutover unit. |
| Q10 | Use an **additive compatibility window followed by a separate cutover**. **The length of the adoption window has not been decided** and must not be invented. | Cutover units S0.2c/S0.3c (and the proxy/claim cutovers) stay separate and are triggered by a later explicit decision, not a date. |
| Q11 | **Yes.** Sprint 0 starts recording a **forward-compatible inventory audit event** for new sales, designed to migrate into the Sprint 2 inventory ledger. | S0.3: the `inventory_events` write is **required** (it was optional). Its design is in S0.3. |
| Q13 | The old Woo REST key must be **verified and revoked** before P1-9 is closed. | P1-9 stays open until someone confirms in WordPress (REST API keys list) that the historical key is gone. This has been added to the S0.4 exit criteria. |

### Roadmap reaffirmation

| Topic | Decision |
|---|---|
| **Production Tracking Lite** | Stays a **core** Fuxia 360 domain on the future roadmap (`00_MASTER_SPEC.md` §5.2, `02_TARGET_ARCHITECTURE.md` §2.1, `03_DATA_MODEL.md` §5.2, `10_SPRINTS.md` Phase 5D). **Not implemented in Sprint 0.** |

### Still open: operational verification items (Sprint 0)

| # | Item | Affects |
|---|---|---|
| **Q7** | Is `loyalty-credit` deployed? Does WordPress call it server-side or from browser JS? | ⛔ S0.0-f (the `loyalty-credit` part only) and migrating that caller in S0.5. Nothing else is blocked. |
| **Q8** | Is `backfill-orders` still deployed, and is it still needed? | S0.0-f (backfill part). Requiring the service-role key is safe either way; only the undeploy decision waits. |

### Not a Sprint 0 blocker: resolved during future domain design

| # | Item | Where it gets resolved |
|---|---|---|
| Q12 | Remaining operational details of distributed fulfillment: how Woo's stock number is maintained today, who marks variants as make-to-order, bazaar leftovers, and manual order routing. The architectural principles are already recorded (`00_MASTER_SPEC.md` §5.1–5.2). | **Does not block Sprint 0.** Resolved during Product, Inventory, Availability, Fulfillment and Production design (Sprints 1, 2, 4, 5C, 5D). |
| Q14 | Production Tracking Lite operations: how make-to-order is tracked today, which workshops, governance roles, and open orders at cutover. | **Does not block Sprint 0.** Resolved during Production design (5D). |

## Guiding constraints

1. **Installed apps keep working.** Old OTA bundles are still in the field. Every server change is either additive, or paired with a client release plus an adoption window, followed by a separate "cutover" unit that removes the legacy path. Cutover units are listed separately so they can be delayed or rolled back on their own. **The length of the adoption window is undecided (Q10).** Each cutover requires its own explicit go-ahead.
2. **Read the live schema before writing to it** (S0.1a). The repo does not describe production (SCHEMA_AUDIT §2, §5).
3. **No loyalty-economics, referral or pricing changes** in Sprint 0 (Q4). The only approved loyalty behavior changes are the two integrity fixes in Q5.
4. **Keep the seller UX as close to today as possible, with individual identity underneath (Q1).** The flow stays channel/location → seller PIN → cart → QR/code. The identity and authorization behind it are individual and server-authoritative. Visible changes, kept to a minimum:
   - each seller is logged in on **their own phone** with **their own account** (the existing OTP login);
   - admins enroll a seller by phone number;
   - admins reset PINs instead of viewing them (Q2).
5. **Staging is mandatory** before destructive or cutover testing of S0.2/S0.3 (Q9).
6. **No production customer data leaves production** (Q6).
7. **Prices come only from the system (Q3).** No seller discounts or price overrides; no discount thresholds are defined.
8. **No shared staff identities (Q1).** Every operational write is attributable to one individual seller (or admin) **and** one location.

## Recommended sequence

```
S0.1a Live schema snapshot (read-only)          ← prerequisite for everything
  │
S0.0  Containment (server-only, compatible)      ← closes P0-1,1b,5(partial),6,7,8
  │
S0.1b Baseline migrations + generated types
  │
S0.2  Staff auth (additive server)  ─┐
S0.3  Atomic POS sale + claim (additive server) ─┤→ R1 client release (OTA)
S0.5  Loyalty apply function (additive) ─┘
  │
S0.2c / S0.3c  Cutover: revoke legacy client paths (after adoption window;
               duration undecided (Q10); needs explicit go-ahead; staging-tested (Q9))
  │
S0.4  Regression verification → Sprint 0 exit
```

---

## S0.1a — Live schema snapshot (read-only)

| | |
|---|---|
| **Goal** | Capture the true production schema, policies, grants, triggers and functions so all later units build on fact |
| **Affected files** | New: `docs/fuxia360/audit/live/schema.sql` (dump output), `docs/fuxia360/audit/LIVE_RECONCILIATION.md` |
| **DB/API impact** | None (read-only) |
| **Security** | **Decided (Q6):** Mario or the project owner runs it. The dump is **schema-only**; **no production customer data is exported**. Check that no secrets appear in function bodies before committing |
| **Data-export rule** | The SCHEMA_AUDIT §7 data-quality queries (7–9) must be run in **aggregate form only**: counts of duplicates, oversold rows, duplicate-PIN groups and drifting cards. They must never return phones, names, PINs, card ids or row-level data. For example, replace `select channel_id, pin, count(*) … having count(*)>1` with `select count(*) from (select 1 from staff group by channel_id, pin having count(*)>1) d`. For S0.2 planning (Q1), also collect these counts only: active `staff` rows; `customers` with `role='staff'`; and channels with more than one active seller. They size the move from shared to individual identities. Row-level remediation lists, if ever needed, stay inside production (the SQL Editor) and are not committed |
| **Migration/rollback** | N/A |
| **Verification** | Run `supabase db dump --schema-only`, plus the metadata queries 1–6 and the aggregate versions of 7–9 from SCHEMA_AUDIT §7. Record the result for each [UNVERIFIED-LIVE] item |
| **Acceptance** | Every item in GAP_ANALYSIS §5 (1-8, 12) is marked confirmed or refuted, with the query output attached. The P0-1 / P0-6 severity is final |

## S0.0 — Emergency containment (server-only, compatible with current clients)

Each sub-unit is a separate commit and a separate deploy, with its own rollback.

### S0.0-a Protect `customers.role` (P0-1)
- **Change:** a `BEFORE INSERT OR UPDATE` trigger on `customers`. It rejects any `role` other than `customer` on INSERT, and any change to `role` on UPDATE, unless the request runs as `service_role` (or a future SECURITY DEFINER admin function). A trigger is preferred over column REVOKE because Supabase's table-level grants make column revokes easy to get wrong.
- **Before deploying:** Carolina or Mario review `select id, name, role from customers where role <> 'customer'` **inside the production SQL Editor** (not exported, per Q6) and confirm every admin/staff row. Any unexpected admin is treated as an incident.
- **Files:** new migration `supabase/migrations/<ts>_protect_customer_role.sql`.
- **Compatibility:** no client ever sets `role` (`useAuth.ts:270-283` doesn't) → no client change.
- **Rollback:** `drop trigger …; drop function …`.
- **Tests:** as a customer JWT, `PATCH customers {role:'admin'}` → error; normal profile update (name, shoe_size) → OK; service role can still change role.
- **Acceptance:** no non-service path can change `role`; existing profile edits still work.

### S0.0-b Constrain loyalty card self-insert (P0-1b)
- **Change:** replace `"cards self insert"` with `WITH CHECK (customer_id = my_customer_id() AND total_points = 0 AND pairs_count = 0 AND tier = 'bronze')`. Add `UNIQUE(customer_id)` **only if** the S0.1a duplicate query returns 0 rows. Otherwise list the duplicates as a separate cleanup decision.
- **Compatibility:** the client inserts exactly these values (`useAuth.ts:292-298`) ✔.
- **Rollback:** restore the previous policy; drop the index.
- **Acceptance:** crafted insert with points > 0 is rejected; new sign-up still creates a card.

### S0.0-c Lock tables that have no RLS (P0-6.1)
- **Change:** `ENABLE ROW LEVEL SECURITY` on `otp_verifications` (no policies; service role only), `qr_scans`, `pending_credits`. `tier_config` gets public read only. Only for tables where S0.1a shows RLS is off.
- **Compatibility:** the client never reads these tables (grep: no `.from('otp_verifications')` in the app) ✔.
- **Rollback:** `DISABLE ROW LEVEL SECURITY`.
- **Acceptance:** anon/authenticated `select` on `otp_verifications` returns 0 rows or is denied; OTP login still works.

### S0.0-d Narrow PII reads (P0-5, partial)
- **Change in S0.0 (compatible with sellers in the field today):**
  - `support_tickets`: SELECT/UPDATE for `my_role()='admin'` only.
  - `offline_sales`: SELECT for `my_role() in ('admin','staff')`, **or** own rows by `customer_id`/phone (keep the existing `"own by phone"` policy); drop the generic authenticated read.
- **Sequenced into S0.2c, not done here:**
  - `inventory_change_requests`: remove anon read/insert (`inventory_approvals_rls_fix.sql:13-36`).
  - Narrow `offline_sales` from "any staff" down to "the individual seller's own channel(s)".
  
  Both depend on individual staff sessions (S0.2) being in use. Q1 answers the design question (individual identities), so this is **sequencing, not a blocker**.
- **Staff PIN** (`staff` SELECT) isn't changed here, because it would break seller login in the field. It moves to S0.2c.
- **Rollback:** recreate the prior policies (recorded in the migration's down section).
- **Acceptance:** a plain customer JWT reads 0 support tickets and 0 other people's sales; the admin Today dashboard, approvals and the seller's "sales today" still work.

### S0.0-e Restrict `woocommerce-proxy` (P0-7)
- **Change:** a per-path parameter whitelist. For `products*`: `per_page, page, category, search, include, orderby, order`, with `status` forced to `publish`. For `GET customers`: only an exact `email` param, and the response trimmed to `[{id, email}]`. For `POST customers`: only `{email, first_name, last_name, billing.phone}` is accepted. Current clients always send the **anon key**, not the user session (`WooCommerceService.ts:24-27`), so POST can't require a user JWT yet. Keep it working for body-whitelisted, exact-email creation during the adoption window, then move it to a JWT-scoped `wc-link-customer` function in R1 and remove it from the proxy at cutover.
- **Files:** `fuxia-native/supabase/functions/woocommerce-proxy/index.ts`.
- **Rollback:** redeploy the previous version (keep the git SHA in the deploy log).
- **Acceptance:** `GET customers` without email → 403; listing pages → 403; the shop, product detail and sign-up WC linking still work.

### S0.0-f Close privileged utility endpoints (P0-6.2/6.3, P0-8)
- **Change:**
  - `backfill-orders` — **Q8 open.** Default until Q8 is answered: require `Authorization` to equal the service-role key. This is safe whether or not the function is still needed. Undeploying it waits for Q8.
  - `whatsapp-otp`: **fail closed** if `OTP_SALT` is unset. Gate the review bypass behind `REVIEW_BYPASS_ENABLED=true` with no hardcoded code or phone defaults. Confirm the demo account is `role='customer'`.
  - `loyalty-credit` — **⛔ BLOCKED (Q7).** Record in the repo how WordPress calls it, and commit the missing SQL (`pending_credits`, `fx_add_points`) from the S0.1a dump. Any hardening of the secret or `idem_key` handling depends on whether the caller is server-side or browser JS.
- **Caution:** rotating `OTP_SALT` changes every derived password. **Do not rotate it** without a migration plan: the password is re-derived at each verify, so it would need a re-set step. Only ensure it is set and strong.
- **Rollback:** redeploy previous versions; unset the flag.
- **Acceptance:** anon call to backfill → 401/404; OTP login works; App Review login works only while the flag is enabled.

### S0.0-g Stop anonymous point minting in `claim-sale` `scan_qr` (P0-2, interim)
- **Problem:** the current seller app sends the **anon key** as Bearer (`sale.tsx:172`), so the server can't require a user JWT without breaking in-field devices.
- **Interim server-only mitigation (compatible):** in `scan_qr`,
  - require `staff_id` to be an active staff member whose `channel_id == channel_id`;
  - recompute `total` and each `unit_price` from `channel_inventory` using `items[].inventory_id` (reject items with no `inventory_id`, or rows not in that channel);
  - cap quantity at `stock - sold`;
  - make the `claim_code` claim atomic: `UPDATE offline_sales SET claimed_at=now() … WHERE id=$1 AND claimed_at IS NULL RETURNING`.
  
  Staff IDs are still forgeable by anyone who can read `staff`, so this is containment only. The full fix is individual staff sessions (S0.2) plus `pos-sale` (S0.3).
- **Loyalty economics unchanged (Q4):** points stay 100 × total quantity.
- **Price (Q3 decided):** the system price is authoritative. Client-sent `total`/`unit_price` are ignored and recomputed from `channel_inventory.price`. This matches what the current app already sends (`sale.tsx:157` uses `it.price`), so legitimate sales don't change.
- **Rollback:** redeploy the previous version.
- **Acceptance:** forged `items` without valid `inventory_id` → 400; valid in-store QR sale → points as before; concurrent double claim → exactly one success.

## S0.1b — Canonical migration baseline + types

| | |
|---|---|
| **Goal** | One migration history that matches production |
| **Files** | New root `supabase/config.toml`, `supabase/migrations/<ts>_baseline.sql` (from the S0.1a dump), plus the S0.0 migrations after it; `database/README.md` stating the legacy files are historical and superseded; generated `fuxia-native/lib/database.types.ts` |
| **DB impact** | None. The baseline is marked applied with `supabase migration repair --status applied` and is **never executed against production** |
| **Security** | Review the dump for secrets before commit |
| **Rollback** | Revert the commit (no DB effect) |
| **Tests** | `supabase db reset` on a local/staging DB reproduces the schema; `diff` against a fresh prod dump is empty |
| **Acceptance** | Fresh local DB == prod schema; types generated; `tsc --noEmit` passes. Switching `createClient<any>` to `<Database>` is **not** part of this unit, to avoid build churn; it is follow-up work |

Moving `fuxia-native/supabase/functions` under root `supabase/functions` is **optional** here. If done, it is its own commit, and deploy commands in README/RUNBOOK are updated.

## S0.2 — Server-side staff authentication (P0-3)

**Decided:**
- **Q1:** individual sellers on personal phones; no shared identities; every action is attributable to seller + location.
- **Q2:** hashed 4-digit PINs, never shown again, admin reset, rate limiting, lockout and audit.

Testing runs on **staging** (Q9).

**Identity model:**
- **Primary identity:** each seller logs in on **their own phone** with **their own Supabase Auth account**, using the existing OTP login for their own phone number.
- **Link:** each `staff` row is linked 1:1 to that account.
- **PIN:** stays as the per-shift step inside the seller flow (channel → PIN), so the UX is preserved. It's verified server-side **for that individual seller only**, never looked up across all staff.
- **Staff capability** comes from an **active `staff` row linked to the caller's auth user**, not from a shared `customers.role='staff'` login. A shared or generic account can't operate, because it isn't linked to exactly one person.
- **Location:** S0.2 enforces the existing assignment (`staff.channel_id`). If sellers really work several locations, a many-to-many assignment is added as an additive table when the unit is approved. That's a data-model detail within the decided policy, not a business decision.
- **Noted, not decided:** a seller's personal account is usually also their customer account. Crediting in-store points to one's own card isn't blocked in Sprint 0, because no rule was given, but every such sale is attributable (seller = customer is visible). A governance rule can be added later.

- **DB (additive):**
  - `staff.auth_user_id uuid UNIQUE NULL` (the 1:1 link), and `staff.phone` (E.164, used for enrollment).
  - `staff.pin_hash` (pgcrypto `crypt(pin, gen_salt('bf'))`), backfilled from `pin` **inside the database** (the plaintext never leaves production).
  - `staff_sessions(id, staff_id, auth_user_id, channel_id, token_hash, created_at, expires_at, revoked_at)`, bound to one seller, one auth user and one channel.
  - `staff_auth_events(id, staff_id?, auth_user_id?, channel_id, success, reason, created_at)`: the audit trail for every attempt, enrollment/link, reset, unlock and lockout.
  - `staff.failed_attempts`, `staff.locked_until` (or equivalent derived from `staff_auth_events`).
- **Enrollment and linking:**
  1. An admin creates or edits a seller with their phone number (`staff-admin`).
  2. The seller logs in to the app on their own phone with OTP for **that** number.
  3. On the first `staff-login`, the server links `staff.auth_user_id` to the caller, **only if** the caller's verified phone equals `staff.phone`, and audits the link.
  4. An existing link is never replaced silently: re-linking (e.g. new phone number) is an admin action.
  
  **Prerequisite:** S0.0-f (OTP / password-derivation hardening), because this link trusts the verified phone.
- **Protection for 4-digit PINs (Q2):**
  - **Per seller (staff row + auth user):** after N consecutive failures (proposed N = 5), a cooldown (proposed 15 min).
  - **Per channel:** a failure ceiling per time window, as defense in depth.
  - **Lockout:** after M failures (proposed M = 10), that seller's PIN login locks until an admin unlocks or resets it. Admins get a push notification.
  
  Because the PIN is checked only against the caller's own staff row, guessing it requires first holding that seller's authenticated session. N/M/window values are **proposed defaults for review, not business thresholds**, and get confirmed when the unit is approved.
- **Edge Functions:**
  - `staff-login` `{channel_id, pin}`:
    - requires the caller's **own** user JWT;
    - resolves the staff row by `auth_user_id` (or runs the enrollment link above);
    - checks the seller is active, not locked, and assigned to `channel_id`;
    - verifies the PIN hash, applies the throttles, and audits the attempt;
    - returns an opaque session token (TTL ≈ one shift, value to be confirmed) plus `{staff_id, name, channel}`.
  - `staff-admin` (admin only): create staff with name + phone + channel; **reset PIN** (the new PIN is shown **once** and never retrievable); deactivate; unlock; re-link. Enforces a unique PIN per channel. Every action is audited with the admin's identity.
- **Client R1 (OTA):**
  - The seller entry point stays in the profile tab. It appears when the logged-in user has a linked active staff row, or has a pending enrollment matching their phone.
  - `vendedora/index.tsx` calls `staff-login` instead of selecting `staff`. The token is kept in memory or SecureStore and sent as `x-staff-session` along with the user's own JWT.
  - The admin staff screens (`admin/staff/index.tsx:131`, `staff/[id].tsx:34,119`) **stop showing PINs**, gain a phone field, and offer "Restablecer PIN" and "Desbloquear".
- **Cutover S0.2c** (a separate unit, triggered by an explicit decision after the adoption window; duration undecided per Q10):
  - `REVOKE SELECT (pin)`, or restrict `staff` SELECT to admin; later set `pin = NULL` / drop the column.
  - **Shared identities removed:** operational RLS and functions stop honoring `customers.role='staff'` on its own and require a linked active staff row plus a valid individual session. Any staff row still unlinked, and any `role='staff'` account not linked to exactly one staff row, loses operational access. S0.1a gives the aggregate counts to plan this.
  - Remove anon ICR read/insert (`inventory_approvals_rls_fix.sql:13-36`). ICRs are created through a staff-session-checked function/RPC, and `requested_by_staff_id` comes from the session.
  - Narrow `offline_sales` reads to admin plus the individual seller's channel(s) (moved here from S0.0-d).
- **Rollback:** additive objects can stay. Cutover rollback = re-grant SELECT and restore the prior policies; the old client path still works because `pin` is only nulled in a later, separate step.
- **Tests (staging):**
  - seller A logged in on their own phone, correct PIN → session bound to A + channel;
  - seller B's PIN entered from A's account → rejected (PINs are per individual);
  - a generic or shared account with no linked staff row → rejected;
  - enrollment links only when the verified phone matches `staff.phone`;
  - an attempt to re-link to another account → rejected without admin action;
  - wrong PIN × N → 429 plus cooldown; after M failures, locked until an admin unlocks or resets;
  - channel not assigned to the seller → rejected;
  - expired or revoked token → 401;
  - a token presented with another user's JWT → rejected;
  - a reset invalidates the old PIN;
  - the admin UI never shows an existing PIN;
  - after cutover, the `staff` table isn't readable by a customer JWT.
- **Acceptance (10_SPRINTS S0.2 + Q1 + Q2):**
  - each seller has an individual, server-verified identity and session, and no shared store identity can operate;
  - every staff action (login, sale, ICR, approval request) records the individual seller **and** the location;
  - PINs are hashed and never readable or displayable again;
  - validation happens on the server; the staff↔channel relationship is enforced;
  - rate limiting and lockout are in place and documented;
  - every login attempt, enrollment/link, reset and unlock is audited.

## S0.3 — Atomic in-store sale + claim (P0-2, P0-4)

**Status:** design approved in principle. No open business blocker: Q3 is closed (system price only), and Q1 is closed (individual sessions). **Technical dependency:** S0.2 individual staff sessions must be in place first. Testing runs on **staging** (Q9).

- **DB (additive):**
  - `offline_sales`: add `idempotency_key UUID UNIQUE`, `status TEXT DEFAULT 'completed'`, `staff_session_id`, `staff_auth_user_id`, `created_by_function`.
  - New `offline_sale_items(id, sale_id, channel_inventory_id, product_name, sku, size, color, quantity, unit_price)`. The `items` JSONB column stays populated for existing readers (`sales-today.tsx`, `tracking/index.tsx`, `claim-sale`).
  - `CHECK (sold >= 0 AND stock >= 0 AND sold <= stock)` on `channel_inventory`, **only after** S0.1a shows no violating rows (otherwise a cleanup decision comes first).
- **SQL function** `pos_record_sale(p_staff_session_id, p_idempotency_key, p_items jsonb, p_customer_card_id uuid null, p_customer_phone text null)`: `SECURITY DEFINER`, EXECUTE granted to `service_role` only. `staff_id`, `auth_user_id` and `channel_id` are **read from the validated staff session**, never passed by the client (Q1). `p_items` holds only `{channel_inventory_id, quantity}`: **no price field** (Q3). In a single transaction it:
  1. returns the existing sale if the idempotency key was already used;
  2. locks the inventory rows `FOR UPDATE` ordered by id;
  3. checks each row belongs to the session's channel and `qty <= stock - sold`;
  4. takes the price **only from the system** (`channel_inventory.price` today; the canonical price source from Sprint 1 onward) and computes the total. There is no discount or override path;
  5. inserts the sale and its items;
  6. runs `UPDATE channel_inventory SET sold = sold + qty` (relative);
  7. if a card is given, calls `loyalty_apply` (S0.5) with reference `offline_sale:<id>`, and marks the sale claimed;
  8. otherwise generates the claim code with `gen_random_bytes`;
  9. **(Q11 decided — required)** inserts one `inventory_events` row per line in the same transaction (see below).
  
  Any failure rolls back everything.
- **`inventory_events` (new, append-only; Q11):** designed so that Sprint 2 can migrate it into `inventory_movements` 1:1 without reinterpretation.
  - **Columns:**
    - `id uuid`
    - `event_type text` — `SALE` in Sprint 0; the CHECK list is taken from 03_DATA_MODEL: `RECEIPT, TRANSFER, SALE, RETURN, ADJUSTMENT, RESERVATION, RELEASE, WRITE_OFF`
    - `quantity int` — positive; direction is given by the from/to fields
    - `from_channel_id uuid null` — the future `from_location_id`
    - `to_channel_id uuid null`
    - `channel_inventory_id uuid` — the legacy row; resolved to `variant_id` in Sprint 1
    - snapshot fields `sku, product_name, size, color` — so Sprint 1 mapping works even if the legacy row is later edited or deleted
    - `business_reference_type text` (`offline_sale`), `business_reference_id uuid`
    - `actor_type text` (`staff`/`admin`/`system`), `actor_staff_id uuid null`, `actor_user_id uuid null`, `staff_session_id uuid null`
    - `idempotency_key text` — unique together with the line number
    - `reason text null`, `created_at timestamptz`
  - **Rules:**
    - no UPDATE/DELETE grants to any client role; inserts only through SECURITY DEFINER functions;
    - no FK to `channel_inventory` with CASCADE. It is a nullable, non-cascading reference, because `channel_inventory` rows can be deleted today and the audit trail must survive that.
  - **Scope in Sprint 0:** only **new** sales through `pos_record_sale` write events. Historical sales and admin/approval-driven stock edits are not backfilled here: historical backfill is Sprint 2's opening-balance work, and adjustments move to the Sprint 2 ledger. The table is **audit only** in Sprint 0. `channel_inventory.stock/sold` stays the operational number, so there is no second source of truth (CLAUDE.md rule 11).
  - **Compatibility with distributed fulfillment (2026-09-24):**
    - Events are recorded per **physical channel/location** (`from_channel_id`), never against "Woo" or a central pool.
    - `event_type` already includes `RESERVATION`/`RELEASE`, so future online-order allocations fit the same shape.
    - Sprint 0 writes only in-store `SALE` events. No allocation, discrepancy or make-to-order logic is added.
    - Because `business_reference_type` is free text (not an enum tied to `offline_sale`), future `RECEIPT` events referencing a `production_request` fit without a schema change. Sprint 0 never records make-to-order demand as a negative movement.
  - **Sprint 2 migration path:** `inventory_events` → `inventory_movements`, with `channel_id` → `location_id` via the Sprint 2 channel→location map and `channel_inventory_id` → `variant_id` via the Sprint 1 map. This will be documented as a migration safeguard (source, target, mapping, duplicate/orphan strategy, validation query) per 09_MIGRATION_PLAN.
- **Edge Function** `pos-sale`:
  - validates the seller's **own** user JWT **and** `x-staff-session` (S0.2), and checks the session belongs to that same auth user, is unexpired and not revoked;
  - **rejects any request containing `price`, `unit_price` or `total`** (400) rather than silently ignoring them, so misuse shows up;
  - resolves the QR to a card server-side, then calls the RPC.
  
  `offline_sales.staff_id`, the new `offline_sales.staff_auth_user_id` and `inventory_events.actor_*` all come from the session (Q1: attributable to the individual seller and the location).
- **`claim-sale` `claim_code`:** requires the user's JWT; the phone/customer comes from the caller, not the body; points come from the stored server-computed sale; the claim is a single atomic claim + loyalty RPC.
- **Client R1 (OTA):** `sale.tsx:143-209` becomes one `pos-sale` call with a UUID idempotency key generated when the cart is confirmed. The UI is unchanged. `claim.tsx` sends the session token.
- **Cutover S0.3c** (a separate unit, triggered by an explicit decision after the adoption window; the duration is undecided per Q10):
  - drop staff UPDATE/DELETE on `channel_inventory` and staff INSERT/UPDATE on `offline_sales` (admin direct edits remain until Sprint 2);
  - `claim-sale` `scan_qr` returns 410;
  - `claim_code` requires a JWT.
- **Rollback:** before cutover, fully reversible (the old path still works). After cutover, re-create the dropped policies and redeploy the previous `claim-sale`.
- **Tests:**
  - 2 parallel sales for the last unit → exactly one succeeds;
  - same idempotency key twice → one sale;
  - a request containing any price/total field → 400; the recorded price always equals the system price;
  - a request with `staff_id`/`channel_id` in the body can't override the session's seller or location;
  - a session token used with a different user's JWT → rejected;
  - item from another channel → reject;
  - RPC failure mid-way → no stock change;
  - QR sale credits points exactly once;
  - double claim → one success;
  - every successful sale line writes exactly one `inventory_events` row; a failed or rolled-back sale writes none; a retry with the same idempotency key writes no extra events;
  - Σ `inventory_events.quantity` (SALE, per `channel_inventory_id`, since go-live) equals the increase in `sold` from new sales over the same period.
- **Acceptance (10_SPRINTS S0.3 + Q1 + Q3 + Q11):**
  - one authoritative server operation;
  - inventory validated;
  - price and total come **only from the system**, and the seller can't enter, discount or override a price;
  - every sale is attributable to the individual seller (staff + auth user + session) and the location;
  - sale + items + stock + loyalty + inventory audit events in one transaction;
  - idempotent and double-submit safe;
  - loyalty economics unchanged (Q4).
- **Promotions (Q3):** centrally approved promotions are a possible **future, separate** capability, administered centrally rather than entered by sellers. They're not part of Sprint 0, and no discount permission thresholds are defined.

## S0.5 — Single loyalty write path (P1-1, P1-2, P1-3)

- **Pre-req:** S0.1a answers whether `trg_update_purchase_stats` / `update_loyalty_tier` already maintain `pairs_count`/`tier` (double-count risk).
- **Q4 decided — no economics change:**
  - 100 points × total line quantity (all Woo lines, as today);
  - Silver 300 / Gold 900 from `tier_config`;
  - **tiers are permanent** (no annual window);
  - referral behavior unchanged: an in-store first purchase credits the referrer 1×; online purchases don't.
  
  The goal is **centralization**, not change.
- **Designed for future category rules (Q4):**
  - one SQL function `loyalty_pairs_for_lines(p_lines jsonb) → int` (or equivalent) is the **only** place that decides which quantities count as pairs. In Sprint 0 it returns Σ quantity, the current behavior;
  - callers pass line items, not precomputed points, so a later category rule changes one function;
  - points-per-pair is read from one place: a new `loyalty_config` row, or a constant in that function, seeded to 100.
- **SQL function** `loyalty_apply(p_card_id, p_points, p_pairs, p_channel, p_ref_type, p_ref_id, p_idempotency_key, p_actor, p_notes)`: inserts the ledger row (unique idempotency) and updates the card with **relative** increments; tier comes from `tier_config`; one transaction. `fx_add_points` is folded in or wrapped.
- **Callers migrated one by one** (each its own deploy): webhook, link-orders, admin-points, claim-sale/pos-sale, then loyalty-credit (⛔ Q7).
- **Referral:** the existing in-store first-purchase bonus is moved as-is behind `loyalty_apply`, with no rule change. Referral across all channels is a **later** decision (Q4) and out of Sprint 0.
- **Retire legacy (Q4):** `calculate-tier` (501/1201) and `calculate-points` are retired **only after** confirming they have no callers: a repo grep (currently no app caller), Supabase function invocation logs over a review period, and the WordPress/Hilo owners confirming they don't call them.
- **Approved integrity fixes (Q5):**
  - P1-2: `link-orders` skips `unmatched_orders` whose latest `wc_status` is refunded/cancelled/failed, and the webhook reversal branch updates `unmatched_orders.wc_status` for orphan orders;
  - P1-3: `admin-points` writes the audit ledger row and the balance change atomically through `loyalty_apply` (no balance change without an audit row).
- **Out of Sprint 0:** correcting the annual-tier copy in `app/payments/index.tsx:75` (Q4: "correct later").
- **Verification:** SCHEMA_AUDIT §7 queries 8-9 (balance vs ledger) produce a drift report **before** and **after**. Existing drift is reported, not auto-corrected (a correction is a separate decision).
- **Acceptance:** no Edge Function updates `loyalty_cards.total_points` directly; concurrent credits don't lose updates; every point change has exactly one ledger row with actor/reference.

## S0.4 — Regression verification (Sprint 0 exit)

- **Critical journeys** (manual script in `docs/fuxia360/audit/S0_REGRESSION_CHECKLIST.md`; run on staging, then prod smoke):
  - customer OTP sign-up and login (plus App Review login);
  - shop/product detail;
  - loyalty card and realtime celebration;
  - Woo order `processing` → points, refund → reversal, retro-credit;
  - seller on **their own phone and account**: enrollment/link → channel → PIN → QR sale / code sale → customer claim; the sale is attributed to that seller + location; the price can't be changed;
  - admin: inventory import, direct adjust, staff request → approve/reject, points adjust, broadcast;
  - order tracking;
  - account deletion.
- **Automated (new, minimal):** Deno tests for the pure logic in functions; SQL tests (pgTAP or plain assertion scripts) for `pos_record_sale`, `loyalty_apply` and the RLS matrix (customer/staff/admin/anon JWTs against each table).
- **Environment:** all destructive and cutover tests run on **staging** first (Q9); production gets only non-destructive smoke checks.
- **Exit criteria:**
  - no open P0 from SECURITY_AUDIT;
  - RLS matrix tests green;
  - balance-vs-ledger drift report reviewed;
  - Carolina or a seller completes a store sale with no new training;
  - **P1-9 closed only once the historical Woo REST key is verified revoked** (Q13): someone confirms in WordPress → WooCommerce → Settings → Advanced → REST API that no key from commits `de22cc3`/`bd6e3df` remains. The confirmation is recorded with date and person.

## Optional S0.7 — Integration observability (06 §7)
Add an `integration_events` table written by the webhook (received, processed, skipped, failed, with error and order id), plus a read-only list in the mobile admin. Changes no behavior. It can slip to Sprint 4.

---

## Out of scope for Sprint 0 (explicitly)
products/variants, locations, online-order allocation, fulfillment tasks, inventory discrepancies, **Production Tracking Lite** (production partners, requests, lifecycle; a core domain planned for Sprint 5D), fulfillment promise, the movement ledger (beyond the audit-only `inventory_events` for new sales, per Q11), receipts, transfers, reservations, Woo product/stock sync, Admin Web, Launch, Growth, the monorepo conversion, any change to points/tier/referral rules (Q4), cross-channel referral (Q4, later), and the annual-tier copy fix (Q4, later).

## Question status summary

| # | Topic | Status | Blocks |
|---|---|---|---|
| Q1 | Seller authentication model | ✅ **CLOSED** — individual sellers on personal phones; individual server-authoritative identity and session; no shared store identities; actions attributable to seller + location | — |
| Q2 | PIN visibility / length | ✅ Decided — hashed, never shown, admin reset, 4 digits + rate limit/lockout/audit | — |
| Q3 | POS discounts / price overrides | ✅ **CLOSED** — no seller discounts or price overrides; the system price is authoritative; central promotions possible later as a separate capability; no thresholds defined | — |
| Q4 | Loyalty rules | ✅ Decided — no economics change; centralize with a category hook; permanent tiers; copy fix later; retire 501/1201 once there are no callers; referral unchanged | — |
| Q5 | Loyalty integrity fixes | ✅ Decided — both approved | — |
| Q6 | Production schema dump | ✅ Decided — Mario/owner, schema-only, no customer data exported | — |
| Q7 | `loyalty-credit` deployment / caller | 🔴 **OPEN** — pending operational verification | S0.0-f (loyalty-credit part), migrating the S0.5 caller |
| Q8 | `backfill-orders` status | 🔴 **OPEN** — pending operational verification | Undeploy decision (a service-key guard is allowed meanwhile) |
| Q9 | Staging | ✅ Decided — staging before destructive/cutover testing of S0.2/S0.3 | — |
| Q10 | Compatibility window | ✅ Decided (approach) — additive window, then a separate cutover. **Duration intentionally undecided** | Triggering S0.2c/S0.3c (needs a later explicit go-ahead) |
| Q11 | Inventory audit event in Sprint 0 | ✅ Decided — yes, forward-compatible `inventory_events` for new sales | — |
| Q12 | Distributed fulfillment / Woo stock / bazaar leftovers | ➖ **Not a Sprint 0 item.** The principles are in the spec; the remaining operational details are resolved during Product, Inventory, Availability, Fulfillment and Production design | — (Sprint 0) |
| Q13 | Old Woo REST key | ✅ Decided (handling) — verify and revoke before closing P1-9. **The verification itself is still pending** | Closure of P1-9 / S0.4 exit |

**Remaining Sprint 0 open items:** only **Q7** and **Q8**, both operational verification. Neither blocks S0.1a.

**Future-sprint questions (do not block Sprint 0):**
- **Q14 — Production Tracking Lite** (core domain, Phase 5D): how are make-to-order orders tracked today, and with which workshops/suppliers? Who assigns work, changes promised dates, confirms quality and receipt, and gets at-risk alerts (`05_GOVERNANCE.md` §5.1)? Which location receives produced pairs? How many make-to-order orders are open right now (needed for cutover capture, `09_MIGRATION_PLAN.md` Phase 5b)?

**Next step:** wait for an explicit go-ahead. The first unit, when approved, is S0.1a (the schema-only dump, run by Mario or the project owner).
