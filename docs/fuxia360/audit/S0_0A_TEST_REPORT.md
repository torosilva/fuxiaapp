# S0.0A — Staging Security Lab: BEFORE (baseline) Report

**Date:** 2026-09-24 · **Target:** STAGING only (`faltxpkaicwpnlqaxrdu`) · **A1–A8:** NOT applied · **Production:** untouched.
**Raw evidence:** `s00a_results/before_baseline.json`, `s00a_results/regression_baseline.json` (synthetic data only; no tokens or keys).
**Tooling:** `scripts/s00a/{run.sh, lib.mjs, lab.mjs, probe.mjs}`, `supabase/staging/{lab_seed.sql, lab_reset.sql}`.

## 1. Lab setup

| Item | Result |
|---|---|
| Staging secrets | `OTP_SALT`, `WC_WEBHOOK_SECRET` (both newly generated for staging), `WC_URL=https://woo.staging.invalid/…`, placeholder Woo keys, `REVIEW_DEMO_PHONE=+15550100090`. Twilio / Resend / paid-API secrets **unset**. Nothing copied from production |
| Functions | The 9 approved functions were deployed with `--project-ref faltxpkaicwpnlqaxrdu`. **Source parity was verified** by downloading them back from staging and running `cmp` against the S0.1a production download: all 9 are byte-identical, `claim-sale` = production v14. `verify_jwt` matches production (webhook `false`, the rest `true`) |
| Buckets | `avatars`, `product-images` (public) |
| Fixtures | 6 synthetic auth users (M1, S1, C1, C2, C3, E1) + all seeded fixtures. `lab.mjs verify` integrity **OK** on 17 counts; `non_lab_customers = 0`; migration history is still only the 2 baseline versions |
| Setup deviations (documented) | (a) The first staging `OTP_SALT` (64 hex chars) made `fuxia_{phone}_{salt}` exceed Supabase Auth's 72-character password limit, so it was regenerated at 32 hex chars. Production's salt is evidently short enough, because production sign-ups work. (b) C1 was given the email `c1@staging.invalid`, so the R3 webhook test can match C1 even though fictional 555 numbers may fail phone validation. (c) The lab uses the staging project's **legacy JWT keys** (anon / service_role), read from the staging project via the logged-in CLI and stored only in `~/.fuxia-staging.env` (mode 600). Production's app uses the legacy anon JWT, and the `verify_jwt` functions only accept JWTs |

**Open hygiene item:** the staging **new-style secret key** that was pasted into the chat is **still active** (same key id and creation time as the project). The lab doesn't use it, but anyone holding it has full access to staging. **Revoke it before the AFTER runs**, so the lab evidence can't be tampered with.

## 2. T1–T27 BEFORE matrix

