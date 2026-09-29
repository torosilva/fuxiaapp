# S0.0A — Staging Security Lab Manifest (PROPOSAL; nothing created yet)

**Target:** STAGING only (`faltxpkaicwpnlqaxrdu`). Production is never touched; no `--linked` writes; no `migration repair`; A1–A8 are **not** applied.
**Purpose:** reproduce every S0.0A vulnerability on the unmodified baseline ("BEFORE"), and establish repeatable security (T) and regression (R) tests. The same tests then prove each A-unit closes its hole ("AFTER").
**Data rule:** no production data, phones, emails, passwords, secrets or Woo credentials. Every identity is synthetic and uses reserved/test values.

---

## A. STAGING_FIXTURE_MANIFEST

### A.1 Conventions

| Item | Convention | Why |
|---|---|---|
| Phone numbers | NANP fictional range **`+1 555 0100 xx`** (`+15550100001`…`+15550100099`) | Reserved for fiction; can never reach a real person |
| Emails | Derived OTP-style emails `{digits}@fuxia.app` for phone users (mirrors the app's scheme so the app's password login works); attacker/test emails on **`staging.invalid`** (RFC 2606 reserved TLD, undeliverable) | No mail can be delivered |
| UUIDs | Fixed, recognizable: `00000000-0000-4000-a000-0000000000NN` (NN per fixture) | Idempotent seed and exact cleanup |
| Woo order ids | `99 000 0xx` range (`990000001`…) | Can't collide with real Woo ids in staging reasoning |
| Names / products | Prefixed `STAGING ` | Obviously synthetic in any screen |
| Staff PINs | `1111`, `2222`, `3333` | Obviously test values |
| Push tokens | `StagingFakeToken-<actor>`. Deliberately **not** `ExponentPushToken[...]`, so the functions that filter by prefix never call Expo | No real push delivery |

### A.2 Fixtures

"svc" = needs service_role or postgres privileges to create.

