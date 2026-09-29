# Runbook — S0.0A-A2 in PRODUCTION (remove anonymous access to operational tables)

**Status: NOT EXECUTED in production.** Staging full rehearsal **CLEAN** (2026-09-25): BEFORE → apply → AFTER → regressions →
rollback (exact restore) → re-apply. Evidence: `docs/fuxia360/audit/s00a_results/a2_rehearsal.json`. P1 decided: option **(a)+(b)**.
**Remaining blockers for production are listed in "Readiness" at the end.**

- Production project: `tgzgiwfzddsghnxgkcqd`.
- Migration file: `supabase/pending/s00a/20260925000200_s00a_a2_remove_anon_operational_access.sql`.
- Rollback file: `supabase/rollbacks/20260925000200_s00a_a2_remove_anon_operational_access.down.sql`.

## What A2 closes (verified in the production schema dump)

| Policy / grant | Exposure today |
|---|---|
| `anon_update_inventory_sold` (channel_inventory, UPDATE, `true/true`) | **Anyone** with the public app key can change **any column** of store inventory, **including price and stock** |
| `anon_read_active_staff` (staff) | Seller **PINs** readable by anyone |
| `anon_read_offline_sales`, `anon_read_own_sales` (offline_sales) | All store sales, **customer phones**, items and totals readable by anyone |
| `anon_insert_offline_sales` | Anyone can create store sales (later claimable for points) |
| `anon_read_inventory`, `anon_read_active_channels` | Stock and channels readable by anyone |
| `icr read open`, `icr insert … OR any active staff.id` | Stock-change requests readable, and insertable with a harvested staff id |
| `GRANT ALL … TO anon` on 6 tables | Base privileges behind the above |

## P · Prechecks (all must be ✔ before scheduling)

- **P1 — BLOCKER: how do sellers enter the seller mode today?**
  - The app shows **"Soy vendedora" on the onboarding screen, before login** (`fuxia-native/app/onboarding/index.tsx:80-86` → `/vendedora`). That path runs as **anon**, and it depends on exactly the policies A2 removes: it reads channels, PINs and inventory, updates `sold`, and inserts `offline_sales`.
  - After A2, **every sale made from the pre-login path fails** (stock read empty, sale insert rejected).
  - The logged-in path ("Modo Vendedora" in Perfil, for `customers.role ∈ {staff, admin}`) keeps working through the authenticated policies.
  - Mario must choose one:
    - **(a) Operational switch, no app change:**
      1. every active seller gets an app account on their own phone, with `customers.role='staff'` set by an admin;
      2. sellers are told to always log in and use Perfil → Modo Vendedora;
      3. A2 is applied after confirming (b-check below).
    - **(b) Ship an app update first** that hides "Soy vendedora" when there is no session (a one-line change in `onboarding/index.tsx`), then apply A2 once it is adopted.
    - **(c) Wait for S0.2** (individual seller identity + server session). This is the correct end state, but it leaves the price/stock exposure open longer.
  - **Recommended: (a) + (b) together.** The exposure (anyone can change store prices) outweighs a short operational change.
- **P2 — seller readiness (aggregate only, no row data).** Run in the production SQL Editor:
  ```sql
  select (select count(*) from staff where active) as active_staff,
         (select count(*) from customers where role = 'staff') as staff_accounts,
         (select count(*) from customers where role = 'admin') as admin_accounts;
  ```
  Expected: `staff_accounts` covers every active seller who will log in (P1-a). If `staff_accounts` = 0, **do not proceed**.
- **P3 — no other anonymous reader.** Confirm with Mario/Adrián that nothing outside the app (website widget, bazaar page, script) reads `channels`, `channel_inventory` or `offline_sales` with the anon key. The repo shows none. If one exists, it breaks and must move to an Edge Function.
- **P4 — live policies still match the dump.** Run read-only in production:
  ```sql
  select tablename, policyname, roles, cmd from pg_policies
  where schemaname = 'public' and tablename in ('staff','channel_inventory','offline_sales','channels','inventory_change_requests')
  order by 1, 2;
  ```
  Expected: the 7 `anon_*` policies plus `icr read open` and `icr insert with valid staff or admin/staff role`, exactly as in `schema.sql:1221-1245,1319-1325`. **Any difference → stop and re-dump.**
