# Pre-production gate · S-G0 + SB0 (2026-10-08)

> STAGING ONLY. Production was not modified (read-only `prod_read.sh` queries only). Production promotion is NOT authorized:
> every gate below waits for Mario's explicit written approval.

## 1 · Staging parity

- Missing in staging and present in production (verified against prod `schema_migrations`): `20261012001100`, `20261013000100`…`0700` (8).
  Overlap check: none of their functions/triggers are redefined by S-G0/SB0 (`20261014*`, `20261015*`). Applied to staging in one
  transaction (rehearsed first with ROLLBACK, 8/8).
- Fingerprint comparison (`tools/preprod/parity_catalog.sql` + `parity_compare.py`): staging 2 835 objects, production 2 250.
  Every difference in the affected areas is **expected** (S-G0, SB0, Board MFA, preprod migrations, D13 viewer→operator), except:
  - **Configuration only:** Vault secret names differ (staging has `f360_sync_*`, `f360_push_*`, `f360_email_*`; production has
    `f360_whatsapp_url` and none of the others); cron `f360-tienda-wp-cron` exists only in production; migration `20261017000100`
    (earn-in, staging only).
  - **Security (pre-existing, not introduced here):** production still has the legacy anonymous policies `anon_insert_offline_sales`,
    `anon_update_inventory_sold`, `anon_read_offline_sales`, `anon_read_own_sales`, `anon_read_inventory`, `anon_read_active_channels`,
    `anon_read_active_staff` (+ related table ACLs). Staging dropped them in Sprint 0. This is audit finding **P0-4**
    (`docs/fuxia360/audit/LIVE_RECONCILIATION.md:63`): anonymous UPDATE of any `channel_inventory` row and anonymous sale inserts.
    Out of this gate's scope; must be scheduled (the published legacy app may still depend on them).
- Staging data fix after parity: `20261012001100` added `sales_targets.orders_mode` (default `off`), which made the staging
  reconciliation skip ("pedidos apagados"). Set `woo_staging4.orders_mode = 'on'` (staging test store); reconcile run 495 ok.

### Incident (staging, 2026-10-08 ~19:20 UTC)
A rehearsal that `\i`-included every rollback inside one `BEGIN … ROLLBACK` committed for real, because one rollback file
(`20261017000100…down.sql`) carries its own `BEGIN/COMMIT`. S-G0/SB0/earn-in objects were dropped and the P0A body re-applied.
Repaired step by step (each rehearsed): S-G0 0100–0600 re-applied (the 2 `legacy_store_sale_imports` rows kept), 20261016000200–0500,
staging board members, earn-in 20261017000100 (E1–E10 PASS). Lost (test data only): staging Board access log, decisions, close
history. **Lesson:** grep every included file for transaction control before a rehearsal; rollbacks are never run for real.

## 2 · Migrations added by the gate (staging)

| Version | What |
|---|---|
| 20261016000100 | Board MFA mandatory (`require_aal2 = true`), `f360_board_access_state`, menu stays visible to reach the challenge |
| 20261016000200 | Tax = `PENDING_ACCOUNTING_CONFIRMATION`; raw amounts kept; `product_net_before_tax` NULL (no fabricated net-of-tax) |
| 20261016000300 | FX documentation: `source_reference`, `source_retrieved_on`, `rate_method` (MONTHLY_AVERAGE / MONTH_END / OTHER) |
| 20261016000400 | Spend source state: Meta = spend exists, source NOT_CONFIGURED; Google Ads = spend UNKNOWN, NOT_CONFIGURED (never $0) |
| 20261016000500 | Bazaar reconciliation preview + guard (only UNMATCHED legacy bazaar sales can ever count) |

## 3 · Full test result (staging, all in rolled-back transactions)

| Suite | Result |
|---|---|
| `scripts/f360/db_tests.mjs` (38 files: store sale, reservations, transfers, G1 commerce, exec dashboard, CRM, …) | **1 018 PASS / 0 FAIL** |
| `scripts/f360/preprod_staging_tests.sh`: gate (MFA, approvals, visibility, FX, spend, tax, bazaar, legacy, seller denials) 64 · favorites 14 · S-G0 measurement 46 · S-G0 reconciliation 32 · online (order shipping, thanks WhatsApp, thanks member) · admin (customer add, address, sellers) | **ALL PASS** |
| `scripts/f360/sb0_staging_tests.sh applied`: unauthorized, seller, generic owner, Carolina, Mario, denied logged, writes logged, history immutable, D10B, D11, D12, T19 seller reports denied, T20 seller flows (s02 28, c3 100, s05_s03 37, reservations 24+22, store_sale_customer) | **ALL PASS** |
| `scripts/f360/preprod_mfa_e2e.mjs` (real staging Auth: aal1 denied / rest works / TOTP enroll / wrong code / aal2 allowed / cleanup) | **ALL PASS** (Carolina + Mario) |
| `test_sb_earnin.sql` | E1–E10 PASS |
| Node: f360-woo (commerce, sync, content, publisher, reconcile) + f360-whatsapp | **68 / 0** |
| admin-web: unit 15/15 · `tsc` clean · eslint clean · `next build` OK | PASS |