| T | Actor | Operation | Expected (baseline) | Actual | Verdict |
|---|---|---|---|---|---|
| T1 | anon; C1 | `rpc fx_add_points(C1.card, 1000)` | succeeds; +1000 each | anon HTTP 200: 100→1100; C1 HTTP 200: →2100 | **PASS (reproduced)** |
| T2 | catalog | EXECUTE on 6 internal functions for anon/authenticated | true | true for all 6 × 2 roles | **PASS (reproduced)** |
| T3 | catalog | default ACL for new functions | anon/authenticated=X | `anon=X`, `authenticated=X` | **PASS (reproduced)** |
| T4 | anon | `select name,pin from staff` | PINs | 2 rows, PINs `1111,2222` | **PASS (reproduced)** |
| T5 | anon | `update channel_inventory set price=1` | 1 row | 1 row; price now 1 | **PASS (reproduced)** |
| T6 | anon | insert `offline_sales` | inserted | HTTP 201 | **PASS (reproduced)** |
| T7 | anon | read `offline_sales.customer_phone` | C1's phone | C1's phone returned | **PASS (reproduced)** |
| T8 | anon | read + insert ICR (with S1's staff id) | allowed | read 1 row; insert 201 | **PASS (reproduced)** |
| T9 | C1 | `update customers set role='admin'` (self) | role admin | role now `admin` | **PASS (reproduced)** |
| T10 | E1 (email-only) | insert own `customers` row with role admin | inserted | 201; **then `admin-points search` HTTP 200, returning 6 customers' contact data** | **PASS (reproduced)** |
| T11 | C1 | change own phone | changed | phone now `+15550100097` | **PASS (reproduced)** |
| T12 | C3 | insert card with 100000 pts | inserted, gold | 201, tier gold | **PASS (reproduced)** |
| T13 | C1 | second card | 2 cards | 201; 2 cards | **PASS (reproduced)** |
| T14 | C1 | read staff PINs | PINs | `1111,2222` | **PASS (reproduced)** |
| T15 | C1 + metadata phone of M1 | update staff / insert channel / delete sale | control blocked, spoof succeeds | control blocked; **spoof also blocked** | **NOT REPRODUCED** (see §4) |
| T16 | C1 + metadata phone of M1 | read/insert M1 push tokens | allowed | read 0 rows; insert 403 | **NOT REPRODUCED** (see §4) |
| T17 | C2 + metadata phone of C1 | `delete-account` | C1 customer + card + tx deleted | HTTP 200. **C1's card, transactions and purchase items deleted.** C1's customer row survived (FK) | **NOT REPRODUCED as specified: partial impact confirmed** (see §4) |
| T18 | E1 + metadata phone of C1 | `link-orders`; `my-orders` | acts on C1; my-orders 5xx | link-orders credited C1's orphan (C1 → 200 pts); my-orders HTTP 500 (resolved C1; Woo unreachable) | **PASS (reproduced)** |
| T19 | anon | `whatsapp-otp` verify `+525555555555`/`555555` (code defaults; **fictional staging demo target**) | session without OTP | HTTP 200, session for `15550100090@fuxia.app` | **PASS (reproduced)** |
| T20 | — | bypass only when enabled | post-A8 | flag doesn't exist in the baseline | **NOT APPLICABLE BEFORE** |
| T21 | E1 | = T10 (repeat run) | inserted as admin | 201; admin-points 200, 6 customers | **PASS (reproduced)** |
| T22 | E1 | squat U1's phone, add card, `link-orders` | U1's orphan credited to E1 | 201; card 201; linked 1, **E1 card = 100 pts from U1's order** | **PASS (reproduced)** |
| T23 | E1 | read staff PINs | PINs | `1111,2222` | **PASS (reproduced)** |
| T24 | E1 | read + insert ICR | allowed | read 1; insert 201 | **PASS (reproduced)** |
| T25 | E1 (no customer row) | admin-points / broadcast / inventory-approve | 403 | 403 / 403 / 403 | **CONTROL PASS** |
| T26 | E1 + metadata phone of M1 | T15/T16 ops, then `delete-account` | all succeed | RLS ops **blocked**; **`delete-account` deleted admin M1's customer record** (M1_left = 0) | **NOT REPRODUCED as specified: `delete-account` part reproduced** (see §4) |
| T27 | — | `app_metadata.verified_phone` stamping | post-A8 | baseline observation (R1): claim absent (`null`) | **NOT APPLICABLE BEFORE** |

Totals: 21 PASS (reproduced) · 4 NOT REPRODUCED (2 of them with partial impact confirmed) · 1 CONTROL PASS · 2 NOT APPLICABLE BEFORE.

## 3. Production P0s reproduced in staging

| P0 | Reproduced by |
|---|---|
| **P0-1** self role escalation (existing customer and email-only stranger) | T9, T10, T21. T10/T21 also show the chain to **customer PII via `admin-points`** |
| **P0-1b** arbitrary initial balance / duplicate card | T12, T13 |
| **P0-3** PINs readable by anon, customers and email-only strangers | T4, T14, T23 |
| **P0-4** anonymous inventory/price writes and sale inserts | T5, T6 |
| **P0-5** anonymous read of sale phones and ICRs | T7, T8 |
| **P0-6.3** review login without OTP (the production default code) | T19 |
| **P0-9** public `fx_add_points` | T1, T2 |
| **P0-11** default privileges | T3 |
| **P0-10 (function part)** `delete-account` / `link-orders` / `my-orders` trust `user_metadata.phone` | T17 (partial), T18, T26 (delete-account part) |
| **G5 phone squatting** (new A3 insert rule) | T22 |

## 4. NOT REPRODUCED: reasons (investigated; tests not changed)

| Test | Reason (verified on staging with read-only catalog checks + probes) | Consequence for the audit |
|---|---|---|
| **T15, T16, T26 (RLS part)** | The spoof itself worked: the JWT carried `user_metadata.phone = +15550100001` (M1). But the `admins_*` and `Users manage their own push tokens` policies test the phone with an `EXISTS (SELECT … FROM customers WHERE phone = <jwt phone> AND role …)` subquery. That subquery runs **as the caller, under `customers` RLS (self-only)**, so the attacker can't see M1's row (the probe's own query returned 0 rows) and the policy evaluates false | **Correction to LIVE_RECONCILIATION P0-10:** the **RLS part is not exploitable** as deployed. The policies are neutralized by `customers` RLS. They are still a fragile latent risk: any future `customers` read policy for staff/admin, or a SECURITY DEFINER helper, would activate them. **A6 is still recommended** as hygiene, and because of the R13 finding below. The **function part of P0-10 is confirmed** (T17, T18, T26) and stays P0 → A7 |
| **T17** | `delete-account` (service role) found C1 by the spoofed phone and **deleted C1's loyalty card, transactions and purchase items**. The final `customers` delete failed silently because C1 is referenced by a claimed store sale (`offline_sales.customer_id`, FK `NO ACTION`), so the customer row survived | The harm is real (**the victim's loyalty history is destroyed**). A victim without claimed store sales is deleted completely (as T26 shows for M1). A7 unchanged |
| **T26** | RLS part: same cause as T15. **`delete-account` part reproduced: the admin customer M1 was deleted by an email-only stranger** | Raises the severity of the P0-10 function part: **an email-only stranger can delete the admin's account data** |

## 5. R1–R13 baseline

| R | Result | Notes |
|---|---|---|
| R1 | **PASS** | OTP row seeded (no SMS or WhatsApp sent); verify → session → customer + bronze card. Baseline: JWT has no `verified_phone` claim (T27) |
| R2 | **PASS (API) + MANUAL REQUIRED** | avatar upload, `avatar_url`, `country` |
| R3 | **PASS** | synthetic signed webhook: +100 then reversed (no external contact: Twilio/Resend unset; no Expo tokens) |
| R4 | **PASS** | orphan credited once (idempotent) |
| R5 | **PARTIAL** | HTTP 500 at the Woo call (`.invalid`); customer resolution succeeded; the success path isn't testable in staging |
| R6 | **PASS (API) + MANUAL REQUIRED** | sold +1, +100 pts. **Store `purchase_items_saved = 0`** (P1-14 confirmed) |
| R7 | **PASS (API) + MANUAL REQUIRED** | ICR approved; stock 7 |
| R8 | **PASS (API) + MANUAL REQUIRED; import-woo UNAVAILABLE IN STAGING** | admin writes OK. **`customers_visible = 1`** for the admin (P1-18 confirmed). **Points adjust left `audit_rows = 0`** (P1-3 confirmed). Broadcast: 0 sent (fake tokens filtered; no Expo call) |
| R9 | **PASS (API) + MANUAL REQUIRED** | own unclaimed sale visible |
| R10 | **PASS** | +100 pts; store `purchase_items_saved = 0` (P1-14) |
| R11 | **PASS** | own deletion; C1 intact |
| R12 | **PASS** | service-role `fx_add_points` and `award_birthday_points` callable |
| R13 | **FAIL** (wishlist add/remove) / PASS (push token) | see §6-1 |

## 6. Unexpected behavior discovered

1. **Wishlist is broken by an RLS error (likely in production too).** Adding or removing a wishlist item fails with `42501 permission denied` for `auth.users`. The dead policy `users own their wishlist` subqueries `auth.users`; `authenticated` has no SELECT on it (verified: `has_table_privilege = false`); and Postgres evaluates every permissive policy, so the whole request errors. Production has the same two policies (`live/schema.sql:1439-1448`), so **wishlist writes very likely fail in production today**. A6 (dropping the dead policy) would restore them. **This is a behavior change (bug fix) that needs to be acknowledged when A6 is approved.**
2. **P0-10 RLS part is not exploitable** (§4), a correction to the S0.1a verdict.
3. **`delete-account` can be triggered by an email-only stranger against the admin** (T26), which is more severe than recorded before.
4. **`delete-account` partial deletion:** a customer with a claimed store sale keeps their profile row but loses their card and history (FK `NO ACTION` + ignored error). Data-integrity issue for S0.5 / account-deletion hardening.
5. Staging-only setup lesson: the `OTP_SALT` length is bounded by the 72-character password limit.

## 7. Readiness for A1
**Staging is ready for A1:** every A1 target (T1, T2, T3) reproduced on the unmodified baseline, the probe is repeatable (reseed per group, integrity-checked), and the regression baseline is recorded. Before running A1 on staging:
- revoke the leaked staging secret key (§1);
- A1 still needs its own approval and its migration file in `supabase/pending/s00a/`. Nothing has been applied.

---

# A1 — Staging validation (2026-09-24)

**Scope:** A1 only (P0-9, P0-11), approved for local implementation and **staging only**. Production untouched; A2+ not implemented.
**Migration:** `supabase/migrations/20260925000100_s00a_a1_revoke_public_rpc.sql` · **Rollback:** `supabase/rollbacks/20260925000100_s00a_a1_revoke_public_rpc.down.sql`
**Evidence:** `s00a_results/after_a1_security.json`, `s00a_results/after_a1_regression.json`

| Step | Result |
|---|---|
| Local review | Signatures match the baseline; executed on staging **inside `BEGIN … ROLLBACK`**: anon lost `fx_add_points`, service_role kept it, `my_role()` stayed executable. After the rollback the state was back to baseline |
| Staging dry-run | Only `20260925000100_s00a_a1_revoke_public_rpc.sql` pending |
| Staging apply | `supabase db push --db-url "$STAGING_DB_URL" --yes`, exit 0 |
| Staging history | `20260924000000`, `20260924000001`, `20260925000100` (Local = Remote) |
| Fixtures | Reseeded; integrity OK. The lab check now expects exactly the versions in `supabase/migrations/` (the old hardcoded 2-version expectation made the first post-A1 reseed report a false failure) |

## T1–T3 BEFORE vs AFTER

| T | BEFORE | AFTER | Status |
|---|---|---|---|
| T1 | anon and C1 `rpc fx_add_points` → HTTP 200, +1000 each | anon **HTTP 401**, C1 **HTTP 403** `42501 permission denied for function fx_add_points`; balance 100→100 | **CLOSED** |
| T2 | EXECUTE true for anon/authenticated on 6 internal functions | PUBLIC/anon/authenticated **false**, service_role **true**, on all 6 | **CLOSED** |
| T3 | default ACL `public`: anon=X, authenticated=X (+ implicit PUBLIC) | `(global):{postgres=X}` (PUBLIC removed); `public:{postgres=X, service_role=X}` | **CLOSED** |

## Catalog verification (read-only; the future-function check runs in a rolled-back transaction)
- **RLS helpers preserved:** `my_customer_id()`, `my_phone()`, `my_role()` are still executable by PUBLIC/anon/authenticated/service_role.
- **Future functions hardened:** a function created in `public` (in a transaction that was rolled back) has PUBLIC/anon/authenticated **false** and service_role **true**.
- **No function added or dropped:** 13 public functions, same as the baseline.
- **Out of scope, noted:** the `storage` schema's default ACL still grants anon/authenticated EXECUTE on new functions created by `postgres` there. That's platform-managed; A1 is scoped to `public`.

## R1–R13 BEFORE vs AFTER
All 13 results are **identical to the BEFORE baseline** (same verdict and same detail): R1, R3, R4, R10, R11, R12 PASS; R2, R6, R7, R8, R9 PASS (API) + MANUAL REQUIRED; R5 PARTIAL; R13 FAIL (the pre-existing wishlist RLS error; not caused by A1 and not fixed by A1). R12 confirms the service-role callers still work (`fx_add_points`, `award_birthday_points`). **New regressions: 0.**
