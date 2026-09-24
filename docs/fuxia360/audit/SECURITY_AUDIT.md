# Fuxia 360 Audit — Security Audit

**Severity scale:** **P0** = an attacker, or any ordinary logged-in user, can change money, points, inventory or privileges, or read other people's PII. **P1** = an integrity or abuse risk that needs a precondition or is limited in impact. **P2** = hygiene.
**Verdicts:** **CONFIRMED** (proven from repo code), **CONFIRMED-IF** (proven unless the live DB or env differs from the repo; the exact check is given), **REFUTED**.

> The anon key and project URL ship in every app bundle (`fuxia-native/lib/supabase.ts:6-7`, `EXPO_PUBLIC_*`). Every Edge Function deployed with verify-jwt accepts the anon key as a valid JWT. So "requires JWT" does **not** mean "requires a logged-in user".

---

## A. Spec P0 concerns (04_SECURITY_MODEL.md §2)

### P0-3 · Staff PIN — **CONFIRMED**
| Spec concern | Evidence |
|---|---|
| Stored in plaintext | `staff.pin TEXT NOT NULL` — `database/offline_sales_migration.sql:21` |
| Readable by ordinary clients | `rls_migration.sql:137-149` gives SELECT on `staff` to **every authenticated user**, and every customer is authenticated. The comment at `:133-135` and `RUNBOOK-fase0.md:95-97` admit it |
| Validated on the client | `app/vendedora/index.tsx:82-88` selects `staff` where `pin = entered` |
| Weak | 4 digits (`index.tsx:19`), no rate limit, no lockout, no audit of login attempts |
| Shown in the admin UI | `app/admin/staff/index.tsx:31,131` and `staff/[id].tsx:29,34` show PINs, so hashing will change admin UX (needs a decision) |
| Staff identity not bound server-side | `staffId` is a route param (`index.tsx:98-106`). It is sent as-is to `claim-sale` (`sale.tsx:180`) and written to `offline_sales.staff_id` (`sale.tsx:193`) and `inventory_change_requests.requested_by_staff_id` (`vendedora/inventory.tsx:107`). Nothing on the server checks it |
| Staff ↔ location relationship | Only checked on the client (`.eq('channel_id', …)` at `index.tsx:86`); the server never checks it |

### P0-4 · Offline sale is client-orchestrated and not atomic — **CONFIRMED**
`app/vendedora/sale.tsx:143-209`:
1. **Lost update:** `update({ sold: it.sold + it.quantity })` (`:162`) writes an absolute value computed from the `sold` read when the screen loaded (`:86-90`). Two devices, or a stale screen, overwrite each other.
2. **Errors ignored:** `Promise.all(decrements)` (`:164`). supabase-js returns `{error}` rather than throwing, so RLS rejections and failures are silently lost. A 0-row update caused by RLS isn't even an error.
3. **Wrong order, no rollback:** stock is decremented *before* the sale is recorded. If `claim-sale` fails (`:184`) or the `offline_sales` insert fails (`:199`), stock stays decremented with no sale.
4. **Client-authoritative price/total:** `total` and `unit_price` come from the cart (`:134,157`). `points_earned` is computed on the client (`:197`).
5. **No idempotency:** a double tap or retry creates a second sale and a second decrement.
6. **Weak claim code:** `Math.random()` (`:51-57`).
7. **The approval workflow can be bypassed:** the RLS policy `"inventory staff write"` is `FOR ALL` for role `staff` (`operational_writes_rls_migration.sql:57-60`). Any staff-role session can therefore `UPDATE`/`DELETE` any `channel_inventory` row in any channel through PostgREST, skipping `inventory_change_requests`. The approval queue is enforced by the UI only.
8. `offline_sales` UPDATE is open to staff/admin (`operational_writes_rls_migration.sql:71-75`), so a staff session can edit totals, `claimed_at` or `customer_id` on any sale.

### P0-2 · `claim-sale` — **CONFIRMED** (worse than the spec anticipated)
`fuxia-native/supabase/functions/claim-sale/index.ts`:
- **No authentication or authorization at all.** It uses the service role (`:162`) and never reads the `Authorization` header. The app calls it with the anon key (`sale.tsx:172`, `claim.tsx:83`).
- **`scan_qr` (`:166-217`)** takes `qr_code, items, total, channel_id, staff_id` from the request body. It creates an already-claimed `offline_sales` row with those values (`:192-205`) and credits `pairs = Σ items[].quantity`, `points = pairs × 100` (`:42-43`). **Anyone with the anon key and a customer's QR string can mint unlimited points** (e.g. `items:[{quantity:10000}]`). Nothing touches inventory, and nothing checks staff, channel, price or stock. The QR format `FX-{last 8 phone digits}-{base36 ms timestamp}-00` (`useAuth.ts:287-288`) is displayed on the card and partly predictable.
- **`claim_code` (`:219-247`)** credits the sale to whatever `phone` is in the body. It isn't tied to the caller, so an attacker who learns a code can credit it to their own phone. The check `if (sale.claimed_at)` (`:233`) and the later update (`:87-93`) are separate statements, so two concurrent claims can both succeed (**double points**).
- Referral bonus (`:98-137`) inherits the same forgery.