| ID | Purpose | Synthetic identity / role | Creates (tables/objects) | Needed by | Removal / reset | svc |
|---|---|---|---|---|---|---|
| F0 | Loyalty config | — | `tier_config`: bronze 0/0, silver 3/300, gold 9/900 (values/descriptions from repo `schema.sql` + `points_orders_migration.sql`; no PII) | T1, T12, R1, R3, R4, R10 | `delete from tier_config where tier in (...)` | ✅ |
| F1 | Storage buckets | — | `storage.buckets`: `avatars` (public), `product-images` (public) | R2, R11 | delete buckets (and their objects) | ✅ |
| F2 | Store channel | `STAGING Tienda X` (store) | `channels` | T4–T8, T14, T15, T24, R6–R8 | delete by fixed UUID (cascades inventory and ICR) | ✅ |
| F3 | Bazaar channel | `STAGING Bazar Y` (bazar) | `channels` | T15 (cross-channel), R8 | same | ✅ |
| M1 | Admin | auth user `15550100001@fuxia.app`, `user_metadata.phone=+15550100001`; customer `STAGING Admin M1`, `role='admin'`, linked `auth_user_id`; card 0 pts | `auth.users`, `customers`, `loyalty_cards` | T15, T16, T25, T26, R7, R8 | admin API delete user, then delete the customer (cascades card/tokens) | ✅ |
| S1 | Seller (individual, Q1) | auth user `15550100021@fuxia.app`; customer `STAGING Seller S1`, `role='staff'`; `staff` row in F2 with PIN `1111` | `auth.users`, `customers`, `loyalty_cards`, `staff` | T4, T8, T14, T23, T24, R6, R7 | delete staff row, customer, auth user | ✅ |
| S2 | Second seller (other channel) | `staff` row only in F3, PIN `2222` (no auth user) | `staff` | T4 (multiple PINs visible), R8 | delete by UUID | ✅ |
| C1 | Victim customer | auth user `15550100011@fuxia.app`; customer `STAGING Cliente C1`, phone `+15550100011`, `wc_customer_id=990001`; card **100 pts / 1 pair** | `auth.users`, `customers`, `loyalty_cards` | T1, T7, T9, T11, T13–T18, T26, R2, R4, R5, R9–R11, R13 | admin API delete user; delete customer (cascades) | ✅ |
| C1-tx | C1 purchase history | 1 web transaction `wc_order_id=990000001`, 100 pts, plus 1 `purchase_items` row | `transactions`, `purchase_items` | T17 (deletion evidence), R2 | removed with C1 (items first) | ✅ |
| C2 | Second customer / attacker with OTP-style account | auth user `15550100012@fuxia.app`; customer `STAGING Cliente C2`; card 0 pts | same as C1 | T17, R11 | same | ✅ |
| C3 | Customer without card | auth user `15550100013@fuxia.app`; customer row, **no card** | `auth.users`, `customers` | T12 | same | ✅ |
| E1 | **Baseline attacker (G5)**: email-only, no phone, no customer row | auth user `e1.attacker@staging.invalid`, created **confirmed via the admin API** (so no email is sent; the resulting session is identical to a public email sign-up) | `auth.users` only | T10, T21–T26 | admin API delete; recreate before each run (T21/T22 may create a customer row for E1) | ✅ (creation) |
| U1 | Unregistered web buyer (phone to be squatted) | **no account**; phone `+15550100099` appears only in F6 | — | T22 | — | — |
| F4 | Inventory | 3 rows in F2 (`STAGING Ballerina Test`, sizes 23/24/25, price 999.00, stock 5, sold 0), 1 row in F3 | `channel_inventory` | T5, R6, R7, R8 | cascade from channels, or delete by UUID | ✅ |
| F5 | Store sales | one **unclaimed** sale in F2, code `STGA01`, `customer_phone=+15550100011` (C1), items JSON from F4, total 999.00; one **claimed** sale for C1 | `offline_sales` | T6, T7, T15, R9, R10 | delete by UUID and code prefix `STG` | ✅ |
| F6 | Orphan web orders | `unmatched_orders`: `990000101` for C1's phone (R4/T18), `990000199` for U1's phone (T22 impact) | `unmatched_orders` | T18, T22, R4 | delete by `wc_order_id` range | ✅ |
| F7 | Inventory change request | one `pending` ICR by S1 in F2 (`adjust_stock` on an F4 row) | `inventory_change_requests` | T8, T24, R7 | cascade from channel, or delete by UUID | ✅ |
| F8 | Admin push token | `push_tokens`: M1 → `StagingFakeToken-M1` (platform `ios`) | `push_tokens` | T16, R8 | cascade from M1 | ✅ |
| F9 | OTP rows for R1/T27 | `otp_verifications` row per run for `+15550100031` (fresh sign-up) with a known code, `expires_at = now()+10m` | `otp_verifications` | R1, T27 | delete by phone | ✅ |

**Not created:** support tickets, broadcasts, pending credits, referrals, free-pair rewards, cron jobs, and any real phone, including the production review demo phone (see D.3).

### A.3 Implementation form (when approved)
- `supabase/staging/lab_seed.sql`: F0–F9 data (idempotent `insert … on conflict do nothing`, fixed UUIDs), applied with `psql "$STAGING_DB_URL"`. **Not** a migration, so it never enters migration history and never reaches production.
- `scripts/s00a/lab_auth.ts` (Deno): creates and deletes auth users M1, S1, C1, C2, C3 and E1 through the staging admin API.
- `scripts/s00a/probe.ts` (Deno): runs T1–T27 and the API-level R tests, and writes JSON results.
- **Hard guards in every script:**
  - abort if any URL or key contains `tgzgiwfzddsghnxgkcqd`;
  - abort unless the target ref equals `faltxpkaicwpnlqaxrdu`;
  - read credentials only from `~/.fuxia-staging.env`; never print them.

---

## B. T1–T27 BEFORE matrix (baseline, no A-unit applied)

"Reproduced" = the vulnerability is observed. "Control" = the test confirms a behavior that is already safe (a regression guard for AFTER).

