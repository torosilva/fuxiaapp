# Sprint 0 — Hardening & Canonical Baseline: Implementation Plan

> **Status: ARCHITECTURE APPROVED IN PRINCIPLE — IMPLEMENTATION NOT STARTED.**
> The audit has been reviewed. The Sprint 0 architecture is approved in principle, with the business decisions recorded in §0 below. **No code, migration, function or config has been changed.** Implementation must not begin until an explicit go-ahead is given. Each unit still needs its own approval before it is implemented (CLAUDE.md; 10_SPRINTS "Working rhythm"). Units blocked by open questions are marked **⛔ BLOCKED (Qn)**.

## 0. Decision log

### Decided

| # | Decision | Effect on this plan |
|---|---|---|
| Q1 | **CLOSED.** Sellers use their **own personal mobile phones**. Each seller must have an **individual identity and session**. **Shared store identities are not acceptable.** Every staff action must be attributable to the individual seller **and** the location. Keep the current seller UX as much as possible (channel/location → seller authentication/PIN → cart → sale), but the identity and authorization underneath must be individual and server-authoritative. | S0.2 is redesigned around individual identity: each `staff` row is linked 1:1 to the seller's own Supabase Auth user, and the PIN is verified for **that** seller. Sessions are bound to seller + auth user + channel. Shared `role='staff'` accounts lose operational access at cutover. The old S0.0-d ICR part is now handled by S0.0A-A2 (anonymous access removed); the remaining narrowing is **sequenced** into S0.2c. S0.3 derives `staff_id` only from the individual session. |
| Q2 | Staff PINs will be hashed. **Existing PINs will never be shown again.** Admins can reset them. PINs stay **4 digits** for now, protected by rate limiting, lockout and an audit trail. | S0.2: `pin_hash`, reset-only admin UI, lockout plus `staff_auth_events`. The PIN display in `admin/staff/*` is removed in R1. |
| Q3 | **CLOSED.** Sellers may **not** discount or override prices. The **authoritative selling price comes from the system.** Centrally approved promotions may be supported separately in the future; seller-entered prices are not allowed. | S0.3 go-live is no longer blocked. The sale request carries **no price fields**: the price comes only from the system (today `channel_inventory.price`), and a request that includes a price is rejected. There is no discount path and there are **no discount permission thresholds** (none invented). Promotions are out of Sprint 0 and will be a separate, centrally administered capability. |
| Q4 | **Loyalty economics do not change in Sprint 0.** Loyalty logic is centralized so that product-category rules can be added later. **Tiers stay permanent**, not annual. The annual-tier copy (`payments/index.tsx:75`) gets corrected later, outside Sprint 0. The legacy 501/1201 `calculate-tier` can be retired once it's confirmed to have no callers. Referral should eventually work across all channels, but **referral behavior does not change in Sprint 0**. | S0.5: one `loyalty_apply` path, same rules as today (100 points × total line quantity, 300/900 from `tier_config`, in-store-only first-purchase referral bonus). The pairs calculation sits behind one function so category rules can be added later without touching callers. `calculate-tier` / `calculate-points` are retired only after a caller check (repo grep and function invocation logs). |
| Q5 | **Both loyalty integrity fixes are approved:** (a) refunded, cancelled or failed orphan orders must not be credited later by `link-orders`, and the webhook reversal branch must record their status; (b) `admin-points` must write its audit row atomically with the balance change. | S0.5: these are no longer [RULE]-pending. |
| Q6 | Mario or the project owner may run a **schema-only** production dump. **No production customer data may be exported.** | S0.1a is unblocked, with owner-run, schema-only scope. The data-quality queries in SCHEMA_AUDIT §7 must return **aggregate counts only** (no rows containing PII). See the revised S0.1a. |
| Q9 | A **staging environment** will be created or used before any destructive or cutover testing of S0.2/S0.3. | Staging is a hard prerequisite for S0.2/S0.3 testing and for every cutover unit. |
| Q10 | Use an **additive compatibility window followed by a separate cutover**. **The length of the adoption window has not been decided** and must not be invented. | Cutover units S0.2c/S0.3c (and the proxy/claim cutovers) stay separate and are triggered by a later explicit decision, not a date. |
| Q11 | **Yes.** Sprint 0 starts recording a **forward-compatible inventory audit event** for new sales, designed to migrate into the Sprint 2 inventory ledger. | S0.3: the `inventory_events` write is **required** (it was optional). Its design is in S0.3. |
| Q15 | **Allow the `manual` loyalty channel.** Every manual adjustment must have an **immutable audit record**: actor, customer/card, points delta, reason and timestamp. **Do NOT enable `popup`** during S0.0: it currently fails, so enabling it would change live economics. It will be reviewed separately as a promotion. | S0.5 (not S0.0): extend `transactions_channel_check` with `manual` only; `admin-points` goes through `loyalty_apply` with an append-only audit record (no UPDATE/DELETE grants). The popup path (`loyalty-credit`, `trg_aplicar_creditos_pendientes`) is left exactly as-is in S0.0A/B. |
| Q16 | **Tiers are permanent.** The annual Gold→Silver downgrade is **not** intended. First check, count-only, whether it's scheduled or has run. If it's scheduled, propose disabling the schedule during hardening. **Do not delete** historical functions or data without separate approval. | Gate G6. Conditional unit S0.0B-7 (unschedule only; the job definition is kept for rollback). `run_annual_tier_review()` stays, with public EXECUTE revoked in S0.0A-A1 (an access change, not a behavior change). |
| P | **Principle:** security containment is not mixed with loyalty economics changes. | S0.0 is split into **S0.0A** (emergency access containment) and **S0.0B** (function and integration hardening). Loyalty behavior changes live only in S0.5 or in separately approved units. |
| Q13 | The old Woo REST key must be **verified and revoked** before P1-9 is closed. | P1-9 stays open until someone confirms in WordPress (REST API keys list) that the historical key is gone. This has been added to the S0.4 exit criteria. |

### Roadmap reaffirmation

| Topic | Decision |
|---|---|
| **Production Tracking Lite** | Stays a **core** Fuxia 360 domain on the future roadmap (`00_MASTER_SPEC.md` §5.2, `02_TARGET_ARCHITECTURE.md` §2.1, `03_DATA_MODEL.md` §5.2, `10_SPRINTS.md` Phase 5D). **Not implemented in Sprint 0.** |

### Still open: operational verification items (Sprint 0)

| # | Item | Affects |
|---|---|---|
| **Q7** | `loyalty-credit` **is deployed** (S0.1a). Does WordPress call it server-side or from browser JS? | Hardening `loyalty-credit`, and migrating that caller in S0.5. Doesn't block S0.0A. |
| **Q8** | `backfill-orders` **is deployed** (S0.1a). Is it still needed? | S0.0B-B1. Requiring the service-role key is safe either way; only the undeploy decision waits. |

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
9. **Authorization comes only from verified, server-controlled identity (G5).** It must never come from `user_metadata`, phone metadata, or merely `auth.role() = 'authenticated'`, because email sign-up is open. Acceptable sources:
   - `customers.auth_user_id` → `customers.role`, where role changes are service-role only (A3);
   - `staff` linked to an auth user (S0.2);
   - `app_metadata` claims, which only the service role can write (A8).

