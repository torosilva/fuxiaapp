# S0.0A — Staging Baseline Rehearsal (A0 point 6)

**Date:** 2026-09-24
**Target:** STAGING only. Project ref `faltxpkaicwpnlqaxrdu`, host `aws-0-us-west-2.pooler.supabase.com:5432`, db `postgres`. The connection string is kept in `~/.fuxia-staging.env` (mode 600), outside the repo, and never printed.
**Production:** untouched. No `--linked`, no `migration repair`, no function deploys. Before every command, the connection string was checked for the production ref `tgzgiwfzddsghnxgkcqd` (not present).
**Tooling:** Supabase CLI v2.107.0 (unchanged during the rehearsal).

| Step | Command / action | Result |
|---|---|---|
| 1 | `supabase migration list --db-url "$STAGING_DB_URL"` | ✅ Remote history **empty**; only the local `20260924000000`, `20260924000001` |
| 2 | `supabase db push --db-url "$STAGING_DB_URL" --dry-run` | ✅ Would push **only** `20260924000000_baseline_live_public_schema.sql`, `20260924000001_baseline_live_storage_policies.sql`. No errors |
| 3 | `supabase db push --db-url "$STAGING_DB_URL"` (approved) | ✅ Both applied, exit 0. Only output: 4 `NOTICE`s *"policy … does not exist, skipping"* from the `DROP POLICY IF EXISTS` lines of file 2 (expected on an empty project). **No errors**; no statement needed adaptation (`pg_cron`, extensions, ownership, publication and grants all replayed) |
| 4a | `supabase migration list --db-url "$STAGING_DB_URL"` | ✅ Both versions recorded remotely (Local = Remote) |
| 4b | Inspection of `supabase_migrations.schema_migrations` (SELECT-only, via `psql` in the local Supabase Postgres image) | ✅ Table columns: `version text NOT NULL` (PK), `statements text[]`, `name text`. It's the only table in the schema. **Exactly 2 rows:** `20260924000000` / `baseline_live_public_schema` / 373 statements; `20260924000001` / `baseline_live_storage_policies` / 8 statements (4 DROP + 4 CREATE). `statements` holds the migration SQL **as text** (reviewed: no secrets). **This is what `repair --status applied` would write in production.** Note: the intended `PGOPTIONS` read-only guard was ignored by the pooler (`default_transaction_read_only = off`). Only SELECTs ran, so nothing changed; future inspections use `BEGIN READ ONLY … ROLLBACK` |
| 5 | `supabase db dump --db-url … -f <scratch>/staging_public.sql` (and `-s storage`) | ✅ Schema-only dumps written to the session scratchpad (not the repo) |
| 6 | `diff` vs `docs/fuxia360/audit/live/schema.sql` | ✅ See below |
| 7 | Classify the differences | ✅ See below |
| 8 | Baseline/security validation (catalog checks + T1–T27 "before") | ⏳ Not run yet (needs the staging config checklist: buckets, `tier_config`, synthetic actors, secrets, functions) |

## Diff results

### `public` schema (staging re-dump vs production snapshot)
- **Every statement is identical.** `diff` with blank lines ignored reports **no difference**.
- The only raw difference is **whitespace**: production has 4 more empty lines between `ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";` and `ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."loyalty_cards";` (production lines 1455-1464 vs staging 1454-1460). That gives 1949 vs 1945 lines.
- **Classification:** expected dump-formatting / platform difference. pg_dump emits separator blank lines for publication-related entries that the CLI filters out, and the number of filtered entries depends on the project. **No semantic difference.**

### `storage` schema
- The staging storage dump is **byte-identical** to the production storage dump, including the Supabase-managed internals (same platform storage version).
- **All 4 `storage.objects` policies exist in staging** and their definitions are identical to production: "Avatars are publicly readable", "Users can delete their own avatar", "Users can update their own avatar", "Users can upload their own avatar".

### Unexpected schema differences
- **None.**

## Status
- The baseline **successfully reproduces the approved production schema on staging** (public: statement-identical; storage: byte-identical).
- **No change was made based on the diff.** The baseline files are untouched (`20260924000000` is still byte-identical to `live/schema.sql`).
- **Re-validation (second fresh dump, same day):**
  - public: statement-identical again, and stable (the fresh staging dump is byte-identical to the first one);
  - storage: byte-identical;
  - the 4 policies match `20260924000001`;
  - `db push --dry-run`: "Remote database is up to date";
  - the history contains only the 2 baseline versions, with **no S0.0A migration** (`supabase/pending/s00a/` is empty and isn't read by the CLI).
- **How the baseline was applied:** by one approved `supabase db push --db-url "$STAGING_DB_URL" --yes`. `--yes` auto-answers the CLI's [Y/n] confirmation, because the agent's terminal is non-interactive. A later repeat of the push reported "Remote database is up to date" (no-op).
- Remaining rehearsal item: 8 (validation), which needs the staging configuration. The production registration (A0 step b) still needs its separate authorization.

---

# A0 — Production baseline registration (executed 2026-09-24)

**Authorization:** owner-approved, strictly limited to registering `20260924000000` and `20260924000001` in the production migration history.
**Not done (not authorized):** executing either baseline file against production, any non-dry-run push, A1/S0.0A, function deploys, secret/RLS/review-login changes, S0.0B, data repair.

| Step | Command | Result |
|---|---|---|
| Pre-check | `cat supabase/.temp/project-ref`; `supabase migration list --linked` | ✅ Linked ref = **`tgzgiwfzddsghnxgkcqd`** (production). Remote history **empty** (no unexpected versions). Local: only `20260924000000`, `20260924000001`; `supabase/pending/s00a/` empty |
| Registration | `supabase migration repair --status applied 20260924000000 20260924000001 --linked` | ✅ `Repaired migration history: [20260924000000 20260924000001] => applied`, exit 0. Per the staging rehearsal (4b), this writes one row per version to `supabase_migrations.schema_migrations` (`version`, `name`, `statements` as text). **No baseline SQL was executed** |
| Post-check 1 | `supabase migration list --linked` | ✅ `20260924000000 \| 20260924000000` and `20260924000001 \| 20260924000001`. **These are the only remote versions** |
| Post-check 2 | `supabase db push --linked --dry-run` | ✅ "Remote database is up to date." |
| Post-check 3–4 | `supabase db dump --linked` (schema-only, `public`), then `cmp` vs `docs/fuxia360/audit/live/schema.sql` | ✅ **Byte-identical** (1949 lines). The public schema is unchanged by the registration. The new dump stayed in the session scratchpad; secret scan clean |
| Baseline file | `cmp supabase/migrations/20260924000000_… live/schema.sql` | ✅ Still byte-identical (unmodified) |

**A0 status: COMPLETE.** Production and staging now share the same migration history (2 baseline versions). Every future production change goes through: `migration list --linked` → `db push --linked --dry-run` (must list only the approved unit) → approved `db push --linked` → production-safe checks.