| T | Actor | Fixtures | Exact action (probe) | Expected BEFORE | AFTER unit |
|---|---|---|---|---|---|
| T1 | anon; C1 | F0, C1 | `rpc('fx_add_points', {p_card_id: C1.card, p_points: 1000})` as anon, then as C1 | **Reproduced:** returns the new total; C1 card +1000 each call | A1 |
| T2 | catalog | — | `has_function_privilege('anon'/'authenticated', <each of 6 fns>, 'EXECUTE')` | **Reproduced:** true | A1 |
| T3 | catalog | — | `pg_default_acl` for `postgres`/`public`: function EXECUTE for anon/authenticated/PUBLIC | **Reproduced:** present | A1 |
| T4 | anon | S1, S2 | `select name, pin from staff` | **Reproduced:** returns `1111`, `2222` | A2 |
| T5 | anon | F4 | `update channel_inventory set price=1 where id=<F4.1>` | **Reproduced:** 1 row updated | A2 |
| T6 | anon | F2 | `insert offline_sales(code 'STGX01', channel F2, items '[]', total 1)` | **Reproduced:** inserted | A2 |
| T7 | anon | F5 | `select code, customer_phone from offline_sales` | **Reproduced:** returns C1's phone | A2 |
| T8 | anon | F7, S1 | select all ICRs; insert an ICR with `requested_by_staff_id=S1.staff` | **Reproduced:** rows returned; insert succeeds | A2 |
| T9 | C1 | C1 | `update customers set role='admin' where auth_user_id=C1` | **Reproduced:** role becomes admin | A3 |
| T10 | E1 | E1 | `insert customers(auth_user_id=E1, phone '+15550100098', name 'STAGING E1', role 'admin')` | **Reproduced:** inserted as admin | A3 (+A8 claim) |
| T11 | C1 | C1 | `update customers set phone='+15550100097' where auth_user_id=C1` | **Reproduced:** phone changed | A3 |
| T12 | C3 | C3 | `insert loyalty_cards(customer C3, total_points 100000, qr 'STG-C3')` | **Reproduced:** inserted; the trigger sets tier `gold` | A4 |
| T13 | C1 | C1 | insert a second card, 0 pts | **Reproduced:** inserted (2 cards) | A4/A4b |
| T14 | C1 | S1, S2 | `select pin from staff` | **Reproduced:** PINs returned | A5 |
| T15 | C1 with spoofed metadata | M1, S1, F2, F5 | `auth.updateUser({data:{phone: M1.phone}})`, refresh session; then `update staff set active=false where id=S1.staff`; `insert channels('STAGING Spoof')`; `delete offline_sales where code='STGA01'` | **Reproduced:** all succeed (via the `admins_*` metadata policies) | A6 |
| T16 | C1 spoofing M1 | F8 | as T15, then select/insert `push_tokens` for M1 | **Reproduced:** M1's token read; insert allowed | A6 |
| T17 | C2 spoofing C1 | C1, C1-tx, C2 | C2 sets `user_metadata.phone = C1.phone`, then calls `delete-account` | **Reproduced (destructive, synthetic):** **C1's customer, card, transactions and items are deleted**; C2's auth user is deleted. Reseed afterwards | A7 |
| T18 | E1 spoofing C1 | C1, F6 | E1 sets `user_metadata.phone = C1.phone`; calls `link-orders`, then `my-orders` | **Reproduced:** `link-orders` resolves C1 and links orphan `990000101` to C1. `my-orders` resolves C1, then fails at the Woo call (WC_URL is `.invalid`), **HTTP 500/502 instead of 404**, which proves the resolution happened | A7 |
| T19 | anon | — | `whatsapp-otp` `verify` with `+525555555555` / `555555` (no `REVIEW_*` secrets, mirroring production) | **Reproduced:** session returned for the configured demo phone (see D.3) | A8 |
| T20 | — | — | Bypass works when enabled | **N/A in BEFORE** (the flag doesn't exist in the baseline code) | AFTER only (A8) |
| T21 | E1 | E1 | = T10 (role escalation at insert) | **Reproduced** | A3 |
| T22 | E1 | E1, F6 (U1) | `insert customers(auth_user_id=E1, phone=U1 '+15550100099', role 'customer')`; then E1 calls `link-orders` | **Reproduced:** row inserted; orphan `990000199` credited to E1's card (if E1 also inserts a card, as the app would) | A3 + A8 |
| T23 | E1 | S1, S2 | `select pin from staff` | **Reproduced:** PINs returned (`auth read staff`) | A5 |
| T24 | E1 | F7, S1 | select ICRs; insert ICR with S1's staff id | **Reproduced** | A2 |
| T25 | E1 | M1 | call `admin-points` (`search`), `admin-broadcast-push`, `inventory-approve` | **Control:** 403 "Requiere admin" (safe on baseline) | guard for A3 |
| T26 | E1 | M1, S1, C1 | E1 sets `user_metadata.phone = M1.phone`, then repeats T15/T16 | **Reproduced:** metadata policies grant admin paths | A6/A7 |
| T27 | new user | F9 | OTP verify for `+15550100031` with a seeded code | **BEFORE:** JWT has **no** `app_metadata.verified_phone` (baseline behavior recorded) | AFTER (A8) |

Reset rule: T9, T11, T12, T13, T15–T18, T21 and T22 mutate fixtures. The probe runs a **full reseed** (A.3) before each destructive test group, and the BEFORE report records every mutation.

---

## C. R1–R13 regression matrix

| R | Flow | Method | Fixtures | Pass criteria | External contact |
|---|---|---|---|---|---|
| R1 | New customer OTP sign-up → profile → card | API (probe): seed F9 OTP → `whatsapp-otp verify` → `customers` insert → `loyalty_cards` insert, using the app's exact payloads (`useAuth.ts:270-298`) | F0, F9 | customer role=customer, `auth_user_id` set, 1 card 0/bronze | none (`send` isn't called; see E) |
| R2 | Existing login; avatar upload; country change | API: password sign-in as C1; upload `avatars/<uid>/a.jpg`; `update customers set country`, `avatar_url` | C1, F1 | succeed | none |
| R3 | Woo webhook `processing` → points; `refunded` → reversal | API: POST a **synthetic signed payload** (HMAC with the **staging** `WC_WEBHOOK_SECRET`) for C1, order `990000002` | C1, F0 | +100 pts / 1 pair, then reversed | none: Twilio/Resend secrets unset (the code skips them); C1 has no Expo-format token |
| R4 | `link-orders` legitimate | API as C1 | C1, F6 | orphan `990000101` credited once | none |
| R5 | `my-orders` legitimate | API as C1 | C1 | **Partial:** only up to customer resolution (the Woo call fails by design) | Woo is **not** contacted (`.invalid`) |
| R6 | Seller: channel → PIN → cart → QR sale / code sale | **Manual**, dev build pointed at staging, S1's own session; plus an API replay of the `sale.tsx` calls | S1, F2, F4, C1 card QR | `sold` +1, sale row, QR points +100 to C1 (deployed `claim-sale`) | the app reads the **public Woo Store API** (read-only GET catalog) |
| R7 | Seller stock +/- → ICR → admin approves | API: S1 inserts an ICR; M1 calls `inventory-approve` | S1, M1, F4, F7 | ICR approved; stock changed | none (`notify-approval-pending` not deployed; the app call fails silently) |
| R8 | Admin: channel/staff create, direct stock edit, Today/reports queries, broadcast, points search/adjust | API as M1 (+ manual screens) | M1, F2–F8 | all succeed as before | broadcast: F8's fake token is filtered, 0 sent, **no Expo call**. `import-woo` is **excluded** (see E) |
| R9 | Customer tracking: own unclaimed sales | API as C1 | C1, F5 | `STGA01` visible | none |
| R10 | Customer claims code (`claim-sale`) | API as C1 with `STGA01` | C1, F5, F0 | +100 pts, sale claimed | none |
| R11 | `delete-account` on own account | API as C2 (no spoof) | C2 | C2 data and auth user deleted; C1 intact | none |
| R12 | Service-role callers | API with the staging service key: `rpc fx_add_points`, `rpc award_birthday_points` | C1 | both allowed | none. `birthday-push` / `loyalty-credit` **not deployed** (see D) |
| R13 | Wishlist add/remove; push-token register | API as C1: `wishlists` insert/delete; `push_tokens` insert (`StagingFakeToken-C1`) | C1 | succeed via the `*self*` policies | none. Manual app use on a real phone would register a **real** device token (see E) |