## Recommended sequence

```
S0.1a Live schema snapshot (read-only)          ← prerequisite for everything
  │
S0.0A Emergency access containment (A0–A8)       ← P0-1,1b,3(anon/customer),4(anon),5(anon),6.3,9,10,11
  │
S0.0B Function & integration hardening (B1–B8)   ← P0-2(interim),5(auth),7,8; P1-16; Q16 if scheduled
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

## S0.0 — Containment, split into S0.0A and S0.0B

> **Principle (decided 2026-09-24): security containment must not be mixed with loyalty economics changes.** S0.0A and S0.0B change **who can do what**. They never change how many points anyone earns. The Q15 `manual` channel, the Q16 schedule, and every other loyalty-behavior change live in S0.5 or in their own approved unit.
>
> This replaces the earlier S0.0-a…g list, which was written before S0.1a. The live findings (P0-9/10/11, the anonymous policies) changed the priorities.

### Gates before S0.0A starts (count-only, owner-run; no PII)

| Gate | Source | Status (authoritative, owner-supplied 2026-09-24; count-only) | Consequence |
|---|---|---|---|
| G1 | `LIVE_RECONCILIATION.md` §9 row | ✅ **PASSED** | — |
| G2 | admin/staff without an auth link | ✅ **PASSED:** `admin_without_auth_link = 0`, `staff_without_auth_link = 0` | A5/A6 lock nobody out |
| G3 | review/demo account role | ✅ **CLOSED:** `demo_is_admin = 1`, `demo_is_staff = 0`. **The public review login (`+525555555555` / `555555`) resolves to an ADMIN account** | P0-6.3 = **public admin login**, the most urgent single item. See A8 below |
| G4 | duplicate cards | ✅ **PASSED:** `customers_multi_card = 0` | A4b (unique index on `loyalty_cards.customer_id`) is **included**, with its own defensive precondition (it aborts if any duplicate exists at apply time) |
| G5 | Authentication → Sign In / Providers → Email | ✅ **CONFIRMED 2026-09-24:** *Enable email provider = ON* ("Allow email-based sign up and log in"). **Anyone can obtain an `authenticated` session with no phone and no customer row** | Security tests use an **email-signup stranger (`E1`)** as the baseline attacker. `auth.role() = 'authenticated'` proves nothing about phone ownership. The email provider configuration is **not** changed in S0.0A (only a separate finding could require it; see Q17) |
| G6 | `pg_cron` jobs | ✅ **CLOSED:** `cron_jobs = 0`, `cron_annual_review_active = 0`, `cron_birthday_active = 0`. No downgrade schedule exists; **tiers stay permanent** | S0.0B-B7 is **not needed** (removed). `run_annual_tier_review()` stays in place; A1 revokes public EXECUTE (access only) |
| G7 | staging project | ✅ **EXISTS** (confirmed by owner 2026-09-24). Connection string kept only in a local file outside the repo (`~/.fuxia-staging.env`, mode 600); never printed or committed | Staging rehearsal (A0 point 6) can start with the step-2 dry run |
| A0 | baseline registration mechanics | ✅ **COMPLETE 2026-09-24.** Staging rehearsal passed (public statement-identical, storage byte-identical). Production history registered: `20260924000000`, `20260924000001` only. `db push --linked --dry-run` = up to date. The production public schema is byte-identical to `live/schema.sql` after registration. No baseline SQL was executed in production. Record: `S0_0A_STAGING_REHEARSAL.md` | S0.0A units can now go through the standard migration path, each with its own approval |

**All gates for the staging rehearsal are met (G7 exists).** Production baseline registration (A0 step b) needs a separate authorization after a successful rehearsal.

> **~~G3 implication (proposal, not executed):~~** *Withdrawn 2026-09-24: no secret rotation as a security-through-secret-change. See "A8 — facts about the deployed bypass".*  the admin review login is live now. The smallest possible containment is a **secrets-only change with no deploy and no schema change**: set `REVIEW_BYPASS_CODE` to a long random value. The deployed code reads it (`whatsapp-otp/index.ts:18`), so `555555` stops working immediately. Rollback: unset the secret. It's a production configuration change and needs its own explicit approval. A8 then removes the defaults for good. Separately, whether the demo phone should keep `role='admin'` is a data/role decision needing its own approval (not in S0.0A).

---

## S0.0A — Emergency Access Containment (implementation plan; NOT implemented)

**Scope (only):**
- public RPC/function access;
- anonymous staff/PIN access;
- anonymous inventory/store-sale writes (and the anonymous reads of the same tables);
- self role escalation;
- arbitrary initial loyalty balances;
- authorization based on user-editable phone/profile data;
- account operations on verified identity only;
- review-login containment.

**Out of S0.0A:** everything in S0.0B, all loyalty economics (Q15 manual → S0.5; popup stays disabled), and PIN hashing and individual sessions (S0.2).

### A0 — Prerequisites (no production schema change)

| Item | Detail |
|---|---|
| Migration home | **Decided: Supabase migrations are the canonical deployment mechanism** (no manual SQL Editor apply or parallel apply log). Root `supabase/` (its `.temp` is linked to `tgzgiwfzddsghnxgkcqd`) holds `migrations/`. Prepared locally, not registered: `supabase/migrations/20260924000000_baseline_live_public_schema.sql` (byte-identical to `live/schema.sql`) and `supabase/migrations/20260924000001_baseline_live_storage_policies.sql` (the 4 live `storage.objects` policies). S0.0A units wait in `supabase/pending/s00a/`, which the CLI doesn't read, until each is approved. `supabase init` (local `config.toml`) is part of A0 execution. Edge Functions stay in `fuxia-native/supabase/functions/`. |
| Baseline registration | See **A0 — Baseline registration mechanics** below. Approved in principle; **production registration not authorized until the staging rehearsal succeeds**; the baseline files are never executed against production. |
| Rollback scripts | Supabase has no down-migrations. Each migration has a paired `supabase/rollbacks/<same-name>.down.sql`, applied by hand only if needed. |
| Staging | A new Supabase project (e.g. `fuxia-staging`), created by the owner (billing/ownership action). The baseline is applied there with `supabase db push --db-url "$STAGING_DB_URL"` (never `--linked`, which points to production). See A0 point 6. Staging gets its own secrets; no production secret or data is copied (Q6). |
| Function sources | A7/A8 touch `delete-account`, `my-orders`, `link-orders` and `whatsapp-otp`. S0.1a confirmed all four are **identical to the deployed versions**, so no sync is needed. (S0.0B must sync `claim-sale` and the others first.) |
| Backup | Before any production step: confirm that a backup or PITR point exists (Dashboard → Database → Backups) and record its timestamp. |

### A0 — Baseline registration mechanics (APPROVED IN PRINCIPLE 2026-09-24; production registration NOT yet authorized)

> **Status and rules (decided 2026-09-24):**
> - A0 is approved in principle, with the staging-rehearsal modification in point 6.
> - **Production registration (step b) is NOT authorized yet.** It gets authorized only after the baseline has **successfully reproduced the approved production schema on staging** (point 6, steps 1–8).
> - **The baseline SQL files are NEVER executed against production.** Production only ever receives the history registration in (b).
> - **The byte-identical public baseline is not modified pre-emptively.**
> - **G7 (staging project) is the only gate before the staging rehearsal.**

**1. Baseline versions / files (prepared locally, not registered)**

| Version | File | Content |
|---|---|---|
| `20260924000000` | `supabase/migrations/20260924000000_baseline_live_public_schema.sql` | Byte-identical to `docs/fuxia360/audit/live/schema.sql` (the `public` schema-only dump) |
| `20260924000001` | `supabase/migrations/20260924000001_baseline_live_storage_policies.sql` | The 4 live `storage.objects` policies (idempotent `DROP IF EXISTS` + `CREATE`); no platform tables, no bucket rows |

Two versions, because the storage policies live outside `public` and aren't in the public dump. Without them, a staging replay wouldn't reproduce production's avatar policies.

**2. Exact commands** (owner's own terminal, from the repo root; the password never enters this conversation)

```bash
cd /Users/bullsilva/Documents/GitHub/fuxiaapp
supabase init            # only if supabase/config.toml doesn't exist yet: local file creation, no remote effect
read -rs "SUPABASE_DB_PASSWORD?DB password: " && export SUPABASE_DB_PASSWORD