### P0 from the spec that is **REFUTED** or needs nuance
- "Offline sale updates `channel_inventory.sold` from the client and *subsequently* creates/claims the sale" — **confirmed exactly as described.**
- Woo webhook signature — **REFUTED as a P0:** the HMAC is mandatory for any payload that contains an order (`woocommerce-webhook/index.ts:206-210`). Remaining issue: a plain string comparison (`:62`) that isn't constant-time (P2).

---

## B. Additional P0 findings not in the spec

### P0-1 · Any authenticated customer can make themselves admin — **CONFIRMED-IF**
- Policy `"customers self update"`: `USING/WITH CHECK (auth_user_id = auth.uid())` with no column restriction (`rls_migration.sql:60-62`). Same for `"customers self insert"` (`:65-66`).
- `customers.role` is the authorization source for all privileged paths: `my_role()` (`operational_writes_rls_migration.sql:33-37`) and the Edge Functions `inventory-approve:126-133`, `admin-points:49-51`, `admin-broadcast-push:89-94`.
- **Exploit:** a logged-in customer sends `PATCH /rest/v1/customers?auth_user_id=eq.<me>` with `{"role":"admin"}`. They then have admin writes on channels, staff and inventory; can use `admin-points` to search any customer's PII (`:58-88`) and set anyone's points (`:108-135`); and can broadcast a push to every customer (`admin-broadcast-push`).
- **Condition:** true unless `UPDATE`/`INSERT` on column `role` has been revoked from `authenticated` in the live DB, or a trigger blocks it. Neither exists in the repo. Check: SCHEMA_AUDIT §7 query 4.

### P0-1b · Customers can create their own loyalty card with any balance — **CONFIRMED-IF**
`"cards self insert"` (`rls_migration.sql:79-80`) checks only `customer_id`. `total_points`, `pairs_count`, `tier` and `qr_code` are whatever the client sends (`useAuth.ts:292-298` sends 0/bronze, but a crafted request can send anything). With no `UNIQUE(customer_id)`, a second, richer card can also be inserted.

### P0-5 · Operational and PII data readable far beyond need — **CONFIRMED**
- Any authenticated customer can read **all** `offline_sales` (customer phones, totals, items), `staff` (PINs), `channel_inventory` and `channels` (`rls_migration.sql:137-149`).
- `support_tickets`: its own migration **disables** RLS (`support_tickets_migration.sql:36`), and `rls_migration.sql:140` re-enables it with authenticated read. Either way, every customer can read every support ticket, including other customers' phones, names and full chatbot transcripts (`last_messages`). Live state is order-dependent (SCHEMA_AUDIT §1).
- `inventory_change_requests`: `USING (true)` (`inventory_approvals_rls_fix.sql:33-36`), so **anonymous** read. It also allows **anonymous insert** as long as the row names any active `staff.id` (`:13-25`), and staff IDs are readable by any authenticated user.

### P0-6 · Pre-auth account takeover vectors — **CONFIRMED-IF**
1. **`otp_verifications` has no RLS in the repo** (`otp_migration.sql`; `points_orders_migration.sql:51-52` only adds a column). With Supabase's default grants, anon could `select code from otp_verifications where phone=…` and log in as anyone. **Check:** SCHEMA_AUDIT §7 query 3/4. If RLS is off → **P0, fix immediately**.
2. **Deterministic password:** every auth user's password is `fuxia_{phone}_{OTP_SALT}`, falling back to the literal `'salt'` if the env var is missing (`whatsapp-otp/index.ts:228-229`). If `OTP_SALT` is unset, or ever leaks, anyone can call `auth/v1/token?grant_type=password` for `{phone}@fuxia.app` and take over any account without OTP. **Check:** `supabase secrets list | grep OTP_SALT` (RUNBOOK Paso 0 asks for this; completion not recorded).
3. **Review bypass always on**, with hardcoded defaults (`whatsapp-otp/index.ts:17-19,184-190`): phone `+525555555555` + code `555555` logs in as `+525543412939`, the same phone as `database/seed_torosilva.sql`. If that account has `role='admin'` or holds real data, this is a public admin login. **Check:** the role of that customer, and whether the `REVIEW_*` secrets are set.