---

## D. Functions, secrets, buckets

### D.1 Edge Functions to deploy to staging (**exact deployed-production versions**, from the S0.1a download; not repo versions where they differ)

| Function | Needed by | Deployed == repo? | Source to deploy |
|---|---|---|---|
| `whatsapp-otp` | T19, T27, R1 | identical | repo (= deployed v50) |
| `delete-account` | T17, R11 | identical | repo (= v9) |
| `link-orders` | T18, T22, R4 | identical | repo (= v9) |
| `my-orders` | T18, R5 | identical | repo (= v6) |
| `admin-points` | T25, R8 | identical | repo (= v5) |
| `admin-broadcast-push` | T25, R8 | identical | repo (= v1) |
| `inventory-approve` | T25, R7 | identical | repo (= v1) |
| `woocommerce-webhook` | R3 | identical | repo (= v45), deployed `--no-verify-jwt` like production |
| `claim-sale` | R6, R10 | **differs** | the **deployed v14 source** (no referral bonus), from the S0.1a download, not the repo |

Each is deployed with `supabase functions deploy <fn> --project-ref faltxpkaicwpnlqaxrdu` (explicit staging ref; never the linked default). verify_jwt matches production per function.

**Not deployed:** `woocommerce-proxy`, `backfill-orders`, `hilo-chat`, `escalate-to-staff`, `virtual-tryon*`, `send-push`, `birthday-push`, `loyalty-credit`, `notify-approval-pending`, `calculate-*`. They aren't needed for T1–T27/R1–R13, and several contact real external systems.