- **P5 — migration history.** `supabase migration list --linked` (read-only): production shows the baseline `20260924000000/…01` as applied, and no F360 migrations. A2 is applied **by SQL, not by `db push`**, so no other pending unit can ride along.
- **P6 — staging rehearsal. ✔ DONE 2026-09-25 (clean; see the evidence file).** Original text: The A2 SQL was executed on staging inside a rolled-back transaction (2026-09-25): 7 anon policies → 0, 0 anon grants left, the new ICR policies created, and staging unchanged afterwards. **Still to do before production:**
  - a full staging apply;
  - the post-checks below;
  - a smoke test with a **logged-in** staff account (seller mode: load stock, make a test sale, request an adjustment);
  - rollback;
  - re-apply.
  
  This needs approval (it changes staging's lab posture).
- **P7 — timing.** Outside store hours. Mario or Carolina available to smoke-test with a real seller account.

## D · Dry-run (production, read-only)

Paste into the production SQL Editor. Each statement is safe:
```sql
BEGIN READ ONLY;
select count(*) as anon_policies from pg_policies where schemaname='public' and 'anon' = any(roles)
  and tablename in ('staff','channel_inventory','offline_sales','channels');                       -- expect 7
select count(*) as anon_grants from information_schema.role_table_grants where grantee='anon' and table_schema='public'
  and table_name in ('staff','channel_inventory','offline_sales','channels','inventory_change_requests','support_tickets'); -- expect > 0
ROLLBACK;
```

## M · Migration (the exact SQL)

**Only after P1–P7 are ✔ and Mario approves this exact step.** It is the content of the pending file, applied by pasting it into the production SQL Editor (or `psql` against the production URL, run by Mario). It runs in one transaction:

```sql
BEGIN;
DROP POLICY IF EXISTS "anon_insert_offline_sales"  ON public.offline_sales;
DROP POLICY IF EXISTS "anon_read_offline_sales"    ON public.offline_sales;
DROP POLICY IF EXISTS "anon_read_own_sales"        ON public.offline_sales;
DROP POLICY IF EXISTS "anon_read_active_staff"     ON public.staff;
DROP POLICY IF EXISTS "anon_read_inventory"        ON public.channel_inventory;
DROP POLICY IF EXISTS "anon_update_inventory_sold" ON public.channel_inventory;
DROP POLICY IF EXISTS "anon_read_active_channels"  ON public.channels;
DROP POLICY IF EXISTS "icr read open" ON public.inventory_change_requests;
DROP POLICY IF EXISTS "icr insert with valid staff or admin/staff role" ON public.inventory_change_requests;
CREATE POLICY "icr read staff admin" ON public.inventory_change_requests FOR SELECT TO authenticated
  USING (public.my_role() = ANY (ARRAY['admin'::text, 'staff'::text]));
CREATE POLICY "icr insert staff admin" ON public.inventory_change_requests FOR INSERT TO authenticated
  WITH CHECK (public.my_role() = ANY (ARRAY['admin'::text, 'staff'::text]));
REVOKE ALL ON public.staff, public.channel_inventory, public.offline_sales, public.inventory_change_requests,
  public.channels, public.support_tickets FROM anon;
COMMIT;
```

## V · Post-deploy verification (within 15 minutes)

1. **Policies:** the P4 query shows 0 `anon_*` policies, plus `icr read staff admin` and `icr insert staff admin`.
2. **Anonymous access is closed.** From any machine, with the public anon key, **read-only**:
   `curl "$URL/rest/v1/staff?select=id&limit=1" -H "apikey: $ANON" -H "Authorization: Bearer $ANON"` → `[]` or 401/403, **never** rows. The same for `channel_inventory` and `offline_sales`.
   Also attempt `PATCH channel_inventory?id=eq.<none>` with anon → rejected. This is the **only write test**, and it targets **no row**.
3. **Seller smoke test** by a real seller logged in with their own account:
   - Perfil → Modo Vendedora → stock loads;
   - one real sale (normal business, not a fake), with and without a QR;
   - the claim code works in the customer app;
   - an adjustment request reaches the admin.
4. **Admin smoke test:** approvals screen and channel inventory screen load.
5. **Logs:** Edge Functions `claim-sale` and `inventory-approve` show no new errors (they use the service role and are unaffected).
6. **Record** the time, who applied it, and the results in `docs/fuxia360/audit/S0_0A_TEST_REPORT.md`.

## R · Rollback

**Trigger:** the seller smoke test fails, or stores cannot sell and there's no immediate fix-forward.

Paste `supabase/rollbacks/20260925000200_s00a_a2_remove_anon_operational_access.down.sql`. It restores the exact production definitions: 7 anon policies, 2 ICR policies, grants.

**Rolling back re-opens the exposure.** The next step must be a fix-forward: P1-a/b, then re-apply.

## Not part of A2

- A3 (role/phone self-escalation);
- A4 (initial loyalty balance);
- A5 (staff PIN visibility for authenticated users; PINs remain readable by **logged-in customers** after A2);
- S0.2 (hashed PINs, individual sessions);
- S0.3 (atomic sale).

Each is a separate unit with its own runbook.

## Staging rehearsal results (2026-09-25)

| Probe | BEFORE | AFTER A2 | After ROLLBACK | FINAL (re-applied) |
|---|---|---|---|---|
| anon policies / anon grants on the 6 tables | 7 / 42 | **0 / 0** | 7 / 42 (identical) | 0 / 0 |
| anon read staff / inventory / sales / channels | rows | **401** | rows | 401 |
| anon UPDATE `channel_inventory` (price) / INSERT sale | allowed | **denied** | allowed | denied |
| logged-in customer: read ICR / insert ICR with a harvested staff id | allowed | **0 rows / denied** | allowed | 0 / denied |
| logged-in staff (`customers.role=staff`): read stock, update sold, insert sale, read/insert ICR | ok | **ok** | ok | ok |
| S0.2 seller shift flow (16 checks) | — | **PASS** | — | — |
| All DB suites (172 checks) | — | **PASS** | — | — |

Write probes ran inside rolled-back transactions. Rollback restored the exact policies and grants: the snapshot is identical to BEFORE.

## Readiness for PRODUCTION (what is still missing)

1. **App release with option (b):** the "Soy vendedora" entry is removed and `/vendedora` requires a session. The code is done (it has no flag dependency), but it is **not released**. A2 must wait until the release is adopted by every seller phone. Otherwise a seller on an old build loses sales.
2. **Option (a) in production:**
   - **every active seller has her own app account**, and an admin set `customers.role='staff'` on it (interim authority until S0.3);
   - verify with P2 (aggregate counts only).
   
   The new f360 seller role/shift (S0.2) needs Fuxia 360 in production, which is **not deployed**. For A2 in production, sellers use the **legacy logged-in path** (Perfil → Modo Vendedora with the legacy PIN) until S0.2 is deployed there.
3. **P3:** confirm there are no external anonymous readers.
4. **P4 / P5:** re-run in production just before applying.
5. **Timing and people** (P7): outside store hours; a real seller available for the smoke test.

When 1–5 are ✔, A2 production is a single approved SQL paste (section M), with verification V and rollback R as rehearsed.