# (a) PRE-CHECK, read-only. Required result: both versions show as local-only, with no remote rows.
supabase migration list --linked

# (b) REGISTRATION. NOT YET AUTHORIZED: only after a successful staging rehearsal (point 6) AND
#     only if (a) shows no unexpected remote migration history.
supabase migration repair --status applied \
  20260924000000 20260924000001 --linked

# (c) POST-CHECKS, read-only
supabase migration list --linked
supabase db push --linked --dry-run      # must report that the remote database is up to date

unset SUPABASE_DB_PASSWORD
```

**Stop rule:** if (a) shows **any** existing remote version (a migration history nobody knows about), stop and report. Don't repair.

**3. What (b) writes to production**
- Only the CLI's migration-history metadata: the schema `supabase_migrations` and its table `schema_migrations`, created if absent (the repo has never used migrations, so they probably don't exist yet), plus **one row per version**: the version, the name taken from the filename, and history bookkeeping. Depending on the CLI version, that bookkeeping may include the file's SQL **as stored text**.
- **Nothing else:** no `public`, `auth` or `storage` object, no data row, no policy, no grant.
- Because the exact bookkeeping columns vary by CLI version, they're confirmed **read-only on staging** after the baseline push (point 6, step 4): `select * from supabase_migrations.schema_migrations;` and `\d supabase_migrations.schema_migrations`. `db push` records the same kind of history row that `repair --status applied` writes. **No repair reverted/applied rehearsal is run on staging.**

**4. It doesn't execute `schema.sql` or change application objects**
- `migration repair` only updates the history table (CLI: "Repair the migration history table"). It never runs migration contents. Contents run only through `db push`, `db reset` or `migration up`, and none of those is part of A0 for production.
- **Proof step, added to A0 (read-only):** after (b), re-run the schema-only dump (the same S0.1a command) and `diff` it against `docs/fuxia360/audit/live/schema.sql`. The only allowed difference is nothing at all: the history table is in schema `supabase_migrations`, not `public`, so the public dump must be **byte-identical**.

**5. Expected `supabase migration list --linked` immediately after**

```
   Local          | Remote         | Time (UTC)
  ----------------|----------------|---------------------
   20260924000000 | 20260924000000 | 2026-09-24 00:00:00
   20260924000001 | 20260924000001 | 2026-09-24 00:00:01