### D.2 Staging secrets (all newly generated for staging; nothing copied from production)

| Secret | Value source | Why |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY` | auto-provided by the staging platform | functions |
| `OTP_SALT` | `openssl rand -hex 32` (staging-only) | derived passwords for fixture users (M1, S1, C1–C3, R1) |
| `WC_WEBHOOK_SECRET` | `openssl rand -hex 32` (staging-only) | R3 signed synthetic payloads |
| `WC_URL` | `https://woo.staging.invalid/wp-json/wc/v3` | guarantees `my-orders` can never reach a real store |
| `WC_CONSUMER_KEY` / `WC_CONSUMER_SECRET` | literal `staging-not-a-key` | placeholders; unusable |
| `REVIEW_DEMO_PHONE` | `+15550100090` (synthetic) | see D.3 |
| **Deliberately unset:** `TWILIO_*`, `RESEND_API_KEY`, `FUXIA_CREDIT_SECRET`, `SUPPORT_STAFF_WHATSAPP`, `REPLICATE_API_TOKEN`, `FITROOM_API_KEY`, `REVIEW_BYPASS_PHONE`, `REVIEW_BYPASS_CODE` | — | no real messaging or paid APIs. The bypass phone/code stay at their **code defaults**, mirroring production |

Local test credentials: the staging publishable key and a **newly rotated** staging secret key. The one pasted earlier in chat must be revoked first. The owner adds them to `~/.fuxia-staging.env` with the same hidden-input method (`STAGING_ANON_KEY`, `STAGING_SERVICE_KEY`). Never printed, never committed.

### D.3 Review-bypass fixture note
Production's code default `REVIEW_DEMO_PHONE` is a **real phone number**. To avoid creating any identity derived from a real number, staging sets only `REVIEW_DEMO_PHONE=+15550100090`. The bypass **phone and code** stay at the code defaults (`+525555555555` / `555555`), exactly as in production, so T19 tests the real exposure. The difference (the demo target) is recorded in the report.

### D.4 Buckets
`avatars` (public) and `product-images` (public), created by the seed (F1). No objects are copied from production.

---

## E. Tests that can't be (fully) reproduced safely in staging