## 4 · MFA

- Board only: every `f360_board_*` RPC requires a JWT with `aal = aal2`; the rest of Fuxia 360 keeps working at aal1 (tested).
- Admin: `/estrategia` shows enrollment (QR + code) or the 6-digit challenge (`BoardMfa.tsx`, `MfaForms.tsx`, `mfa-actions.ts`).
- **Enrollment:** Carolina and Mario each scan the QR once with an authenticator app (Google Authenticator / 1Password / Authy).
- **Recovery:** if the phone is lost, a Supabase project owner deletes the factor (Dashboard → Authentication → user → MFA factors)
  and the person enrolls again. Until then that person cannot open the Board (the rest of Fuxia 360 keeps working). Recommend each
  of them stores the TOTP in a password manager with backup, and that the two never lose their factor at the same time.

## 5 · Owner-role dependency — review (no change made)

Current rule: allowlist (by `auth.users.id`) **+** `f360.user_roles.role = 'owner'` **+** MFA.

- **A · What `owner` adds:** a second, independent switch. Removing the owner role (e.g. a compromised account being demoted) cuts
  Board access immediately without touching the Board allowlist. It also prevents a stale allowlist row from granting access to
  someone who has left operations.
- **B · Risk of the coupling:** Board governance becomes hostage to an operational role. Operational role changes are made in a
  different screen, by different people/processes (e.g. `/vendedoras`, seller activation triggers — finding F5), for operational
  reasons. A routine operational change can silently remove a board member's access, and anyone who can grant `owner` can make
  the second check pass. It also blocks a future board member who should not be an operational owner (investor, advisor).
- **C · If Mario or Carolina change operational role:** they lose the Board the moment they stop being `owner`, with no Board-side
  record of why (only a `denied: not_owner` line in the access log).
- **D · Recommendation:** move to **active authenticated account + explicit, audited Board membership (with scopes and active
  flag) + MFA (aal2)**, without the generic owner role. Keep the defence in depth by making membership changes themselves the
  controlled step: only through an RPC that requires an existing member at aal2, never self-approval (the other member approves),
  logged in `board_member_changes`. Deactivating a person = `active = false` there. This keeps one source of truth for Board access
  and removes the cross-module dependency. **Not changed** — needs Mario's decision.

## 6 · Bazaar reconciliation preview (PRODUCTION, read-only aggregates)

Carolina's summaries: **GDL 22–24 Sep** (MXN 208 500, 69 pairs) and **Querétaro – El Campanario 29 Sep–1 Oct** (MXN 49 000, 18 pairs).
Legacy individual bazaar sales: **29 sales, MXN 126 500**.

| Class | Sales | MXN | Days | Channel | Reason |
|---|---|---|---|---|---|
| LIKELY_DUPLICATE | 15 | 74 800 | 22–24 Sep | Guadalajara | inside GDL summary dates, same place; totals don't reconcile (74 800 vs 208 500) |
| AMBIGUOUS | 9 | 35 900 | 30 Sep | Guadalajara | recorded on the "Guadalajara" channel during the Querétaro bazaar |
| UNMATCHED | 5 | 15 800 | 18 May – 16 Sep | Guadalajara, Monterrey | no bazaar summary within 2 days |
| MATCHED | 0 | — | | | |

Only UNMATCHED may ever count; LIKELY_DUPLICATE and AMBIGUOUS are excluded from financial truth until Carolina decides.

## 7 · Measurement health (staging, after parity)

| Source | Status | Last success | Data through | Known gap |
|---|---|---|---|---|
| WooCommerce (realtime) | HEALTHY | 2026-10-08 | staging4 orders | staging test store only |
| Order reconciliation | HEALTHY | 2026-10-08 19:56 UTC (run 495, 0 missing) | 2026-10-08 | runs every 15 min |
| Store sales | HEALTHY | — | 2026-10-08 | 2 legacy registered; bazaar sales need review |
| Historical orders | HEALTHY (staging) | 2026-10-08 18:51 UTC (backfill run 456) | staging4: 90/90 current | production history not imported (P0D) |
| Marketing spend | NOT_CONFIGURED | — | — | no CSV/API |
| Meta Ads | NOT_CONFIGURED | — | — | spend exists, no reliable source |
| Google Ads | NOT_CONFIGURED | — | — | spend unknown (never $0) |
| GA4 | NOT_CONFIGURED | — | — | no Data API credentials |
| FX rates | NOT_CONFIGURED | — | — | COP→MXN, USD→MXN not loaded/approved |