```

`supabase db push --linked --dry-run` should then report that the remote database is up to date. No S0.0A file shows up, because those files stay in `supabase/pending/s00a/` until each unit is approved.

**6. Staging rehearsal (canonical; replaces the earlier draft)**
- The root `supabase/` is **linked to production**, so for staging **never use `--linked`**. Every staging command passes `--db-url "$STAGING_DB_URL"`. The owner provides the connection string in their own terminal; it's never pasted into this conversation.
- **Canonical rehearsal steps:**
  1. **Confirm staging migration history is empty:** `supabase migration list --db-url "$STAGING_DB_URL"` must show no remote versions.
  2. **Dry run:** `supabase db push --db-url "$STAGING_DB_URL" --dry-run` must list exactly `20260924000000` and `20260924000001`, and nothing else.
  3. **Apply both baseline migrations to staging:** `supabase db push --db-url "$STAGING_DB_URL"`.
  4. **Inspect staging history read-only:** `supabase migration list --db-url "$STAGING_DB_URL"` (both versions Local = Remote). Then, read-only in the staging SQL editor: `select * from supabase_migrations.schema_migrations;` and `\d supabase_migrations.schema_migrations`, which document exactly which columns and values a history row contains.
  5. **Re-dump the staging public schema:** `supabase db dump --db-url "$STAGING_DB_URL" -f <scratch>/staging_public.sql` (schema-only).
  6. **Compare** it against the approved production snapshot `docs/fuxia360/audit/live/schema.sql` (`diff`).
  7. **Review every difference.** Classify each as platform/version-specific, environment-specific, or a real mismatch. Record all of them in `docs/fuxia360/audit/S0_0A_STAGING_REHEARSAL.md`.
  8. **Run the approved baseline and security validation.** Catalog checks (functions, grants, policies, triggers, RLS flags match the snapshot), then security tests T1–T27 in their **"before" (vulnerable) state**. This proves the staging environment faithfully reproduces production's exposure.
- **No `migration repair` reverted/applied rehearsal on staging** after the baseline has been pushed.
- **Staging configuration that is not schema** (separate checklist, all synthetic, done after step 3):
  - buckets `avatars` / `product-images`;
  - `tier_config` rows (0/300/900 from the repo migration);
  - synthetic actors E1, C1, C2, S1, M1 and synthetic channels and inventory;
  - staging-only secrets;
  - auth provider settings mirroring production (email provider ON, G5);
  - deploy of the **currently deployed** function versions with `--project-ref <staging-ref>`.
- **If the baseline replay fails (step 3):**
  1. **STOP.** Don't continue the rehearsal and don't retry with edits.
  2. Identify the **exact failing statement** (file, line in the baseline, error).
  3. Explain whether it's **platform-owned** (Supabase-managed object or privilege), **environment-specific** (e.g. an extension or setting that differs between projects), or a **real production dependency** (something production has that the baseline doesn't capture).
  4. Propose the **minimum reviewed adaptation** (for example, a separate, documented pre-step on staging, or a reviewed edit). It needs explicit approval.
  5. **Never silently remove or modify statements.** Any approved change to what gets replayed is recorded in the rehearsal report. It must never break the byte-identity between `20260924000000` and `live/schema.sql` without an explicit, recorded decision.
- **Exit of the rehearsal:** steps 1–8 pass (or every difference is explained and accepted). That's what unlocks the request to authorize production step (b).

**7. Can the full live baseline replay on an empty Supabase project?**

**Expected yes, with specific points that the staging rehearsal proves or disproves.** The file is the CLI's own schema-dump format, which is exactly what the CLI replays for `db push` / `db reset`.

| Item in the baseline | On a fresh Supabase project | Risk |
|---|---|---|
| `pgcrypto`, `uuid-ossp`, `pg_stat_statements` (schema `extensions`), `supabase_vault` (schema `vault`) | Pre-installed; `IF NOT EXISTS` makes these no-ops | Low |
| `CREATE EXTENSION pg_cron WITH SCHEMA pg_catalog` | Available on Supabase in this exact form | Low. If a permission error appears, enable pg_cron in Dashboard → Database → Extensions and rerun |
| FKs to `auth.users`; `auth.uid()`, `auth.jwt()`, `auth.role()` in policies | Present in every Supabase project | Low |
| `ALTER … OWNER TO postgres`, `COMMENT ON SCHEMA public`, `ALTER PUBLICATION supabase_realtime OWNER TO postgres` / `ADD TABLE loyalty_cards` | `postgres` already owns these on new projects, so they're effectively no-ops | Medium-low. This is the most likely place for a platform-version difference; watch it in the rehearsal |
| `ALTER DEFAULT PRIVILEGES FOR ROLE postgres …` and the permissive `GRANT ALL … TO anon/authenticated` | Applies | **Intended.** Staging must reproduce production's vulnerabilities so that T1–T20 "before" results are real |
| Storage policies (file 2) | `storage.objects` exists (platform) | Low |
| **Not in any baseline (configured separately):** bucket rows, `tier_config` rows, auth provider/OTP settings, Edge Functions and their secrets, vault secrets, cron jobs (none in prod, G6) | — | Handled by the staging checklist (6.7) |

If the replay fails on staging, the **failure protocol in point 6** applies (stop, identify, classify, propose the minimum reviewed adaptation, and never silently change statements). The baseline files are never executed against production, so a replay failure can't affect production.

**8. Recovery if the wrong version is marked applied**

All of these are history-only operations. None changes schema or data, and the backup/PITR point from A0 exists regardless.

| Situation | Detection | Recovery |
|---|---|---|
| Wrong/typo version registered (e.g. `20260924000010`) | Post-check (c) shows a remote version with no local file | `supabase migration repair --status reverted 20260924000010 --linked`, then register the correct version; re-run (c) |
| A real, unapplied migration (e.g. an S0.0A unit) mistakenly marked applied, so its protection is **not** in the DB but `push` would skip it | `migration list` shows it applied, but the unit's catalog checks (e.g. T2 `has_function_privilege`) still show it open | `repair --status reverted <v> --linked`, then `db push --linked --dry-run` (must list only `<v>`), then the approved `db push` |
| Baseline missing or reverted in production history | `db push --dry-run` lists `20260924000000` | **Stop. Never push.** A push would try to re-execute the whole baseline on production: most statements are no-ops, but its `GRANT ALL` lines would undo A1. Re-register with `repair --status applied 20260924000000 20260924000001 --linked` and re-run (c) |
| Pre-check (a) shows an unexpected existing history | Step (a) | Stop, don't repair, report the list. This needs a separate reconciliation decision |

**Standing rule for every future production migration:** `migration list --linked`, then `db push --linked --dry-run` (it must list **only** the approved unit), then `db push --linked`. Then run the unit's production-safe checks.

### A-units: exact files, change, rollback

All migrations are idempotent (`DROP POLICY IF EXISTS`, `CREATE OR REPLACE`), wrapped in a transaction, and contain **no data changes**.

#### A1 — Close public RPC / function execution (P0-9, P0-11)
> **Status 2026-09-24: ✅ STAGING-VALIDATED.** Migration `supabase/migrations/20260925000100_s00a_a1_revoke_public_rpc.sql`, rollback in `supabase/rollbacks/`. T1–T3 CLOSED on staging, RLS helpers preserved, 0 new regressions (see `S0_0A_TEST_REPORT.md` → A1). **Not applied to production**; production application needs its own approval. Correction to the original draft: removing PUBLIC's default EXECUTE for future functions needs the **global** `ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` (per-schema defaults can only add privileges), plus the `IN SCHEMA public` revoke for anon/authenticated.
- **File:** `supabase/pending/s00a/20260925000100_s00a_a1_revoke_public_rpc.sql`
- **Change:**
  - `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated` on `fx_add_points(uuid,integer)`, `award_birthday_points(uuid)`, `award_referral_points(uuid)`, `check_free_pair_reward(uuid,uuid)`, `run_annual_tier_review()` and `delete_expired_otps()`. `PUBLIC` is included because Postgres grants EXECUTE to PUBLIC by default and `pg_dump` doesn't show it.
  - Keep EXECUTE for `service_role` (used by `loyalty-credit`, `birthday-push`) and for the owner `postgres` (used inside the SECURITY DEFINER trigger `fx_aplicar_creditos_pendientes`).
  - `my_customer_id()`, `my_phone()` and `my_role()` **keep** EXECUTE for anon/authenticated, because RLS policies call them.
  - Trigger functions aren't callable through PostgREST and are left unchanged.
  - `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;` so future functions aren't exposed by default.
  - Table default privileges are **not** changed in A1: existing tables are unaffected, and every S0 migration will explicitly `REVOKE`/`GRANT` for any new table. Revisit in S0.1b.
- **App impact:** none. The app makes no `.rpc()` calls (repo grep). Callers are service-role only.
- **Rollback:** `supabase/rollbacks/20260925000100_s00a_a1_revoke_public_rpc.down.sql`. It re-grants EXECUTE to `PUBLIC, anon, authenticated` on the six functions and restores the default privileges. **The rollback re-opens P0-9**, so use it only on a proven regression.

#### A2 — Remove anonymous access to operational tables (P0-3 anon, P0-4 anon, P0-5 anon)
- **File:** `supabase/pending/s00a/20260925000200_s00a_a2_remove_anon_operational_access.sql`
- **Change:**
  - `DROP POLICY IF EXISTS` for `anon_read_active_staff`, `anon_update_inventory_sold`, `anon_insert_offline_sales`, `anon_read_offline_sales`, `anon_read_own_sales` and `anon_read_inventory` (all `schema.sql:1221-1245`), plus `anon_read_active_channels`.
  - Replace `icr read open` and `icr insert with valid staff or admin/staff role` with `TO authenticated` policies **requiring `my_role() IN ('admin','staff')`**, for both read and insert. The staff-id-only insert path is dropped.
    - **Why (G5):** an email-signup stranger is `authenticated`, so `TO authenticated` alone would still let them read all requests and insert fake ones with a harvested `staff.id`.
    - **Compatible:** requests are only created from seller/admin screens, which require role staff/admin, and G2 = 0.
    - Staff-session attribution comes in S0.2c.
  - Defense in depth: `REVOKE ALL ON staff, channel_inventory, offline_sales, inventory_change_requests, channels, support_tickets FROM anon;`.
- **Why this is compatible:** every screen that touches these tables is behind login (`vendedora/*`, `admin/*`, `inventory/bulk-add`, `tracking`), so those requests carry a user JWT (role `authenticated`) and none of the dropped policies applied to them. Anonymous flows (QR claim) go through Edge Functions with the service role.
- > **CORRECTION 2026-09-25 (Track C audit):** the compatibility claim above is **wrong for one entry point**. The
  > onboarding screen shows **"Soy vendedora" before login** (`fuxia-native/app/onboarding/index.tsx:80-86` → `/vendedora`),
  > which runs as **anon** and depends on exactly these policies. A2 is therefore **blocked by precheck P1** in
  > `docs/fuxia360/ops/A2_PRODUCTION_RUNBOOK.md`. The SQL file now exists in `supabase/pending/s00a/` (it did not before).
- **Rollback:** `...a2...down.sql` recreates the seven policies exactly as dumped, restores the two ICR policies without `TO`, and `GRANT ALL ... TO anon`.

#### A3 — Block self role escalation and self identity changes (P0-1; supports P0-10)
- **File:** `supabase/pending/s00a/20260925000300_s00a_a3_guard_customer_identity.sql`
- **Change:** a trigger function `public.customers_guard_identity()` (SECURITY INVOKER; `REVOKE EXECUTE FROM PUBLIC, anon, authenticated`) plus `BEFORE INSERT OR UPDATE ON public.customers`.
  - **When the request role is `anon` or `authenticated`** (read from `auth.role()`; `service_role`, the SQL Editor and migrations are unaffected):
    - INSERT: `NEW.role` must be `'customer'`, **and `NEW.phone` must equal the server-verified phone claim `auth.jwt() -> 'app_metadata' ->> 'verified_phone'`** (stamped by A8; `app_metadata` is writable only by the service role). Otherwise raise.
      - **Why (G5):** without this, an email-signup stranger with no customer row can create one with any **unregistered** buyer's phone. They'd then receive that buyer's web-order points (the webhook matches by phone), orphan orders (`link-orders`) and unclaimed store sales (`my_phone()`).
    - UPDATE: raise if `role`, `phone` or `auth_user_id` differ from OLD.
  - **Why phone too:** a self-changed phone would redirect web-order crediting (the webhook matches by phone) and unclaimed-sale visibility (`my_phone()`). Phone changes belong to the OTP-verified server flow.
  - Referral fields are **not** guarded here (loyalty behavior; untouched per the principle).
- **Compatibility:**
  - The app only updates `avatar_url` (`profile.tsx:104`), `country` (`CountryService.ts:132`) and `wc_customer_id` (`useAuth.ts:126`), and inserts with the default role (`useAuth.ts:272-283`). Edge Functions use the service role.
  - The insert rule needs the `verified_phone` claim, so **A8 must be deployed first**.
  - Existing customers aren't affected (the rule applies to INSERT only).
  - Edge case: someone who verified OTP *before* A8 deployed but hasn't created their profile yet must verify again. The app already re-runs OTP on a fresh login.
- **Rollback:** `...a3...down.sql` drops the trigger and the function.

#### A4 — No arbitrary initial loyalty balance (P0-1b)
- **File:** `supabase/pending/s00a/20260925000400_s00a_a4_card_insert_initial_state.sql`
- **Change:** replace `cards self insert` with:
  ```
  WITH CHECK (customer_id = my_customer_id()
              AND coalesce(total_points,0) = 0 AND coalesce(pairs_count,0) = 0
              AND coalesce(total_pairs_count,0) = 0 AND coalesce(purchases_this_year,0) = 0
              AND last_purchase_at IS NULL
              AND NOT EXISTS (SELECT 1 FROM loyalty_cards lc WHERE lc.customer_id = my_customer_id()))
  ```
  - `tier` is forced from points by the existing `trg_update_tier`, so with 0 points it's bronze.
  - **A4b (included; G4 = 0):** `CREATE UNIQUE INDEX IF NOT EXISTS loyalty_cards_customer_id_key ON loyalty_cards(customer_id)`, in its own file (`…000410_s00a_a4b_card_unique_customer.sql`). Not `CONCURRENTLY`, because migrations run inside a transaction. The table is small, so the lock is brief. **Defensive precondition:** the file first runs a `DO` block that raises (aborting the apply) if `select 1 from loyalty_cards group by customer_id having count(*) > 1` returns any row.
  - **Unchanged on purpose:** the `trg_aplicar_creditos_pendientes` popup failure (P1-13) is left as-is per Q15. The popup stays disabled; fixing it is a separate economics decision.
- **Compatibility:** the app inserts exactly 0/0/bronze once, at sign-up (`useAuth.ts:292-298`).
- **Rollback:** `...a4...down.sql` restores the original policy and drops the index if it was created.

#### A5 — Seller PIN visibility limited to staff/admin (P0-3, interim until S0.2)
- **File:** `supabase/pending/s00a/20260925000500_s00a_a5_staff_read_by_role.sql`
- **Change:** drop `auth read staff` and `staff_read_own`, and create `staff read by staff/admin` `FOR SELECT TO authenticated USING (my_role() IN ('admin','staff'))`.
  - It's safe only **after A3**, because the role can no longer be self-assigned.
  - Ordinary customers can no longer read seller PINs.
  - **Residual:** staff can still read each other's PINs until S0.2 (hashing plus individual sessions, Q1/Q2).
- **Compatibility:** only seller and admin screens read `staff` (`vendedora/index.tsx:82`, `admin/staff/*`, `admin/index.tsx:114`, `admin/reports.tsx:62`), and they're only reachable with role staff/admin (`profile.tsx:352-367`).
- **Precondition:** G2 = 0.
- **Rollback:** `...a5...down.sql` restores the two original policies.

#### A6 — Stop trusting user-editable `user_metadata` in RLS (P0-10, RLS part)
- **File:** `supabase/pending/s00a/20260925000600_s00a_a6_drop_metadata_trust_policies.sql`
- **Change:** `DROP POLICY IF EXISTS` for `admins_all_channels`, `admins_all_inventory`, `admins_all_staff`, `admins_staff_all_sales`, `customers_read_own_sales`, `Users manage their own push tokens` and the dead `users own their wishlist`.
- **What remains** (all `my_role()`/`my_customer_id()` based, i.e. keyed on `auth_user_id`, not on editable data):
  - `channels admin write`, `auth read channels`, `read_active_channels`
  - `inventory staff write`, `auth read channel_inventory`, `read_inventory`
  - `staff admin write` + A5
  - `offline_sales staff insert/update`, `auth read offline_sales`, `offline_sales own by phone`
  - `push self all`, `wishlist self all`
- **Intended behavior differences:**
  - staff lose write on `channels` (the app never writes channels as staff; `channel-new` is admin-only);
  - staff/admin lose DELETE on `offline_sales` (the app never deletes sales).
- **Precondition:** G2 = 0.
- **Rollback:** `...a6...down.sql` recreates the seven policies exactly as dumped (`schema.sql:1189-1217, 1312, 1439-1444`).

#### A7 — Account operations on verified identity only (P0-10, function part)
- **Files:**
  - `fuxia-native/supabase/functions/delete-account/index.ts`: resolve the customer **only** by `customers.auth_user_id = user.id` (drop `user_metadata.phone`, `:38-49`); delete `otp_verifications` by the customer row's phone. If no linked customer is found, delete only the auth user and avatar files, and touch no customer rows.
  - `fuxia-native/supabase/functions/my-orders/index.ts`: remove the `metaPhone` fallback (`:56-65`), resolve only by `auth_user_id`, and keep returning 404 otherwise.
  - `fuxia-native/supabase/functions/link-orders/index.ts`: remove the `metaPhone` fallback (`:53-61`).
- **Deploy:** `npx supabase functions deploy <fn> --project-ref <ref>`, one function at a time; verify_jwt stays as deployed (true).
- **Precondition:** `customers_unlinked_auth` from G1 is reviewed. An unlinked customer who opens the app is linked at the next OTP verify.
- **Rollback:** redeploy the previous version from git (`git show b1b4171:<path>`), recorded per function in the apply log.

#### A8 — facts about the deployed bypass (verified 2026-09-24 from the deployed source; no secret changed)

The deployed `whatsapp-otp` (v50) is **byte-identical** to the repo file (S0.1a download + `cmp`).

| Question | Answer | Evidence |
|---|---|---|
| 1. What does `REVIEW_BYPASS_ENABLED` do? | **Nothing. It doesn't exist in the deployed code.** It's the flag *proposed* for A8. The only review settings the deployed code reads are `REVIEW_BYPASS_PHONE`, `REVIEW_BYPASS_CODE` and `REVIEW_DEMO_PHONE`, each with a hardcoded fallback | `whatsapp-otp/index.ts:17-19` |
| 2. Does setting it `false` disable the bypass? | **No.** The bypass is **unconditional**: a verify with `phone === REVIEW_BYPASS_PHONE && code === REVIEW_BYPASS_CODE` always issues a session for `REVIEW_DEMO_PHONE`, skipping OTP. Only a code deploy (A8) can add a real on/off switch | `:184-191`; also `check_phone` `:124` and `send` `:143` |
| 3. Do secret changes apply without a redeploy? | **Likely yes, but not provable from the source.** The values are read **once per function instance, at module load** (top-level `Deno.env.get`, `:17-19`). Supabase injects project secrets into the runtime without redeploying, but instances that are already running may keep old values until they recycle. Must be **verified on staging** (set, call, observe) before anyone relies on it | `:17-19` |
| 4. Does App Store / Play review depend on it? | **Yes, both stores were given these credentials.** Whether a review is **in progress right now** can't be seen from the repo; it has to be checked in App Store Connect and the Play Console. Apple needs a working demo login for **every** submission; Google may re-review at any time | `APP_STORE_METADATA.md:114-115`; `store/android/PLAY_LISTING.md:104-123`; `ANDROID_PUBLISHING.md:134`; `BACKLOG.md:147` |

Additional facts:
- **G3:** the demo login resolves to an **admin**, so every store reviewer (and anyone who reads these docs) gets the **admin panel**.
- **The credentials are committed to this repository** in four documents. If the repository or those documents are visible outside the team, they're effectively public.
- **Consequence for A8 design (unchanged, now confirmed necessary):** the explicit enable flag, no defaults, and a dedicated **customer-role** demo account (not admin). Operationally, the flag is on only during a store review window, and the store-review notes must stop presenting an admin account. **Pre-deploy check:** confirm in both consoles that no review is in progress, and coordinate the next submission with the flag.

#### A8 — `whatsapp-otp`: review-login containment + server-verified phone claim (P0-6.3; prerequisite of A3)
- **File:** `fuxia-native/supabase/functions/whatsapp-otp/index.ts`.
- **Change 1 — review login:**
  - The bypass is active **only** when `REVIEW_BYPASS_ENABLED === 'true'` **and** `REVIEW_BYPASS_PHONE`, `REVIEW_BYPASS_CODE` and `REVIEW_DEMO_PHONE` are all explicitly set. The hardcoded defaults at `:17-19` are removed.
  - With the flag off, the bypass phone is treated like any other number (real OTP).
  - Missing `OTP_SALT` → fail closed (it is set today).
  - G3: the current default demo phone resolves to an **admin**. The flag must only ever point at a dedicated **customer-role** demo account.
- **Change 2 — verified phone claim (G5):**
  - On every successful OTP verify, before issuing the session, set `app_metadata.verified_phone = <E.164 phone that just passed OTP>` through the admin API: `createUser({ app_metadata })` for new users, `updateUserById(id, { app_metadata })` for existing ones.
  - This is the only phone claim authorization may trust (A3 insert rule). `user_metadata.phone` is left in place for the existing app code paths but is never used for authorization.
- **Operational:** the owner enables the review flag only during an App Store / Play review window, then disables it. **Check before deploying** that no review is in progress, or coordinate the timing.
- **Rollback:**
  - review login: instant, with no redeploy (set `REVIEW_BYPASS_ENABLED=true` plus the three secrets);
  - full rollback: redeploy the previous version. A harmless leftover `app_metadata.verified_phone` stays on users, and it **must not** be rolled back while A3 is applied (A3 would block new sign-ups).

### Order of application (staging first, then production)

`A0 → A1 → A2 → A8 → A3 → A4 → A4b → A5 → A6 → A7`

- A1 and A2 have no preconditions and close the internet-facing holes first.
- A8 moves ahead of A3: it closes the **public admin login** (G3), and its verified-phone claim is required by A3's insert rule.
- Rollback order is the reverse. Never roll back A8 while A3 is applied.
- A5 and A6 require A3 (role immutability) and G2.
- A7 and A8 are function deploys.
- Each unit is a separate commit, a separate apply, and a separate verification. Stop on the first failure.

### Security tests — each must fail before the change and pass after (staging)

Harness: new file `scripts/s00a/probe.ts` (Deno + supabase-js) plus `supabase/tests/s00a_catalog.sql`.
- The probe **refuses to run write-probes unless the target ref ≠ `tgzgiwfzddsghnxgkcqd`**.
- Actors on staging: `anon`; **`E1`, an email-signup stranger with no phone and no customer row (the baseline attacker per G5)**; customers `C1` and `C2`; a staff account `S1` (role staff, a staff row in channel X); an admin `M1`. All are synthetic. Staging mirrors production's auth settings (email provider ON).

| Test | Proves | Action | Before (expected vulnerable) | After (required) |
|---|---|---|---|---|
| T1 | P0-9 closed | anon and C1: `rpc('fx_add_points', {p_card_id: C1.card, p_points: 1000})` | succeeds, points +1000 | `42501 permission denied`; balance unchanged |
| T2 | P0-11 closed | catalog: `has_function_privilege('anon', 'public.fx_add_points(uuid,integer)', 'EXECUTE')` (same for the other 5 functions, and for `authenticated`) | true | false |
| T3 | Default privileges | catalog: `pg_default_acl` for `postgres` in `public` has no function EXECUTE for anon/authenticated/PUBLIC | present | absent |
| T4 | Anonymous PIN read closed | anon: `select pin from staff` | rows returned | 0 rows / permission denied |
| T5 | Anonymous inventory write closed | anon: `update channel_inventory set price = 1 where id = X` | 1 row updated | permission denied / 0 rows; price unchanged |
| T6 | Anonymous sale insert closed | anon: `insert offline_sales` | inserted | denied |
| T7 | Anonymous sale PII read closed | anon: `select customer_phone from offline_sales` | rows | 0 / denied |
| T8 | Anonymous ICR read/insert closed | anon: select/insert `inventory_change_requests` with S1's staff id | allowed | denied |
| T9 | P0-1 closed | C1: `update customers set role='admin' where auth_user_id = C1` | succeeds | error from guard; role still customer |
| T10 | Insert escalation closed | new user C3: `insert customers (..., role:'admin')` | succeeds | error |
| T11 | Phone takeover closed | C1: `update customers set phone = '<unused number>'` | succeeds | error |
| T12 | P0-1b closed | C3: `insert loyalty_cards (total_points 100000)` | succeeds, tier gold | denied |
| T13 | Duplicate card closed | C1 (has a card): insert a second card with 0 points | succeeds | denied |
| T14 | Customer PIN read closed | C1: `select pin from staff` | rows | 0 rows |
| T15 | P0-10 RLS closed | C1 sets `user_metadata.phone = M1.phone` (auth.updateUser), then `update staff set active=false where id=S1` / `insert channels` / `delete offline_sales` | succeeds | 0 rows / denied |
| T16 | P0-10 push tokens | C1 with spoofed `M1` phone: select/insert `push_tokens` for M1 | allowed | 0 rows / denied |
| T17 | P0-10 delete-account closed | C2 sets `user_metadata.phone = C1.phone`, calls `delete-account` | **C1's customer data deleted** | C1 untouched; only C2's auth user deleted |
| T18 | my-orders / link-orders spoof | a fresh auth user with no customer row and `user_metadata.phone = C1.phone` calls both | returns C1 data / links C1 orphans | 404 / no link |
| T19 | P0-6.3 closed | flag unset: `verify` with `+525555555555` / `555555` | session for the demo account | normal OTP path → "Código incorrecto o expirado" |
| T21 | G5 baseline attacker: role | **E1** (fresh email sign-up, no customer row): `insert customers (role:'admin', phone: unused number)` | succeeds, then E1 has admin rights | denied (role and unverified phone) |
| T22 | G5: phone squatting | **E1**: `insert customers (role:'customer', phone: an unregistered buyer's number)` | succeeds; E1 then receives that phone's web-order points | denied (no matching `app_metadata.verified_phone`) |
| T23 | G5: PIN read | **E1**: `select pin from staff` | rows | 0 rows (A5) |
| T24 | G5: inventory requests | **E1**: select / insert `inventory_change_requests` with a known `staff.id` | allowed | denied (A2) |
| T25 | G5: admin functions | **E1**: call `admin-points` (search), `admin-broadcast-push`, `inventory-approve` | 403 today (role check) | still 403; E1 can't reach admin via A3 |
| T26 | G5: metadata claims ignored | **E1** sets `user_metadata.phone` = admin's phone, then retries T15/T16/T17 | allowed today | denied (A6/A7) |
| T27 | Verified claim stamping | new OTP sign-up on staging | — | JWT contains `app_metadata.verified_phone` equal to the OTP phone; the customer insert succeeds (R1) |
| T20 | Bypass works when enabled | flag and secrets set on staging | — | the demo session is returned for the configured demo customer only |

### Regression tests — legitimate flows still work (staging, dev build pointed at staging)

| R | Flow | Pass criteria |
|---|---|---|
| R1 | New customer OTP sign-up → profile → card | customer row role=customer, `auth_user_id` set, exactly one card with 0 points / bronze |
| R2 | Existing customer login | profile, card and realtime work; `avatar_url` upload and `country` change succeed (A3 allows them) |
| R3 | Woo webhook `processing` → points; refund → reversal (signed test payload) | same points as before; card updated (service role unaffected) |
| R4 | `link-orders` for a linked customer with an orphan order | credited as before |
| R5 | `my-orders` for a linked customer | orders returned |
| R6 | Seller S1: Vendedora → channel → PIN → cart → QR sale / code sale | stock `sold` updated, sale recorded, QR points credited as before |
| R7 | Seller S1: stock +/- creates an ICR; M1 approves via `inventory-approve` | request inserted (authenticated), applied |
| R8 | Admin M1: create channel, create staff, import from Woo, direct stock edit, Today dashboard, reports, broadcast, points search/adjust | all succeed as before (admin-points audit behavior unchanged, see Q15) |
| R9 | Customer tracking: own unclaimed sales visible | `offline_sales own by phone` still returns them |
| R10 | Customer claims a code (`claim-sale`) | unchanged (hardening is S0.0B) |
| R11 | `delete-account` by a customer on their own account | own data deleted, auth user deleted |
| R12 | `birthday-push` / `loyalty-credit` (service role) | still able to call `award_birthday_points` / `fx_add_points` |
| R13 | Wishlist add/remove, push-token registration | work via the `*self*` policies |

### Staging → production procedure

1. **Staging build:** create the project (G7); apply the baseline; deploy the current production function versions; set staging-only secrets (test Twilio or the review bypass enabled **on staging only**, a test Woo endpoint or a signed fake webhook payload); create the synthetic actors and data with the service role.
2. **Baseline run:** run T1–T20. The vulnerable "before" results must reproduce, which proves each test detects the problem.
3. **Apply A1…A8** one by one. After each unit, run its tests plus R1–R13. Record the results in `docs/fuxia360/audit/S0_0A_TEST_REPORT.md`.
4. **Rollback rehearsal:** on staging, apply every `.down.sql` in reverse, confirm the "before" results come back, then re-apply. This proves each rollback works.
5. **Production:**
   - confirm the backup/PITR point;
   - apply in the same order, in a low-traffic window, one unit at a time;
   - after each unit, run **production-safe checks only**:
     - catalog queries (`has_function_privilege`, `has_table_privilege`, `pg_policies`, trigger presence);
     - anonymous probes that can't mutate (reads, and writes filtered to a nonexistent UUID, where the expected result is permission denied);
     - no write probes against real customers.
   - A manual smoke test by an admin and a seller on their own phones covers R2, R6, R7 and R8.
6. **Stop rule:** any regression means applying that unit's `.down.sql` (or redeploying the previous function), logging it, and not continuing.
7. **Exit for S0.0A:** T1–T19 pass in production-safe form; R-smoke passes; the apply log and test report are committed.

### Residual risk after S0.0A (addressed later)
- staff can read other staff PINs (S0.2);
- `claim-sale` point minting, `backfill-orders`, the Woo proxy and `birthday-push` (S0.0B);
- authenticated users can read all `offline_sales` and `support_tickets` (S0.0B);
- non-atomic sale (S0.3);
- loyalty write races and the admin audit gap (S0.5).

---

## S0.0B — Function and Integration Hardening (scope only; detailed plan after S0.0A)

The same rules apply: no economics changes, staging first, a rollback per unit. **Pre-step:** sync the deployed sources of `claim-sale`, `calculate-points`, `hilo-chat`, `virtual-tryon*`, `notify-approval-pending`, `birthday-push` and `send-push` into the repo **before** editing them. Otherwise the undeployed repo referral bonus would ship (L4).

| Unit | Target | Direction |
|---|---|---|
| B1 | `backfill-orders` (P0-8) | require the service-role key, or undeploy (Q8) |
| B2 | `birthday-push` (P1-16) | require the service-role key or a cron secret (after checking how it's invoked, G6) |
| B3 | `woocommerce-proxy` (P0-7) | per-path parameter whitelist; `customers` exact-email only with a trimmed response; POST body whitelist (the client uses the anon key, `WooCommerceService.ts:24-27`) |
| B4 | `claim-sale` interim (P0-2) | starting from the **deployed** source: server price, active staff in channel, stock cap, atomic claim. **No referral bonus** (preserve live behavior) |
| B5 | Store/support visibility (P0-5 authenticated part) | `support_tickets` admin-only; `offline_sales` authenticated read narrowed to admin/staff plus own by phone |
| B6 | `escalate-to-staff`, `virtual-tryon`, `virtual-tryon-status`, `notify-approval-pending` | require a user JWT (a real user, not the anon key) |
| B7 | ~~Q16 unschedule~~ | **Not needed.** G6: no cron jobs exist (`cron_jobs = 0`). Nothing to disable; tiers stay permanent |
| B8 | `send-push` | replace the substring auth check with an exact service-role comparison (P2) |
| B9 | **Auth hardening (Q17)** | Two proposals, each approved separately: (1) whether public email sign-up is needed by any legitimate flow, and if not, a proposal to disable it; (2) a migration plan from predictable `{phone}@fuxia.app` identities to server-controlled identity linked to the verified phone / auth identity. No automatic account replacement/relinking |

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

> **RE-BASED 2026-09-25 on Track C · C1:** roles and seller↔location authority come from `f360.user_roles` (role
> `seller`) and `f360.location_assignments` (several locations per seller, D-L2), checked by `f360.require_location`.
> Sessions bind `auth user + f360 location`. `staff.channel_id` stops being an authority after S0.2c.
> See `docs/fuxia360/ops/TRACK_C_BOUNDARY_S0.md`.

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
  
  **Prerequisite:** S0.0A (A3 phone immutability, A6/A7 no `user_metadata` trust, A8 review-login containment), because this link trusts the verified phone.
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
  - Narrow `offline_sales` reads to admin plus the individual seller's channel(s) (the authenticated-visibility part starts in S0.0B-B5).
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

> **STAGING IMPLEMENTATION 2026-09-25:** see `docs/fuxia360/ops/CLOSED_LOOP_STORE_SALE.md` §8 (the RPC-only D-E1, no referral D-R1, self-sale 0 D-S2). Not in production.

> **RE-SCOPED 2026-09-25 (decision D-X1, approved):** S0.3 does **NOT** create `public.inventory_events`. The single
> ledger already exists (`f360.inventory_events` + `f360.inventory_movements`, `f360.inventory_balances` as cache).
> `pos-sale` keeps every security control described below (seller JWT + session, no price fields, idempotency,
> location from the session) and routes by `f360.locations.ledger_authority`: **legacy** locations → an atomic
> `pos_record_sale_legacy` on `channel_inventory` + `offline_sales` + `offline_sale_items` (the per-line audit);
> **f360** locations → `f360_record_store_sale` on the single ledger (Track C · C3). The `inventory_events` bullets
> below are SUPERSEDED. See `docs/fuxia360/ops/TRACK_C_BOUNDARY_S0.md`.

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

> **STAGING IMPLEMENTATION 2026-09-25:** see `docs/fuxia360/ops/CLOSED_LOOP_STORE_SALE.md` §8 (the RPC-only D-E1, no referral D-R1, self-sale 0 D-S2). Not in production.

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
  - P1-3: `admin-points` writes the audit ledger row and the balance change atomically through `loyalty_apply` (no balance change without an audit row). **Per Q15:** add `manual` (only) to `transactions_channel_check`. The audit record (actor, customer/card, delta, reason, timestamp) is immutable: no client or function UPDATE/DELETE path. `popup` is **not** enabled.
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
| Q7 | `loyalty-credit` caller | 🔴 **OPEN** — deployed (S0.1a); caller type pending | `loyalty-credit` hardening; migrating the S0.5 caller |
| Q8 | `backfill-orders` still needed? | 🔴 **OPEN** — deployed (S0.1a) | S0.0B-B1 undeploy decision (a service-key guard is allowed meanwhile) |
| Q9 | Staging | ✅ Decided — staging before destructive/cutover testing of S0.2/S0.3 | — |
| Q10 | Compatibility window | ✅ Decided (approach) — additive window, then a separate cutover. **Duration intentionally undecided** | Triggering S0.2c/S0.3c (needs a later explicit go-ahead) |
| Q11 | Inventory audit event in Sprint 0 | ✅ Decided — yes, forward-compatible `inventory_events` for new sales | — |
| Q12 | Distributed fulfillment / Woo stock / bazaar leftovers | ➖ **Not a Sprint 0 item.** The principles are in the spec; the remaining operational details are resolved during Product, Inventory, Availability, Fulfillment and Production design | — (Sprint 0) |
| Q15 | Manual/popup loyalty channels | ✅ Decided — `manual` allowed with an immutable audit record (S0.5); `popup` NOT enabled | — |
| Q17 | Auth architecture: predictable synthetic-email identity + open email sign-up (G5) | 🔴 **OPEN — tracked as an auth architecture issue.** Direction decided (below); no implementation in S0.0A unless an approved test requires it; **no automatic account replacement/relinking** | S0.0B / Auth Hardening |
| Q16 | Annual tier downgrade | ✅ Decided and verified — not intended; G6 shows no schedule (`cron_jobs = 0`); nothing to unschedule; no deletion | — |
| Q13 | Old Woo REST key | ✅ Decided (handling) — verify and revoke before closing P1-9. **The verification itself is still pending** | Closure of P1-9 / S0.4 exit |

**Remaining Sprint 0 open items:** only **Q7** and **Q8**, both operational verification. Neither blocks S0.1a.

**New decision item from G5 (does not block S0.0A):**
- **Q17 — derived-email squatting.**
  - **The problem:** OTP users are Supabase auth users with the predictable email `{phone digits}@fuxia.app` (`whatsapp-otp/index.ts:228`). With email sign-up open, a stranger can pre-register that address for a phone that hasn't joined the app yet.
  - **The effect:** when the real owner later verifies their OTP, `signInWithPassword` fails, then `createUser` fails with "already registered", so **the real customer can't create an account (lockout/DoS)**. It isn't a takeover: the stranger can't pass A3's verified-phone insert rule.
  - **Options (decide separately; not in S0.0A per your instruction):**
    - (a) `whatsapp-otp` detects an existing unconfirmed or foreign user at the derived address and replaces or relinks it (server-side);
    - (b) move OTP users to an unguessable internal email;
    - (c) restrict or disable public email sign-up, if the app doesn't need it (a provider-configuration change).
  - "Confirm email" status affects severity, but not the fix.
  - **Direction (decided 2026-09-24):**
    - Predictable `{phone}@fuxia.app` addresses are **not** a durable identity architecture.
    - **No** automatic account replacement or relinking for now (option a is rejected for now).
    - **S0.0B / Auth Hardening** determines whether public email sign-up is required by any legitimate Fuxia flow. If it isn't, it proposes disabling it (option c; provider configuration, approved separately).
    - **Separately**, it proposes a migration away from synthetic-email identity toward **server-controlled identity linked to the verified phone / auth identity** (option b, with a migration plan for existing users).

**Future-sprint questions (do not block Sprint 0):**
- **Q14 — Production Tracking Lite** (core domain, Phase 5D): how are make-to-order orders tracked today, and with which workshops/suppliers? Who assigns work, changes promised dates, confirms quality and receipt, and gets at-risk alerts (`05_GOVERNANCE.md` §5.1)? Which location receives produced pairs? How many make-to-order orders are open right now (needed for cutover capture, `09_MIGRATION_PLAN.md` Phase 5b)?

**Next step:** wait for an explicit go-ahead. The first unit, when approved, is S0.1a (the schema-only dump, run by Mario or the project owner).