| Item | Limitation | Handling |
|---|---|---|
| R5 `my-orders` success path | needs a real Woo store | **Partial:** resolution only; the Woo success path stays covered by production smoke after A7 (read-only for the owner's own account) |
| R8 `import-woo` | needs `woocommerce-proxy` with real Woo credentials | **Excluded** in staging; the admin screen is checked manually in production smoke |
| R1 real SMS/WhatsApp delivery | would contact Twilio and real phones | **Excluded.** The OTP row is seeded directly; only `verify` is exercised |
| Public email sign-up with confirmation mail | would send email | E1 is created confirmed through the admin API. Same session semantics; mail delivery not tested |
| Q17 (derived-email squatting) | outside S0.0A | not tested (tracked for S0.0B-B9) |
| App-UI flows (R2, R6–R9, R13 on a device) | need a dev build pointed at staging; manual | done manually by the owner/tester; API-level equivalents run automatically |

### E.1 Tests that could touch real-world systems even from staging (and the mitigation)

| Path | Real system | Mitigation |
|---|---|---|
| `whatsapp-otp` `send` | **Twilio → SMS/WhatsApp to real phones** | never called by the probe; Twilio secrets unset in staging (the call would fail) |
| `woocommerce-webhook` welcome (first purchase) | Twilio WhatsApp + Resend email | secrets unset, so the code returns early |
| `woocommerce-webhook` / `birthday-push` push | Expo push service | `birthday-push` not deployed; webhook test customers have no Expo-format tokens |
| `admin-broadcast-push` | Expo push service | only `StagingFakeToken-*` tokens exist and are filtered by prefix, so there's **no Expo call** |
| `my-orders`, `woocommerce-proxy`, `backfill-orders`, `import-woo` | **real WooCommerce store** | `WC_URL` = `.invalid`; proxy/backfill not deployed; import excluded |
| App dev build pointed at staging | reads the **public Woo Store API** of fuxiaballerinas.com (catalog GETs) | read-only public data; accepted, or skip catalog screens |
| Manual app use on a real phone | registers a **real device push token** in staging | only the tester's own device; push functions that could use it (`birthday-push`, `send-push`) aren't deployed; the webhook R3 test customer is C1 (no real token). If a tester registers a real token, delete it after the session |
| `escalate-to-staff`, `hilo-chat`, `virtual-tryon*` | Twilio to staff phones / Railway / paid APIs | not deployed |

---

## F. Setup and reset procedure

**Prerequisites (owner):**
1. Revoke the staging secret key that was pasted in chat, and create a new one.
2. Add `STAGING_ANON_KEY` and `STAGING_SERVICE_KEY` to `~/.fuxia-staging.env` via hidden input.
3. Approve this manifest.

**Setup (after approval), in order, staging only, each step guarded against the production ref:**
1. Set staging secrets (D.2) with `supabase secrets set … --project-ref faltxpkaicwpnlqaxrdu`.
2. Deploy the 9 functions (D.1) with `--project-ref faltxpkaicwpnlqaxrdu`; `claim-sale` from the deployed-v14 source.
3. `lab_auth.ts create`: auth users M1, S1, C1, C2, C3, E1.
4. `psql "$STAGING_DB_URL" -f supabase/staging/lab_seed.sql`: F0–F9, linking the customers to the auth-user ids.
5. Verify: fixture counts, and that the catalog matches the baseline (no A-unit present: `supabase migration list --db-url` shows only the 2 baseline versions).

**Run BEFORE:** `probe.ts --phase before`. Output goes to `docs/fuxia360/audit/S0_0A_TEST_REPORT.md` (results, including every reproduced vulnerability), with reseeds between destructive groups.

**Reset:**
- **Soft reset** (between groups/runs): `lab_seed.sql` in reset mode deletes fixture rows by fixed UUID, `STG` codes and the `99…` Woo id ranges, then re-inserts; `lab_auth.ts reset` deletes and recreates the 6 auth users. Only fixture-tagged rows are touched.
- **Hard reset** (if staging drifts): recreate the staging project and replay the two baseline migrations (the proven rehearsal path), then setup steps 1–4.
- **Lab teardown:** `lab_auth.ts delete`, seed in delete-only mode, `supabase functions delete <fn> --project-ref faltxpkaicwpnlqaxrdu` for the 9 functions, unset the staging secrets.

**Nothing in this procedure uses `--linked`, touches production, applies A1–A8, runs `migration repair`, or begins S0.0B.**