### P0-7 · `woocommerce-proxy` exposes Woo customer PII and customer creation — **CONFIRMED**
`woocommerce-proxy/index.ts:24-34,66-70`: `GET customers` is allowed with **any** caller-supplied params (`email`, `search`, `per_page`, `page`, `role`…). Any holder of the anon key can page through all Woo customers (names, emails, billing/shipping addresses and phones). `POST customers` lets anyone create Woo customer accounts with any body. The app itself calls the proxy with the anon key (`services/WooCommerceService.ts:24-27`), so the proxy cannot currently tell app users from anyone else. The comment "solo por email exacto" (`:29`) is not enforced. `products` GET also passes arbitrary params (e.g. `status=draft|private`), which leaks unpublished products (P1).

### P0-8 · `backfill-orders` is callable with the anon key and returns PII — **CONFIRMED-IF deployed**
Deployed with verify-jwt (`backfill-orders/index.ts:18-19`), and the anon key satisfies that. The response includes `customer`, `phone` and `email` for every paid Woo order (`:138,155`), and `{dry_run:false}` writes points. The header comment says to delete the function after use. **Check:** `supabase functions list`.

---

## C. P1 findings

| ID | Finding | Evidence |
|---|---|---|
| P1-1 | Every loyalty write is a non-atomic read-modify-write on `loyalty_cards.total_points` from Deno. Two concurrent events for the same customer lose one update. No DB transaction ties `transactions` + `purchase_items` + `loyalty_cards` together | webhook `:318-341`, claim-sale `:34-92`, link-orders `:74-107`, admin-points `:116-132`, backfill `:149-176` |
| P1-2 | Refunded or cancelled Woo orders that are still in `unmatched_orders` are credited later by `link-orders`: the reverse branch only looks at `transactions` (`woocommerce-webhook/index.ts:218-223`), and `link-orders` never checks `wc_status` (`link-orders/index.ts:80-99`) | |
| P1-3 | `admin-points` changes the balance first, then inserts the audit row and ignores the error. With the repo CHECK (`channel` ∉ {`manual`}), manual adjustments may have **no audit trail** | `admin-points/index.ts:124-132`; `schema.sql:44` |
| P1-4 | `escalate-to-staff` has no auth. Anyone can create tickets with any `customer_id` and trigger WhatsApp messages to staff numbers (cost and spam) | `escalate-to-staff/index.ts:116-163` |
| P1-5 | `virtual-tryon` / `virtual-tryon-status` have no auth → paid FASHN API abuse | `virtual-tryon/index.ts:30,58` |
| P1-6 | `notify-approval-pending` has no auth. Anyone can re-trigger admin pushes for pending requests | `notify-approval-pending/index.ts:48-58` |
| P1-7 | `loyalty-credit` (untracked): the shared secret `x-fuxia-secret` is compared with `!==`. **If WordPress calls it from browser JS, the secret is public.** `idem_key` is caller-controlled, so varying it bypasses the per-phone dedupe (`:99`); up to 500 pts per call | `loyalty-credit/index.ts:72-76,99` |
| P1-8 | `check_phone` allows phone enumeration without rate limiting | `whatsapp-otp/index.ts:119-133` |
| P1-9 | Woo REST keys were committed in git history (`de22cc3`, `bd6e3df`). BACKLOG #14 says they were rotated — needs confirmation that the old keys are revoked in WP | `constants/WooCommerce.ts:7-9` |
| P1-10 | `delete-account` misses `offline_sales`, `support_tickets`, `wishlists`, `unmatched_orders` and `inventory_change_requests.reviewed_by`. It may fail on FKs or leave PII behind | `delete-account/index.ts:51-77` |
| P1-11 | Admin screens are gated by UI only (`profile.tsx:352-367`). Safe only if RLS/functions are correct, and today they aren't (P0-1) | |
| P1-12 | No staff/admin action audit: admin direct stock edits (`vendedora/inventory.tsx:89-100`), channel/staff CRUD and Woo imports leave no actor record | |

## D. P2 / hygiene
- Non-constant-time HMAC comparison (`woocommerce-webhook/index.ts:62`).
- `CORS: *` on every function. Acceptable for native, but it should be tightened for Admin Web.
- `debug:` error details returned to clients (`whatsapp-otp:170,246`, `woocommerce-webhook:330`).
- Two committed `supabase/.temp` dirs; `pooler-url` is committed (no password, but it's infrastructure detail).
- The customer is resolved from `user_metadata.phone`, not `auth_user_id` (`useAuth.ts:91-101`, `delete-account:38-49`).

## E. Recommended remediation order
See SPRINT_0_IMPLEMENTATION_PLAN.md. In short: **S0.0 containment** (P0-1, 1b, 5, 6, 7, 8, a matter of hours to days, reversible policy/config changes), then **S0.2 staff auth** (P0-3), then **S0.3 atomic sale + claim** (P0-2, P0-4). Nothing in the Fuxia 360 inventory roadmap should start before those three are done.