## 8 · S-G1 readiness (Growth Cockpit) and 9 · SB1 readiness (CEO Cockpit)

| Metric | Status | Source / blocker |
|---|---|---|
| Revenue (raw, per currency) | PARTIAL | `measurement_sales`; prod history not imported (P0D); tax pending accounting; consolidated needs FX |
| Orders | PARTIAL | same; legacy/bazaar need review |
| AOV | PARTIAL | per currency only |
| Customers (new / repeat) | PARTIAL | identity rules (S-G1) + history (P0D) |
| Spend | MISSING | Meta/Google source |
| CAC | MISSING | spend |
| ROAS | MISSING | spend |
| MER | MISSING | spend (+ FX for consolidated) |
| COGS | MISSING | product cost versions empty (needs costs) |
| Gross margin | MISSING | COGS |
| OPEX | MISSING | monthly close captures |
| EBITDA | MISSING | COGS + OPEX |
| Cash | MISSING | monthly close captures |
| Inventory | PARTIAL | units live; value needs cost |

## 10 · Inputs needed from Mario / Carolina

1. Accounting: do MX web prices include IVA? store prices? Colombia equivalent? shipping and discount tax treatment?
2. FX: source and monthly method for COP→MXN and USD→MXN (e.g. Banxico FIX monthly average; Banco de la República TRM), then the
   first approved months.
3. Meta spend: CSV export or read-only API access; Google Ads: does spend exist?
4. Product costs (per model/variant), who loads them, who approves.
5. Bazaars: for GDL 22–24 Sep and the 30 Sep sales on the GDL channel, which record counts (summary or individual sales).
6. Legal entities MX/CO (Cali = casa matriz, pending Carolina).
7. Owner-role decision (§5).
8. Monthly close inputs (OPEX, cash) — who captures.

## 11 · Production plan by gate (NOT executed)

| Gate | Contents | Depends on | Duration | Verification | Rollback | Blast radius | Go / no-go |
|---|---|---|---|---|---|---|---|
| **P0A** Security / Board | pase `20261009_p0a_seguridad_consejo.sql` = 20261015000100–0400 + 20261016000100; then membership pase by id (Carolina `31da6b13…`, Mario `d11a8d33…`) | — | 5 min | prod_sql dry-run OK; no schema USAGE for authenticated; seller gets 42501 on the 4 demand RPCs; a store test sale works | `.down.sql` 20261016000100 → 20261015000100 (export logs first; 0400 down re-opens the seller hole) | new schema only + 4 RPC gates (sellers lose demand reports) | dry-run OK + seller sale OK |
| **P0B** Measurement foundation | pase `20261009_p0b_medicion.sql` = 20261014000100–0600 + 20261016000200–0500 | P0A (catalog definitions) | 5 min | `f360_measurement_health` answers; no change to `/tablero` numbers | `.down.sql` reverse; data tables kept unless empty | new tables/views + `commerce_source_health` view | dry-run OK |
| **P0C** Reconciliation activation | deploy `f360-woo-sync` (gated by `orders_mode`); Mario loads Vault `f360_sync_url` + `f360_sync_secret`; existing cron `f360-commerce-poll` then reconciles | P0B | 1 h watch | a `reconcile` run every 15 min, ok, `detected_missing = recovered` | redeploy previous function or remove the 2 Vault secrets | reads Woo; writes only through the existing capture path | 4 consecutive ok runs |
| **P0D** Historical Woo import | `scripts/f360/sg0_woo_history_import.mjs` with a production mode (to add) — dry run, import, re-run = 0, cross-check Woo admin (84 orders, Jun–Oct) | P0C | 15 min | counts by status match Woo; inventory untouched | delete rows `first_captured_via = 'backfill'` by key (Mario's OK) | commerce facts only; `/tablero` gains Jun–Oct | dry run reviewed |
| **P0E** Legacy store / bazaar | owner runs `f360_legacy_store_sales_import` dry run → review → real run for UNMATCHED only; bazaar decisions by Carolina | P0B + Carolina's decisions | 15 min | `needs_review` excludes bazaar duplicates | registry rows voided (append-only) | measurement only | Carolina approves |
| **P0F** UI publication | `deploy_prod_admin.sh` (Medición tab, `/estrategia` + MFA screens, D13 page guards) | P0A + P0B | 5 min | Carolina/Mario enroll MFA and open `/estrategia`; seller cannot open `/favoritos` | Vercel → previous deployment | admin only | MFA enrollment done by both |

## 12 · Rollback summary
Reverse order F → A. Functions: redeploy previous version. Vault: delete the two sync secrets. SQL: run `.down.sql` files in reverse,
never `\i` a file with its own transaction control inside another transaction. Tables holding data are kept unless Mario approves
dropping them. Board schema drop only after exporting `access_log`, decisions and closes.
